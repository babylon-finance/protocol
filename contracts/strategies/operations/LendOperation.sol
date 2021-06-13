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
import {ILendIntegration} from '../../interfaces/ILendIntegration.sol';

/**
 * @title LendOperatin
 * @author Babylon Finance
 *
 * Executes a lend operation
 */
contract LendOperation is Operation {
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
     * Sets operation data for the lend operation
     *
     * @param _data                   Operation data
     */
    function validateOperation(
        address _data,
        IGarden _garden,
        address, /* _integration */
        uint256 /* _index */
    ) external view override onlyStrategy {}

    /**
     * Executes the lend operation
     * @param _asset              Asset to receive into this operation
     * @param _capital            Amount of asset received
     * param _assetStatus         Status of the asset amount
     * @param _data               Address of the asset to lend
     * param _garden              Garden of the strategy
     * @param _integration        Address of the integration to execute
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8, /* _assetStatus */
        address _data,
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
        address assetToken = _data;
        if (assetToken != _asset) {
            IStrategy(msg.sender).trade(_asset, _capital, assetToken);
        }
        uint256 numTokensToSupply = IERC20(assetToken).balanceOf(msg.sender);
        uint256 exactAmount = ILendIntegration(_integration).getExpectedShares(assetToken, numTokensToSupply);
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
        ILendIntegration(_integration).supplyTokens(msg.sender, assetToken, numTokensToSupply, minAmountExpected);
        return (assetToken, numTokensToSupply, 1); // put as collateral
    }

    /**
     * Exits the lend operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        address _borrowToken,
        uint256 _remaining,
        uint8, /* _assetStatus */
        uint256 _percentage,
        address _assetToken,
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
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        // Normalize to underlying asset if any (ctokens for compound)
        uint256 numTokensToRedeem = ILendIntegration(_integration).getInvestmentTokenAmount(msg.sender, _assetToken);
        // Apply percentage
        numTokensToRedeem = numTokensToRedeem.mul(_percentage.div(10**(18)));
        uint256 remainingDebtInCollateralTokens = _getRemainingDebt(_borrowToken, _assetToken, _remaining);
        remainingDebtInCollateralTokens = SafeDecimalMath.normalizeAmountTokens(
            _borrowToken,
            _assetToken,
            remainingDebtInCollateralTokens
        );

        if (_remaining > 0) {
            // Update amount so we can exit if there is debt
            numTokensToRedeem = numTokensToRedeem.sub(remainingDebtInCollateralTokens.mul(130).div(100));
        }
        uint256 exchangeRate = ILendIntegration(_integration).getExchangeRatePerToken(_assetToken);
        ILendIntegration(_integration).redeemTokens(
            msg.sender,
            _assetToken,
            numTokensToRedeem,
            exchangeRate.mul(numTokensToRedeem.sub(numTokensToRedeem.preciseMul(SLIPPAGE_ALLOWED)))
        );
        if (_assetToken != _garden.reserveAsset()) {
            IStrategy(msg.sender).trade(_assetToken, IERC20(_assetToken).balanceOf(msg.sender), _garden.reserveAsset());
        }
        return (
            _assetToken,
            IERC20(ILendIntegration(_integration).getInvestmentToken(_assetToken)).balanceOf(msg.sender),
            1
        );
    }

    /**
     * Gets the NAV of the lend op in the reserve asset
     *
     * @param _assetToken         Asset lent
     * @param _garden             Garden the strategy belongs to
     * @param _integration        Status of the asset amount
     * @return _nav           NAV of the strategy
     */
    function getNAV(
        address _assetToken,
        IGarden _garden,
        address _integration
    ) external view override onlyStrategy returns (uint256) {
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return 0;
        }
        uint256 numTokensToRedeem =
            IERC20(ILendIntegration(_integration).getInvestmentToken(_assetToken)).balanceOf(msg.sender);
        uint256 assetTokensAmount =
            ILendIntegration(_integration).getExchangeRatePerToken(_assetToken).mul(numTokensToRedeem);
        uint256 price = _getPrice(_garden.reserveAsset(), _assetToken);
        uint256 NAV =
            SafeDecimalMath.normalizeAmountTokens(_garden.reserveAsset(), _assetToken, assetTokensAmount).preciseDiv(
                price
            );
        require(NAV != 0, 'NAV has to be bigger 0');
        return NAV;
    }

    function _getRemainingDebt(
        address _borrowToken,
        address _assetToken,
        uint256 _remaining
    ) private view returns (uint256) {
        if (_remaining == 0) {
            return 0;
        }
        uint256 price = _getPrice(_borrowToken, _assetToken);
        return _remaining.preciseMul(price);
    }
}
