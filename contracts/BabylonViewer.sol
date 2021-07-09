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
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';

import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {IRewardsDistributor} from './interfaces/IRewardsDistributor.sol';
import {IBabController} from './interfaces/IBabController.sol';
import {IGardenValuer} from './interfaces/IGardenValuer.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IStrategy} from './interfaces/IStrategy.sol';
import {IIshtarGate} from './interfaces/IIshtarGate.sol';
import {IGardenNFT} from './interfaces/IGardenNFT.sol';
import {IStrategyNFT} from './interfaces/IStrategyNFT.sol';
import {Math} from './lib/Math.sol';

/**
 * @title BabylonViewer
 * @author Babylon Finance
 *
 * Class that holds common view functions to retrieve garden information effectively
 */
contract BabylonViewer {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using Math for int256;

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
            string memory,
            string memory,
            address,
            address,
            bool[2] memory,
            address[] memory,
            address[] memory,
            uint256[11] memory,
            uint256[10] memory
        )
    {
        IGarden garden = IGarden(_garden);
        IGardenValuer valuer = IGardenValuer(controller.gardenValuer());
        uint256 totalSupply = IERC20(_garden).totalSupply();
        uint256 valuationPerToken =
            totalSupply > 0 ? valuer.calculateGardenValuation(_garden, garden.reserveAsset()) : 0;
        uint256 seed = _getGardenSeed(_garden);

        return (
            ERC20(_garden).name(),
            ERC20(_garden).symbol(),
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
                valuationPerToken > 0 ? totalSupply.preciseMul(valuationPerToken) : 0,
                totalSupply,
                seed
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
            string memory,
            uint256[12] memory,
            bool[] memory,
            uint256[] memory
        )
    {
        IStrategy strategy = IStrategy(_strategy);
        bool[] memory status = new bool[](3);
        uint256[] memory ts = new uint256[](4);
        (, status[0], status[1], status[2], ts[0], ts[1], ts[2]) = strategy.getStrategyState();
        uint256 rewards =
            strategy.exitedAt() != 0
                ? IRewardsDistributor(controller.rewardsDistributor()).getStrategyRewards(_strategy)
                : 0;
        ts[3] = strategy.enteredCooldownAt();
        return (
            strategy.strategist(),
            IStrategyNFT(controller.strategyNFT()).getStrategyName(_strategy),
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
                strategy.getNAV(),
                rewards
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
            bytes[] memory
        )
    {
        IStrategy strategy = IStrategy(_strategy);
        uint256 count = strategy.getOperationsCount();
        uint8[] memory types = new uint8[](count);
        address[] memory integrations = new address[](count);
        bytes[] memory datas = new bytes[](count);

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

    function getUserStrategyActions(address[] memory _strategies, address _user)
        external
        view
        returns (uint256, uint256)
    {
        uint256 strategiesCreated;
        uint256 totalVotes;
        for (uint8 i = 0; i < _strategies.length; i++) {
            IStrategy strategy = IStrategy(_strategies[i]);
            if (strategy.strategist() == _user) {
                strategiesCreated = strategiesCreated.add(1);
            }
            int256 votes = strategy.getUserVotes(_user);
            if (votes != 0) {
                totalVotes = totalVotes.add(uint256(Math.abs(votes)));
            }
        }
        return (strategiesCreated, totalVotes);
    }

    function getContributionAndRewards(address _garden, address _user)
        external
        view
        returns (uint256[] memory, uint256[] memory)
    {
        IGarden garden = IGarden(_garden);
        uint256[] memory contribution = new uint256[](9);
        (
            contribution[0],
            contribution[1],
            contribution[2],
            contribution[3],
            contribution[4],
            contribution[5],
            ,
            ,
            contribution[8]
        ) = garden.getContributor(_user);
        contribution[6] = IERC20(_garden).balanceOf(_user);
        contribution[7] = garden.getLockedBalance(_user);
        uint256[] memory totalRewards =
            IRewardsDistributor(controller.rewardsDistributor()).getRewards(
                _garden,
                _user,
                garden.getFinalizedStrategies()
            );
        return (contribution, totalRewards);
    }

    /* ============ Private Functions ============ */

    function _getGardenSeed(address _garden) private view returns (uint256) {
        return IGardenNFT(controller.gardenNFT()).gardenSeeds(_garden);
    }
}
