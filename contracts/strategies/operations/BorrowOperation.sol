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
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Operation} from './Operation.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {IBorrowIntegration} from '../../interfaces/IBorrowIntegration.sol';

/**
 * @title LendOperatin
 * @author Babylon Finance
 *
 * Executes a borrow operation
 */
contract BorrowOperation is Operation {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

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
     * @param _data                   Operation data
     */
    function validateOperation(
        address _data,
        IGarden _garden,
        address, /* _integration */
        uint256 _index
    ) external view override onlyStrategy {
        require(IBorrowIntegration(_integration).getCollateralBalance > 0 , "Neds to be collateral");
        require(_index > 0, 'The operation cannot be the first. Needs to be a lend first');
    }

    /**
     * Executes the borrow operation
     * @param _asset              Asset to receive into this operation
     * @param _capital            Amount of asset received
     * @param _assetStatus        Status of the asset amount
     * @param _borrowToken        Token to borrow
     * param _garden              Garden of the strategy
     * @param _integration        Address of the integration to execute
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8 _assetStatus,
        address _borrowToken,
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
        require(_capital > 0 && _assetStatus == 1, 'There is collateral locked');
        IBorrowIntegration(_integration).borrow(
            _borrowToken,
            IBorrowIntegration(_integration).maxCollateralFactor().preciseMul(_capital)
        );
        return (_borrowToken, IERC20(_borrowToken).balanceOf(address(msg.sender)), 0); // borrowings are liquid
    }

    /**
     * Exits the borrow operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        uint256 _percentage,
        address _assetToken,
        IGarden _garden,
        address _integration
    ) external override onlyStrategy {
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        uint256 numTokensToRepay =
            IERC20(IBorrowIntegration(_integration).getBorrowBalance(_assetToken)).balanceOf(msg.sender).preciseMul(
                _percentage
            );
        IBorrowIntegration(_integration).repay(
            _assetToken,
            IERC20(_assetToken).balanceOf(address(msg.sender)) // We repay all that we can
        );
    }

    /**
     * Gets the NAV of the lend op in the reserve asset
     *
     * @param _assetToken         Asset borrowed
     * @param _garden             Garden the strategy belongs to
     * @param _integration        Status of the asset amount
     * @return _nav               NAV of the strategy
     */
    function getNAV(
        address _assetToken,
        IGarden _garden,
        address _integration
    ) external view override onlyStrategy returns (uint256) {
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return 0;
        }
        uint256 tokensOwed = IBorrowIntegration(_integration).getBorrowBalance(_assetToken);
        uint256 price = _getPrice(_garden.reserveAsset(), _assetToken);
        uint256 NAV = SafeDecimalMath.normalizeDecimals(_assetToken, tokensOwed).preciseDiv(price);
        require(NAV != 0, 'NAV has to be different than 0');
        return uint256(-NAV);
    }
}
