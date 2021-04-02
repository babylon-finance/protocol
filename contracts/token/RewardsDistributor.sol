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

/**
 * @title Rewards Distributor implementing the BABL Mining Program
 * @author Babylon Finance
 * Rewards Distributor contract is a smart contract used to calculate and distribute all the BABL rewards of the BABL Mining Program
 * along the time reserve for executed strategies. It implements a supply curve to distribute 500K BABL along the time.
 * The supply curve is designed to optimize the long-term sustainability of the protocol.
 * The rewards are front-loaded but they last for more than 10 years, slowly decreasing quarter by quarter.
 * For that, it houses the state of the protocol power along the time as each strategy power is compared to the whole protocol usage.
 */

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

    uint256 public EPOCH_DURATION = 90 days; // Duration of its EPOCH in days
    uint256 public START_TIME; // Starting time of the rewards distribution

    // 500K BABL allocated to this BABL Mining Program, the first quarter is Q1_REWARDD and the following quarters will follow the supply curve using a decay rate
    uint256 public constant Q1_REWARDS = 53_571_428_571_428_600e6; // First quarter (epoch) BABL rewards
    uint256 public constant DECAY_RATE = 120000000000000000; // 12% quarterly decay rate (each 90 days) (Rewards on Q1 = 1,12 * Rewards on Q2) being Q1= Quarter 1, Q2 = Quarter 2

    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    constructor(TimeLockedToken _bablToken, IBabController _controller) {
        babltoken = _bablToken;
        controller = _controller;
        //START_TIME = block.timestamp;
        START_TIME = 1614618000; //  TODO return to block.timestamp JUST FOR TESTING PURPOSES 2021 MARCH 1 18H CET
    }

    /* ============ External Functions ============ */

    function addProtocolPrincipal(uint256 _capital) public onlyStrategy {
        //console.log('ADDING CAPITAL %s at QUARTER %s timestamp %s',_capital, getQuarter(block.timestamp), block.timestamp);
        protocolPrincipal = protocolPrincipal.add(_capital);
        ProtocolPerTimestamp storage protocolCheckpoint = protocolPerTimestamp[block.timestamp];
        protocolCheckpoint.principal = protocolPrincipal;
        protocolCheckpoint.time = block.timestamp;
        protocolCheckpoint.quarterBelonging = getQuarter(block.timestamp);
        protocolCheckpoint.timeListPointer = pid;
        if (pid == 0) {
            // The very first strategy of all strategies in the mining program
            protocolCheckpoint.power = 0;
        } else {
            // Any other strategy different from the very first one (will have an antecesor)
            protocolCheckpoint.power = protocolPerTimestamp[timeList[pid.sub(1)]].power.add(
                protocolCheckpoint.time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time).mul(
                    protocolPerTimestamp[timeList[pid.sub(1)]].principal
                )
            );
        }

        timeList.push(block.timestamp); // Register of added strategies timestamps in the array for iteration
        // Here we control the accumulated protocol power per each quarter
        // Create the quarter checkpoint in case the checkpoint is the first in the epoch
        _addProtocolPerQuarter(block.timestamp);
        pid++;
    }

    function substractProtocolPrincipal(uint256 _capital) public onlyStrategy {
        //console.log('SUBSTRACTING CAPITAL %s at QUARTER %s on timestamp %s',_capital, getQuarter(block.timestamp),block.timestamp);
        protocolPrincipal = protocolPrincipal.sub(_capital);
        ProtocolPerTimestamp storage protocolCheckpoint = protocolPerTimestamp[block.timestamp];
        protocolCheckpoint.principal = protocolPrincipal;
        protocolCheckpoint.time = block.timestamp;
        protocolCheckpoint.quarterBelonging = getQuarter(block.timestamp);
        protocolCheckpoint.timeListPointer = pid;
        protocolCheckpoint.power = protocolPerTimestamp[timeList[pid.sub(1)]].power.add(
            protocolCheckpoint.time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time).mul(
                protocolPerTimestamp[timeList[pid.sub(1)]].principal
            )
        );
        timeList.push(block.timestamp);
        // Here we control the accumulated protocol power per each quarter
        // Create the quarter checkpoint in case the checkpoint is the first in the epoch
        _addProtocolPerQuarter(block.timestamp);
        pid++;
    }

    function getStrategyRewards(address _strategy) public returns (uint96) {
        //console.log('CALCULATING STRATEGY REWARDS OF %s',_strategy);
        strategy = IStrategy(_strategy);
        (uint256 numQuarters, uint256 startingQuarter) = getRewardsWindow(strategy.executedAt(), strategy.exitedAt());
        uint256 bablRewards = 0;
        if (numQuarters <= 1) {
            //console.log('REWARDS FOR ONLY ONE QUARTER OF %s',_strategy);

            bablRewards = (
                (strategy.capitalAllocated().preciseMul(strategy.exitedAt().sub(strategy.executedAt()))).div(
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

                // We iterate all the quarters where the strategy was active
                uint256 percentage = 1000000000000000000;
                if (strategy.executedAt().add(EPOCH_DURATION) > slotEnding) {
                    // We are in the first quarter of the strategy

                    strategyPower[i] = strategy.capitalAllocated().mul(slotEnding.sub(strategy.executedAt()));
                } else if (strategy.executedAt() < slotEnding.sub(EPOCH_DURATION) && slotEnding < strategy.exitedAt()) {
                    // We are in an intermediate quarter different from starting or ending quarters
                    strategyPower[i] = strategy.capitalAllocated().mul(slotEnding.sub(slotEnding.sub(EPOCH_DURATION)));
                } else {
                    // We are in the last quarter of the strategy
                    percentage = block.timestamp.sub(slotEnding.sub(EPOCH_DURATION)).preciseDiv(slotEnding.sub(slotEnding.sub(EPOCH_DURATION)));
                    
                    strategyPower[i] = strategy.capitalAllocated().mul(
                        strategy.exitedAt().sub(slotEnding.sub(EPOCH_DURATION))
                    );

                    
                }
                protocolPower[i] = protocolPerQuarter[startingQuarter.add(i)].quarterPower;
                
                console.log('QUARTER NUM ITERATION #',i.add(1));
                console.log('Strategy Power',strategyPower[i]);
                console.log('Strategy Capital Allocated',strategy.capitalAllocated());
                console.log('BABL REWARDS UNTIL NOW',bablRewards);
                console.log('Protocol Power',protocolPower[i]);
                console.log('SUPPLY this quarter',protocolPerQuarter[startingQuarter.add(i)].supplyPerQuarter);
                console.log('Percentage', percentage);


                
                bablRewards = bablRewards.add(
                    strategyPower[i]
                        .preciseDiv(protocolPower[i])
                        .preciseMul(protocolPerQuarter[startingQuarter.add(i)].supplyPerQuarter).preciseMul(percentage)
                        
                );
                console.log('NEW BABL REWARDS',bablRewards);

            }
        }
        uint256 percentageMul =
            bablRewards.preciseMul(strategy.capitalReturned().preciseDiv(strategy.capitalAllocated()));
        if (strategy.capitalAllocated() > strategy.capitalReturned()) {
            // Negative profits
            bablRewards = bablRewards.sub(bablRewards.sub(percentageMul));
        } else {
            bablRewards = bablRewards.add(percentageMul.sub(bablRewards));
        }
        console.log('CAPITAL RETURNED',strategy.capitalReturned());
        console.log('FINAL BABL REWARDS without safe96',bablRewards);
        console.log('FINAL BABL REWARDS with safe96',Safe3296.safe96(bablRewards, 'overflow 96 bits'));

        return Safe3296.safe96(bablRewards, 'overflow 96 bits');
    }

    function sendTokensToContributor(address _to, uint256 _amount) public onlyStrategy {
        require(controller.isSystemContract(msg.sender));
        _safeBABLTransfer(_to, _amount);
    }

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

    function getEpochRewards(uint256 epochs) public pure returns (uint96[] memory) {
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

    function tokenSupplyPerQuarter(uint256 quarter) public pure returns (uint96) {
        require(quarter >= 1, 'There are only 1 or more quarters');
        //require(quarter < 513, 'overflow');
        uint256 firstFactor = (SafeDecimalMath.unit().add(DECAY_RATE)).powDecimal(quarter.sub(1));
        uint256 supplyForQuarter = Q1_REWARDS.divideDecimal(firstFactor);

        return Safe3296.safe96(supplyForQuarter, 'overflow 96 bits');
    }

    function checkProtocol(uint256 _time)
        public
        view
        returns (
        uint256 principal,
        uint256 time,
        uint256 quarterBelonging, 
        uint256 timeListPointer,
        uint256 power
        )
    {
        return (
            protocolPerTimestamp[_time].principal,
            protocolPerTimestamp[_time].time,
            protocolPerTimestamp[_time].quarterBelonging,
            protocolPerTimestamp[_time].timeListPointer,
            protocolPerTimestamp[_time].power
        );
    }

    /* ============ Internal Functions ============ */

    function _addProtocolPerQuarter(uint256 _time) internal {
        ////console.log('UPDATE PROTOCOL QUARTER at timestamp %s having TIME INPUT as %s', block.timestamp, _time);
        ProtocolPerQuarter storage protocolCheckpoint = protocolPerQuarter[getQuarter(_time)];
        if (!isProtocolPerQuarter[getQuarter(_time).sub(1)]) {
            // The quarter is not yet initialized then we create it
            protocolCheckpoint.quarterNumber = getQuarter(_time);
            if (pid == 0) {
                // The first strategy added in the first epoch
                protocolCheckpoint.quarterPower = 0;
            } else {
                // Each time a new epoch starts with either a new strategy execution or finalization
                // We just take the proportional power for this quarter from previous quarter
                // TODO REVIEW IT AVOID STARTING WITH PREVIOUS POWER INHERITANCE AND JUST CALCULATE 0 + REAL NEW QUARTER DATA (BASED ON PRINCIPAL)
                // TODO UPDATE PREVIOUS QUARTER POWER AS WELL
                protocolCheckpoint.quarterPower = protocolPerTimestamp[_time]
                    .power
                    .mul(_time.sub(getQuarter(_time).mul(EPOCH_DURATION).sub(EPOCH_DURATION)))
                    .div(_time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time));
            }
            protocolCheckpoint.supplyPerQuarter = tokenSupplyPerQuarter(getQuarter(_time));
            isProtocolPerQuarter[getQuarter(_time).sub(1)] = true;
        } else {
            // Quarter checkpoint already created, it must have been filled with general info
            protocolCheckpoint.quarterPower = protocolCheckpoint.quarterPower.add(
                protocolPerTimestamp[_time].power
            );
        }
        protocolCheckpoint.quarterPrincipal = protocolPrincipal;
        //console.log('UPDATE PROTOCOL QUARTER - PROTOCOL POWER IS %s at time %s',protocolCheckpoint.quarterPower, block.timestamp);
    }

    // Safe BABL transfer function, just in case if rounding error causes DistributorRewards to not have enough BABL.
    function _safeBABLTransfer(address _to, uint256 _amount) internal {
        ////console.log('SAFE SENDING %s BABL TO %s at timestamp %s', _amount, _to, block.timestamp);
        uint256 bablBal = babltoken.balanceOf(address(this));
        if (_amount > bablBal) {
            babltoken.transfer(_to, bablBal);
        } else {
            babltoken.transfer(_to, _amount);
        }
    }
}
