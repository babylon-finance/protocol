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

pragma solidity 0.7.4;

import 'hardhat/console.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';

import {Strategy} from './Strategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {ITradeIntegration} from '../interfaces/ITradeIntegration.sol';
import {ILendIntegration} from '../interfaces/ILendIntegration.sol';

/**
 * @title LendStrategy
 * @author Babylon Finance
 *
 * Allows to supply funds to protocols (Compound, Aave) to earn interest over time.
 */
contract LendStrategy is Strategy {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;

    address public assetToken;

    /**
     * Sets integration data for the long strategy
     *
     * @param _assetToken                  ERC20 Token to supply.
     */
    function setData(address _assetToken) public onlyGardenAndNotSet {
        kind = 3;
        assetToken = _assetToken;

        dataSet = true;
    }

    /**
     * Gets the NAV of the lend asset in ETH
     *
     * @return _nav           NAV of the strategy
     */
    function getNAV() external view override returns (uint256) {
        if (!active || finalized) {
            return 0;
        }
        // TODO
        return 0;
    }

    /**
     * Enters the lend strategy
     */
    function _enterStrategy(uint256 _capital) internal override {
        if (assetToken != garden.reserveAsset()) {
            _trade(garden.reserveAsset(), _capital, assetToken);
        }
        uint256 numTokensToSupply = IERC20(assetToken).balanceOf(address(this));
        uint256 exactAmount = ILendIntegration(integration).getExpectedShares(assetToken, numTokensToSupply);
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
        ILendIntegration(integration).supplyTokens(assetToken, numTokensToSupply, minAmountExpected);
    }

    /**
     * Exits the lend strategy.
     */
    function _exitStrategy() internal override {
        uint256 numTokensToRedeem =
            IERC20(ILendIntegration(integration).getInvestmentToken(assetToken)).balanceOf(address(this));
        ILendIntegration(integration).redeemTokens(
            assetToken,
            numTokensToRedeem,
            ILendIntegration(integration).getExchangeRatePerToken(assetToken).mul(
                numTokensToRedeem.sub(numTokensToRedeem.preciseMul(SLIPPAGE_ALLOWED))
            )
        );
        if (assetToken != garden.reserveAsset()) {
            _trade(assetToken, IERC20(assetToken).balanceOf(address(this)), garden.reserveAsset());
        }
    }
}
