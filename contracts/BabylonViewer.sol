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
     * @param _garden            Address of the garden to fetch
     * @return                   Garden complete details
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

    /**
     * Gets complete strategy details
     *
     * @param _strategy            Address of the strategy to fetch
     * @return                     All strategy details
     */
    function getCompleteStrategy(address _strategy)
        external
        view
        returns (
            address,
            uint256[11] memory,
            bool[] memory,
            uint256[] memory
        )
    {
        IStrategy strategy = IStrategy(_strategy);
        bool[] memory status = new bool[](3);
        uint256[] memory ts = new uint256[](3);
        (, status[0], status[1], status[2], ts[0], ts[1], ts[2]) = strategy.getStrategyState();
        return (
            strategy.strategist(),
            [
                strategy.getOperationsCount(),
                strategy.stake(),
                strategy.totalPositiveVotes(),
                strategy.totalNegativeVotes(),
                strategy.capitalAllocated(),
                strategy.capitalReturned(),
                strategy.duration(),
                strategy.expectedReturn(),
                strategy.maxCapitalRequested(),
                strategy.enteredAt(),
                strategy.getNAV()
            ],
            status,
            ts
        );
    }

    function getOperationsStrategy(address _strategy)
        public
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

    function getGardensUser(address _user, uint256 _offset) external view returns (address[] memory, bool[] memory) {
        address[] memory gardens = controller.getGardens();
        address[] memory userGardens = new address[](25);
        bool[] memory hasUserDeposited = new bool[](25);
        uint8 resultIndex;
        IIshtarGate gate = IIshtarGate(controller.ishtarGate());
        for (uint256 i = _offset; i < gardens.length; i++) {
            IGarden garden = IGarden(gardens[i]);
            if (garden.active() && (!garden.guestListEnabled() || gate.canJoinAGarden(gardens[i], _user))) {
                userGardens[resultIndex] = gardens[i];
                hasUserDeposited[resultIndex] = IERC20(gardens[i]).balanceOf(_user) > 0;
                resultIndex = resultIndex + 1;
            }
        }
        return (userGardens, hasUserDeposited);
    }

    /* ============ Private Functions ============ */
}
