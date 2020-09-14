pragma solidity ^0.5.1;


contract Futures {
    // contract-level variables 
    address public buyer;
    address public seller;
    // addresses of Tokens that are being used
    
    // Token that is common for both parties and being used for settling the contract
    ERC20 public common_token;

    ERC20 public buyer_token; // Need to convert to ERC20 type 
    ERC20 public seller_token; // Need to convert to ERC20 type
    
    
    // NOTE: For the simple version (where one of the token pairs is used to settle the contract) of the contract, we store the current exchange rate (used for margin mechanics)
    // TODO : Change the name to cur_strike_price, think about this
    uint public cur_strike_price;

    
    // Derivative related variables
    uint public maturity;

    // hard-code the collateral value that must be held by each party (a number between 0 to 100 to represent % is ideal, for now it is a hard coded literal collateral value required)
    uint public buyer_collateral = 40;
    uint public seller_collateral = 40;
    
    // Hard code the maintenance margin that triggers liquidation if collateral goes below this value,
    uint public buyer_collateral_maintenance = 20;
    uint public seller_collateral_maintenance = 20;
    
    // Pricefeed that provides the exchange values 
    PriceFeed public Pricefeed;
    
    // Define initial state of contract
    DerivateState contract_state = DerivateState.Init;
    
    // Define an enum that keeps track of the "state" of the contract 
    // Replace Execute with Matured
    enum DerivateState{Init, Active, Matured, Liquidated}

    // Using safeMath to safeguard against integer overflow attacks
    using SafeMath for uint256;

    // Modifiers to ensure functions can only be called when in the correct state
    modifier InInitState() {
        require(contract_state == DerivateState.Init, "Contract not in the Init State");
        _;
    }

    modifier InActiveState() {
        require(contract_state == DerivateState.Active, "Contract not in an Active State");
        _;
    }
    
        // Create a modifier that takes in a user and finds out if their margin is above the maintenance margin 
    modifier positiveBuyerMarginAccount() {
        require(buyer_collateral > buyer_collateral_maintenance, "Not enough funds to be able to withdraw");
        _;
    }
    
    modifier positiveSellerMarginAccount() {
        require(seller_collateral > seller_collateral_maintenance, "Not enough funds to be able to withdraw");
        _;
    }
    
    // check if sender is the buyer
    modifier buyerIsSender() {
        require(msg.sender == buyer, "Buyer not calling this function");
        _;
    }
    
    // check if sender if the seller
    
    modifier sellerIsSender() {
        require(msg.sender == seller, "seller not calling this function");
        _;
    }

    
    // Unused function parameters there to show the next stages of the contract where collateral is set during contract creation 
    constructor(address _buyer,address _seller,address _buyer_tkn,address _seller_tkn, uint _buyer_collateral, uint _seller_collateral, address _ERC20add, address _Pricefeed, uint _exchange_price) public {
        buyer = _buyer;
        seller = _seller;
        buyer_token = ERC20(_buyer_tkn);
        seller_token = ERC20(_seller_tkn);
        // casting the ERC20 token address to the ERC20 contract type 
        common_token = ERC20(_ERC20add);
        Pricefeed = PriceFeed(_Pricefeed);
        cur_strike_price = _exchange_price;
        
        buyer_collateral = _buyer_collateral;
        seller_collateral = _seller_collateral;
    } 
    

    
    
    // Contract state changing functions from the contract states 
    // Modifier, with the enum
    function activate() InInitState public {
        // If activate is called when not in init state, handled by a modifier
        require(contract_state == DerivateState.Init, "Derivative not in INIT state");
        
        // The state is changed before carrying out operations
        contract_state = DerivateState.Active;

        
        // If both pass, then initiate transfers of collateral from the parties addresses to the address of this smart contract
        common_token.transferFrom(buyer, address(this), buyer_collateral);
        common_token.transferFrom(seller, address(this), seller_collateral);
        
        // After having successfully transferred the collateral funds, we progress to the execute state    
    }

    
    // Multiple requirements of execute_contract function 
    // 1. Get price feed data and check if the party is below liquidation, if under liquidation follow the liquidate protocol
    // 2. Check if maturity date has been reached, and if it has, then transfer the amount of tokens for the strike price
    // (the strike price being a ratio between the tokens that is agreed.) 
    
    function execute_contract() InActiveState public {
        
        // only works if in state Active or in Execute 
        
        
            
        // Get price feed data and calculate whether the parties are below liquidation
        // Hard coded eth/usd 
        uint new_price = Pricefeed.getPrice('ETH_USD');
        
        // Check if price of ETH decreased or increased or stayed the same 
        if (new_price > cur_strike_price) {
            // The buyer benefits and when the exchange price is reset, a portion of the collateral of the seller is sent to the buyer
            uint profit = new_price.sub(cur_strike_price);
            // use safe math 
            // Updating margins
            seller_collateral = seller_collateral.sub(profit);
            
            buyer_collateral = buyer_collateral.add(profit);
            
            //updating the cur_strike_price
            cur_strike_price = new_price;

            
        } else if (new_price < cur_strike_price) {
            // The seller benefits and when the exchange price is reset, a portion of the collateral of the buyer is sent to the seller
            uint profit = new_price.sub(cur_strike_price);
            
            // Updating margins

            buyer_collateral = buyer_collateral.sub(profit);
            seller_collateral = seller_collateral.add(profit);
            
            cur_strike_price = new_price;
            
            
        } else {
            
            // In the case price doesnt change, no transfer of collateral occurs
            // Potentially, carry any calculations?
            // Upon Advice, left as is 
            
        }
        
        // Check the margin accounts to ensure collateral is atleast above the maintenance margin, for the purposes of liquidation 

        if (buyer_collateral < buyer_collateral_maintenance) {
            // trigger liquidation
            liquidation(true);
            
        } else if (seller_collateral < seller_collateral_maintenance) {
            liquidation(false);
        }
        
        // if no liquidation, then continue, do nothing 
            
    }
    
    // Called internally to liquidate the contract and trasnfer the collateral to the "honest"/non-defaulting contract holder.
    function liquidation(bool is_buyer) private {
        
        // Update contract state to Liquidate
        contract_state = DerivateState.Liquidated;
        
        // Initiate transfer of collateral to non-defaulting contract holder.
        if (is_buyer) {
            common_token.transfer(msg.sender, buyer_collateral);
        } else {
            common_token.transfer(msg.sender, seller_collateral);
        }
        
        
    }
    
    // A function that allows a buyer or seller to withdraw their additional funds upto their (initial margin, however for the simple case use) **maintenance margin** 
    // The function must only be callable by a buyer or a seller who's collateral is above the maintenance margin 
    

    
    // The buyer withdrawal function 
    function withdraw_buyer_funds(uint withdraw_amount) positiveBuyerMarginAccount buyerIsSender  public {
        uint possible_funds = buyer_collateral.sub(buyer_collateral_maintenance);
        require(possible_funds >= withdraw_amount, "Not enough funds to withdraw");
        
        // Reentrace issue, so remove funds from collateral account before transferring
        buyer_collateral = buyer_collateral.sub(withdraw_amount);
        
        // Transfer the token amount 
        common_token.transfer(buyer, withdraw_amount);
     
        
    }
    

    
    function withdraw_seller_funds(uint withdraw_amount) positiveSellerMarginAccount sellerIsSender  public {
        uint possible_funds = seller_collateral.sub(seller_collateral_maintenance);
        require(possible_funds >= withdraw_amount, "Not enough funds to withdraw");
        
        // Reentrace issue, so remove funds from collateral account before transferring
        seller_collateral = seller_collateral.sub(withdraw_amount);
        
        // Transfer the token amount 
        common_token.transfer(seller, withdraw_amount);
     
        
    }
    
    

    
}
    
