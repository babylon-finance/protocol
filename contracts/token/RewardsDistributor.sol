/*
    Copyright 2020 Babylon Finance.

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

import {TimeLockedToken} from './TimeLockedToken.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';

import {IBabController} from '../interfaces/IBabController.sol';
import {IRollingGarden} from '../interfaces/IRollingGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {TimeLockedToken} from './TimeLockedToken.sol';

import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {RewardsSupplySchedule} from './RewardsSupplySchedule.sol';

import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';

contract RewardsDistributor is Ownable {
    using SafeMath for uint256;
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;
    using SafeDecimalMath for uint256;
    using Math for uint256;
    using Math for uint256;

    /* ========== Events ========== */

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    // Garden that these strategies belong to
    IRollingGarden public garden;

    // Strategies that the reward calculations belong to
    IStrategy public strategy;

    // Supply Schedule contract
    RewardsSupplySchedule public supplySchedule;

    // BABL Token contract
    TimeLockedToken public babltoken;

    struct UserInfo {
        uint256 lastUserClaim;
        uint96 amount;
        uint96 rewardDebt;
        int256 votes;
        bool isLP;
        bool isGardenCreator;
        bool isStrategist;
        bool isSteward;
    }

    mapping(address => mapping(address => UserInfo)) public userInfo;

    struct StrategyPoolInfo {
        IRollingGarden lpToken;
        uint96 strategyPower;
        int256 strategyProfit;
        uint96 bablPerShare;
        uint256 lastRewardBlock;
        uint96 strategyPrincipal;
        uint256 strategyStart;
        uint256 strategyEnd;
        uint256 strategyDuration;
        uint256 lastUpdate;
        address strategist;
    }

    mapping(address => StrategyPoolInfo) public strategyPoolInfo;

    //StrategyPoolInfo[] public strategyPoolInfo;
    address[] public strategyList;

    uint256 public bablPerBlock;
    uint256 public totalAllocPoint = 0;
    uint256 public startBlock;

    struct RewardsProtocol {
        uint256 protocolPrincipal;
        uint256 protocolDuration;
        uint256 quarterStart;
        uint256 quarterEnd;
        uint96 potentialProtocolTokenRewards;
        uint96 availableProtocolTokenRewards;
        uint256 lastUpdate;
    }
    mapping(uint256 => RewardsProtocol) public rewardsProtocol;
    mapping(address => bool) public strategyIncluded;

    uint256 public EPOCH_DURATION = 90 days;
    uint256 public START_TIME;

    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    constructor(RewardsSupplySchedule _supply, TimeLockedToken _bablToken) {
        supplySchedule = _supply;
        babltoken = _bablToken;
        START_TIME = block.timestamp;
    }

    /* ============ External Functions ============ */

    // Add a new strategy to the pool. Can only be called by the owner / strategy // TODO CHECK.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        IRollingGarden _lpToken,
        IStrategy _strategy,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools(_lpToken);
        }
        //uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        StrategyPoolInfo storage newStrategyPoolInfo = strategyPoolInfo[address(_strategy)];

        newStrategyPoolInfo.lpToken = _lpToken; // Rolling Garden repsonsible of the strategy
        newStrategyPoolInfo.strategyProfit = int256(_strategy.capitalReturned().sub(_strategy.capitalAllocated()));
        newStrategyPoolInfo.bablPerShare = uint96(0); // TODO - NEED TO BE UPDATED FOR REWARDS CALCULATION
        newStrategyPoolInfo.lastRewardBlock = 0; // TODO - DEFINE HOW TO HANDLE REWARDS BASED ON BLOCKS
        newStrategyPoolInfo.strategyPrincipal = uint96(_strategy.capitalAllocated());
        newStrategyPoolInfo.strategyStart = _strategy.executedAt();
        newStrategyPoolInfo.strategyEnd = _strategy.exitedAt();
        newStrategyPoolInfo.strategyDuration = newStrategyPoolInfo.strategyEnd.sub(newStrategyPoolInfo.strategyStart);
        newStrategyPoolInfo.lastUpdate = block.timestamp;
        newStrategyPoolInfo.strategist = _strategy.strategist();
        newStrategyPoolInfo.strategyPower = uint96(
            newStrategyPoolInfo.strategyDuration.mul(newStrategyPoolInfo.strategyPrincipal)
        );

        // Include it to avoid gas cost on massive updating
        strategyIncluded[address(_strategy)] = true;
        // For counting we also include it in the strategy array
        strategyList.push(address(_strategy));
        
        // We update the Total Allocation of the Protocol
        totalAllocPoint = totalAllocPoint.add(newStrategyPoolInfo.strategyPrincipal);

    }

    // Update the given strategy its BABL allocation point. Can only be called by the owner.
    function updateStrategy(
        address _address, // Address of the Strategy to be set / updated
        uint96 _strategyPrincipal,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools(strategyPoolInfo[_address].lpToken);
        }
        // If we introduce a value DIFFERENT FROM ZERO, as Owners, the strategy principal will be overrided so does the protocol be updated accordingly
        if (_strategyPrincipal != 0) { 
            // We also update Protocol Principal and the Strategy Principal with the new value
            totalAllocPoint = totalAllocPoint.sub(strategyPoolInfo[_address].strategyPrincipal).add(_strategyPrincipal);
            strategyPoolInfo[_address].strategyPrincipal = _strategyPrincipal;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getSupplyForPeriod(uint256 _from, uint256 _to) public view returns (uint256[] memory) {
        // check number of quarters and what quarters are they
        uint256 quarters = _to.sub(_from).preciseDivCeil(EPOCH_DURATION);
        uint256 startingQuarter = _from.preciseDivCeil(EPOCH_DURATION);
        uint256 endingQuarter = startingQuarter.add(quarters);
        uint256[] memory supplyPerQuarter;
        if (quarters <= 1) {
            // Strategy Duration less than a quarter
            supplyPerQuarter[0] = supplySchedule.tokenSupplyPerQuarter(endingQuarter);
            return supplyPerQuarter;
        } else if (quarters <= 2) {
            // Strategy Duration less or equal of 2 quarters - we assume that high % of strategies will have a duration <= 2 quarters avoiding the launch of a for loop
            supplyPerQuarter[0] = supplySchedule.tokenSupplyPerQuarter(startingQuarter);
            supplyPerQuarter[1] = supplySchedule.tokenSupplyPerQuarter(endingQuarter);
            return supplyPerQuarter;
        } else {
            for (uint256 i = 0; i <= quarters; i++) {
                supplyPerQuarter[i] = supplySchedule.tokenSupplyPerQuarter(startingQuarter + i);
            }
            return supplyPerQuarter;
        }
    }

    /* ============ Getter Functions ============ */

    function poolLength() external view returns (uint256) {
        return strategyList.length;
    }

    function getEpochRewards(uint256 epochs) public {
        uint256 timestamp = block.timestamp;
        for (uint256 i = 0; i <= epochs; i++) {
            rewardsProtocol[i].potentialProtocolTokenRewards = uint96(supplySchedule.tokenSupplyPerQuarter(i.add(1)));
            rewardsProtocol[i].lastUpdate = timestamp;
        }
    }

    function massUpdatePools(IRollingGarden _garden) public returns (uint256) {
        // TODO CHECK GAS REDUCTION IT UPDATES ALL FINALIZED STRATEGIES WITHIN A GARDEN

        address[] memory finalizedStrategies = _garden.getFinalizedStrategies();
        uint256 strategiesCount = 0;

        for (uint256 i = 0; i <= finalizedStrategies.length; i++) {
            if (!strategyIncluded[address(finalizedStrategies[i])]) {
                // It only updates new finalized strategies
                IStrategy updatingStrategy = IStrategy(finalizedStrategies[i]);

                strategiesCount++;
                StrategyPoolInfo storage newFinalizedStrategy = strategyPoolInfo[address(updatingStrategy)];
                newFinalizedStrategy.lpToken = _garden; // Rolling Garden repsonsible of the strategy
                newFinalizedStrategy.strategyProfit = int256(
                    updatingStrategy.capitalReturned().sub(updatingStrategy.capitalAllocated())
                );
                newFinalizedStrategy.bablPerShare = uint96(0); // TODO - NEED TO BE UPDATED FOR REWARDS CALCULATION
                newFinalizedStrategy.lastRewardBlock = 0; // TODO - DEFINE HOW TO HANDLE REWARDS BASED ON BLOCKS
                newFinalizedStrategy.strategyPrincipal = uint96(updatingStrategy.capitalAllocated());
                newFinalizedStrategy.strategyStart = updatingStrategy.executedAt();
                newFinalizedStrategy.strategyEnd = updatingStrategy.exitedAt();
                newFinalizedStrategy.strategyDuration = newFinalizedStrategy.strategyEnd.sub(
                    newFinalizedStrategy.strategyStart
                );
                newFinalizedStrategy.lastUpdate = block.timestamp;
                newFinalizedStrategy.strategist = updatingStrategy.strategist();
                newFinalizedStrategy.strategyPower = uint96(
                    newFinalizedStrategy.strategyDuration.mul(newFinalizedStrategy.strategyPrincipal)
                );

                // we include it in the mapping to use a filter for updates
                strategyIncluded[address(updatingStrategy)] = true;
                // For counting we also include it in the strategy array
                strategyList.push(address(updatingStrategy));
            } else if (!strategyIncluded[address(finalizedStrategies[i])]) {
                // We only update Profit and Principal
                IStrategy updatingStrategy = IStrategy(finalizedStrategies[i]);
                StrategyPoolInfo storage newFinalizedStrategy = strategyPoolInfo[address(updatingStrategy)];
                newFinalizedStrategy.strategyProfit = int256(
                    updatingStrategy.capitalReturned().sub(updatingStrategy.capitalAllocated())
                );
                newFinalizedStrategy.strategyPrincipal = uint96(updatingStrategy.capitalAllocated());
                strategiesCount++;
            }
        }

        return strategiesCount; // Returns the number of strategies updated
    }

    /* ========== View functions ========== */

    /**
     * @notice Retrieve the length of the finalized strategies in a garden array
     */
    function finalizedStrategiesinGardenLength(IRollingGarden _garden) external view returns (uint256) {
        return _garden.getFinalizedStrategies().length;
    }
}
