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
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBabController} from './interfaces/IBabController.sol';
import {IHeart} from './interfaces/IHeart.sol';

/**
 * @title HeartViewer
 * @author Babylon Finance
 *
 * Class that holds common view functions to retrieve heart and governance information effectively
 */
contract HeartViewer {
    IBabController public controller;

    constructor(IBabController _controller) {
        require(address(_controller) != address(0), 'Controller must exist');
        controller = _controller;
    }

    /* ============ External Getter Functions ============ */

    /**
     * Gets all the heart details in one view call
     */
    function getAllHeartDetails()
        external
        view
        returns (
            address,
            uint256[] memory,
            uint256[] memory,
            address[] memory,
            uint256[] memory,
            uint256[2] memory,
            uint256[2] memory
        )
    {
        IHeart heart = IHeart(address(0));
        return (
            heart.assetToLend(),
            heart.getTotalStats(),
            heart.getFeeDistributionWeights(),
            heart.getVotedGardens(),
            heart.getGardenWeights(),
            [heart.bablRewardLeft(), heart.weeklyRewardAmount()],
            [heart.lastPumpAt(), heart.lastVotesAt()]
        );
    }

    /* ============ Private Functions ============ */
}
