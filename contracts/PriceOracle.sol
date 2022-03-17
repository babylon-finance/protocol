// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol';

import {IBabController} from './interfaces/IBabController.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {ICToken} from './interfaces/external/compound/ICToken.sol';
import {ITokenIdentifier} from './interfaces/ITokenIdentifier.sol';
import {ISnxExchangeRates} from './interfaces/external/synthetix/ISnxExchangeRates.sol';
import {ICurveMetaRegistry} from './interfaces/ICurveMetaRegistry.sol';
import {ICurvePoolV3} from './interfaces/external/curve/ICurvePoolV3.sol';
import {IHarvestUniv3Pool} from './interfaces/external/harvest/IHarvestUniv3Pool.sol';
import {ICurvePoolV3DY} from './interfaces/external/curve/ICurvePoolV3DY.sol';
import {IUniswapV2Router} from './interfaces/external/uniswap/IUniswapV2Router.sol';
import {IUniswapViewer} from './interfaces/external/uniswap-v3/IUniswapViewer.sol';
import {IUniVaultStorage} from './interfaces/external/uniswap-v3/IUniVaultStorage.sol';
import {INFTPositionManager} from './interfaces/external/uniswap-v3/INFTPositionManager.sol';
import {ISnxSynth} from './interfaces/external/synthetix/ISnxSynth.sol';
import {ISnxProxy} from './interfaces/external/synthetix/ISnxProxy.sol';
import {IYearnRegistry} from './interfaces/external/yearn/IYearnRegistry.sol';
import {IYearnVault} from './interfaces/external/yearn/IYearnVault.sol';
import {IStETH} from './interfaces/external/lido/IStETH.sol';
import {IWstETH} from './interfaces/external/lido/IWstETH.sol';

import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from './lib/SafeDecimalMath.sol';
import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';
import {AddressArrayUtils} from './lib/AddressArrayUtils.sol';
import {ControllerLib} from './lib/ControllerLib.sol';

/**
 * @title PriceOracle
 * @author Babylon Finance Protocol
 *
 * Uses Uniswap V3 to get a price of a token pair
 */
