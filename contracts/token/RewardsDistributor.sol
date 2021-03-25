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
import {IGarden} from '../interfaces/IGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';

import {IRewardsDistributor} from  "../interfaces/IRewardsDistributor.sol";
import {RewardsSupplySchedule} from  "./RewardsSupplySchedule.sol";


import {SafeDecimalMath} from "../lib/SafeDecimalMath.sol";
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';



contract BABLRewardsDistributor is Ownable {
    using SafeMath for uint;
    using SafeMath for uint256;
    using PreciseUnitMath for uint;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint;
    using SafeDecimalMath for uint256;
    using Math for uint;
    using Math for uint256;

    /* ========== Events ========== */


    
    /* ============ Modifiers ============ */


    /* ============ State Variables ============ */

    // Babylon Controller Address
    IBabController public controller;

    // Garden that these strategies belong to
    IGarden public garden;

    // Strategies that the reward calculations belong to
    IStrategy public strategy;

    // Strategies that the reward calculations belong to
    RewardsSupplySchedule public supplySchedule;

    struct AccountStrategies{
        bool isGardenCreator;
        bool isStrategist;
        bool isSteward;
        bool isLP;
        uint96 votes;
        uint96 principalInStrategy;
        uint96 rewardsInStrategy;
        bool claimedRewards;

    }
    struct AccountTokenRewards {
        uint256 tokensRewardedAlready;
        uint256 availableTokenRewards;
        uint256 lastClaim;
        mapping(address => AccountStrategies) accountStrategies; // mapping of strategies by the account
    }

    mapping(address => AccountTokenRewards) public accountTokenRewards;

    struct StrategyTokenRewards {
        address gardenBelonging;
        int256 strategyProfit;
        uint256 strategyPrincipal;
        uint256 strategyStart;
        uint256 strategyEnd;
        uint256 strategyDuration;
        uint96 potentialTokenRewards;
        uint96 finalTokenRewards;
        address strategist;
        uint256 lastUpdate;
        address[] voters;
        //mapping(address => int256) votes;
    }

    mapping(address => StrategyTokenRewards) public strategyTokenRewards;
    mapping(address => bool) public strategyIncluded;

    struct RewardsProtocol {
        uint256 protocolPrincipal;
        uint256 protocolDuration;
        uint256 quarterStart;
        uint256 quarterEnd;
        uint96 potentialProtocolTokenRewards;
        uint96 availableProtocolTokenRewards;
        uint256 lastUpdate;
    }
    mapping(uint256=> RewardsProtocol) public rewardsProtocol;

    uint256 public EPOCH_DURATION = 90 days;




    /* ============ Functions ============ */

    /* ============ Constructor ============ */


    constructor(RewardsSupplySchedule _supply, uint epochs) {
        uint256 timestamp = block.timestamp;
        for (uint i=0; i <= epochs; i++) {
            rewardsProtocol[i].potentialProtocolTokenRewards = uint96(_supply.tokenSupplyPerQuarter(i));
            rewardsProtocol[i].lastUpdate = timestamp;
        }

    }


    /* ============ External Functions ============ */


    /* ============ Getter Functions ============ */

    function getFinalizedStrategiesinGarden(IGarden _garden) public returns (uint) {
        // TODO CHECK GAS REDUCTION 

        address[] memory finalizedStrategies = _garden.getFinalizedStrategies();
        uint256 strategiesCount = 0 ;
        
        for (uint i = 0 ; i <= finalizedStrategies.length ; i++) {
                        
            if (!strategyIncluded[address(finalizedStrategies[i])]) {
                // Only updates new finalized strategies 
                IStrategy updatingStrategy = IStrategy(finalizedStrategies[i]);

                strategiesCount++;
                StrategyTokenRewards storage newFinalizedStrategy = strategyTokenRewards[address(updatingStrategy)];    
                newFinalizedStrategy.gardenBelonging = address(_garden);
                newFinalizedStrategy.strategyProfit = updatingStrategy.profit();
                newFinalizedStrategy.strategyPrincipal = updatingStrategy.capitalAllocated();
                newFinalizedStrategy.strategyStart = updatingStrategy.executedAt();
                newFinalizedStrategy.strategyEnd = updatingStrategy.exitedAt();
                newFinalizedStrategy.strategyDuration = newFinalizedStrategy.strategyEnd.sub(newFinalizedStrategy.strategyStart);
                newFinalizedStrategy.potentialTokenRewards = uint96(SafeDecimalMath.multiplyDecimal(newFinalizedStrategy.strategyPrincipal,newFinalizedStrategy.strategyDuration));
                newFinalizedStrategy.finalTokenRewards = uint96(0); // TODO To be calculated depending on profit
                newFinalizedStrategy.strategist = address(updatingStrategy.strategist());
                newFinalizedStrategy.voters = updatingStrategy.voters();
                newFinalizedStrategy.lastUpdate = block.timestamp;
                // we include it in the mapping to use a filter for updates
                strategyIncluded[address(updatingStrategy)]=true;
            }
            
        }
        
        return strategiesCount; // Returns the number of strategies updated
    }


    /* ========== View functions ========== */

    /**
     * @notice Retrieve the length of the finalized strategies in a garden array
     */
    function finalizedStrategiesinGardenLength(IGarden _garden) external view returns (uint) {
        return _garden.getFinalizedStrategies().length;
    }


}
