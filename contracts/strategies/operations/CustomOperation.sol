// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {UniversalERC20} from '../../lib/UniversalERC20.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';

import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {ICustomIntegration} from '../../interfaces/ICustomIntegration.sol';

import {Operation} from './Operation.sol';

/**
 * @title CustomOperation
 * @author Babylon Finance
 *
 * Executes a custom operation
 */
contract CustomOperation is Operation {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;
    using BytesLib for bytes;
    using UniversalERC20 for IERC20;

    /* ============ Constructor ============ */

    /**
     * Creates the operation
     *
     * @param _name                   Name of the operation
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _controller) Operation(_name, _controller) {}

    /**
     * Sets operation data for the custom operation
     *
     * @param _data                   Operation data
     */
    function validateOperation(
        bytes calldata _data,
        IGarden _garden,
        address _integration,
        uint256 /* _index */
    ) external view override onlyStrategy {
        require(_garden.customIntegrationsEnabled(), 'Custom integrations are not allowed in this garden');
        require(ICustomIntegration(_integration).isValid(_data), 'Not valid data');
    }

    /**
     * Executes the custom operation
     * @param _asset              Asset to receive into this operation
     * @param _capital            Amount of asset received
     * param _assetStatus         Status of the asset amount
     * @param _data               OpData e.g. Address of the pool to enter
     * @param _garden             Garden of the strategy
     * @param _integration        Address of the integration to execute
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8, /* _assetStatus */
        bytes calldata _data,
        IGarden _garden,
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
        (address[] memory _inputTokens, uint256[] memory _inputWeights) =
            ICustomIntegration(_integration).getInputTokensAndWeights(_data);
        // Get the tokens needed to enter the operation
        uint256[] memory maxAmountsIn = _tradeInputTokens(_asset, _capital, _garden, _inputWeights, _inputTokens);
        uint256 priceResultToken = _getPriceOrCustom(_integration, _data, _garden.reserveAsset());
        ICustomIntegration(_integration).enter(
            msg.sender,
            _data,
            1, // TODO: fix
            _inputTokens,
            maxAmountsIn
        );
        // Check that the NAV is same to capital deposited
        return (
            _getResultTokenFromBytes(_integration, _data),
            IERC20(_getResultTokenFromBytes(_integration, _data)).balanceOf(msg.sender),
            0
        );
    }

    /**
     * Exits the custom operation.
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
        address tokenToExit = _getResultTokenFromBytes(_integration, _data);
        uint256 amountExit = IERC20(tokenToExit).balanceOf(msg.sender).preciseMul(_percentage);
        (address[] memory exitTokens, uint256[] memory _minAmountsOut) =
            ICustomIntegration(_integration).getOutputTokensAndMinAmountOut(_data, amountExit);
        ICustomIntegration(_integration).exit(msg.sender, _data, amountExit, exitTokens, _minAmountsOut);
        // Exit result tokens to a consolidated asset
        address reserveAsset = WETH;
        for (uint256 i = 0; i < exitTokens.length; i++) {
            if (exitTokens[i] != reserveAsset) {
                if (IERC20(exitTokens[i]).isETH() && address(msg.sender).balance > MIN_TRADE_AMOUNT) {
                    IStrategy(msg.sender).handleWeth(true, address(msg.sender).balance);
                    exitTokens[i] = WETH;
                }
                if (exitTokens[i] != reserveAsset) {
                    if (IERC20(exitTokens[i]).balanceOf(msg.sender) > MIN_TRADE_AMOUNT) {
                        IStrategy(msg.sender).trade(
                            exitTokens[i],
                            IERC20(exitTokens[i]).balanceOf(msg.sender),
                            reserveAsset
                        );
                    }
                }
            }
        }
        // Only claim and sell rewards on final exit
        if (_percentage == HUNDRED_PERCENT) {
            _sellRewardTokens(_integration, _data, reserveAsset);
        }
        return (reserveAsset, IERC20(reserveAsset).balanceOf(msg.sender), 0);
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
    ) public view override returns (uint256, bool) {
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return (0, true);
        }
        IERC20 resultToken = IERC20(_getResultTokenFromBytes(_integration, _data));
        uint256 price = _getPriceOrCustom(_integration, _data, _garden.reserveAsset());
        require(price != 0, 'Could not price result token');
        uint256 NAV =
            SafeDecimalMath.normalizeAmountTokens(
                address(resultToken),
                _garden.reserveAsset(),
                resultToken.balanceOf(msg.sender).preciseMul(price)
            );
        // get rewards if hanging around
        try ICustomIntegration(_integration).getRewardTokens(_data) returns (address[] memory rewards) {
            for (uint256 i = 0; i < rewards.length; i++) {
                if (rewards[i] != address(0) && IERC20(rewards[i]).balanceOf(msg.sender) > MIN_TRADE_AMOUNT) {
                    price = _getPrice(_garden.reserveAsset(), rewards[i]);
                    if (price > 0) {
                        NAV = NAV.add(
                            SafeDecimalMath.normalizeAmountTokens(
                                rewards[i],
                                _garden.reserveAsset(),
                                IERC20(rewards[i]).balanceOf(msg.sender)
                            )
                        );
                    }
                }
            }
        } catch {}
        require(NAV != 0, 'NAV has to be bigger 0');
        return (NAV, true);
    }

    /* ============ Private Functions ============ */

    function _getResultTokenFromBytes(address _integration, bytes calldata _data) internal view returns (address) {
        return ICustomIntegration(_integration).getResultToken(BytesLib.decodeOpDataAddress(_data));
    }

    function _getMaxAmountTokenInput(
        address _asset,
        uint256 _capital,
        IGarden, /* _garden */
        uint256 _inputWeight,
        address _inputToken
    ) private returns (uint256) {
        uint256 normalizedAssetAmount = _capital.preciseMul(_inputWeight);
        uint256 price = _getPrice(_asset, IERC20(_inputToken).isETH() ? WETH : _inputToken);
        uint256 normalizedTokenAmount =
            SafeDecimalMath.normalizeAmountTokens(_asset, _inputToken, normalizedAssetAmount.preciseMul(price));
        if (_inputToken != _asset && !IERC20(_inputToken).isETH()) {
            IStrategy(msg.sender).trade(_asset, normalizedAssetAmount, _inputToken);
            normalizedTokenAmount = normalizedTokenAmount <= IERC20(_inputToken).balanceOf(msg.sender)
                ? normalizedTokenAmount
                : IERC20(_inputToken).balanceOf(msg.sender);
            return normalizedTokenAmount;
        }
        if (IERC20(_inputToken).isETH()) {
            if (_asset != WETH) {
                IStrategy(msg.sender).trade(_asset, normalizedAssetAmount, WETH); // normalized amount in original asset decimals
            }
            // Convert WETH to ETH
            // We consider the slippage in the trade
            normalizedTokenAmount = normalizedTokenAmount <= IERC20(WETH).balanceOf(msg.sender)
                ? normalizedTokenAmount
                : IERC20(WETH).balanceOf(msg.sender);
            IStrategy(msg.sender).handleWeth(false, normalizedTokenAmount); // normalized WETH/ETH amount with 18 decimals
        } else {
            // Reserve asset
            normalizedTokenAmount = normalizedTokenAmount <= IERC20(_inputToken).balanceOf(msg.sender)
                ? normalizedTokenAmount
                : IERC20(_inputToken).balanceOf(msg.sender);
        }
        return normalizedTokenAmount;
    }

    function _tradeInputTokens(
        address _asset,
        uint256 _capital,
        IGarden _garden,
        uint256[] memory _inputWeights,
        address[] memory _inputTokens
    ) internal returns (uint256[] memory) {
        uint256[] memory maxAmountsIn = new uint256[](_inputTokens.length);
        for (uint256 i = 0; i < _inputTokens.length; i++) {
            if (_inputWeights[i] > 0) {
                maxAmountsIn[i] = _getMaxAmountTokenInput(_asset, _capital, _garden, _inputWeights[i], _inputTokens[i]);
            }
        }
        return maxAmountsIn;
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
        try ICustomIntegration(_integration).getRewardTokens(_data) returns (address[] memory rewards) {
            for (uint256 i = 0; i < rewards.length; i++) {
                if (rewards[i] != address(0) && IERC20(rewards[i]).balanceOf(msg.sender) > MIN_TRADE_AMOUNT) {
                    try
                        IStrategy(msg.sender).trade(
                            rewards[i],
                            IERC20(rewards[i]).balanceOf(msg.sender),
                            _reserveAsset,
                            70e15
                        )
                    {} catch {}
                }
            }
        } catch {}
    }

    function _getPriceOrCustom(
        address _integration,
        bytes calldata _data,
        address _tokenOut
    ) internal view returns (uint256) {
        uint256 price = _getPrice(_getResultTokenFromBytes(_integration, _data), _tokenOut);
        if (price == 0) {
            price = ICustomIntegration(_integration).getPriceResultToken(_data, _tokenOut);
        }
        return price;
    }

    function _getMinAmountOut(uint256 _capital, uint256 _priceInverse) internal view returns (uint256) {
        return _capital.preciseDiv(_priceInverse).preciseMul(95e16);
    }
}
