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

    // future tokens total
    uint256 public totalTokens;

    // future tokens refunded
    uint256 public refundedTokens;

    // funders future tokens
    mapping(uint128 => uint256) public tokens;

    // funders funds in ETH
    mapping (uint128 => uint256) public fundedETH;

    // funders funds in BTC
    mapping (uint128 => uint256) public fundedBTC;

    // funds raised, ETH
    uint256 public raisedETH;

    // funds raised, BTC
    uint256 public raisedBTC;

    // funding struct for oraclize queries
    struct Funding {
        uint128 funder;
        bytes3 currency;
        uint256 funds;
        uint256 tx;
        uint256 rate;
    }

    // funding oraclize queries
    mapping (bytes32 => Funding) public fundingQueries;

    // store funding transactions to prevent double usage
    mapping (uint256 => bool) public fundingTransactions;

    // urls for ETH and BTC rates using by oraclize
    string public ethRateURL = "json(https://api.coinmarketcap.com/v1/ticker/ethereum/).0.price_usd";
    string public btcRateURL = "json(https://api.coinmarketcap.com/v1/ticker/bitcoin/).0.price_usd";

    // oraclize gas limit
    uint256 public oraclizeGasLimit = 200000;

    // rate exponent
    uint256 public constant RATE_EXPONENT = 4;

    // ETH decimals
    uint256 public constant ETH_DECIMALS = 18;

    // BTC decimals
    uint256 public constant BTC_DECIMALS = 8;

    // future tokens decimals
    uint256 public constant FUTURE_TOKENS_DECIMALS = 18;

    // hard cap of future tokens to propose
    uint256 public constant FUTURE_TOKENS_HARD_CAP = 4000000 * (10 ** FUTURE_TOKENS_DECIMALS);

    /**
     * event for funding query logging
     * @param funder who initiated funding
     * @param queryId oraclize query id
     */
    event FundingQueryEvent(uint128 indexed funder, bytes32 queryId);

    /**
     * event for funding query logging
     * @param funder who paid for the tokens
     * @param tokens amount of future tokens purchased
     */
    event FundEvent(uint128 indexed funder, uint256 tokens);

    /**
     * event for funding query logging
     * @param funder who paid for the tokens
     * @param tokens amount of future tokens refunded
     */
    event RefundEvent(uint128 indexed funder, uint256 tokens);


    /**
     * CONSTRUCTOR
     *
     * @dev Initialize the BetexSAFT
     * @param _startTime start time
     */
    function BetexSAFT(uint256 _startTime) public {
        startTime = _startTime;
    }

    // accept ether to contract (for oraclize queries)
    function () public payable {}

    /**
     * @dev Makes query for purchase future tokens.
     * @param _funder who paid for the tokens
     * @param _currency symbol of the payment currency
     * @param _funds amount of transferred funds
     * @param _tx hash of the transfer transaction
     */
    function fund(uint128 _funder, bytes3 _currency, uint256 _funds, uint256 _tx) onlyOwner public { // solium-disable-line arg-overflow
        require(liveSAFTCampaign());
        require(oraclize_getPrice("URL") <= this.balance);
        require(_funder != 0);
        require(_currency == "ETH" || _currency == "BTC");
        require(_funds > 0);
        require(!fundingTransactions[_tx]);

        bytes32 _queryId;

        if (_currency == "ETH") {
            _queryId = oraclize_query("URL", ethRateURL, oraclizeGasLimit);
        } else {
            _queryId = oraclize_query("URL", btcRateURL, oraclizeGasLimit);
        }

        fundingQueries[_queryId].funder = _funder;
        fundingQueries[_queryId].currency = _currency;
        fundingQueries[_queryId].funds = _funds;
        fundingQueries[_queryId].tx = _tx;

        FundingQueryEvent(_funder, _queryId);
    }

    /**
     * @dev Get current rate from oraclize and purchase future tokens.
     * @param _queryId oraclize query id
     * @param _result current rate of the specified currency
     */
    function __callback(bytes32 _queryId, string _result) public {  // solium-disable-line mixedcase
        require(msg.sender == oraclize_cbAddress());

        uint256 _rate = parseInt(_result, RATE_EXPONENT);

        uint128 _funder = fundingQueries[_queryId].funder;
        bytes3 _currency = fundingQueries[_queryId].currency;
        uint256 _funds = fundingQueries[_queryId].funds;
        uint256 _tx = fundingQueries[_queryId].tx;

        if (fundingTransactions[_tx])
            revert();

        fundingQueries[_queryId].rate = _rate;

        uint256 _sum = _funds.mul(_rate);

        if (_currency == "ETH") {
            _sum = _sum.mul(10 ** (FUTURE_TOKENS_DECIMALS - ETH_DECIMALS));
        } else {
            _sum = _sum.mul(10 ** (FUTURE_TOKENS_DECIMALS - BTC_DECIMALS));
        }

        _sum = _sum.div(10 ** RATE_EXPONENT);

        uint256 _tokens = calcTokens(totalTokens, _sum);

        if (totalTokens.add(_tokens) > FUTURE_TOKENS_HARD_CAP)
            revert();

        tokens[_funder] = tokens[_funder].add(_tokens);
        totalTokens = totalTokens.add(_tokens);

        if (_currency == "ETH") {
            fundedETH[_funder] = fundedETH[_funder].add(_funds);
            raisedETH = raisedETH.add(_funds);
        } else {
            fundedBTC[_funder] = fundedBTC[_funder].add(_funds);
            raisedBTC = raisedBTC.add(_funds);
        }

        fundingTransactions[_tx] = true;

        FundEvent(_funder, _tokens);
    }

    /**
     * @dev Refunds tokens
     * @param _funder who get refunding
     */
    function refund(uint128 _funder) onlyOwner public {
        require(liveSAFTCampaign());
        require(_funder != 0);

        uint256 _tokens = tokens[_funder];

        tokens[_funder] = 0;
        refundedTokens = refundedTokens.add(_tokens);

        raisedETH = raisedETH.sub(fundedETH[_funder]);
        raisedBTC = raisedBTC.sub(fundedBTC[_funder]);

        fundedETH[_funder] = 0;
        fundedBTC[_funder] = 0;

        RefundEvent(_funder, _tokens);
    }

    /**
     * @dev Calculate amount of tokens to be purchased
     * @param _totalTokens total amount of tokens is been sold already
     * @param _sum sum of funding
     */
    function calcTokens(uint256 _totalTokens, uint256 _sum) public pure returns (uint256 _tokens) {
        uint256 E = 10 ** 6; // solium-disable-line mixedcase
        uint256 D = 10 ** FUTURE_TOKENS_DECIMALS; // solium-disable-line mixedcase
        uint256 F = _totalTokens.mul(25).add(3 * E * D); // solium-disable-line mixedcase
        _tokens = sqrt(_sum.mul(50 * E * D).add(F ** 2)).sub(F).div(25);
        return _tokens;
    }

    // sqrt function
    function sqrt(uint256 x) public pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    // set oraclize gas limit
    function setOraclizeGasLimit(uint256 _gasLimit) onlyOwner public {
        require(_gasLimit > 0);
        oraclizeGasLimit = _gasLimit;
    }

    // set oraclize gas price
    function setOraclizeGasPrice(uint256 _gasPrice) onlyOwner public {
        require(_gasPrice > 0);
        oraclize_setCustomGasPrice(_gasPrice);
    }

    // withdraw remain ether from contract
    function withdrawRemainEther() onlyOwner public {
        require(this.balance > 0);
        owner.transfer(this.balance);
    }

    // @return true if the SAFT camapign is alive
    function liveSAFTCampaign() internal view returns (bool) {
        return now >= startTime && totalTokens <= FUTURE_TOKENS_HARD_CAP; // solium-disable-line security/no-block-members
    }
}
