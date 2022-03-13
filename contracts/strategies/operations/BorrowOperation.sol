// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBorrowIntegration} from '../../interfaces/IBorrowIntegration.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {Errors, _require} from '../../lib/BabylonErrors.sol';
import {UniversalERC20} from '../../lib/UniversalERC20.sol';

import {Operation} from './Operation.sol';

/**
 * @title BorrowOperation
 * @author Babylon Finance
 *
 * Executes a borrow operation
 */
contract BorrowOperation is Operation {
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
     * Sets operation data for the borrow operation
     *
     * param _data                   Operation data
     * param _garden                 Garden
     * param _integration            Integration used
     * @param _index                  Index of this operation
     */
    function validateOperation(
        bytes calldata, /* _data */
        IGarden, /* _garden */
        address, /* _integration */
        uint256 _index
    ) external view override onlyStrategy {
        require(_index > 0, 'The operation cannot be the first. Needs to be a lend first');
    }

    /**
     * Executes the borrow operation
     * @param _asset              Asset to receive into this operation
     * @param _capital            Amount of asset received
     * @param _assetStatus        Status of the asset amount
     * @param _data               Operation data (e.g. Token to borrow)
     * param _garden              Garden of the strategy
     * @param _integration        Address of the integration to execute
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8 _assetStatus,
        bytes memory _data,
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
        address borrowToken = BytesLib.decodeOpDataAddressAssembly(_data, 12);
        uint256 normalizedAmount = _getBorrowAmount(_asset, borrowToken, _capital, _integration);

        require(_capital > 0 && _assetStatus == 1 && _asset != borrowToken, 'There is no collateral locked');

        _onlyPositiveCollateral(msg.sender, _asset, _integration);
        IBorrowIntegration(_integration).borrow(msg.sender, borrowToken, normalizedAmount);
        // if borrowToken is ETH wrap it to WETH
        if (borrowToken == address(0)) {
            IStrategy(msg.sender).handleWeth(true, normalizedAmount);
            borrowToken = WETH;
        }
        return (borrowToken, normalizedAmount, 0); // borrowings are liquid
    }

    function _onlyPositiveCollateral(
        address _sender,
        address _asset,
        address _integration
    ) internal view {
        require(
            IBorrowIntegration(_integration).getCollateralBalance(_sender, _asset) > 0,
            'There is no collateral locked'
        );
    }

    function _getBorrowAmount(
        address _asset,
        address _borrowToken,
        uint256 _capital,
        address _integration
    ) internal view returns (uint256) {
        uint256 price = _getPrice(_asset, _borrowToken);
        // % of the total collateral value in the borrow token
        // Use the % max we can borrow (maxCollateral)
        // Use the % of the collateral asset
        uint256 amountToBorrow =
            _capital.preciseMul(price).preciseMul(IBorrowIntegration(_integration).maxCollateralFactor()).preciseMul(
                IBorrowIntegration(_integration).getCollateralFactor(_asset)
            );
        uint256 normalizedAmount = SafeDecimalMath.normalizeAmountTokens(_asset, _borrowToken, amountToBorrow);
        return normalizedAmount;
    }

    /**
     * Exits the borrow operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        address _asset,
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
        address assetToken = BytesLib.decodeOpDataAddress(_data);
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        uint256 debtAmount = IBorrowIntegration(_integration).getBorrowBalance(msg.sender, assetToken);
        // if debt token is different than the token received
        _asset = _asset == address(0) ? WETH : _asset;
        _tradeToDebtToken(_asset, assetToken);

        uint256 debtTokenBalance = IERC20(assetToken).universalBalanceOf(address(msg.sender));

        uint256 amountToRepay =
            debtAmount > debtTokenBalance
                ? debtTokenBalance.preciseMul(_percentage)
                : debtAmount.preciseMul(_percentage);
        IBorrowIntegration(_integration).repay(
            msg.sender,
            assetToken,
            amountToRepay // We repay the percentage of all that we can
        );
        return (assetToken, IBorrowIntegration(_integration).getBorrowBalance(msg.sender, assetToken), 2);
    }

    /**
     * Gets the NAV of the lend op in the reserve asset
     *
     * @param _data               OpData e.g. Asset borrowed
     * @param _garden             Garden the strategy belongs to
     * @param _integration        Status of the asset amount
     * @return _nav               NAV of the strategy
     */
    function getNAV(
        bytes calldata _data,
        IGarden _garden,
        address _integration
    ) external view override onlyStrategy returns (uint256, bool) {
        address borrowToken = BytesLib.decodeOpDataAddress(_data); // 64 bytes (w/o signature prefix bytes4)
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return (0, true);
        }
        uint256 tokensOwed = IBorrowIntegration(_integration).getBorrowBalance(msg.sender, borrowToken);
        uint256 price = _getPrice(_garden.reserveAsset(), borrowToken);
        // if there are liquidations or it is the last op (borrowings not used)
        uint256 borrowTokenBalance = IERC20(borrowToken == address(0) ? WETH : borrowToken).balanceOf(msg.sender);
        if (borrowTokenBalance > 0) {
            tokensOwed = tokensOwed >= borrowTokenBalance ? tokensOwed.sub(borrowTokenBalance) : 0;
        }
        uint256 NAV =
            tokensOwed == 0 ? 0 :
            SafeDecimalMath.normalizeAmountTokens(borrowToken, _garden.reserveAsset(), tokensOwed).preciseDiv(price);

        return (NAV, false);
    }

    function _tradeToDebtToken(address _asset, address _assetToken) private {
        uint256 debtTokenBalance = IERC20(_assetToken).universalBalanceOf(address(msg.sender));
        if (_asset != _assetToken && debtTokenBalance == 0) {
            if (_asset == address(0)) {
                IStrategy(msg.sender).handleWeth(true, address(msg.sender).balance);
                _asset = WETH;
            }
            if (_assetToken != address(0)) {
                IStrategy(msg.sender).trade(_asset, IERC20(_asset).balanceOf(msg.sender), _assetToken);
            } else {
                if (_asset != WETH) {
                    IStrategy(msg.sender).trade(_asset, IERC20(_asset).balanceOf(msg.sender), WETH);
                }
                IStrategy(msg.sender).handleWeth(false, IERC20(WETH).balanceOf(msg.sender));
            }
        }
    }
}
