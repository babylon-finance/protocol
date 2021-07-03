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

import 'hardhat/console.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {ILendIntegration} from '../../interfaces/ILendIntegration.sol';

import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';

import {Operation} from './Operation.sol';

/**
 * @title LendOperation
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
        bytes calldata _data,
        IGarden _garden,
        address, /* _integration */
        uint256 /* _index */
    ) external view override onlyStrategy {}

    /**
     * Executes the lend operation
     * @param _asset              Asset to receive into this operation
     * @param _capital            Amount of asset received
     * param _assetStatus         Status of the asset amount
     * @param _data               OpData e.g. Address of the asset to lend
     * param _garden              Garden of the strategy
     * @param _integration        Address of the integration to execute
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8, /* _assetStatus */
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
        address assetToken = abi.decode(_data[4:], (address)); // We just use the first 20 bytes from the whole opEncodedData
        if (assetToken != _asset) {
            // Trade to WETH if is 0x0 (eth in compound)
            if (assetToken != address(0) || _asset != WETH) {
                IStrategy(msg.sender).trade(_asset, _capital, assetToken == address(0) ? WETH : assetToken);
            }
        }
        uint256 numTokensToSupply;
        if (assetToken == address(0)) {
            // change it to plain eth for compound
            IStrategy(msg.sender).handleWeth(false, IERC20(WETH).balanceOf(msg.sender));
            numTokensToSupply = address(msg.sender).balance;
        } else {
            numTokensToSupply = IERC20(assetToken).balanceOf(msg.sender);
        }
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
        address assetToken = abi.decode(_data[4:],(address));
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        // Normalize to underlying asset if any (ctokens for compound)
        uint256 numTokensToRedeem = ILendIntegration(_integration).getInvestmentTokenAmount(msg.sender, assetToken);
        // Apply percentage
        numTokensToRedeem = numTokensToRedeem.mul(_percentage.div(10**(18)));
        

        if (_remaining > 0) {
            // Update amount so we can exit if there is debt
            numTokensToRedeem = numTokensToRedeem.sub(_remainingDebtInCollateral(_percentage, _borrowToken, assetToken, _remaining).mul(130).div(100));
        }
        uint256 exchangeRate = ILendIntegration(_integration).getExchangeRatePerToken(assetToken);
        ILendIntegration(_integration).redeemTokens(
            msg.sender,
            assetToken,
            numTokensToRedeem,
            exchangeRate.mul(numTokensToRedeem.sub(numTokensToRedeem.preciseMul(SLIPPAGE_ALLOWED)))
        );
        address tokenToTradeFrom = assetToken;
        // if eth, convert it to weth
        if (assetToken == address(0)) {
            tokenToTradeFrom = WETH;
            IStrategy(msg.sender).handleWeth(true, address(msg.sender).balance);
        }
        if (tokenToTradeFrom != _garden.reserveAsset()) {
            IStrategy(msg.sender).trade(
                tokenToTradeFrom,
                IERC20(tokenToTradeFrom).balanceOf(msg.sender),
                _garden.reserveAsset()
            );
        }
        return (
            assetToken,
            IERC20(ILendIntegration(_integration).getInvestmentToken(assetToken)).balanceOf(msg.sender),
            1
        );
    }

    function _remainingDebtInCollateral(uint256 _percentage, address _borrowToken, address _assetToken, uint256 _remaining ) internal view returns(uint256) {
        uint256 remainingDebtInCollateralTokens = _getRemainingDebt(_borrowToken, _assetToken, _remaining);
        remainingDebtInCollateralTokens = SafeDecimalMath.normalizeAmountTokens(
            _borrowToken,
            _assetToken,
            remainingDebtInCollateralTokens
        );
        return remainingDebtInCollateralTokens;
    }

    /**
     * Gets the NAV of the lend op in the reserve asset
     *
     * @param _data               OpData e.g. Asset lent
     * @param _garden             Garden the strategy belongs to
     * @param _integration        Status of the asset amount
     * @return _nav               NAV of the strategy
     */
    function getNAV(
        bytes calldata _data,
        IGarden _garden,
        address _integration
    ) external view override returns (uint256, bool) {
        address lendToken = abi.decode(_data[4:], (address));
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return (0, true);
        }
        uint256 assetTokenAmount = ILendIntegration(_integration).getInvestmentTokenAmount(msg.sender, lendToken);
        uint256 price = _getPrice(_garden.reserveAsset(), lendToken);
        uint256 NAV =
            SafeDecimalMath.normalizeAmountTokens(lendToken, _garden.reserveAsset(), assetTokenAmount).preciseDiv(
                price
            );
        require(NAV != 0, 'NAV has to be bigger 0');
        return (NAV, true);
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
