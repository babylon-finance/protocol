/*
    Copyright 2021 Babylon Finance

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.7.6;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol';

import {IBabController} from './interfaces/IBabController.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {ICToken} from './interfaces/external/compound/ICToken.sol';
import {ITokenIdentifier} from './interfaces/ITokenIdentifier.sol';
import {ISnxExchangeRates} from './interfaces/external/synthetix/ISnxExchangeRates.sol';
import {ICurveAddressProvider} from './interfaces/external/curve/ICurveAddressProvider.sol';
import {ICurveRegistry} from './interfaces/external/curve/ICurveRegistry.sol';
import {ICurvePoolV3} from './interfaces/external/curve/ICurvePoolV3.sol';
import {IPriceTri} from './interfaces/external/curve/IPriceTri.sol';
import {IUniswapV2Router} from './interfaces/external/uniswap/IUniswapV2Router.sol';
import {ISnxSynth} from './interfaces/external/synthetix/ISnxSynth.sol';
import {ISnxProxy} from './interfaces/external/synthetix/ISnxProxy.sol';
import {IYearnRegistry} from './interfaces/external/yearn/IYearnRegistry.sol';
import {IYearnVault} from './interfaces/external/yearn/IYearnVault.sol';
import {IStETH} from './interfaces/external/lido/IStETH.sol';
import {IWstETH} from './interfaces/external/lido/IWstETH.sol';

import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from './lib/SafeDecimalMath.sol';
import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';

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

    /* ============ Constants ============ */

    // Address of Uniswap factory
    IUniswapV3Factory internal constant factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    ISnxExchangeRates internal constant snxEchangeRates = ISnxExchangeRates(0xd69b189020EF614796578AfE4d10378c5e7e1138);
    // Address of Curve Registry
    ICurveAddressProvider internal constant curveAddressProvider =
        ICurveAddressProvider(0x0000000022D53366457F9d5E68Ec105046FC4383);
    IUniswapV2Router internal constant uniRouterV2 = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IYearnRegistry private constant yearnRegistry = IYearnRegistry(0xE15461B18EE31b7379019Dc523231C57d1Cbc18c);

    address internal constant ETH_ADD_CURVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant BABL = 0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    IStETH private constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH private constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address private constant TRI_CURVE_POOL_2_LP = 0xc4AD29ba4B3c580e6D59105FFf484999997675Ff;

    // the desired seconds agos array passed to the observe method
    uint32 private constant SECONDS_GRANULARITY = 30;
    uint256 private constant CURVE_SLIPPAGE = 6e16;

    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;
    uint24 private constant FEE_HIGH = 10000;
    int24 private constant baseThreshold = 1000;
    int24 private constant INITIAL_TWAP_DEVIATION = 300;

    /* ============ State Variables ============ */

    ITokenIdentifier public tokenIdentifier;
    IBabController public controller;
    mapping(address => bool) public reserveAssets;
    address[] public reserveAssetsList;
    mapping(address => bool) public blackListReserveForOracle;
    int24 private maxTwapDeviation;

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyGovernanceOrEmergency {
        require(
            msg.sender == controller.owner() || msg.sender == controller.EMERGENCY_OWNER(),
            'Not enough privileges'
        );
        _;
    }

    /* ============ Constructor ============ */

    constructor(ITokenIdentifier _tokenIdentifier, IBabController _controller) {
        tokenIdentifier = _tokenIdentifier;
        controller = _controller;
        maxTwapDeviation = INITIAL_TWAP_DEVIATION;
        // Blacklist babl as an oracle reserve
        blackListReserveForOracle[BABL] = true;
        _updateReserves();
    }

    /* ============ External Functions ============ */

    function updateTokenIdentifier(ITokenIdentifier _tokenIdentifier) public override onlyGovernanceOrEmergency {
        require(address(_tokenIdentifier) != address(0), 'Address needs to exist');
        tokenIdentifier = _tokenIdentifier;
    }

    function updateMaxTwapDeviation(int24 _maxTwapDeviation) public override onlyGovernanceOrEmergency {
        require(_maxTwapDeviation < 1500, 'Max twap deviation must be within range');
        maxTwapDeviation = _maxTwapDeviation;
    }

    function updateReserves() public override {
        require(address(controller) == msg.sender, 'Only controller can call this');
        _updateReserves();
    }

    function updateOracleReserveBlackList(address _reserveOracle, bool _value)
        public
        override
        onlyGovernanceOrEmergency
    {
        require(reserveAssets[_reserveOracle], 'Must be a reserve asset');
        blackListReserveForOracle[_reserveOracle] = _value;
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
        uint256 exchangeRate;
        (uint8 tokenInType, uint8 tokenOutType, address _finalAssetIn, address _finalAssetOut) =
            tokenIdentifier.identifyTokens(_tokenIn, _tokenOut);
        // Comp assets
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

        // Checks synthetix
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

        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        // Direct curve pair
        price = _checkPairThroughCurve(_tokenIn, _tokenOut);
        if (price != 0) {
            return price;
        }

        // Curve LP tokens
        if (tokenInType == 5) {
            if (_tokenIn != TRI_CURVE_POOL_2_LP) {
                address crvPool = curveRegistry.get_pool_from_lp_token(_tokenIn);
                if (crvPool != address(0)) {
                    address denominator = _cleanCurvePoolDenominator(crvPool, curveRegistry);
                    return
                        curveRegistry.get_virtual_price_from_lp_token(_tokenIn).preciseMul(
                            getPrice(denominator, _tokenOut)
                        );
                }
            } else {
                // TRI2
                return
                    IPriceTri(0xE8b2989276E2Ca8FDEA2268E3551b2b4B2418950).lp_price().preciseMul(
                        getPrice(DAI, _tokenOut)
                    );
            }
        }
        if (tokenOutType == 5) {
            // Token out is a curve lp
            if (_tokenOut != TRI_CURVE_POOL_2_LP) {
                address crvPool = curveRegistry.get_pool_from_lp_token(_tokenOut);
                if (crvPool != address(0)) {
                    address denominator = _cleanCurvePoolDenominator(crvPool, curveRegistry);
                    return
                        getPrice(_tokenIn, denominator).preciseDiv(
                            curveRegistry.get_virtual_price_from_lp_token(_tokenOut)
                        );
                }
            } else {
                // TRI2
                return
                    getPrice(_tokenIn, DAI).preciseDiv(
                        IPriceTri(0xE8b2989276E2Ca8FDEA2268E3551b2b4B2418950).lp_price()
                    );
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

        // Curve pair through Curve Assets (DAI, WETH, USDC, WBTC)
        for (uint256 i = 0; i < reserveAssetsList.length; i++) {
            address reserve = reserveAssetsList[i];
            if (_tokenIn != reserve && _tokenOut != reserve) {
                uint256 tokenInPrice = _checkPairThroughCurve(_tokenIn, reserve);
                uint256 tokenOutPrice = _checkPairThroughCurve(reserve, _tokenOut);
                if (tokenInPrice != 0 || tokenOutPrice != 0) {
                    if (tokenInPrice == 0) {
                        tokenInPrice = _getUniV3PriceNaive(_tokenIn, reserve);
                    }
                    if (tokenOutPrice == 0) {
                        tokenOutPrice = _getUniV3PriceNaive(reserve, _tokenOut);
                    }
                    price = tokenInPrice.preciseMul(tokenOutPrice);
                    if (price != 0) {
                        return price;
                    }
                }
            }
        }
        // Checks stETH && wstETH (Lido tokens)
        if (tokenInType == 7) {
            uint256 shares = 1e18;
            if (_tokenIn == address(wstETH)) {
                shares = wstETH.getStETHByWstETH(shares);
            }
            return getPrice(WETH, _tokenOut).preciseMul(stETH.getPooledEthByShares(shares));
        }
        if (tokenOutType == 7) {
            uint256 shares = 1e18;
            if (_tokenOut == address(wstETH)) {
                shares = wstETH.getStETHByWstETH(shares);
            }
            return getPrice(_tokenIn, WETH).preciseDiv(stETH.getSharesByPooledEth(shares));
        }
        // Direct UNI3
        price = _getBestPriceUniV3(_tokenIn, _tokenOut);
        if (price != 0) {
            return price;
        }
        // Use only univ2 for UI
        if (_forNAV) {
            price = _getUNIV2Price(_tokenIn, _tokenOut);
        }
        // No valid price
        return price;
    }

    function _cleanCurvePoolDenominator(address _pool, ICurveRegistry _curveRegistry) internal view returns (address) {
        address[8] memory coins = _curveRegistry.get_underlying_coins(_pool);
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
        if (!_isOracleReserve(_tokenIn)) {
            (reservePathIn, priceAux) = _getHighestLiquidityPathToReserveUniV3(_tokenIn, true);
            price = priceAux;
        }
        // Go from a reserve to token out (choose best on the the highest liquidity in DAI)
        if (!_isOracleReserve(_tokenOut)) {
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
        uint256 price = 0;
        address reserveChosen;
        IUniswapV3Pool maxpool;
        uint256 maxLiquidityInDai;
        for (uint256 i = 0; i < reserveAssetsList.length; i++) {
            (address pool, uint256 liquidityInDai) =
                _getUniswapHighestLiquidityInReserveAsset(_token, reserveAssetsList[i], DAI);
            if (liquidityInDai > maxLiquidityInDai) {
                maxpool = IUniswapV3Pool(pool);
                maxLiquidityInDai = liquidityInDai;
                reserveChosen = reserveAssetsList[i];
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
        uint256 poolLiquidity = uint256(pool.liquidity());
        uint256 liquidityInReserve;
        address denominator;
        address token0 = pool.token0();
        address token1 = pool.token1();

        if (_isOracleReserve(token0)) {
            liquidityInReserve = poolLiquidity.mul(poolLiquidity).div(ERC20(token1).balanceOf(address(pool)));
            denominator = token0;
        } else {
            liquidityInReserve = poolLiquidity.mul(poolLiquidity).div(ERC20(token0).balanceOf(address(pool)));
            denominator = token1;
        }
        // Normalize to reserve asset
        if (denominator != _reserveAsset) {
            uint256 price = getPrice(denominator, _reserveAsset);
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
        address _tokenOut
    ) private view returns (uint256) {
        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        (int128 i, int128 j, bool underlying) = curveRegistry.get_coin_indices(_curvePool, _tokenIn, _tokenOut);
        uint256 price = 0;
        if (
            _curvePool == 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46 ||
            _curvePool == 0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5
        ) {
            price = ICurvePoolV3(_curvePool).get_dy(
                uint256(i),
                uint256(j),
                10**(_tokenIn == ETH_ADD_CURVE ? 18 : ERC20(_tokenIn).decimals())
            );
        } else {
            if (underlying) {
                price = ICurvePoolV3(_curvePool).get_dy_underlying(
                    i,
                    j,
                    10**(_tokenIn == ETH_ADD_CURVE ? 18 : ERC20(_tokenIn).decimals())
                );
            } else {
                price = ICurvePoolV3(_curvePool).get_dy(
                    i,
                    j,
                    10**(_tokenIn == ETH_ADD_CURVE ? 18 : ERC20(_tokenIn).decimals())
                );
            }
        }
        price = price.mul(10**(18 - (_tokenOut == ETH_ADD_CURVE ? 18 : ERC20(_tokenOut).decimals())));
        uint256 delta = price.preciseMul(CURVE_SLIPPAGE);
        if (price < uint256(1e18).add(delta) && price > uint256(1e18).sub(delta)) {
            return price;
        }
        return 0;
    }

    function _checkPairThroughCurve(address _tokenIn, address _tokenOut) private view returns (uint256) {
        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        address curvePool = curveRegistry.find_pool_for_coins(_tokenIn, _tokenOut);
        if (_tokenIn == WETH && curvePool == address(0)) {
            _tokenIn = ETH_ADD_CURVE;
            curvePool = curveRegistry.find_pool_for_coins(ETH_ADD_CURVE, _tokenOut);
        }
        if (_tokenOut == WETH && curvePool == address(0)) {
            _tokenOut = ETH_ADD_CURVE;
            curvePool = curveRegistry.find_pool_for_coins(_tokenIn, ETH_ADD_CURVE);
        }
        if (curvePool != address(0)) {
            uint256 price = _getPriceThroughCurve(curvePool, _tokenIn, _tokenOut);
            return price;
        }
        return 0;
    }

    function _updateReserves() private {
        address[] memory reserveAssetsC = IBabController(controller).getReserveAssets();
        delete reserveAssetsList;
        for (uint256 i = 0; i < reserveAssetsC.length; i++) {
            reserveAssets[reserveAssetsC[i]] = true;
            reserveAssetsList.push(reserveAssetsC[i]);
        }
    }

    function _isOracleReserve(address _reserve) private view returns (bool) {
        return reserveAssets[_reserve] && !blackListReserveForOracle[_reserve];
    }
}
