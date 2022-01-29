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

import {IComptroller} from '../../interfaces/external/compound/IComptroller.sol';
import {IRewardsDistributor} from '../../interfaces/external/compound/IRewardsDistributor.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

import {CompoundLendIntegration} from './CompoundLendIntegration.sol';

/**
 * @title FuseLendIntegration
 * @author Babylon Finance
 *
 * Class that houses fuse lending logic.
 */
contract FuseLendIntegration is CompoundLendIntegration {
    /* ============ State Variables ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller             Address of the controller
     * @param _comptroller            Address of the fuse pool comptroller
     */
    constructor(IBabController _controller, address _comptroller)
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

    function _getRewardsAccrued(
        address /* _strategy */
    ) internal view override returns (uint256) {
        address[] memory rewards = IComptroller(comptroller).getRewardsDistributors();
        if (rewards.length > 0) {
          return IRewardsDistributor(rewards[0]).compAccrued();
        }
        return 0;
    }

    function _claimRewardsCallData(
        address _strategy
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
        address[] memory rewards = IComptroller(comptroller).getRewardsDistributors();
        if (rewards.length > 0) {
          return (rewards[0], 0, abi.encodeWithSignature('claimRewards(address)', _strategy));
        }
        return (address(0), 0, bytes(''));
    }
}
