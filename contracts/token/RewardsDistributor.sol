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

    /* ============ State Variables ============ */

    // Controller contract
    IBabController public controller;

    // Strategies that the reward calculations belong to
    IStrategy public strategy;

    // BABL Token contract
    TimeLockedToken public babltoken;

    struct PrincipalPerTimestamp {
        // Allocation points per timestamp along the time
        uint256 principal;
        uint256 time;
        uint256 timeListPointer; // Pointer to the array of times in order to enable the possibility of iteration
    }

    uint256 public protocolPrincipal = 0; // Total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all strategy pools.
    mapping(uint256 => PrincipalPerTimestamp) principalPerTimestamp; // Total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all strategy pools.
    uint256[] public timeList; // TODO needs to be updated anytime there is a checkpoint of new strategy changing
    uint256 public pid = 0; // Initialization of the ID assigning timeListPointer to the checkpoint number

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

    function addProtocolPrincipal(uint256 _capital) public onlyOwner {
        protocolPrincipal = protocolPrincipal.add(_capital);
        principalPerTimestamp[block.timestamp].principal = protocolPrincipal;
        principalPerTimestamp[block.timestamp].time = block.timestamp;
        principalPerTimestamp[block.timestamp].timeListPointer = pid;
        timeList[pid] = block.timestamp;
        pid++;
    }

    function substractProtocolPrincipal(uint256 _capital) public onlyOwner {
        protocolPrincipal = protocolPrincipal.sub(_capital);
        principalPerTimestamp[block.timestamp].principal = protocolPrincipal;
        principalPerTimestamp[block.timestamp].time = block.timestamp;
        principalPerTimestamp[block.timestamp].timeListPointer = pid;
        timeList[pid] = block.timestamp;
        pid++;
    }

    function getProtocolPrincipalByTimestamp(uint256 _timestamp) public view onlyOwner returns (uint256) {
        return principalPerTimestamp[_timestamp].principal;
    }

    /** 
    function getProtocolDurationByTimestamp(uint256 _timestamp) public view onlyOwner returns(uint256){
        return durationPerTimestamp[_timestamp];
    }
    */

    function getStrategyRewards(address _strategy) public onlyOwner returns (uint96) {
        (uint256 numQuarters, uint256 startingQuarter, uint256 endingQuarter) =
            getRewardsWindow(IStrategy(_strategy).executedAt(), IStrategy(_strategy).exitedAt());
        uint96[] memory quarters = new uint96[](numQuarters); // Array to allocate the corresponding BABL rewards per quarter
        uint96 rewards = 0; // Total Strategy Rewards
        uint256 counterOfTime = IStrategy(_strategy).executedAt(); // Timestamp counter to move along the Protocol Principal changes during the strategy duration
        uint256 indexCounter = 0; // Counter to iterate over the timeList of timestamps that will be used to iterate the mapping
        uint256 counterOfPrincipal = 0; // Counter to calculate the Principal of the Protocol in the period of the strategy
        uint256 endOfSlotTime = 0;
        // Check if the strategy duration is within an epoch, all calculations are simplified in that case
        if (numQuarters <= 1) {
            uint256 counterOfPower = 0;
            uint256 strategyPower =
                IStrategy(_strategy).capitalAllocated().mul(IStrategy(_strategy).exitedAt().sub(IStrategy(_strategy).executedAt()));
            while (principalPerTimestamp[counterOfTime].time < IStrategy(_strategy).exitedAt()) {
                counterOfPrincipal = principalPerTimestamp[counterOfTime].principal;
                indexCounter = principalPerTimestamp[counterOfTime].timeListPointer;
                indexCounter++;
                endOfSlotTime = timeList[indexCounter]; // The following timestamp / it could be the ending timestamp
                require(endOfSlotTime == principalPerTimestamp[endOfSlotTime].time, 'time slot mismatch');
                counterOfPower = counterOfPower.add(
                    counterOfPrincipal.mul(
                        principalPerTimestamp[endOfSlotTime].time.sub(principalPerTimestamp[counterOfTime].time)
                    )
                ); // Time difference for the slot
                counterOfTime = endOfSlotTime;
            }
            quarters[0] = Safe3296.safe96(tokenSupplyPerQuarter(startingQuarter.add(1)), 'overflow 96 bits');
            uint256 powerRatio = strategyPower.div(counterOfPower); // Strategy Power vs. Protocol Power during the strategy time (not the epoch)
            uint256 percentageOfQuarter =
                IStrategy(_strategy).exitedAt().sub(IStrategy(_strategy).executedAt()).div(EPOCH_DURATION); // % of time within the epoch
            rewards = Safe3296.safe96(
                uint256(quarters[0]).mul(powerRatio).mul(percentageOfQuarter),
                'overflow 96 bits'
            );
            return rewards;
        } else {
            uint256[] memory powerRatio = new uint256[](numQuarters); // Power ratio in each Epoch
            uint256[] memory percentageOfQuarter = new uint256[](numQuarters); // percentage of Quarter in each Epoch (starting and ending slots could not be 100% but intermediate slots should be equalt to its Epoch duration)
            uint256[] memory strategyPower = new uint256[](numQuarters); // Strategy power in each Epoch
            uint256[] memory counterOfPower = new uint256[](numQuarters); // Protocol power in each Epoch
            uint256 counterEpoch = 0; // Counter of epoch under calculations
            bool flag = false; // flag to control whether we are changing Epoch in the middle of timestamps
            uint256 tempPower = 0; // Used with the flag to add manage unchanged power between epochs, once it passes it is restored with the flag into zero.

            for (uint256 i = 0; i <= quarters.length - 1; i++) {
                powerRatio[i] = 0; //Initialization
                percentageOfQuarter[i] = 0; //Initialization
                counterOfPower[i] = 0; //Initialization
                counterEpoch = startingQuarter.add(i); //Initialization # of the slot
                uint256 counterSlotLimit = counterEpoch * EPOCH_DURATION; // Initialization timestamp of the end of the slot
                uint256 counterSlotStarting = counterSlotLimit.sub(EPOCH_DURATION); // Initialization timestamp of the beginning of the slot
                uint256 strategyDuration = 0;
                if (IStrategy(_strategy).executedAt().add(EPOCH_DURATION) < counterSlotLimit) {
                    // We are in the first epoch of the strategy
                    strategyPower[i] = IStrategy(_strategy).capitalAllocated().mul(
                        counterSlotLimit.sub(IStrategy(_strategy).executedAt())
                    );
                    strategyDuration = counterSlotLimit.sub(IStrategy(_strategy).executedAt());
                } else if (
                    IStrategy(_strategy).executedAt() < counterSlotStarting && counterSlotLimit < IStrategy(_strategy).exitedAt()
                ) {
                    // If we are in an intermediate quarter
                    strategyPower[i] = IStrategy(_strategy).capitalAllocated().mul(
                        counterSlotLimit.sub(counterSlotStarting)
                    );
                    strategyDuration = EPOCH_DURATION; // The strategy is ongoing during a complete epoch
                } else {
                    // It is the last slot
                    strategyPower[i] = IStrategy(_strategy).capitalAllocated().mul(
                        IStrategy(_strategy).exitedAt().sub(counterSlotStarting)
                    );
                    strategyDuration = IStrategy(_strategy).exitedAt().sub(counterSlotStarting);
                }

                while (
                    principalPerTimestamp[counterOfTime].time < counterSlotLimit &&
                    principalPerTimestamp[counterOfTime].time < IStrategy(_strategy).exitedAt()
                ) {
                    // Recurring calculations within the same Epoch per all the slots where there was a new or finished strategy
                    counterOfPrincipal = principalPerTimestamp[counterOfTime].principal; // Check principal amount in specific time stamp
                    indexCounter = principalPerTimestamp[counterOfTime].timeListPointer;
                    indexCounter++;

                    // TODO CHECK OUT OF BOUNDS IF IT IS THE LAST STRATEGY BEING FINISHED

                    endOfSlotTime = timeList[indexCounter]; // The following timestamp / it could be the ending timestamp
                    require(endOfSlotTime == principalPerTimestamp[endOfSlotTime].time, 'time slot mismatch');
                    if (counterSlotLimit < endOfSlotTime) {
                        // Situation where We are changing Epoch but we have to give to each epoch the real duration of the strategy
                        flag = true;
                        tempPower = counterOfPower[i].add(
                            counterOfPrincipal.mul(endOfSlotTime.sub(principalPerTimestamp[counterSlotLimit].time))
                        ); // Partial power entering into the new epoch
                        counterOfPower[i] = counterOfPower[i].add(
                            counterOfPrincipal.mul(counterSlotLimit.sub(principalPerTimestamp[counterOfTime].time))
                        ); // Partial power inside the current epoch
                    } else {
                        flag = false; // reset (if any) the flag which is only activated when there is a change of epoch between two time stamps.
                        // In case of a change between epoch between two protocol principal changes (time stamps) we recover
                        counterOfPower[i] = tempPower.add(counterOfPower[i]).add(
                            counterOfPrincipal.mul(principalPerTimestamp[endOfSlotTime].time).sub(
                                principalPerTimestamp[counterOfTime].time
                            )
                        ); // Time difference for the slot
                        tempPower = 0; // Reset the flag that is only used when changing between epochs.
                    }
                    counterOfTime = endOfSlotTime;
                }
                quarters[i] = Safe3296.safe96(tokenSupplyPerQuarter(counterEpoch.add(1)), 'overflow 96 bits'); // MAX BABL Rewards for each quarter/epoch
                powerRatio[i] = strategyPower[i].div(counterOfPower[i]); // Strategy Power vs. Protocol Power during the epoch under calculation
                percentageOfQuarter[i] = strategyDuration.div(EPOCH_DURATION); // % Used to provide the MAX BABL rewards depending on the exact execution blocks
                rewards = Safe3296.safe96(
                    uint256(rewards).add(quarters[i]).mul(powerRatio[i]).mul(percentageOfQuarter[i]),
                    'overflow 96 bits'
                );
            }
        }
        return rewards;
    }

    function sendTokensToContributor(address _to, uint256 _amount) public onlyOwner {
        require(controller.isSystemContract(msg.sender));
        safeBABLTransfer(_to, _amount);
    }

    /* ============ Getter Functions ============ */
    /* ========== View functions ========== */

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

    function getRewardsWindow(uint256 _from, uint256 _to)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 quarters = (_to.sub(_from).preciseDivCeil(EPOCH_DURATION)).div(1e18);
        uint256 startingQuarter = (_from.sub(START_TIME).preciseDivCeil(EPOCH_DURATION)).div(1e18);
        uint256 endingQuarter = startingQuarter.add(quarters);

        return (quarters.add(1), startingQuarter, endingQuarter);
    }

    function getSupplyForPeriod(uint256 _from, uint256 _to) public view returns (uint96[] memory) {
        // check number of quarters and what quarters are they
        (uint256 quarters, uint256 startingQuarter, uint256 endingQuarter) = getRewardsWindow(_from, _to);
        uint96[] memory supplyPerQuarter = new uint96[](quarters);
        if (quarters <= 1) {
            // Strategy Duration less than a quarter
            supplyPerQuarter[0] = Safe3296.safe96(tokenSupplyPerQuarter(endingQuarter.add(1)), 'overflow 96 bits');
            return supplyPerQuarter;
        } else if (quarters <= 2) {
            // Strategy Duration less or equal of 2 quarters - we assume that high % of strategies will have a duration <= 2 quarters avoiding the launch of a for loop
            supplyPerQuarter[0] = Safe3296.safe96(tokenSupplyPerQuarter(startingQuarter), 'overflow 96 bits');
            supplyPerQuarter[1] = Safe3296.safe96(tokenSupplyPerQuarter(endingQuarter), 'overflow 96 bits');
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

    function tokenSupplyPerQuarter(uint256 quarter) public pure returns (uint256) {
        require(quarter >= 1, 'There are only 1 or more quarters');
        //require(quarter < 513, 'overflow');

        uint256 firstFactor = (SafeDecimalMath.unit().add(DECAY_RATE)).powDecimal(quarter.sub(1));
        uint256 supplyForQuarter = Q1_REWARDS.divideDecimal(firstFactor);

        return supplyForQuarter;
    }

    /* ============ Internal Functions ============ */

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
