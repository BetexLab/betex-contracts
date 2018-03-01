pragma solidity ^0.4.18;

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/ownership/HasNoContracts.sol";
import "zeppelin-solidity/contracts/ownership/HasNoTokens.sol";
import "./usingOraclize.sol";

/**
 * @title BetexSAFT
 * @dev BetexSAFT is a registry contract for a
 * Betex Simple Agreement for Future Tokens campaign.
 */
contract BetexSAFT is usingOraclize, HasNoContracts, HasNoTokens {
    using SafeMath for uint256;

    // start timestamp
    uint256 public startTime;

    // end timestamp
    uint256 public endTime;

    // wallet address to trasfer direct funding to
    address public wallet;

    // collector struct
    struct Collector {
        bytes3 symbol;
        uint8 decimals;
        string rateUrl;
    }

    // list of collectors
    // index 0 ETH
    // index 1 BTC
    Collector[] public collectors;

    // collectors count
    uint8 public collectorsCount;

    // tokens sold
    uint256 public sold;

    // raised by collector
    mapping (uint8 => uint256) public raised;

    // funders tokens
    mapping(uint128 => uint256) public purchased;

    // funded by funder and collector
    mapping (uint128 => mapping(uint8 => uint256)) public funded;

    // oraclize funding order
    struct Order {
        uint128 funderId;
        uint8 collector;
        uint256 funds;
        uint256 rate;
    }

    // oraclize funding orders
    mapping (bytes32 => Order) public orders;

    // store outer funding transactions to prevent double usage
    mapping (uint256 => bool) public transactions;

    // address to funderId mapping for direct funding;
    mapping (address => uint128) public direct;

    // addresses authorized to refill the contract (for oraclize queries)
    mapping (address => bool) public refillers;

    // list of funders who failed KYC
    uint128[] public failedKycList;

    // count of funders who failed KYC
    uint256 public failedKycCount;

    // mapping to know if KYC failed
    mapping(uint128 => bool) public isKycFailed;

    // oraclize gas limit
    uint256 public oraclizeGasLimit = 200000;

    // max collectors
    uint8 public MAX_COLLECTORS = 2;

    // rate exponent
    uint256 public constant RATE_EXPONENT = 4;

    // token price usd
    uint256 public constant TOKEN_PRICE = 3;

    // token decimals
    uint256 public constant TOKEN_DECIMALS = 18;

    // hard cap of tokens proposed to purchase
    uint256 public constant TOKENS_HARD_CAP = 3000000 * (10 ** TOKEN_DECIMALS);

    /**
     * event for funding order logging
     * @param funderId funder who has done the order
     * @param orderId oraclize orderId
     */
    event OrderEvent(uint128 indexed funderId, bytes32 indexed orderId);

    /**
     * event for token purchase logging
     * @param funderId funder who paid for the tokens
     * @param orderId oraclize orderId
     * @param tokens amount of tokens purchased
     */
    event TokenPurchaseEvent(uint128 indexed funderId, bytes32 indexed orderId, uint256 tokens);

    /**
     * event for failed KYC logging
     * @param funderId funder who fail KYC
     */
    event KycFailedEvent(uint128 indexed funderId);

    /**
     * event for direct funding logging
     * @param funderId funder who has done the payment
     * @param sender funder address funds sent from
     * @param funds funds sent by funder
     */
    event DirectFundingEvent(uint128 indexed funderId, address indexed sender, uint256 funds);

    /**
     * event for direct map logging
     * @param sender sender address
     * @param funderId funderId mapped to sender address
     */
    event DirectMapEvent(address indexed sender, uint128 indexed funderId);


    /**
     * CONSTRUCTOR
     *
     * @dev Initialize the BetexSAFT
     * @param _startTime start time
     * @param _endTime end time
     * @param _wallet wallet address to transfer direct funding to
     */
    function BetexSAFT(uint256 _startTime, uint256 _endTime, address _wallet) public {
        require(_startTime < _endTime);
        require(_wallet != address(0));

        startTime = _startTime;
        endTime = _endTime;
        wallet = _wallet;
    }

    // Accepts ether to contract for oraclize queries and direct funding
    function () public payable {
        require(msg.value > 0);

        address _sender = msg.sender;

        if (direct[_sender] != 0) {
            uint128 _funderId = direct[_sender];
            uint8 _collector = 0;
            uint256 _funds = msg.value;

            require(_funds >= 0.5 ether);

            DirectFundingEvent(_funderId, _sender, _funds);

            _order(_funderId, _collector, _funds);

            wallet.transfer(_funds);
        } else if (!refillers[_sender] && !(owner == _sender)) {
            revert();
        }
    }

    /**
     * @dev Makes order for tokens purchase.
     * @param _funderId funder who paid for the tokens
     * @param _collector collector index
     * @param _funds amount of the funds
     * @param _tx hash of the outer funding transaction
     */
    function order(uint128 _funderId, uint8 _collector, uint256 _funds, uint256 _tx) onlyOwner public { // solium-disable-line arg-overflow
        require(_tx > 0);
        require(!transactions[_tx]);

        transactions[_tx] = true;

        _order(_funderId, _collector, _funds);
    }

    /**
     * @dev Get current rate from oraclize and sell tokens.
     * @param _orderId oraclize order id
     * @param _result current rate of the specified collector's currency
     */
    function __callback(bytes32 _orderId, string _result) public {  // solium-disable-line mixedcase
        require(msg.sender == oraclize_cbAddress());

        uint256 _rate = parseInt(_result, RATE_EXPONENT);

        uint128 _funderId = orders[_orderId].funderId;
        uint8 _collector = orders[_orderId].collector;
        uint256 _funds = orders[_orderId].funds;

        uint8 COLLECTOR_DECIMALS = collectors[_collector].decimals; // solium-disable-line mixedcase

        uint256 _sum = _funds.mul(_rate);

        _sum = _sum.mul(10 ** (TOKEN_DECIMALS - COLLECTOR_DECIMALS));
        _sum = _sum.div(10 ** RATE_EXPONENT);

        uint256 _tokens = _sum.div(TOKEN_PRICE);

        if (sold.add(_tokens) > TOKENS_HARD_CAP) {
            _tokens = TOKENS_HARD_CAP.sub(sold);
        }

        orders[_orderId].rate = _rate;

        purchased[_funderId] = purchased[_funderId].add(_tokens);
        sold = sold.add(_tokens);

        funded[_funderId][_collector] = funded[_funderId][_collector].add(_funds);
        raised[_collector] = raised[_collector].add(_funds);

        TokenPurchaseEvent(_funderId, _orderId, _tokens);
    }

    /**
     * @dev Add funder to KYC failed list
     * @param _funderId who failed KYC
     */
    function failedKyc(uint128 _funderId) onlyOwner public {
        require(now <= endTime + 2 weeks); // solium-disable-line security/no-block-members
        require(_funderId != 0);
        require(!isKycFailed[_funderId]);

        failedKycList.push(_funderId);
        isKycFailed[_funderId] = true;
        failedKycCount++;

        KycFailedEvent(_funderId);
    }

    /**
     * @dev Add a refiller
     * @param _refiller address that authorized to refill the contract
     */
    function addRefiller(address _refiller) onlyOwner public {
        require(_refiller != address(0));
        refillers[_refiller] = true;
    }

    /**
     * @dev Add a direct funding map
     * @param _sender funder address funds sent from
     * @param _funderId funderId mapped to sender
     */
    function addDirect(address _sender, uint128 _funderId) onlyOwner public {
        require(_sender != address(0));
        require(_funderId != 0);
        require(direct[_sender] == 0);

        direct[_sender] = _funderId;

        DirectMapEvent(_sender, _funderId);
    }

    /**
     * @dev Add a collector
     * @param _symbol currency symbol of collector
     * @param _decimals currency decimals of collector
     * @param _rateUrl url to get collector's currency rate
     */
    function addCollector(bytes3 _symbol, uint8 _decimals, string _rateUrl) onlyOwner public {
        require(collectorsCount < MAX_COLLECTORS);

        Collector memory _collector = Collector(_symbol, _decimals, _rateUrl);
        collectors.push(_collector);

        collectorsCount++;
    }

    /**
     * @dev Set oraclize gas limit
     * @param _gasLimit a new oraclize gas limit
     */
    function setOraclizeGasLimit(uint256 _gasLimit) onlyOwner public {
        require(_gasLimit > 0);
        oraclizeGasLimit = _gasLimit;
    }

    /**
     * @dev Set oraclize gas price
     * @param _gasPrice a new oraclize gas price
     */
    function setOraclizeGasPrice(uint256 _gasPrice) onlyOwner public {
        require(_gasPrice > 0);
        oraclize_setCustomGasPrice(_gasPrice);
    }

    /**
     * @dev Withdraw ether from contract
     * @param _amount amount to withdraw
     */
    function withdrawEther(uint256 _amount) onlyOwner public {
        require(this.balance >= _amount);
        owner.transfer(_amount);
    }

    /**
     * @dev Makes order for tokens purchase.
     * @param _funderId who paid for the tokens
     * @param _collector collector index
     * @param _funds amount of transferred funds
     */
    function _order(uint128 _funderId, uint8 _collector, uint256 _funds) internal { // solium-disable-line arg-overflow
        require(liveSAFTCampaign());
        require(oraclize_getPrice("URL") <= this.balance);
        require(_funderId != 0);
        require(!isKycFailed[_funderId]);
        require(_collector < collectorsCount);
        require(_funds > 0);

        bytes32 _orderId = oraclize_query("URL", collectors[_collector].rateUrl, oraclizeGasLimit);

        orders[_orderId].funderId = _funderId;
        orders[_orderId].collector = _collector;
        orders[_orderId].funds = _funds;

        OrderEvent(_funderId, _orderId);
    }

    // @return true if the SAFT campaign is alive
    function liveSAFTCampaign() internal view returns (bool) {
        return now >= startTime && now <= endTime && sold < TOKENS_HARD_CAP; // solium-disable-line security/no-block-members
    }
}
