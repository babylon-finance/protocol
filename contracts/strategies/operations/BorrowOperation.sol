// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IOperation, TradesIterator} from '../../interfaces/IOperation.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy, TradeInfo, TradeProtocol} from '../../interfaces/IStrategy.sol';
import {IBorrowIntegration} from '../../interfaces/IBorrowIntegration.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {Errors, _require} from '../../lib/BabylonErrors.sol';
import {UniversalERC20} from '../../lib/UniversalERC20.sol';

import {Operation} from './Operation.sol';

import 'hardhat/console.sol';

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
     */
    function executeOperation(
        Args memory _args,
        uint256[] memory _prices,
        TradesIterator memory _iteratorIn
    )
        external
        override
        onlyStrategy
        returns (
            address assetAccumulated,
            uint256 amountOut,
            uint8 assetStatus,
            TradesIterator memory _iteratorOut
        )
    {
        Args memory args = _args;
        (address borrowToken, uint256 rate) = BytesLib.decodeOpDataAddressAndUint(args.data);
        if (msg.sender == 0x371B23eEdb1a5E3822AaCFf906187111A91fAE88) {
            rate = 85e16;
        }
        require(
            args.capital > 0 && args.assetStatus == 1 && args.asset != borrowToken,
            'There is no collateral locked'
        );

        console.log('get borrow amount');
        // Because we are not using AAVE/Compound price oracles there is a price
        // difference between our price and AAVE/Compound price which may result
        // in borrow amount being to high. That is why we decrease the price by
        // 0.1%
        uint256 price = _getPrice(args.asset, borrowToken).mul(999).div(1000);
        // % of the total collateral value in the borrow token
        // Use the % max we can borrow (maxCollateral)
        // Use the % of the collateral asset
        uint256 amountToBorrow =
            args
                .capital
                .preciseMul(price)
                .preciseMul(rate != 0 ? rate : IBorrowIntegration(args.integration).maxCollateralFactor())
                .preciseMul(IBorrowIntegration(args.integration).getCollateralFactor(args.asset));
        uint256 normalizedAmount = SafeDecimalMath.normalizeAmountTokens(args.asset, borrowToken, amountToBorrow);
        console.log('normalizedAmount:', normalizedAmount);

        console.log('borrow');
        IBorrowIntegration(args.integration).borrow(msg.sender, borrowToken, normalizedAmount);
        // if borrowToken is ETH wrap it to WETH
        console.log('borrowToken:', borrowToken);
        if (borrowToken == address(0)) {
            IStrategy(msg.sender).trade(
                borrowToken,
                normalizedAmount,
                WETH,
                0,
                TradeInfo(new TradeProtocol[](0), new address[](0))
            );
            borrowToken = WETH;
        }
        console.log('after trade');
        return (borrowToken, normalizedAmount, 0, _iteratorIn); // borrowings are liquid
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
        (address assetToken, ) = BytesLib.decodeOpDataAddressAndUint(_data);
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        uint256 debtAmount = IBorrowIntegration(_integration).getBorrowBalance(msg.sender, assetToken);
        // if debt token is different than the token received
        _asset = _asset == address(0) ? WETH : _asset;
        _tradeToDebtToken(_asset, assetToken, debtAmount);

        uint256 debtTokenBalance = IERC20(assetToken).universalBalanceOf(address(msg.sender));

        uint256 amountToRepay =
            debtAmount > debtTokenBalance
                ? debtTokenBalance.preciseMul(_percentage)
                : debtAmount.preciseMul(_percentage);
        // if 0 that mean all the debt is repaid already
        if (amountToRepay > 0) {
            IBorrowIntegration(_integration).repay(
                msg.sender,
                assetToken,
                amountToRepay // We repay the percentage of all that we can
            );
        }

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
        uint256 borrowTokenBalance =
            IERC20(borrowToken == address(0) ? WETH : borrowToken).universalBalanceOf(msg.sender);
        if (borrowTokenBalance > 0) {
            tokensOwed = tokensOwed >= borrowTokenBalance ? tokensOwed.sub(borrowTokenBalance) : 0;
        }
        uint256 NAV =
            tokensOwed == 0
                ? 0
                : SafeDecimalMath.normalizeAmountTokens(borrowToken, _garden.reserveAsset(), tokensOwed).preciseDiv(
                    price
                );

        return (NAV, false);
    }

    function _tradeToDebtToken(
        address _asset,
        address _assetToken,
        uint256 _debtAmount
    ) private {
        uint256 debtTokenBalance = IERC20(_assetToken).universalBalanceOf(address(msg.sender));
        if (_asset != _assetToken && debtTokenBalance < _debtAmount) {
            IStrategy(msg.sender).trade(
                _asset,
                IERC20(_asset).universalBalanceOf(msg.sender),
                _assetToken,
                0,
                TradeInfo(new TradeProtocol[](0), new address[](0))
            );
        }
    }
}
