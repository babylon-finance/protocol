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
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import {IRewardsDistributor} from './interfaces/IRewardsDistributor.sol';
import {IBabController} from './interfaces/IBabController.sol';
import {IGardenValuer} from './interfaces/IGardenValuer.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IStrategy} from './interfaces/IStrategy.sol';
import {IIshtarGate} from './interfaces/IIshtarGate.sol';
import {IGardenNFT} from './interfaces/IGardenNFT.sol';

/**
 * @title BabylonViewer
 * @author Babylon Finance
 *
 * Class that holds common view functions to retrieve garden information effectively
 */
contract BabylonViewer {
    IBabController public controller;

    constructor(IBabController _controller) {
        require(address(_controller) != address(0), 'Controller must exist');
        controller = _controller;
    }

    /* ============ External Getter Functions ============ */

    /**
     * Gets garden details
     *
     * @return  address[]        Returns list of addresses
     */
    function getGardenDetails(address _garden)
        external
        view
        returns (
            address,
            address,
            bool[2] memory,
            address[] memory,
            address[] memory,
            uint256[11] memory,
            uint256[8] memory
        )
    {
        IGarden garden = IGarden(_garden);
        IGardenValuer valuer = IGardenValuer(controller.gardenValuer());
        uint256 valuation = valuer.calculateGardenValuation(_garden, garden.reserveAsset());
        return (
            garden.creator(),
            garden.reserveAsset(),
            [garden.active(), garden.guestListEnabled()],
            garden.getStrategies(),
            garden.getFinalizedStrategies(),
            [
                garden.depositHardlock(),
                garden.withdrawalsOpenUntil(),
                garden.minVotesQuorum(),
                garden.maxContributors(),
                garden.maxDepositLimit(),
                garden.minVoters(),
                garden.minStrategyDuration(),
                garden.maxStrategyDuration(),
                garden.strategyCooldownPeriod(),
                garden.minContribution(),
                garden.minLiquidityAsset()
            ],
            [
                garden.principal(),
                garden.reserveAssetRewardsSetAside(),
                garden.reserveAssetPrincipalWindow(),
                uint256(garden.absoluteReturns()),
                garden.gardenInitializedAt(),
                garden.totalContributors(),
                garden.totalStake(),
                valuation
            ]
        );
    }

    function getOperationsStrategy(address _strategy)
        external
        view
        returns (
            uint8[] memory,
            address[] memory,
            address[] memory
        )
    {
        IStrategy strategy = IStrategy(_strategy);
        uint256 count = strategy.getOperationsCount();
        uint8[] memory types = new uint8[](count);
        address[] memory integrations = new address[](count);
        address[] memory datas = new address[](count);

        for (uint8 i = 0; i < count; i++) {
            (types[i], integrations[i], datas[i]) = strategy.getOperationByIndex(i);
        }
        return (types, integrations, datas);
    }

    function getPermissions(address _user) external view returns (bool, bool) {
        IIshtarGate gate = IIshtarGate(controller.ishtarGate());
        return (IERC721(address(gate)).balanceOf(_user) > 0, gate.canCreate(_user));
    }

    function getGardenPermissions(address _garden, address _user)
        external
        view
        returns (
            bool,
            bool,
            bool
        )
    {
        IIshtarGate gate = IIshtarGate(controller.ishtarGate());
        return (
            gate.canJoinAGarden(_garden, _user),
            gate.canVoteInAGarden(_garden, _user),
            gate.canAddStrategiesInAGarden(_garden, _user)
        );
    }
}
