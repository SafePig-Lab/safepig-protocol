pragma solidity ^0.5.16;

import "./CErc20.sol";
import "./CToken.sol";
import "./PriceOracle.sol";
import "./Exponential.sol";
import "./EIP20Interface.sol";


interface AggregatorInterface {
  function decimals() external view returns (uint8);
  function latestAnswer() external view returns (int256);
  function latestTimestamp() external view returns (uint256);
  function latestRound() external view returns (uint256);
  function getAnswer(uint256 roundId) external view returns (int256);
  function getTimestamp(uint256 roundId) external view returns (uint256);

  event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 timestamp);
  event NewRound(uint256 indexed roundId, address indexed startedBy);
}

contract PriceOracleProxy is PriceOracle, Exponential {
    address public admin;

    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /// @notice Chainlink Aggregators
    mapping(address => AggregatorInterface) public aggregators;

    address public cEthAddress;

    /**
     * @param admin_ The address of admin to set aggregators
     * @param cEthAddress_ The address of cETH, which will return a constant 1e18, since all prices relative to ether
     */
    constructor(address admin_, address cEthAddress_) public {
        admin = admin_;
        cEthAddress = cEthAddress_;
    }

    /**
     * @notice Get the underlying USD price of a listed cToken asset
     * @param cToken The cToken to get the underlying USD price of
     * @return The underlying asset USD price mantissa (scaled by 1e18)
     */
    function getUnderlyingPrice(CToken cToken) public view returns (uint) {
        address cTokenAddress = address(cToken);
        AggregatorInterface aggregator = aggregators[cTokenAddress];
        if (address(aggregator) != address(0)) {
            MathError mathErr;
            Exp memory price;
            (mathErr, price) = getPriceFromChainlink(aggregator);
            if (mathErr != MathError.NO_ERROR) {
                return 0;
            }

            if (price.mantissa == 0) {
                return 0;
            }

            if (cTokenAddress != cEthAddress) {
                uint underlyingDecimals;
                underlyingDecimals = EIP20Interface(CErc20(cTokenAddress).underlying()).decimals();
                (mathErr, price) = mulScalar(price, 10**(18 - underlyingDecimals));
                if (mathErr != MathError.NO_ERROR ) {
                    return 0;
                }
            }

            return price.mantissa;
        }

        return 0;
    }

    /**
     * @notice Get price from ChainLink
     * @param aggregator The ChainLink aggregator to get the USD price of
     * @return The price(scaled by 1e18)
     */
    function getPriceFromChainlink(AggregatorInterface aggregator) internal view returns (MathError, Exp memory) {
        int256 chainLinkPrice = aggregator.latestAnswer();
        if (chainLinkPrice <= 0) {
            return (MathError.INTEGER_OVERFLOW, Exp({mantissa: 0}));
        }
        MathError mathErr;
        Exp memory price;
        (mathErr, price) = mulScalar(Exp({mantissa: uint(chainLinkPrice)}), 10**(18 - uint(aggregator.decimals())));
        return (mathErr, price);
    }

    event AggregatorUpdated(address cTokenAddress, address source);

    /**
     * @notice Set ChainLink USD aggregators for multiple cTokens
     * @param cTokenAddresses The list of underlying tokens
     * @param sources The list of ChainLink USD aggregator sources
     */
    function _setAggregators(address[] calldata cTokenAddresses, address[] calldata sources) external {
        require(msg.sender == admin, "only the admin may set the aggregators");
        for (uint i = 0; i < cTokenAddresses.length; i++) {
            aggregators[cTokenAddresses[i]] = AggregatorInterface(sources[i]);
            emit AggregatorUpdated(cTokenAddresses[i], sources[i]);
        }
    }

}
