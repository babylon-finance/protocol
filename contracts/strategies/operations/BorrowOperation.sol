/*
    Copyright 2021 Babylon Finance.

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

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBorrowIntegration} from '../../interfaces/IBorrowIntegration.sol';

import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {Errors, _require} from '../../lib/BabylonErrors.sol';

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
        borrowToken = borrowToken == address(0) ? WETH : borrowToken;
        return (borrowToken, IERC20(borrowToken).balanceOf(address(msg.sender)), 0); // borrowings are liquid
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
        uint256 amountToBorrow =
            _capital.preciseMul(price).preciseMul(IBorrowIntegration(_integration).maxCollateralFactor());
        uint256 normalizedAmount = SafeDecimalMath.normalizeAmountTokens(_asset, _borrowToken, amountToBorrow);
        return normalizedAmount;
    }

    /**
     * Exits the borrow operation.
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
        address assetToken = BytesLib.decodeOpDataAddress(_data);
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        IBorrowIntegration(_integration).repay(
            msg.sender,
            assetToken,
            address(0) == assetToken ? address(msg.sender).balance : IERC20(assetToken).balanceOf(address(msg.sender)) // We repay all that we can
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
    ) external view override returns (uint256, bool) {
        address borrowToken = BytesLib.decodeOpDataAddress(_data); // 64 bytes (w/o signature prefix bytes4)
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return (0, true);
        }
        uint256 tokensOwed = IBorrowIntegration(_integration).getBorrowBalance(msg.sender, borrowToken);
        uint256 price = _getPrice(_garden.reserveAsset(), borrowToken);
        uint256 NAV =
            SafeDecimalMath.normalizeAmountTokens(borrowToken, _garden.reserveAsset(), tokensOwed).preciseDiv(price);
        return (NAV, false);
    }
}
