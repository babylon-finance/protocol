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
import {TimeLockedToken} from './TimeLockedToken.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';

import {IBabController} from '../interfaces/IBabController.sol';
import {IRollingGarden} from '../interfaces/IRollingGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {TimeLockedToken} from './TimeLockedToken.sol';

import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';

import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';
import {Safe3296} from '../lib/Safe3296.sol';

contract RewardsDistributor is Ownable {
    using SafeMath for uint256;
    using SafeMath for int256;
    using PreciseUnitMath for uint256;
    using PreciseUnitMath for int256;
    using SafeDecimalMath for uint256;
    using SafeDecimalMath for int256;
    using Math for uint256;
    using Math for int256;
    using Safe3296 for uint256;
    using Safe3296 for int256;
    using Safe3296 for uint96;
    using Safe3296 for uint32;

    /* ========== Events ========== */

    /* ============ Modifiers ============ */

    modifier onlyStrategy {
        address garden = IStrategy(msg.sender).garden();
        require(controller.isSystemContract(garden));
        _;
    }

    /* ============ State Variables ============ */

    // Controller contract
    IBabController public controller;

    // Strategies that the reward calculations belong to
    IStrategy public strategy;

    // BABL Token contract
    TimeLockedToken public babltoken;

    struct ProtocolPerTimestamp {
        // Allocation points per timestamp along the time
        uint256 principal;
        uint256 time;
        uint256 quarterBelonging; // Checkpoint quarter
        uint256 timeListPointer; // Pointer to the array of times in order to enable the possibility of iteration
        uint256 power; // Protocol power checkpoint
    }

    uint256 public protocolPrincipal = 0; // Total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all strategy pools.
    mapping(uint256 => ProtocolPerTimestamp) protocolPerTimestamp; // Total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all strategy pools.
    uint256[] public timeList; // TODO needs to be updated anytime there is a checkpoint of new strategy changing
    uint256 public pid = 0; // Initialization of the ID assigning timeListPointer to the checkpoint number

    struct ProtocolPerQuarter {
        // Allocation points per timestamp along the time
        uint256 quarterPrincipal; //
        uint256 quarterNumber; // # Quarter since START_TIME
        uint256 quarterPower; // Protocol power checkpoint
        uint96 supplyPerQuarter; // Supply per quarter
    }
    mapping(uint256 => ProtocolPerQuarter) protocolPerQuarter; //
    mapping(uint256 => bool) isProtocolPerQuarter; // Check if the protocol per quarter data has been initialized

    //uint256 public protocolDuration = 0; // Total Duration of the procotol (total execution blocks of all strategies in the pool)
    // mapping(uint256 => uint256) durationPerTimestamp; // Total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all strategy pools.

    uint256 public EPOCH_DURATION = 90 days; // Duration of its EPOCH in days
    uint256 public START_TIME; // Starting time of the rewards distribution

    // 500K BABL allocated to this BABL Mining Program More info at: https://medium.com/babylon-finance/babl-mining-program-4829c313268d
    uint256 public constant Q1_REWARDS = 53_571_428_571_428_600e6; // First quarter (epoch) BABL rewards
    uint256 public constant DECAY_RATE = 120000000000000000; // 12% quarterly decay rate (each 90 days) (Rewards on Q1 = 1,12 * Rewards on Q2) being Q1= Quarter 1, Q2 = Quarter 2

    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    constructor(TimeLockedToken _bablToken, IBabController _controller) {
        babltoken = _bablToken;
        controller = _controller;
        //START_TIME = block.timestamp; // TODO RECOVER FOR PRODUCTION
        START_TIME = 1614618000; // March the 1st for TESTING PURPOSES ONLY
    }

    /* ============ External Functions ============ */

    function addProtocolPrincipal(uint256 _capital) public onlyStrategy {
        protocolPrincipal = protocolPrincipal.add(_capital);
        protocolPerTimestamp[block.timestamp].principal = protocolPrincipal;
        protocolPerTimestamp[block.timestamp].time = block.timestamp;
        protocolPerTimestamp[block.timestamp].quarterBelonging = getQuarter(block.timestamp);
        protocolPerTimestamp[block.timestamp].timeListPointer = pid;
        if (pid == 0) {
            // The very first strategy of all strategies in the mining program
            protocolPerTimestamp[block.timestamp].power = EPOCH_DURATION;
        } else {
            // Any other strategy different from the very first one (will have an antecesor)
            protocolPerTimestamp[block.timestamp].power = protocolPerTimestamp[timeList[pid.sub(1)]].power.add(
                protocolPerTimestamp[block.timestamp].time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time).mul(
                    protocolPerTimestamp[timeList[pid.sub(1)]].principal
                )
            );
        }

        timeList.push(block.timestamp); // Register of added strategies timestamps in the array for iteration
        // Here we control the accumulated protocol power per each quarter
        // Create the quarter checkpoint in case the checkpoint is the first in the epoch
        addProtocolPerQuarter(block.timestamp);
        pid++;
    }

    function substractProtocolPrincipal(uint256 _capital) public onlyStrategy {
        protocolPrincipal = protocolPrincipal.sub(_capital);
        protocolPerTimestamp[block.timestamp].principal = protocolPrincipal;
        protocolPerTimestamp[block.timestamp].time = block.timestamp;
        protocolPerTimestamp[block.timestamp].quarterBelonging = getQuarter(block.timestamp);
        protocolPerTimestamp[block.timestamp].timeListPointer = pid;
        protocolPerTimestamp[block.timestamp].power = protocolPerTimestamp[timeList[pid.sub(1)]].power.add(
            protocolPerTimestamp[block.timestamp].time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time).mul(
                protocolPerTimestamp[timeList[pid.sub(1)]].principal
            )
        );
        timeList.push(block.timestamp);
        // Here we control the accumulated protocol power per each quarter
        // Create the quarter checkpoint in case the checkpoint is the first in the epoch
        addProtocolPerQuarter(block.timestamp);
        pid++;
    }

    /**
    function getProtocolDurationByTimestamp(uint256 _timestamp) public view onlyOwner returns(uint256){
        return durationPerTimestamp[_timestamp];
    }
    */
    function getStrategyRewards(address _strategy) public returns (uint96) {
        strategy = IStrategy(_strategy);
        (uint256 numQuarters, uint256 startingQuarter) = getRewardsWindow(strategy.executedAt(), strategy.exitedAt());
        uint256 bablRewards = 0;
        if (numQuarters <= 1) {
            bablRewards = (
                (strategy.capitalAllocated().mul(strategy.exitedAt().sub(strategy.executedAt()))).div(
                    protocolPerQuarter[startingQuarter].quarterPower
                )
            )
                .mul(protocolPerQuarter[startingQuarter].supplyPerQuarter);
        } else {
            // The strategy takes longer than one quarter / epoch
            // We need to calculate the strategy vs. protocol power ratio per each quarter
            uint256[] memory strategyPower = new uint256[](numQuarters); // Strategy power in each Epoch
            uint256[] memory protocolPower = new uint256[](numQuarters); // Protocol power in each Epoch
            for (uint256 i = 0; i <= numQuarters.sub(1); i++) {
                uint256 slotEnding = START_TIME.add(startingQuarter.add(i) * EPOCH_DURATION); // Initialization timestamp at the end of the first slot where the strategy starts its execution
                //uint256 slotStarting = slotEnding.sub(EPOCH_DURATION); // Initialization timestamp at the beginning of the first slot where the strategy starts its execution

                // We iterate all the quarters where the strategy was active
                uint256 percentage = 1;
                if (strategy.executedAt().add(EPOCH_DURATION) > slotEnding) {
                    // We are in the first quarter of the strategy

                    strategyPower[i] = strategy.capitalAllocated().mul(slotEnding.sub(strategy.executedAt()));
                } else if (strategy.executedAt() < slotEnding.sub(EPOCH_DURATION) && slotEnding < strategy.exitedAt()) {
                    // We are in an intermediate quarter different from starting or ending quarters
                    strategyPower[i] = strategy.capitalAllocated().mul(slotEnding.sub(slotEnding.sub(EPOCH_DURATION)));
                } else {
                    strategyPower[i] = strategy.capitalAllocated().mul(
                        strategy.exitedAt().sub(slotEnding.sub(EPOCH_DURATION))
                    );

                    percentage = (block.timestamp.sub(slotEnding.sub(EPOCH_DURATION))).divideDecimal(EPOCH_DURATION);
                }
                protocolPower[i] = protocolPerQuarter[startingQuarter.add(i)].quarterPower;
                bablRewards = bablRewards.add(
                    strategyPower[i]
                        .divideDecimal(protocolPower[i])
                        .multiplyDecimal(protocolPerQuarter[startingQuarter.add(i)].supplyPerQuarter)
                        .multiplyDecimal(percentage)
                );
            }
        }
        uint256 percentageMul =
            bablRewards.preciseMul(strategy.capitalReturned().preciseDiv(strategy.capitalAllocated()));
        if (strategy.capitalAllocated() > strategy.capitalReturned()) {
            // Negative profits
            bablRewards = bablRewards.sub(percentageMul);
        } else {
            bablRewards = bablRewards.add(percentageMul);
        }
        return Safe3296.safe96(bablRewards, 'overflow 96 bits');
    }

    function sendTokensToContributor(address _to, uint256 _amount) public onlyStrategy {
        require(controller.isSystemContract(msg.sender));
        safeBABLTransfer(_to, _amount);
    }

    /* ========= Getter Functions ========= */
    /* ========== View functions ========== */

    function getProtocolPrincipalByTimestamp(uint256 _timestamp) public view onlyOwner returns (uint256) {
        return protocolPerTimestamp[_timestamp].principal;
    }

    function getProtocolPowerPerQuarterByTimestamp(uint256 _timestamp) public view onlyOwner returns (uint256) {
        return protocolPerQuarter[getQuarter(_timestamp)].quarterPower;
    }

    function getProtocolPowerPerQuarterById(uint256 _id) public view onlyOwner returns (uint256) {
        return protocolPerQuarter[_id].quarterPower;
    }

    function getProtocolSupplyPerQuarterByTimestamp(uint256 _timestamp) public view onlyOwner returns (uint256) {
        return protocolPerQuarter[getQuarter(_timestamp)].supplyPerQuarter;
    }

    function getEpochRewards(uint256 epochs) public view returns (uint96[] memory) {
        uint96[] memory tokensPerEpoch = new uint96[](epochs);
        for (uint256 i = 0; i <= epochs - 1; i++) {
            tokensPerEpoch[i] = (uint96(tokenSupplyPerQuarter(i.add(1))));
        }
        return tokensPerEpoch;
    }

    function getCheckpoints() public view returns (uint256) {
        return pid;
    }

    function getQuarter(uint256 _now) public view returns (uint256) {
        uint256 quarter = (_now.sub(START_TIME).preciseDivCeil(EPOCH_DURATION)).div(1e18);
        return quarter.add(1);
    }

    function getRewardsWindow(uint256 _from, uint256 _to) public view returns (uint256, uint256) {
        uint256 quarters = (_to.sub(_from).preciseDivCeil(EPOCH_DURATION)).div(1e18);
        uint256 startingQuarter = (_from.sub(START_TIME).preciseDivCeil(EPOCH_DURATION)).div(1e18);

        return (quarters.add(1), startingQuarter.add(1));
    }

    function getSupplyForPeriod(uint256 _from, uint256 _to) public view returns (uint96[] memory) {
        // check number of quarters and what quarters are they
        (uint256 quarters, uint256 startingQuarter) = getRewardsWindow(_from, _to);
        uint96[] memory supplyPerQuarter = new uint96[](quarters);
        if (quarters <= 1) {
            // Strategy Duration less than a quarter
            supplyPerQuarter[0] = Safe3296.safe96(tokenSupplyPerQuarter(startingQuarter.add(1)), 'overflow 96 bits');
            return supplyPerQuarter;
        } else if (quarters == 2) {
            // Strategy Duration less or equal of 2 quarters - we assume that high % of strategies will have a duration <= 2 quarters avoiding the launch of a for loop
            supplyPerQuarter[0] = Safe3296.safe96(tokenSupplyPerQuarter(startingQuarter), 'overflow 96 bits');
            supplyPerQuarter[1] = Safe3296.safe96(tokenSupplyPerQuarter(startingQuarter.add(1)), 'overflow 96 bits');
            return supplyPerQuarter;
        } else {
            for (uint256 i = 0; i <= quarters.sub(1); i++) {
                supplyPerQuarter[i] = Safe3296.safe96(
                    tokenSupplyPerQuarter(startingQuarter.add(1).add(i)),
                    'overflow 96 bits'
                );
            }
            return supplyPerQuarter;
        }
    }

    function tokenSupplyPerQuarter(uint256 quarter) public view returns (uint96) {
        require(quarter >= 1, 'There are only 1 or more quarters');
        //require(quarter < 513, 'overflow');
        uint256 firstFactor = (SafeDecimalMath.unit().add(DECAY_RATE)).powDecimal(quarter.sub(1));
        uint256 supplyForQuarter = Q1_REWARDS.divideDecimal(firstFactor);

        return Safe3296.safe96(supplyForQuarter, 'overflow 96 bits');
    }

    /* ============ Internal Functions ============ */

    function addProtocolPerQuarter(uint256 _time) internal {
        // TODO CHECK BOUNDS
        if (!isProtocolPerQuarter[getQuarter(_time).sub(1)]) {
            // The quarter is not yet initialized then we create it
            protocolPerQuarter[getQuarter(_time)].quarterNumber = getQuarter(_time);
            if (pid == 0) {
                // The first strategy added in the first epoch
                protocolPerQuarter[getQuarter(_time)].quarterPower = EPOCH_DURATION;
            } else {
                // We just take the proportional power for this quarter from previous quarter
                protocolPerQuarter[getQuarter(_time)].quarterPower = protocolPerTimestamp[_time]
                    .power
                    .mul(_time.sub(getQuarter(_time).mul(EPOCH_DURATION).sub(EPOCH_DURATION)))
                    .div(_time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time));
            }
            protocolPerQuarter[getQuarter(_time)].supplyPerQuarter = tokenSupplyPerQuarter(getQuarter(_time));
            isProtocolPerQuarter[getQuarter(_time).sub(1)] = true;
        } else {
            // Quarter checkpoint already created, it must have been filled with general info
            protocolPerQuarter[getQuarter(_time)].quarterPower = protocolPerQuarter[getQuarter(_time)].quarterPower.add(
                protocolPerTimestamp[_time].power
            );
        }
        protocolPerQuarter[getQuarter(_time)].quarterPrincipal = protocolPrincipal;
    }

    // Safe BABL transfer function, just in case if rounding error causes DistributorRewards to not have enough BABL.
    function safeBABLTransfer(address _to, uint256 _amount) internal {
        uint256 bablBal = babltoken.balanceOf(address(this));
        if (_amount > bablBal) {
            babltoken.transfer(_to, bablBal);
        } else {
            babltoken.transfer(_to, _amount);
        }
    }
}
