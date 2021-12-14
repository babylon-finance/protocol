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

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IHarvestV3Stake} from '../../interfaces/external/harvest/IHarvestV3Stake.sol';

/**
 * @title HarvestV3StakeIntegration
 * @author Babylon Finance Protocol
 *
 * Harvest V3 Stake Integration
 */
contract HarvestV3StakeIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State Variables ============ */

    mapping(address => address) poolToStakeContract;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PassiveIntegration('harvest_stake_v3', _controller) {
        poolToStakeContract[0xadb16df01b9474347e8fffd6032360d3b54627fb] = 0x3e6397E309f68805FA8Ef66A6216bD2010DdAF19; // fBablWeth
        poolToStakeContract[0x65383Abd40f9f831018dF243287F7AE3612c62AC] = 0x11301B7C82Cd953734440aaF0D5Dd0B36E2aB1d8; // fWethSeth
        poolToStakeContract[0xc53DaB6fDD18AF6CD5cF37fDE7C941d368f8664f] = 0x6055d7f2E84e334176889f6d8c3F84580cA4F507; // fWethUsdt 3-4.5k
        poolToStakeContract[0xEA46CfcB43D5274991344cF6F56765e39A7Eae1a] = 0xFd1121b2292eBD475791Ee2d646ccC8451c9F7Ae; // fWethUsdt 4.2-5.5k
        poolToStakeContract[0x503Ea79B73995Cf0C8d323C17782047ED5cC72B2] = 0xEFb78d1E3BA4272E7D806b9dC88e239e08e4082D; // fDaiWeth 3-4.5k
        poolToStakeContract[0x8137ac6dF358fe2D0DFbB1b5aA87C110950A16Cd] = 0x35De0D0F9448B35a09e1E884C7d23A00027fbD8f; // fDaiWeth 4.2-5.5k
        poolToStakeContract[0x3b2ED6013f961404AbA5a030e20A2AceB486832d] = 0x7931D6263798f99A082Caf1416b2457605628e2D; // fUsdcWeth 3-4.5k
        poolToStakeContract[0xC74075F5c9aD58C655a6160bA955B4aCD5dE8d0B] = 0xe9D5571a741AF8201e6ca11241aF4d2D635D6c85; // fUsdcWeth 4.2-5.5k;
    }

    /* ============ Internal Functions ============ */
    function _getSpender(address _stakingPool, uint8 /* _op */) internal view override returns (address) {
        return _stakingPool;
    }

    function _getExpectedShares(
        address, /* _asset */
        uint256 _amount
    ) internal pure override returns (uint256) {
        return _amount;
    }

    function _getPricePerShare(
        address /* _asset */
    ) internal pure override returns (uint256) {
        return 1e18;
    }

    function _getInvestmentAsset(address _asset) internal view override returns (address lptoken) {
        return IHarvestV3Stake(_asset).lpToken();
    }

    function _getResultAsset(address _investment) internal view virtual override returns (address) {
        return _investment;
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _asset                          Address of the vault
     * hparam  _investmentTokensOut            Amount of investment tokens to send
     * hparam  _tokenIn                        Addresses of tokens to send to the investment
     * @param  _maxAmountIn                    Amounts of tokens to send to the investment
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getEnterInvestmentCalldata(
        address, /* _strategy */
        address _asset,
        uint256, /* _investmentTokensOut */
        address, /* _tokenIn */
        uint256 _maxAmountIn
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address lpToken = _getInvestmentAsset(_asset);
        require(lpToken != address(0), 'Harvest V3 Stake pool does not exist');
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('stake(uint256)', _maxAmountIn);
        return (_asset, 0, methodData);
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _asset                          Address of the investment
     * hparam  _investmentTokensIn             Amount of investment tokens to receive
     * hparam  _tokenOut                       Addresses of tokens to receive
     * hparam  _minAmountOut                   Amounts of investment tokens to receive
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getExitInvestmentCalldata(
        address, /* _strategy */
        address _asset,
        uint256 _investmentTokensIn,
        address, /* _tokenOut */
        uint256 /* _minAmountOut */
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Withdraw all and claim
        bytes memory methodData = abi.encodeWithSignature('withdraw(uint256)', _investmentTokensIn);
        // Go through the reward pool instead of the booster
        return (_asset, 0, methodData);
    }


    function _getRewards(address _strategy, address _asset)
        internal
        view
        override
        returns (address token, uint256 balance)
    {
        IHarvestV3Stake pool = IHarvestV3Stake(_asset);
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        uint256 rewardsLength = pool.rewardTokensLength();
        if (rewardsLength > 0) {
            for (uint256 i = 0; i < rewardsLength; i++) {
                uint rewardAmount = pool.earned(i, _strategy);
                totalAmount = totalAmount.add(
                    oracle.getPrice(rewards.extraRewards(i), extraRewards.rewardToken()).preciseMul(
                        extraRewards.earned(_strategy)
                    )
                );
            }
        }
        return (rewards.rewardToken(), totalAmount);
    }
}
