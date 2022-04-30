// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {TradesIterator, NumbersIterator} from '../../interfaces/IOperation.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy, TradeInfo, TradeProtocol} from '../../interfaces/IStrategy.sol';
import {IPoolIntegration} from '../../interfaces/IPoolIntegration.sol';

import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {UniversalERC20} from '../../lib/UniversalERC20.sol';
import {NumberIteratorLib} from '../../lib/NumberIteratorLib.sol';
import {TradeIteratorLib} from '../../lib/TradeIteratorLib.sol';

import {Operation} from './Operation.sol';

/**
 * @title AddLiquidityOperation
 * @author Babylon Finance
 *
 * Executes an add liquidity operation
 */
contract AddLiquidityOperation is Operation {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;
    using BytesLib for bytes;
    using UniversalERC20 for IERC20;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _controller) Operation(_name, _controller) {}

    /**
     * Sets operation data for the add liquidity operation
     *
     * @param _data                   Operation data
     */
    function validateOperation(
        bytes calldata _data,
        IGarden, /* _garden */
        address _integration,
        uint256 /* _index */
    ) external view override onlyStrategy {
        require(IPoolIntegration(_integration).isPool(_data), 'Not a valid pool');
    }

    /**
     * Executes the add liquidity operation
     */
    function executeOperation(
        Args memory _args,
        NumbersIterator memory _pricesIterator,
        TradesIterator memory _tradesIterator
    )
        external
        override
        onlyStrategy
        returns (ExecRet memory ret)
    {
        Args memory args = _args;
        address[] memory poolTokens =
            IPoolIntegration(args.integration).getPoolTokens(args.data, false);
        uint256[] memory poolWeights =
            IPoolIntegration(args.integration).getPoolWeights(args.data);
        // if the weights need to be adjusted by price, do so
        try IPoolIntegration(args.integration).poolWeightsByPrice(args.data) returns (bool priceWeights) {
            if (priceWeights) {
                uint256 poolTotal = 0;
                for (uint256 i = 0; i < poolTokens.length; i++) {
                    poolWeights[i] = SafeDecimalMath.normalizeAmountTokens(
                        poolTokens[i],
                        poolTokens[poolTokens.length - 1],
                        poolWeights[i].preciseMul(_getPrice(poolTokens[i], poolTokens[poolTokens.length - 1]))
                    );
                    poolTotal = poolTotal.add(poolWeights[i]);
                }
                for (uint256 i = 0; i < poolTokens.length; i++) {
                    poolWeights[i] = poolWeights[i].mul(1e18).div(poolTotal);
                }
            }
        } catch {}
// Get the tokens needed to enter the pool
        uint256[] memory maxAmountsIn = _maxAmountsIn(args.asset, args.capital,
                                                      args.garden, poolWeights, poolTokens);
        uint256 poolTokensOut =
            IPoolIntegration(args.integration).getPoolTokensOut(args.data, poolTokens[0], maxAmountsIn[0]);
        IPoolIntegration(args.integration).joinPool(
            msg.sender,
            args.data,
            poolTokensOut.sub(poolTokensOut.preciseMul(SLIPPAGE_ALLOWED)),
            poolTokens,
            maxAmountsIn
        );
        ret.assetAccumulated = IPoolIntegration(args.integration).getLPToken(BytesLib.decodeOpDataAddress(args.data));
        ret.amountOut = IERC20(ret.assetAccumulated).balanceOf(msg.sender);
        ret.assetStatus = 0;
        ret.pricesCounter =  _pricesIterator.counter;
        ret.tradesCounter =  _tradesIterator.counter;
    }

    /**
     * Exits the add liquidity operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        address, /* _asset */
        uint256, /* _remaining */
        uint8, /* _assetStatus */
        uint256 _percentage,
        bytes calldata _data,
        IGarden, /* _garden */
        address _integration
    )
        external
        override
        onlyStrategy
        returns (
            address,
            uint256,
            uint8
        )
    {
        require(_percentage <= 1e18, 'Unwind Percentage <= 100%');
        address pool = BytesLib.decodeOpDataAddress(_data);
        address[] memory poolTokens = IPoolIntegration(_integration).getPoolTokens(_data, false);
        uint256 lpTokens =
            IERC20(IPoolIntegration(_integration).getLPToken(pool)).universalBalanceOf(msg.sender).preciseMul(
                _percentage
            ); // Sell all pool tokens
        uint256[] memory _minAmountsOut = IPoolIntegration(_integration).getPoolMinAmountsOut(_data, lpTokens);
        IPoolIntegration(_integration).exitPool(
            msg.sender,
            _data,
            lpTokens, // Sell all pool tokens
            poolTokens,
            _minAmountsOut
        );
        // Exit Pool tokens to a consolidated asset
        address reserveAsset = WETH;
        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (poolTokens[i] != reserveAsset) {
                if (_isETH(poolTokens[i]) && address(msg.sender).balance > MIN_TRADE_AMOUNT) {
                    IStrategy(msg.sender).trade(
                        poolTokens[i],
                        address(msg.sender).balance,
                        reserveAsset,
                        0,
                        TradeIteratorLib.none()
                    );
                    poolTokens[i] = WETH;
                }
                if (poolTokens[i] != reserveAsset) {
                    if (IERC20(poolTokens[i]).universalBalanceOf(msg.sender) > MIN_TRADE_AMOUNT) {
                        IStrategy(msg.sender).trade(
                            poolTokens[i],
                            IERC20(poolTokens[i]).universalBalanceOf(msg.sender),
                            reserveAsset,
                            0,
                            TradeIteratorLib.none()
                        );
                    }
                }
            }
        }
        // Only claim and sell rewards on final exit
        if (_percentage == HUNDRED_PERCENT) {
            _sellRewardTokens(_integration, _data, reserveAsset);
        }
        // BUG: Should respect percentage and not return all the capital
        return (reserveAsset, IERC20(reserveAsset).universalBalanceOf(msg.sender), 0);
    }

    /**
     * Gets the NAV of the add liquidity op in the reserve asset
     *
     * @param _data               OpData e.g. PoolId or asset address
     * @param _garden             Garden the strategy belongs to
     * @param _integration        Status of the asset amount
     * @return _nav               NAV of the strategy
     */
    function getNAV(
        bytes calldata _data,
        IGarden _garden,
        address _integration
    ) external view override returns (uint256, bool) {
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return (0, true);
        }
        address pool = BytesLib.decodeOpDataAddress(_data); // 64 bytes (w/o signature prefix bytes4)
        pool = IPoolIntegration(_integration).getPool(pool);
        IERC20 lpToken = IERC20(IPoolIntegration(_integration).getLPToken(pool));
        // Get price multiplier if needed (harvestv3)
        uint256 price = _getPrice(address(lpToken), _garden.reserveAsset());
        require(price != 0, 'Could not price lp token');
        uint256 NAV =
            SafeDecimalMath.normalizeAmountTokens(
                address(lpToken),
                _garden.reserveAsset(),
                lpToken.balanceOf(msg.sender).preciseMul(price)
            );
        // get rewards if hanging around
        try IPoolIntegration(_integration).getRewardTokens(_data) returns (address[] memory rewards) {
            for (uint256 i = 0; i < rewards.length; i++) {
                if (rewards[i] != address(0) && IERC20(rewards[i]).universalBalanceOf(msg.sender) > MIN_TRADE_AMOUNT) {
                    price = _getPrice(_garden.reserveAsset(), rewards[i]);
                    if (price > 0) {
                        NAV += SafeDecimalMath.normalizeAmountTokens(
                            rewards[i],
                            _garden.reserveAsset(),
                            IERC20(rewards[i]).universalBalanceOf(msg.sender)
                        );
                    }
                }
            }
        } catch {}
        require(NAV != 0, 'NAV has to be bigger 0');
        return (NAV, true);
    }

    /* ============ Private Functions ============ */

    function _getMaxAmountTokenPool(
        address _asset,
        uint256 _capital,
        IGarden, /* _garden */
        uint256 _poolWeight,
        address _poolToken
    ) private returns (uint256) {
        uint256 normalizedAssetAmount = _capital.preciseMul(_poolWeight);
        uint256 price = _getPrice(_asset, _isETH(_poolToken) ? WETH : _poolToken);
        uint256 normalizedTokenAmount =
            SafeDecimalMath.normalizeAmountTokens(_asset, _poolToken, normalizedAssetAmount.preciseMul(price));
        if (_poolToken != _asset) {
            return
                IStrategy(msg.sender).trade(
                    _asset,
                    normalizedAssetAmount,
                    _poolToken,
                    0,
                    TradeIteratorLib.none()
                );
        }
        // Reserve asset
        uint256 reserveBalance = IERC20(_poolToken).universalBalanceOf(msg.sender);
        return normalizedTokenAmount <= reserveBalance ? normalizedTokenAmount : reserveBalance;
    }

    function _maxAmountsIn(
        address _asset,
        uint256 _capital,
        IGarden _garden,
        uint256[] memory _poolWeights,
        address[] memory poolTokens
    ) internal returns (uint256[] memory) {
        uint256[] memory maxAmountsIn = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (_poolWeights[i] > 0) {
                maxAmountsIn[i] = _getMaxAmountTokenPool(_asset, _capital, _garden, _poolWeights[i], poolTokens[i]);
            }
        }
        return maxAmountsIn;
    }

    function _joinPool(
        address _asset,
        uint256 _capital,
        bytes memory _data,
        IGarden _garden,
        address _integration,
        uint256[] memory _poolWeights,
        address[] memory _poolTokens
    )
        internal
        returns (
            address,
            uint256,
            uint8
        )
    {
        
    }

    // TODO: Make a lib helper
    function _isETH(address _address) internal pure returns (bool) {
        return _address == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE || _address == address(0);
    }

    /**
     * Sells the reward tokens obtained.
     * @param _integration                    Address of the integration
     * @param _data                           Calldata
     * @param _reserveAsset                   Reserve Asset
     */
    function _sellRewardTokens(
        address _integration,
        bytes calldata _data,
        address _reserveAsset
    ) internal {
        try IPoolIntegration(_integration).getRewardTokens(_data) returns (address[] memory rewards) {
            for (uint256 i = 0; i < rewards.length; i++) {
                if (rewards[i] != address(0) && IERC20(rewards[i]).universalBalanceOf(msg.sender) > MIN_TRADE_AMOUNT) {
                    try
                        IStrategy(msg.sender).trade(
                            rewards[i],
                            IERC20(rewards[i]).universalBalanceOf(msg.sender),
                            _reserveAsset,
                            70e15
                        )
                    {} catch {}
                }
            }
        } catch {}
    }
}