// Basic fake PriceFeed implementation for testing purposes of the futures smart contract, will have to be replaced with actual price feed
    
contract PriceFeed {
    mapping(string => uint) prices;
    mapping(string => uint) timestamps;
    
    constructor() public {
        prices['ETH_USD'] = 100;
        prices['BTC_USD'] = 500;
        
        timestamps['ETH_USD'] = block.timestamp;
        timestamps['BTC_USD'] = block.timestamp;
    }
    
    function getPrice(string memory ticker) public view returns(uint) {
        return prices[ticker];
    }
    
    function setPrice(string memory ticker, uint new_price) public {
        prices[ticker] = new_price;
        timestamps[ticker] = block.timestamp;
    }
    
}

// Here to provide all contracts in one file for testing purposes on Remix or on Truffle 

// Code from https://gist.github.com/giladHaimov/8e81dbde10c9aeff69a1d683ed6870be#file-basicerc20-sol-L61
contract ERC20 {

    string public constant name = "ERC20Basic";
    string public constant symbol = "BSC";
    uint8 public constant decimals = 18;  


    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
    event Transfer(address indexed from, address indexed to, uint tokens);


    mapping(address => uint256) balances;

    mapping(address => mapping (address => uint256)) allowed;
    
    uint256 totalSupply_;

    using SafeMath for uint256;


   constructor(uint256 total) public {  
    totalSupply_ = total;
    balances[msg.sender] = totalSupply_;
    }  

    function totalSupply() public view returns (uint256) {
    return totalSupply_;
    }
    
    function balanceOf(address tokenOwner) public view returns (uint) {
        return balances[tokenOwner];
    }
    
    // my code: allows any address to ask to give it tokens by specifying the amount
    
    function give_tokens(uint numTokens) public returns (bool) {
        balances[msg.sender] = numTokens;
    }

    function transfer(address receiver, uint numTokens) public returns (bool) {
        require(numTokens <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender].sub(numTokens);
        balances[receiver] = balances[receiver].add(numTokens);
        emit Transfer(msg.sender, receiver, numTokens);
        return true;
    }

    function approve(address delegate, uint numTokens) public returns (bool) {
        allowed[msg.sender][delegate] = numTokens;
        emit Approval(msg.sender, delegate, numTokens);
        return true;
    }

    function allowance(address owner, address delegate) public view returns (uint) {
        return allowed[owner][delegate];
    }

    function transferFrom(address owner, address buyer, uint numTokens) public returns (bool) {
        require(numTokens <= balances[owner]);    
        require(numTokens <= allowed[owner][msg.sender]);
    
        balances[owner] = balances[owner].sub(numTokens);
        allowed[owner][msg.sender] = allowed[owner][msg.sender].sub(numTokens);
        balances[buyer] = balances[buyer].add(numTokens);
        emit Transfer(owner, buyer, numTokens);
        return true;
    }
}

// SafeMath library provided by OpenZeppelin

library SafeMath { 
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
      assert(b <= a);
      return a - b;
    }
    
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
      uint256 c = a + b;
      assert(c >= a);
      return c;
    }
}



