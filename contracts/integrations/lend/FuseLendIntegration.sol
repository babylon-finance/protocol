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

pragma solidity >=0.7.0 <0.9.0;
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ICToken} from '../../interfaces/external/compound/ICToken.sol';
import {IComptroller} from '../../interfaces/external/compound/IComptroller.sol';
import {ILensPool} from '../../interfaces/external/rari/ILensPool.sol';
import {IRewardsDistributor} from '../../interfaces/external/compound/IRewardsDistributor.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {CompoundLendIntegration} from './CompoundLendIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';

/**
 * @title FuseLendIntegration
 * @author Babylon Finance
 *
 * Class that houses Fuse lending logic.
 */
contract FuseLendIntegration is CompoundLendIntegration {
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;

    /* ============ State Variables ============ */

    address private constant FUSE_LENS_ADDRESS = 0xc76190E04012f26A364228Cfc41690429C44165d;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller             Address of the controller
     * @param _comptroller            Address of the fuse pool comptroller
     */
    constructor(IBabController _controller, IComptroller _comptroller)
        CompoundLendIntegration('fuselend', _controller, _comptroller)
    {}

    /* ============ Internal Functions ============ */

    function _getRewardToken() internal view override returns (address) {
        address[] memory rewards = IComptroller(comptroller).getRewardsDistributors();
        if (rewards.length > 0) {
            return IRewardsDistributor(rewards[0]).rewardToken();
        }
        return address(0);
    }

    function _getRewardsAccrued(address _strategy) internal view override returns (uint256) {
        address[] memory distributors = IComptroller(comptroller).getRewardsDistributors();
        uint256 totalRewards;
        if (distributors.length > 0) {
            address[] memory markets = IComptroller(comptroller).getAllMarkets();
            uint256 nblocks = _getDurationStrategy(_strategy).div(14); // assuming 14 secs per block
            for (uint256 i = 0; i < markets.length; i++) {
                uint256 balanceCToken = IERC20(markets[i]).balanceOf(_strategy);
                uint256 rewardPerBlock;
                uint256 divisor;
                // If there is balance, strategy supplied
                if (balanceCToken > 0) {
                    (
                        ,
                        // err
                        uint256 cTokenBalance, // borrow balance
                        ,
                        uint256 exchangeRateMantissa
                    ) = ICToken(markets[i]).getAccountSnapshot(_strategy);
                    balanceCToken = cTokenBalance.preciseMul(exchangeRateMantissa);
                    rewardPerBlock = IRewardsDistributor(distributors[0]).compSupplySpeeds(markets[i]);
                    divisor = ICToken(markets[i]).getCash();
                } else {
                    // Check if borrow enabled
                    if (ICToken(markets[i]).borrowRatePerBlock() > 0) {
                        (, , balanceCToken, ) = ICToken(markets[i]).getAccountSnapshot(_strategy);
                        // If there is borrow balance, strategy borrowed from this market
                        if (balanceCToken > 0) {
                            rewardPerBlock = IRewardsDistributor(distributors[0]).compBorrowSpeeds(markets[i]);
                            divisor = ICToken(markets[i]).totalBorrows();
                        }
                    }
                }
                if (balanceCToken > 0 && rewardPerBlock > 0 && divisor > 0) {
                    totalRewards = totalRewards.add(
                        rewardPerBlock.preciseMul(balanceCToken.preciseDiv(divisor)).mul(nblocks)
                    );
                }
            }
        }
        return totalRewards;
    }

    function _claimRewardsCallData(address _strategy)
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address[] memory rewards = IComptroller(comptroller).getRewardsDistributors();
        if (rewards.length > 0) {
            return (rewards[0], 0, abi.encodeWithSignature('claimRewards(address)', _strategy));
        }
        return (address(0), 0, bytes(''));
    }
}