contract PriceOracle is Ownable, IPriceOracle {
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using ControllerLib for IBabController;

    /* ============ Constants ============ */

    // Address of Uniswap factory
    IUniswapV3Factory internal constant factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    ISnxExchangeRates internal constant snxEchangeRates = ISnxExchangeRates(0xd69b189020EF614796578AfE4d10378c5e7e1138);
    IUniswapV2Router internal constant uniRouterV2 = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IYearnRegistry private constant yearnRegistry = IYearnRegistry(0xE15461B18EE31b7379019Dc523231C57d1Cbc18c);
    IUniswapViewer private constant uniswapViewer = IUniswapViewer(0x25c81e249F913C94F263923421622bA731E6555b);
    INFTPositionManager private constant nftPositionManager =
        INFTPositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    address internal constant ETH_ADD_CURVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant BABL = 0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    IStETH private constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH private constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    address private constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address private constant palStkAAVE = 0x24E79e946dEa5482212c38aaB2D0782F04cdB0E0;
    address private constant curvePalStkAave = 0x48536EC5233297C367fd0b6979B75d9270bB6B15;

    // the desired seconds agos array passed to the observe method
    uint32 private constant SECONDS_GRANULARITY = 30;
    uint256 private constant CURVE_SLIPPAGE = 6e16;

    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;
    uint24 private constant FEE_HIGH = 10000;
    int24 private constant baseThreshold = 1000;
    int24 private constant INITIAL_TWAP_DEVIATION = 800; // locally for testing. It should be halved in main

    /* ============ State Variables ============ */

    ITokenIdentifier public tokenIdentifier;
    IBabController public controller;
    mapping(address => bool) public hopTokens;
    address[] public hopTokensList;
    int24 private maxTwapDeviation;

    /* ============ Modifiers ============ */

    /* ============ Constructor ============ */

    constructor(ITokenIdentifier _tokenIdentifier, IBabController _controller) {
        tokenIdentifier = _tokenIdentifier;
        controller = _controller;
        maxTwapDeviation = INITIAL_TWAP_DEVIATION;

        _updateReserves(AddressArrayUtils.toDynamic(WETH, DAI, USDC, WBTC));
    }

    /* ============ External Functions ============ */

    function updateTokenIdentifier(ITokenIdentifier _tokenIdentifier) public override {
        controller.onlyGovernanceOrEmergency();
        require(address(_tokenIdentifier) != address(0), 'Address needs to exist');
        tokenIdentifier = _tokenIdentifier;
    }

    function updateMaxTwapDeviation(int24 _maxTwapDeviation) public override {
        controller.onlyGovernanceOrEmergency();
        require(_maxTwapDeviation < 1500, 'Max twap deviation must be within range');
        maxTwapDeviation = _maxTwapDeviation;
    }

    function updateReserves(address[] memory list) public override {
        controller.onlyGovernanceOrEmergency();
        _updateReserves(list);
    }

    /**
     * Returns the amount out corresponding to the amount in for a given token
     * @param _tokenIn              Address of the first token
     * @param _tokenOut             Address of the second token
     * @return price                Price of the pair
     */
    function getPriceNAV(address _tokenIn, address _tokenOut) public view override returns (uint256 price) {
        price = _getPrice(_tokenIn, _tokenOut, true);
        require(price != 0, 'Price not found');
        return price;
    }

    /**
     * Returns the amount out corresponding to the amount in for a given token
     * @param _tokenIn              Address of the first token
     * @param _tokenOut             Address of the second token
     * @return price                Price of the pair
     */
    function getPrice(address _tokenIn, address _tokenOut) public view virtual override returns (uint256 price) {
        price = _getPrice(_tokenIn, _tokenOut, false);
        require(price != 0, 'Price not found');
        return price;
    }

    function getCompoundExchangeRate(address _asset, address _underlying) public view override returns (uint256) {
        uint256 exchangeRateNormalized = ICToken(_asset).exchangeRateStored();
        if (ERC20(_underlying).decimals() > 8) {
            exchangeRateNormalized = exchangeRateNormalized.div(10**(ERC20(_underlying).decimals() - 8));
        } else {
            exchangeRateNormalized = exchangeRateNormalized.mul(10**(8 - ERC20(_underlying).decimals()));
        }
        return exchangeRateNormalized;
    }

    function getCreamExchangeRate(address _asset, address _underlying) public view override returns (uint256) {
        uint256 exchangeRateNormalized = ICToken(_asset).exchangeRateStored();
        if (ERC20(_underlying).decimals() > 8) {
            exchangeRateNormalized = exchangeRateNormalized.div(10**(ERC20(_underlying).decimals() - 8));
        } else {
            exchangeRateNormalized = exchangeRateNormalized.mul(10**(8 - ERC20(_underlying).decimals()));
        }
        return exchangeRateNormalized;
    }

    /* ============ Internal Functions ============ */

    /**
     * Returns the amount out corresponding to the amount in for a given token
     * @param _tokenIn              Address of the first token
     * @param _tokenOut             Address of the second token
     * @param _forNAV               Whether it is just for display purposes
     * @return price                Price of the pair
     */
    function _getPrice(
        address _tokenIn,
        address _tokenOut,
        bool _forNAV
    ) private view returns (uint256 price) {
        // Same asset. Returns base unit
        if (_tokenIn == _tokenOut) {
            return 10**18;
        }

        _tokenIn = _tokenIn == address(0) ? WETH : _tokenIn;
        _tokenOut = _tokenOut == address(0) ? WETH : _tokenOut;

        ICurveMetaRegistry curveMetaRegistry = ICurveMetaRegistry(controller.curveMetaRegistry());
        (uint8 tokenInType, uint8 tokenOutType, address _finalAssetIn, address _finalAssetOut) =
            tokenIdentifier.identifyTokens(_tokenIn, _tokenOut, curveMetaRegistry);

        // Comp assets
        uint256 exchangeRate;
        if (tokenInType == 1) {
            exchangeRate = getCompoundExchangeRate(_tokenIn, _finalAssetIn);
            return getPrice(_finalAssetIn, _tokenOut).preciseMul(exchangeRate);
        }
        if (tokenOutType == 1) {
            exchangeRate = getCompoundExchangeRate(_tokenOut, _finalAssetOut);
            return getPrice(_tokenIn, _finalAssetOut).preciseDiv(exchangeRate);
        }

        // aave tokens. 1 to 1 with underlying
        if (tokenInType == 2) {
            return getPrice(_finalAssetIn, _tokenOut);
        }

        if (tokenOutType == 2) {
            return getPrice(_tokenIn, _finalAssetOut);
        }

        // crTokens Cream prices 0xde19f5a7cF029275Be9cEC538E81Aa298E297266
        // cTkens use same interface as compound
        if (tokenInType == 3) {
            exchangeRate = getCreamExchangeRate(_tokenIn, _finalAssetIn);
            return getPrice(_finalAssetIn, _tokenOut).preciseMul(exchangeRate);
        }
        if (tokenOutType == 3) {
            exchangeRate = getCreamExchangeRate(_tokenOut, _finalAssetOut);
            return getPrice(_tokenIn, _finalAssetOut).preciseDiv(exchangeRate);
        }

        // Checks Synthetix
        if (tokenInType == 4) {
            address targetImpl = ISnxProxy(_tokenIn).target();
            exchangeRate = snxEchangeRates.rateForCurrency(ISnxSynth(targetImpl).currencyKey());
            return getPrice(USDC, _tokenOut).preciseMul(exchangeRate);
        }

        if (tokenOutType == 4) {
            address targetImpl = ISnxProxy(_tokenOut).target();
            exchangeRate = snxEchangeRates.rateForCurrency(ISnxSynth(targetImpl).currencyKey());
            return getPrice(_tokenIn, USDC).preciseDiv(exchangeRate);
        }

        if (tokenInType == 5) {
            address crvPool = curveMetaRegistry.getPoolFromLpToken(_tokenIn);
            if (crvPool != address(0)) {
                address denominator = _cleanCurvePoolDenominator(crvPool, curveMetaRegistry);
                return
                    curveMetaRegistry.getVirtualPriceFromLpToken(_tokenIn).preciseMul(getPrice(denominator, _tokenOut));
            }
        }

        if (tokenOutType == 5) {
            // Token out is a curve lp
            address crvPool = curveMetaRegistry.getPoolFromLpToken(_tokenOut);
            if (crvPool != address(0)) {
                address denominator = _cleanCurvePoolDenominator(crvPool, curveMetaRegistry);
                return
                    getPrice(_tokenIn, denominator).preciseDiv(curveMetaRegistry.getVirtualPriceFromLpToken(_tokenOut));
            }
        }
        // Yearn vaults
        if (tokenInType == 6) {
            price = IYearnVault(_tokenIn).pricePerShare().preciseMul(
                getPrice(IYearnVault(_tokenIn).token(), _tokenOut)
            );
            uint256 yvDecimals = ERC20(_tokenIn).decimals();
            if (yvDecimals < 18) {
                price = price.mul(10**(18 - yvDecimals));
            }
            return price;
        }

        if (tokenOutType == 6) {
            address vaultAsset = IYearnVault(_tokenOut).token();
            price = getPrice(_tokenIn, vaultAsset).preciseDiv(IYearnVault(_tokenOut).pricePerShare());

            uint256 yvDecimals = ERC20(_tokenOut).decimals();
            if (yvDecimals < 18) {
                price = price.div(10**(18 - yvDecimals));
            }
            return price;
        }

        // univ2 or sushi or mooniswap
        if (tokenInType == 8 || tokenInType == 9 || tokenInType == 10) {
            return _getPriceUniV2LpToken(_tokenIn, WETH).preciseMul(getPrice(WETH, _tokenOut));
        }
        if (tokenOutType == 8 || tokenOutType == 9 || tokenInType == 10) {
            return getPrice(_tokenIn, WETH).preciseDiv(_getPriceUniV2LpToken(_tokenOut, WETH));
        }

        // palstkaave (Curve cannot find otherwise weth-palstk)
        if (_tokenIn == palStkAAVE) {
            uint256 tokenInPrice = _getPriceThroughCurve(curvePalStkAave, palStkAAVE, AAVE, curveMetaRegistry);
            if (tokenInPrice != 0) {
                return tokenInPrice.preciseMul(_getBestPriceUniV3(AAVE, _tokenOut));
            }
        }

        if (_tokenOut == palStkAAVE) {
            uint256 tokenOutPrice = _getPriceThroughCurve(curvePalStkAave, AAVE, palStkAAVE, curveMetaRegistry);
            if (tokenOutPrice != 0) {
                return tokenOutPrice.preciseMul(_getBestPriceUniV3(_tokenIn, AAVE));
            }
        }

        // Direct curve pair
        price = _checkPairThroughCurve(_tokenIn, _tokenOut, curveMetaRegistry);
        if (price != 0) {
            return price;
        }

        // Direct UNI3
        price = _getBestPriceUniV3(_tokenIn, _tokenOut);
        if (price != 0) {
            return price;
        }

        // Curve to UniV3 or UniV3 to Curve via DAI/WETH/WBTC/USDC
        for (uint256 i = 0; i < hopTokensList.length; i++) {
            address reserve = hopTokensList[i];
            if (_tokenIn != reserve && _tokenOut != reserve) {
                uint256 tokenInPrice = _checkPairThroughCurve(_tokenIn, reserve, curveMetaRegistry);
                if (tokenInPrice != 0) {
                    return tokenInPrice.preciseMul(_getBestPriceUniV3(reserve, _tokenOut));
                }
                uint256 tokenOutPrice = _checkPairThroughCurve(reserve, _tokenOut, curveMetaRegistry);
                if (tokenOutPrice != 0) {
                    return tokenOutPrice.preciseMul(_getBestPriceUniV3(_tokenIn, reserve));
                }
            }
        }

        // Use only univ2 for UI
        if (_forNAV) {
            price = _getUNIV2Price(_tokenIn, _tokenOut);
        }
        // No valid price
        return price;
    }

    function _cleanCurvePoolDenominator(address _pool, ICurveMetaRegistry _curveMetaRegistry)
        internal
        view
        returns (address)
    {
        address[8] memory coins = _curveMetaRegistry.getCoinAddresses(_pool, true);
        if (coins[0] != address(0)) {
            return coins[0] == ETH_ADD_CURVE ? WETH : coins[0];
        }
        if (coins[1] != address(0)) {
            return coins[1] == ETH_ADD_CURVE ? WETH : coins[1];
        }
        if (coins[2] != address(0)) {
            return coins[2] == ETH_ADD_CURVE ? WETH : coins[2];
        }
        return address(0);
    }

    // Susceptible to flash loans.
    // Only use for UI and getNAV
    function _getUNIV2Price(address _tokenIn, address _tokenOut) private view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        return uniRouterV2.getAmountsOut(ERC20(_tokenIn).decimals(), path)[1];
    }

    function _getUNIV3Price(
        IUniswapV3Pool pool,
        address _tokenIn,
        address _tokenOut
    ) private view returns (uint256) {
        // Same asset. Returns base unit
        if (_tokenIn == _tokenOut) {
            return 10**18;
        }
        int24 tick;

        (, tick, , , , , ) = pool.slot0();
        if (!_checkPrice(tick, pool)) {
            return 0;
        }
        return
            OracleLibrary
                .getQuoteAtTick(
                tick,
                // because we use 1e18 as a precision unit
                uint128(uint256(1e18).mul(10**(uint256(18).sub(ERC20(_tokenOut).decimals())))),
                _tokenIn,
                _tokenOut
            )
                .div(10**(uint256(18).sub(ERC20(_tokenIn).decimals())));
    }

    function _getUniV3PriceNaive(address _tokenIn, address _tokenOut) private view returns (uint256) {
        // Same asset. Returns base unit
        if (_tokenIn == _tokenOut) {
            return 10**18;
        }
        IUniswapV3Pool pool = _getUniswapPoolWithHighestLiquidity(_tokenIn, _tokenOut);
        if (address(pool) == address(0)) {
            return 0;
        }
        return _getUNIV3Price(pool, _tokenIn, _tokenOut);
    }

    function _getBestPriceUniV3(address _tokenIn, address _tokenOut) private view returns (uint256) {
        uint256 price = 1e18;
        uint256 priceAux;
        address reservePathIn = _tokenIn;
        address reservePathOut = _tokenOut;
        // Go from token in to a reserve (choose best on the the highest liquidity in DAI)
        if (!hopTokens[_tokenIn]) {
            (reservePathIn, priceAux) = _getHighestLiquidityPathToReserveUniV3(_tokenIn, true);
            price = priceAux;
        }
        // Go from a reserve to token out (choose best on the the highest liquidity in DAI)
        if (!hopTokens[_tokenOut]) {
            (reservePathOut, priceAux) = _getHighestLiquidityPathToReserveUniV3(_tokenOut, false);
            // If reserves are different
            if (reservePathIn != reservePathOut) {
                price = price.preciseMul(_getUniV3PriceNaive(reservePathIn, reservePathOut));
            }
            // Multiply from out reserve path to out token
            return price.preciseMul(priceAux);
        }
        // If reserves are different
        if (reservePathIn != reservePathOut) {
            price = price.preciseMul(_getUniV3PriceNaive(reservePathIn, reservePathOut));
        }
        return price;
    }

    function _getHighestLiquidityPathToReserveUniV3(address _token, bool _in) private view returns (address, uint256) {
        uint256 price;
        address reserveChosen;
        IUniswapV3Pool maxpool;
        uint256 maxLiquidityInDai;
        for (uint256 i = 0; i < hopTokensList.length; i++) {
            (address pool, uint256 liquidityInDai) =
                _getUniswapHighestLiquidityInReserveAsset(_token, hopTokensList[i], DAI);
            if (liquidityInDai > maxLiquidityInDai) {
                maxpool = IUniswapV3Pool(pool);
                maxLiquidityInDai = liquidityInDai;
                reserveChosen = hopTokensList[i];
            }
        }
        if (maxLiquidityInDai > 0) {
            if (_in) {
                price = _getUNIV3Price(maxpool, _token, reserveChosen);
            } else {
                price = _getUNIV3Price(maxpool, reserveChosen, _token);
            }
        }
        return (reserveChosen, price);
    }

    function _getUniswapPoolWithHighestLiquidity(address sendToken, address receiveToken)
        private
        view
        returns (IUniswapV3Pool pool)
    {
        IUniswapV3Pool poolLow = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_LOW));
        IUniswapV3Pool poolMedium = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_MEDIUM));
        IUniswapV3Pool poolHigh = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_HIGH));

        uint128 liquidityLow = address(poolLow) != address(0) ? poolLow.liquidity() : 0;
        uint128 liquidityMedium = address(poolMedium) != address(0) ? poolMedium.liquidity() : 0;
        uint128 liquidityHigh = address(poolHigh) != address(0) ? poolHigh.liquidity() : 0;
        if (liquidityLow >= liquidityMedium && liquidityLow >= liquidityHigh) {
            return poolLow;
        }
        if (liquidityMedium >= liquidityLow && liquidityMedium >= liquidityHigh) {
            return poolMedium;
        }
        return poolHigh;
    }

    function _getUniswapHighestLiquidityInReserveAsset(
        address _sendToken,
        address _receiveToken,
        address _reserveAsset
    ) private view returns (address, uint256) {
        IUniswapV3Pool pool = _getUniswapPoolWithHighestLiquidity(_sendToken, _receiveToken);
        if (address(pool) == address(0)) {
            return (address(0), 0);
        }
        uint256 liquidityInReserve;
        address denominator;
        address token0 = pool.token0();
        address token1 = pool.token1();

        if (hopTokens[token0]) {
            liquidityInReserve = ERC20(token0).balanceOf(address(pool));
            denominator = token0;
        } else {
            liquidityInReserve = ERC20(token1).balanceOf(address(pool));
            denominator = token1;
        }
        // Normalize to reserve asset
        if (denominator != _reserveAsset) {
            uint256 price = _getUniV3PriceNaive(denominator, _reserveAsset);
            // price is always in 18 decimals
            // preciseMul returns in the same decimals than liquidityInReserve, so we have to normalize into reserve Asset decimals
            // normalization into reserveAsset decimals
            liquidityInReserve = SafeDecimalMath.normalizeAmountTokens(
                denominator,
                _reserveAsset,
                liquidityInReserve.preciseMul(price)
            );
        }
        return (address(pool), liquidityInReserve);
    }

    /// @dev Revert if current price is too close to min or max ticks allowed
    /// by Uniswap, or if it deviates too much from the TWAP. Should be called
    /// whenever base and limit ranges are updated. In practice, prices should
    /// only become this extreme if there's no liquidity in the Uniswap pool.
    function _checkPrice(int24 mid, IUniswapV3Pool _pool) private view returns (bool) {
        int24 tickSpacing = _pool.tickSpacing();
        // TODO: Add the other param from charm
        if (mid < TickMath.MIN_TICK + baseThreshold + tickSpacing) {
            // "price too low"
            return false;
        }
        if (mid > TickMath.MAX_TICK - baseThreshold - tickSpacing) {
            // "price too high"
            return false;
        }

        // Check TWAP deviation. This check prevents price manipulation before
        // the rebalance and also avoids rebalancing when price has just spiked.
        int56 twap = _getTwap(_pool);

        int56 deviation = mid > twap ? mid - twap : twap - mid;
        // Fail twap check
        return deviation < maxTwapDeviation;
    }

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    function _getTwap(IUniswapV3Pool _pool) private view returns (int56 twap) {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = SECONDS_GRANULARITY;
        secondsAgo[1] = 0;
        // observe fails if the pair has no observations
        try _pool.observe(secondsAgo) returns (
            int56[] memory tickCumulatives,
            uint160[] memory /* secondsPerLiquidityCumulativeX128s */
        ) {
            return (tickCumulatives[1] - tickCumulatives[0]) / SECONDS_GRANULARITY;
        } catch {
            return 0;
        }
    }

    function _getPriceThroughCurve(
        address _curvePool,
        address _tokenIn,
        address _tokenOut,
        ICurveMetaRegistry _curveMetaRegistry
    ) private view returns (uint256) {
        (uint256 i, uint256 j, bool underlying) = _curveMetaRegistry.getCoinIndices(_curvePool, _tokenIn, _tokenOut);
        uint256 price = 0;
        uint256 decimalsIn = 10**(_tokenIn == ETH_ADD_CURVE ? 18 : ERC20(_tokenIn).decimals());
        if (underlying) {
            price = _getCurveDYUnderlying(_curvePool, i, j, decimalsIn);
        } else {
            price = _getCurveDY(_curvePool, i, j, decimalsIn);
        }
        price = price.mul(10**(18 - (_tokenOut == ETH_ADD_CURVE ? 18 : ERC20(_tokenOut).decimals())));
        uint256 delta = price.preciseMul(CURVE_SLIPPAGE);
        if (price < uint256(1e18).add(delta) && price > uint256(1e18).sub(delta)) {
            return price;
        }
        return 0;
    }

    function _getCurveDY(
        address _curvePool,
        uint256 i,
        uint256 j,
        uint256 decimals
    ) private view returns (uint256) {
        try ICurvePoolV3DY(_curvePool).get_dy(i, j, decimals) returns (uint256 price) {
            return price;
        } catch {
            try ICurvePoolV3(_curvePool).get_dy(int128(i), int128(j), decimals) returns (uint256 price2) {
                return price2;
            } catch {
                revert('get dy failed');
            }
        }
    }

    /**
     * Calculates the value of a univ2 lp token or sushi in denominator asset
     * @param _pool                      Address of the univ2 style lp token
     * @param _denominator               Address of the denominator asset
     */
    function _getPriceUniV2LpToken(address _pool, address _denominator) internal view returns (uint256) {
        address[] memory poolTokens = new address[](2);
        poolTokens[0] = IUniswapV2Pair(_pool).token0();
        poolTokens[1] = IUniswapV2Pair(_pool).token1();
        ERC20 lpToken = ERC20(_pool);
        uint256 result = 0;
        for (uint256 i = 0; i < poolTokens.length; i++) {
            address asset = _isETH(poolTokens[i]) ? WETH : poolTokens[i];
            uint256 price = getPrice(_denominator, asset);
            uint256 balance = !_isETH(poolTokens[i]) ? ERC20(poolTokens[i]).balanceOf(_pool) : _pool.balance;
            // Special case for weth in some pools
            if (poolTokens[i] == WETH && balance == 0) {
                balance = _pool.balance;
            }
            if (price != 0 && balance != 0) {
                result = result.add(
                    SafeDecimalMath.normalizeAmountTokens(
                        asset,
                        _denominator,
                        balance.preciseDiv(lpToken.totalSupply()).preciseDiv(price)
                    )
                );
            }
        }
        return result;
    }

    function _getCurveDYUnderlying(
        address _curvePool,
        uint256 i,
        uint256 j,
        uint256 decimals
    ) private view returns (uint256) {
        try ICurvePoolV3DY(_curvePool).get_dy_underlying(i, j, decimals) returns (uint256 price) {
            return price;
        } catch {
            try ICurvePoolV3(_curvePool).get_dy_underlying(int128(i), int128(j), decimals) returns (uint256 price2) {
                return price2;
            } catch {
                try ICurvePoolV3(_curvePool).get_dy(int128(i), int128(j), decimals) returns (uint256 price3) {
                    return price3;
                } catch {
                    revert('get dy underlying failed');
                }
            }
        }
    }

    function _checkPairThroughCurve(
        address _tokenIn,
        address _tokenOut,
        ICurveMetaRegistry _curveMetaRegistry
    ) private view returns (uint256) {
        address curvePool = _curveMetaRegistry.findPoolForCoins(_tokenIn, _tokenOut, 0);
        if (_tokenIn == WETH && curvePool == address(0)) {
            _tokenIn = ETH_ADD_CURVE;
            curvePool = _curveMetaRegistry.findPoolForCoins(ETH_ADD_CURVE, _tokenOut, 0);
        }
        if (_tokenOut == WETH && curvePool == address(0)) {
            _tokenOut = ETH_ADD_CURVE;
            curvePool = _curveMetaRegistry.findPoolForCoins(_tokenIn, ETH_ADD_CURVE, 0);
        }
        if (curvePool != address(0)) {
            uint256 price = _getPriceThroughCurve(curvePool, _tokenIn, _tokenOut, _curveMetaRegistry);
            return price;
        }
        return 0;
    }

    function _updateReserves(address[] memory list) private {
        for (uint256 i = 0; i < hopTokensList.length; i++) {
            hopTokens[hopTokensList[i]] = false;
        }
        delete hopTokensList;
        for (uint256 i = 0; i < list.length; i++) {
            hopTokens[list[i]] = true;
            hopTokensList.push(list[i]);
        }
    }

    function _isETH(address _address) internal pure returns (bool) {
        return _address == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE || _address == address(0);
    }
}
