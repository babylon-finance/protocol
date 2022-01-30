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

import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';

import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';
import {Errors, _require} from '../lib/BabylonErrors.sol';

import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IRewardsAssistant} from '../interfaces/IRewardsAssistant.sol';
import {IProphets} from '../interfaces/IProphets.sol';

/**
 * @title Rewards Assistant is an assistant contract for Rewards Distributor
 * @author Babylon Finance
 */
contract RewardsAssistant is OwnableUpgradeable, IRewardsAssistant {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using PreciseUnitMath for uint256;
    using PreciseUnitMath for int256;
    using SafeDecimalMath for uint256;
    using SafeDecimalMath for int256;
    using Math for uint256;
    using Math for int256;

    /* ========== Events ========== */

    /* ============ Modifiers ============ */

    /* ============ Constants ============ */
    // 500K BABL allocated to this BABL Mining Program, the first quarter is Q1_REWARDS
    // and the following quarters will follow the supply curve using a decay rate
    uint256 private constant Q1_REWARDS = 53_571_428_571_428_600e6; // First quarter (epoch) BABL rewards
    // 12% quarterly decay rate (each 90 days)
    // (Rewards on Q1 = 1,12 * Rewards on Q2) being Q1= Quarter 1, Q2 = Quarter 2
    uint256 private constant DECAY_RATE = 12e16;
    // Duration of its EPOCH in days  // BABL & profits split from the protocol
    uint256 private constant EPOCH_DURATION = 90 days;
    // DAI normalize asset
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    // NFT Prophets
    IProphets private constant PROPHETS_NFT = IProphets(0x26231A65EF80706307BbE71F032dc1e5Bf28ce43);

    /* ============ State Variables ============ */

    // Instance of the Controller contract
    IBabController private controller;

    // Rewards Distributor
    IRewardsDistributor private rewardsDistributor;

    // Starting time of the rewards distribution
    uint256 private START_TIME;

    /* ============ Constructor ============ */

    function initialize(IBabController _controller) public {
        OwnableUpgradeable.__Ownable_init();
        _require(address(_controller) != address(0), Errors.ADDRESS_IS_ZERO);
        controller = _controller;
        rewardsDistributor = IRewardsDistributor(controller.rewardsDistributor());
        START_TIME = IRewardsDistributor(rewardsDistributor).START_TIME();
    }

    /* ============ External Functions ============ */

    /* ========== View functions ========== */

    /**
     * Calculates the profits and BABL that a contributor should receive from a series of finalized strategies
     * @param _garden                   Garden to which the strategies and the user must belong to
     * @param _contributor              Address of the contributor to check
     * @param _finalizedStrategies      List of addresses of the finalized strategies to check
     * @return Array of size 8 with the following distribution:
     * rewards[0]: Strategist BABL
     * rewards[1]: Strategist Profit
     * rewards[2]: Steward BABL
     * rewards[3]: Steward Profit
     * rewards[4]: LP BABL
     * rewards[5]: total BABL
     * rewards[6]: total Profits
     * rewards[7]: Creator bonus
     */
    function getRewards(
        address _garden,
        address _contributor,
        address[] calldata _finalizedStrategies
    ) public view override returns (uint256[] memory) {
        _require(controller.isGarden(_garden), Errors.ONLY_ACTIVE_GARDEN);
        uint256[] memory totalRewards = new uint256[](8);
        uint256 claimedAt;
        (, , claimedAt, , , , , , , ) = IGarden(_garden).getContributor(_contributor);
        for (uint256 i = 0; i < _finalizedStrategies.length; i++) {
            // Security check
            _require(IGarden(_garden).isGardenStrategy(_finalizedStrategies[i]), Errors.STRATEGY_GARDEN_MISMATCH);

            uint256[] memory tempRewards = new uint256[](8);

            tempRewards = _getStrategyProfitsAndBABL(_garden, _finalizedStrategies[i], _contributor, claimedAt);
            totalRewards[0] = totalRewards[0].add(tempRewards[0]);
            totalRewards[1] = totalRewards[1].add(tempRewards[1]);
            totalRewards[2] = totalRewards[2].add(tempRewards[2]);
            totalRewards[3] = totalRewards[3].add(tempRewards[3]);
            totalRewards[4] = totalRewards[4].add(tempRewards[4]);
            totalRewards[5] = totalRewards[5].add(tempRewards[5]);
            totalRewards[6] = totalRewards[6].add(tempRewards[6]);
            totalRewards[7] = totalRewards[7].add(tempRewards[7]);
        }

        return totalRewards;
    }

    /**
     * Get an estimation of user rewards for active strategies
     * @param _strategy        Address of the strategy to estimate BABL rewards
     * @param _contributor     Address of the garden contributor
     * @return Array of size 8 with the following distribution:
     * rewards[0]: Strategist BABL
     * rewards[1]: Strategist Profit
     * rewards[2]: Steward BABL
     * rewards[3]: Steward Profit
     * rewards[4]: LP BABL
     * rewards[5]: total BABL
     * rewards[6]: total Profits
     * rewards[7]: Creator bonus
     */
    function estimateUserRewards(address _strategy, address _contributor)
        external
        view
        override
        returns (uint256[] memory)
    {
        // strategyDetails array mapping:
        // strategyDetails[0]: executedAt
        // strategyDetails[1]: exitedAt
        // strategyDetails[2]: updatedAt
        // strategyDetails[3]: enteredAt
        // strategyDetails[4]: totalPositiveVotes
        // strategyDetails[5]: totalNegativeVotes
        // strategyDetails[6]: capitalAllocated
        // strategyDetails[7]: capitalReturned
        // strategyDetails[8]: expectedReturn
        // strategyDetails[9]: strategyRewards
        // strategyDetails[10]: profitValue
        // strategyDetails[11]: distanceValue
        // strategyDetails[12]: startingGardenSupply
        // strategyDetails[13]: endingGardenSupply
        // profitData array mapping:
        // profitData[0]: profit
        // profitData[1]: distance

        uint256[] memory rewards = new uint256[](8);
        if (IStrategy(_strategy).isStrategyActive()) {
            address garden = address(IStrategy(_strategy).garden());
            (address strategist, uint256[] memory strategyDetails, bool[] memory profitData) =
                _estimateStrategyRewards(_strategy);
            // Get the contributor share % within the strategy window out of the total garden and users
            uint256 contributorShare = rewardsDistributor.getSafeUserSharePerStrategy(garden, _contributor, _strategy);
            rewards = _getRewardsPerRole(
                garden,
                _strategy,
                strategist,
                _contributor,
                contributorShare,
                strategyDetails,
                profitData
            );
            // add Prophets NFT bonus if staked in the garden
            rewards = _boostRewards(garden, _contributor, rewards, strategyDetails);
        }
        return rewards;
    }

    /**
     * Get an estimation of strategy BABL rewards for active strategies in the mining program
     * @param _strategy        Address of the strategy to estimate BABL rewards
     * @return the estimated BABL rewards
     */
    function estimateStrategyRewards(address _strategy) external view override returns (uint256) {
        if (IStrategy(_strategy).isStrategyActive()) {
            (, uint256[] memory strategyDetails, ) = _estimateStrategyRewards(_strategy);
            return strategyDetails[9];
        } else {
            return 0;
        }
    }

    /**
     * Apply specific BABL mining weights to baseline BABL mining rewards based on mining benchmark params
     * @param _returned           Strategy capital returned
     * @param _allocated          Strategy capital allocated
     * @param _rewards            Strategy baseline BABL rewards
     * @param _executedAt         Strategy timestamp of initial execution
     */
    function getBenchmarkRewards(
        uint256 _returned,
        uint256 _allocated,
        uint256 _rewards,
        uint256 _executedAt
    ) public view override returns (uint256) {
        // We categorize the strategy APY profits into one of the 3 segments (very bad, regular and cool strategies)
        // Bad and regular will be penalized from bigger penalization to lower
        // Cool strategies will be boosted
        // As we get real time profit (returned / allocated) we need to annualize the strategy profits (APY)
        // Real time profit
        uint256[5] memory benchmark = rewardsDistributor.getBenchmark();
        uint256 percentageProfit = _returned.preciseDiv(_allocated);
        // Time weighted profit if > 1e18 duration less than 1 year, < 1e18 longer than 1 year
        uint256 timedAPY =
            uint256(365 days).preciseDiv(block.timestamp > _executedAt ? block.timestamp.sub(_executedAt) : 1);
        uint256 returnedAPY; // initialization for absolute return APY (in reserve asset decimals)
        uint256 rewardsFactor;
        if (percentageProfit >= 1e18) {
            // Strategy is on positive profit
            // We calculate expected absolute returns in reserve asset decimals
            // If strategy is less than 1 year, APY earnings will be higher
            // else, APY earnings will be lower than today (we need to estimate annualized earnings)
            returnedAPY = _allocated.add(_returned.sub(_allocated).preciseMul(timedAPY));
        } else {
            // Strategy is in loss
            // We calculate expected absolute returns in reserve asset decimals
            // If strategy is less than 1 year, APY loses will be higher
            // else, APY loses will be lower than today (we need to estimate annualized loses)
            returnedAPY = _allocated.sub(_returned).preciseMul(timedAPY);
            returnedAPY = returnedAPY < _allocated ? _allocated.sub(returnedAPY) : 0;
        }
        // Now we normalize into 18 decimals the estimated APY profit percentage using expected return APY
        uint256 profitAPY = returnedAPY.preciseDiv(_allocated);
        // TODO: Replace _allocated by avgCapitalAllocated to handle adding or removing capital from strategy
        // with lower impact along the time
        if (profitAPY < benchmark[0]) {
            // Segment 1:
            // Bad strategy, usually gets penalty by benchmark[2] factor
            rewardsFactor = benchmark[2];
        } else if (profitAPY < benchmark[1]) {
            // Segment 2:
            // Not a cool strategy, can get penalty by benchmark[3] factor
            rewardsFactor = benchmark[3];
        } else {
            // Segment 3:
            // A real cool strategy, can get boost by benchmark[4] factor. Must be always >= 1e18
            rewardsFactor = benchmark[4];
        }
        return
            _rewards.preciseMul(rewardsDistributor.bablPrincipalWeight()).add(
                _rewards.preciseMul(rewardsDistributor.bablProfitWeight()).preciseMul(percentageProfit).preciseMul(
                    rewardsFactor
                )
            );
    }

    /* ============ Internal Functions ============ */

    /* ========== Internal View functions ========== */

    /**
     * Get an estimation of user rewards for active strategies
     * @param _garden               Address of the garden
     * @param _strategy             Address of the strategy to estimate rewards
     * @param _strategist           Address of the strategist
     * @param _contributor          Address of the garden contributor
     * @param _contributorShare     Contributor share in a specific time
     * @param _strategyDetails      Details of the strategy in that specific moment
     * @param _profitData           Array of profit Data (if profit as well distance)
     * @return Array of size 8 with the following distribution:
     * rewards[0]: Strategist BABL
     * rewards[1]: Strategist Profit
     * rewards[2]: Steward BABL
     * rewards[3]: Steward Profit
     * rewards[4]: LP BABL
     * rewards[5]: total BABL
     * rewards[6]: total Profits
     * rewards[7]: Creator bonus
     */
    function _getRewardsPerRole(
        address _garden,
        address _strategy,
        address _strategist,
        address _contributor,
        uint256 _contributorShare,
        uint256[] memory _strategyDetails,
        bool[] memory _profitData
    ) internal view returns (uint256[] memory) {
        uint256[] memory rewards = new uint256[](8);
        // rolesWeight[0]: strategist babl weight
        // rolesWeight[1]: strategist profit weight
        // rolesWeight[2]: stewards babl weight
        // rolesWeight[3]: stewards profit weight
        // rolesWeight[4]: lp babl weight
        // rolesWeight[5]: lp profit weight (not used for rewards as it is compounded)
        // rolesWeight[6]: garden creator
        uint256[7] memory rolesWeight = rewardsDistributor.getRoleWeights(_garden);
        // Get strategist BABL rewards in case the contributor is also the strategist of the strategy
        rewards[0] = _strategist == _contributor
            ? _getStrategyStrategistBabl(_strategyDetails, _profitData, rolesWeight[0])
            : 0;
        // Get strategist profit
        rewards[1] = (_strategist == _contributor && _profitData[0] == true)
            ? _getStrategyStrategistProfits(_strategyDetails[10], rolesWeight[1])
            : 0;
        // Get steward rewards
        rewards[2] = _getStrategyStewardBabl(_strategy, _contributor, _strategyDetails, _profitData, rolesWeight[2]);
        // If not profits _getStrategyStewardsProfits should not execute
        rewards[3] = _profitData[0] == true
            ? _getStrategyStewardProfits(_strategy, _contributor, _strategyDetails, _profitData, rolesWeight[3])
            : 0;
        // Get LP rewards
        // Contributor share is fluctuating along the way in each new deposit
        rewards[4] = _getStrategyLPBabl(_strategyDetails[9], _contributorShare, rolesWeight[4]);
        // Total BABL including creator bonus (if any)
        rewards[5] = _getCreatorBonus(
            _garden,
            _contributor,
            rewards[0].add(rewards[2]).add(rewards[4]),
            rolesWeight[6]
        );
        // Total profit
        rewards[6] = rewards[1].add(rewards[3]);
        // Creator bonus
        rewards[7] = rewards[5] > (rewards[0].add(rewards[2]).add(rewards[4]))
            ? rewards[5].sub(rewards[0].add(rewards[2]).add(rewards[4]))
            : 0;
        return rewards;
    }

    /**
     * Boost BABL Rewards in case of a staked NFT prophet
     * @param _garden           Garden address
     * @param _contributor      Contributor address
     * @param _rewards          Precalculated rewards array
     * @param _strategyDetails  Array with strategy context
     * @return Rewards array with boosted rewards (if any)
     */
    function _boostRewards(
        address _garden,
        address _contributor,
        uint256[] memory _rewards,
        uint256[] memory _strategyDetails
    ) internal view returns (uint256[] memory) {
        // _prophetBonus[0]: NFT id
        // _prophetBonus[1]: BABL loot
        // _prophetBonus[2]: strategist NFT bonus
        // _prophetBonus[3]: steward NFT bonus (voter)
        // _prophetBonus[4]: LP NFT bonus
        // _prophetBonus[5]: creator bonus
        // _prophetBonus[6]: stake NFT ts
        uint256[7] memory prophetBonus = PROPHETS_NFT.getStakedProphetAttrs(_contributor, _garden);
        // We calculate the percentage to apply or if any, depending on staking ts
        uint256 percentage = _getNFTPercentage(prophetBonus[6], _strategyDetails[0], _strategyDetails[1]);
        if (prophetBonus[0] != 0 && percentage > 0) {
            // Has staked a prophet in the garden before the strategy finished
            _rewards[0] = _rewards[0].add(_rewards[0].multiplyDecimal(prophetBonus[2].preciseMul(percentage)));
            _rewards[2] = _rewards[2].add(_rewards[2].multiplyDecimal(prophetBonus[3].preciseMul(percentage)));
            _rewards[4] = _rewards[4].add(_rewards[4].multiplyDecimal(prophetBonus[4].preciseMul(percentage)));
            _rewards[7] = _rewards[7].add(_rewards[7].multiplyDecimal(prophetBonus[5].preciseMul(percentage)));
            _rewards[5] = _rewards[0].add(_rewards[2]).add(_rewards[4]).add(_rewards[7]);
        }
        return _rewards;
    }

    /**
     * Get the percentage to apply the NFT prophet bonus, if any depending on staking ts
     * @param _stakedAt        Timestamp when the NFT was staked (if any)
     * @param _executedAt      Strategy executedAt timestamp
     * @param _exitedAt        Strategy exitedAt timestamp (it can be finished or not == 0)
     * @return the estimated proportional percentage to apply from NFT bonuses
     */
    function _getNFTPercentage(
        uint256 _stakedAt,
        uint256 _executedAt,
        uint256 _exitedAt
    ) internal view returns (uint256) {
        if (_stakedAt == 0) {
            // un-staked
            return 0;
        } else if (_stakedAt <= _executedAt && _executedAt > 0) {
            // NFT staked before the strategy was executed
            // gets 100% of Prophet bonuses
            return 1e18;
            // From this point stakeAt > executedAt
        } else if (_stakedAt < _exitedAt && _exitedAt > 0) {
            // NFT staked after the strategy was executed + strategy finished
            // gets proportional
            return (_exitedAt.sub(_stakedAt)).preciseDiv(_exitedAt.sub(_executedAt));
        } else if (_stakedAt < block.timestamp && _exitedAt == 0) {
            // Strategy still live
            // gets proportional
            return (block.timestamp.sub(_stakedAt)).preciseDiv(block.timestamp.sub(_executedAt));
        } else {
            // Strategy finalized before or in the same block than staking the NFT
            // NFT is not eligible then for this strategy
            return 0;
        }
    }

    /**
     * Get the rewards for a specific contributor activately contributing in strategies of a specific garden
     * @param _garden               Garden address responsible of the strategies to calculate rewards
     * @param _strategy             Strategy address
     * @param _contributor          Contributor address
     * @param _claimedAt            User last claim timestamp

     * @return Array of size 8 with the following distribution:
     * rewards[0]: Strategist BABL 
     * rewards[1]: Strategist Profit
     * rewards[2]: Steward BABL
     * rewards[3]: Steward Profit
     * rewards[4]: LP BABL
     * rewards[5]: Total BABL
     * rewards[6]: Total Profits
     * rewards[7]: Creator bonus
     */
    function _getStrategyProfitsAndBABL(
        address _garden,
        address _strategy,
        address _contributor,
        uint256 _claimedAt
    ) private view returns (uint256[] memory) {
        uint256[] memory rewards = new uint256[](8);
        (address strategist, uint256[] memory strategyDetails, bool[] memory profitData) =
            IStrategy(_strategy).getStrategyRewardsContext();

        // strategyDetails array mapping:
        // strategyDetails[0]: executedAt
        // strategyDetails[1]: exitedAt
        // strategyDetails[2]: updatedAt
        // strategyDetails[3]: enteredAt
        // strategyDetails[4]: totalPositiveVotes
        // strategyDetails[5]: totalNegativeVotes
        // strategyDetails[6]: capitalAllocated
        // strategyDetails[7]: capitalReturned
        // strategyDetails[8]: expectedReturn
        // strategyDetails[9]: strategyRewards
        // strategyDetails[10]: profitValue
        // strategyDetails[11]: distanceValue
        // strategyDetails[12]: startingGardenSupply
        // strategyDetails[13]: endingGardenSupply
        // profitData array mapping:
        // profitData[0]: profit
        // profitData[1]: distance

        // Positive strategies not yet claimed
        // Users might get BABL rewards if they join the garden before the strategy ends
        // Contributor power will check their exact contribution (avoiding flashloans)
        if (strategyDetails[1] > _claimedAt) {
            // Get the contributor share until the the strategy exit timestamp
            uint256 contributorShare = rewardsDistributor.getSafeUserSharePerStrategy(_garden, _contributor, _strategy);
            rewards = _getRewardsPerRole(
                _garden,
                _strategy,
                strategist,
                _contributor,
                contributorShare,
                strategyDetails,
                profitData
            );
            // add Prophets NFT bonus if staked in the garden
            rewards = _boostRewards(_garden, _contributor, rewards, strategyDetails);
        }
        return rewards;
    }

    /**
     * Get the BABL rewards (Mining program) for a Steward profile
     * @param _strategy                 Strategy address
     * @param _contributor              Contributor address
     * @param _strategyDetails          Strategy details data
     * @param _profitData               Strategy profit data
     * @param _stewardsBABLPercentage   Stewards BABL percentage defined by governance
     */
    function _getStrategyStewardBabl(
        address _strategy,
        address _contributor,
        uint256[] memory _strategyDetails,
        bool[] memory _profitData,
        uint256 _stewardsBABLPercentage
    ) private view returns (uint256) {
        // Assumptions:
        // It executes in all cases as non profited strategies can also give BABL rewards to those who voted against

        int256 userVotes = IStrategy(_strategy).getUserVotes(_contributor);
        uint256 totalVotes = _strategyDetails[4].add(_strategyDetails[5]);

        uint256 bablCap;
        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        uint256 babl;
        if (userVotes > 0 && _profitData[0] == true && _profitData[1] == true) {
            // Voting in favor of the execution of the strategy with profits and positive distance
            // Negative votes in this case will not receive BABL so we divide only by positive votes
            babl = _strategyDetails[9].multiplyDecimal(_stewardsBABLPercentage).preciseMul(
                uint256(userVotes).preciseDiv(_strategyDetails[4])
            );
        } else if (userVotes > 0 && _profitData[0] == true && _profitData[1] == false) {
            // Voting in favor positive profits but below expected return
            babl = _strategyDetails[9].multiplyDecimal(_stewardsBABLPercentage).preciseMul(
                uint256(userVotes).preciseDiv(totalVotes)
            );
            // We discount the error of expected return vs real returns
            babl = babl.sub(babl.preciseMul(_strategyDetails[11].preciseDiv(_strategyDetails[8])));
        } else if (userVotes > 0 && _profitData[0] == false) {
            // Voting in favor of a non profitable strategy get nothing
            babl = 0;
        } else if (userVotes < 0 && _profitData[1] == false) {
            // Voting against a strategy that got results below expected return provides rewards
            // to the voter (helping the protocol to only have good strategies)
            // If no profit at all, the whole steward benefit goes to those voting against
            uint256 votesAccounting = _profitData[0] ? totalVotes : _strategyDetails[5];
            babl = _strategyDetails[9].multiplyDecimal(_stewardsBABLPercentage).preciseMul(
                uint256(Math.abs(userVotes)).preciseDiv(votesAccounting)
            );

            bablCap = babl.mul(2); // Max cap
            // We add a bonus inverse to the error of expected return vs real returns
            babl = babl.add(babl.preciseMul(_strategyDetails[11].preciseDiv(_strategyDetails[8])));
            if (babl > bablCap) {
                // We limit 2x by a Cap
                babl = bablCap;
            }
        } else if (userVotes < 0 && _profitData[1] == true) {
            babl = 0;
        }
        return babl;
    }

    /**
     * Get the rewards for a Steward profile
     * @param _strategy                 Strategy address
     * @param _contributor              Contributor address
     * @param _strategyDetails          Strategy details data
     * @param _profitData               Strategy profit data
     * @param _stewardsProfitPercentage Stewards profit percentage
     */
    function _getStrategyStewardProfits(
        address _strategy,
        address _contributor,
        uint256[] memory _strategyDetails,
        bool[] memory _profitData,
        uint256 _stewardsProfitPercentage
    ) private view returns (uint256 stewardBabl) {
        // Assumptions:
        // Assumption that the strategy got profits. Should not execute otherwise.
        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        int256 userVotes = IStrategy(_strategy).getUserVotes(_contributor);
        uint256 totalVotes = _strategyDetails[4].add(_strategyDetails[5]);
        if (userVotes > 0) {
            // If the strategy got profits equal or above expected return only positive votes counts,
            // so we divide by only positive
            // Otherwise, we divide by all total votes as also voters against will get some profits
            // if the strategy returned less than expected
            uint256 accountingVotes = _profitData[1] ? _strategyDetails[4] : totalVotes;
            stewardBabl = _strategyDetails[10]
                .multiplyDecimal(_stewardsProfitPercentage)
                .preciseMul(uint256(userVotes))
                .preciseDiv(accountingVotes);
        } else if ((userVotes < 0) && _profitData[1] == false) {
            stewardBabl = _strategyDetails[10]
                .multiplyDecimal(_stewardsProfitPercentage)
                .preciseMul(uint256(Math.abs(userVotes)))
                .preciseDiv(totalVotes);
        } else if ((userVotes < 0) && _profitData[1] == true) {
            // Voted against a very profit strategy above expected returns, get no profit at all
            stewardBabl = 0;
        }
    }

    /**
     * Get the BABL rewards (Mining program) for a Strategist profile
     * @param _strategyDetails          Strategy details data
     * @param _profitData               Strategy details data
     */
    function _getStrategyStrategistBabl(
        uint256[] memory _strategyDetails,
        bool[] memory _profitData,
        uint256 _strategistBABLPercentage
    ) private pure returns (uint256) {
        // Assumptions:
        // We assume that the contributor is the strategist. Should not execute this function otherwise.
        uint256 babl;
        babl = _strategyDetails[9].multiplyDecimal(_strategistBABLPercentage); // Standard calculation to be ponderated
        if (_profitData[0] == true && _profitData[1] == true) {
            uint256 bablCap = babl.mul(2); // Cap x2
            // Strategist get a bonus based on the profits with a max cap of x2
            babl = babl.preciseMul(_strategyDetails[7].preciseDiv(_strategyDetails[6]));
            if (babl > bablCap) {
                babl = bablCap;
            }
            return babl;
        } else if (_profitData[0] == true && _profitData[1] == false) {
            // under expectations
            // The more the results are close to the expected the less penalization it might have
            return babl.sub(babl.sub(babl.preciseMul(_strategyDetails[7].preciseDiv(_strategyDetails[8]))));
        } else {
            // No positive profit, no BABL assigned to the strategist role
            return 0;
        }
    }

    /**
     * Get the rewards for a Strategist profile
     * @param _profitValue                  Strategy profit value
     * @param _strategistProfitPercentage   % profit for strategist defined by the garden
     */
    function _getStrategyStrategistProfits(uint256 _profitValue, uint256 _strategistProfitPercentage)
        private
        pure
        returns (uint256)
    {
        // Assumptions:
        // Only executes if the contributor was the strategist of the strategy
        // AND the strategy had profits
        return _profitValue.multiplyDecimal(_strategistProfitPercentage);
    }

    /**
     * Get the BABL rewards (Mining program) for a LP profile
     * @param _strategyRewards      Strategy rewards
     * @param _contributorShare     Contributor share in the period
     * @param _lpsBABLPercentage    LP BABL percentage defined by governance
     */
    function _getStrategyLPBabl(
        uint256 _strategyRewards,
        uint256 _contributorShare,
        uint256 _lpsBABLPercentage
    ) private pure returns (uint256) {
        // All params must have 18 decimals precision
        return _strategyRewards.multiplyDecimal(_lpsBABLPercentage).preciseMul(_contributorShare);
    }

    /**
     * Calculates the BABL rewards supply for each quarter
     * @param _quarter      Number of the epoch (quarter)
     */
    function _tokenSupplyPerQuarter(uint256 _quarter) internal pure returns (uint256) {
        _require(_quarter >= 1, Errors.QUARTERS_MIN_1);
        if (_quarter >= 513) {
            return 0; // Avoid math overflow
        } else {
            uint256 firstFactor = (SafeDecimalMath.unit().add(DECAY_RATE)).powDecimal(_quarter.sub(1));
            return Q1_REWARDS.divideDecimal(firstFactor);
        }
    }

    /**
     * Calculates the quarter number for a specific time since START_TIME
     * @param _now      Timestamp to calculate its quarter
     */
    function _getQuarter(uint256 _now) internal view returns (uint256) {
        // Avoid underflow for active strategies during mining activation
        uint256 quarter = _now >= START_TIME ? (_now.sub(START_TIME).preciseDivCeil(EPOCH_DURATION)).div(1e18) : 0;
        return quarter.add(1);
    }

    /**
     * Calculates the range (starting quarter and ending quarter since START_TIME)
     * @param _from   Starting timestamp
     * @param _to     Ending timestamp
     */
    function _getRewardsWindow(uint256 _from, uint256 _to) internal view returns (uint256, uint256) {
        // Avoid underflow for active strategies during mining activation
        if (_from < START_TIME) {
            _from = START_TIME;
        }
        uint256 quarters = (_to.sub(_from).preciseDivCeil(EPOCH_DURATION)).div(1e18);

        uint256 startingQuarter = (_from.sub(START_TIME).preciseDivCeil(EPOCH_DURATION)).div(1e18);
        uint256 endingQuarter = (_to.sub(START_TIME).preciseDivCeil(EPOCH_DURATION)).div(1e18);

        if (
            startingQuarter != endingQuarter &&
            endingQuarter == startingQuarter.add(1) &&
            _to.sub(_from) < EPOCH_DURATION
        ) {
            quarters = quarters.add(1);
        }
        return (quarters.add(1), startingQuarter.add(1));
    }

    /**
     * Gives creator bonus to the user and returns original + bonus
     * @param _garden               Address of the garden
     * @param _contributor          Address of the contributor
     * @param _contributorBABL      BABL obtained in the strategy
     * @param _gardenCreatorBonus   % bonus for creator
     */
    function _getCreatorBonus(
        address _garden,
        address _contributor,
        uint256 _contributorBABL,
        uint256 _gardenCreatorBonus
    ) private view returns (uint256) {
        IGarden garden = IGarden(_garden);
        bool isCreator = garden.creator() == _contributor;
        uint8 creatorCount = garden.creator() != address(0) ? 1 : 0;
        for (uint8 i = 0; i < 4; i++) {
            address _extraCreator = garden.extraCreators(i);
            if (_extraCreator != address(0)) {
                creatorCount++;
                isCreator = isCreator || _extraCreator == _contributor;
            }
        }
        // Get a multiplier bonus in case the contributor is the garden creator
        if (creatorCount == 0) {
            // If there is no creator divide the creator bonus across al members
            return
                _contributorBABL.add(
                    _contributorBABL.multiplyDecimal(_gardenCreatorBonus).div(IGarden(_garden).totalContributors())
                );
        } else {
            if (isCreator) {
                // Check other creators and divide by number of creators or members if creator address is 0
                return _contributorBABL.add(_contributorBABL.multiplyDecimal(_gardenCreatorBonus).div(creatorCount));
            }
        }
        return _contributorBABL;
    }

    function _estimateStrategyRewards(address _strategy)
        internal
        view
        returns (
            address strategist,
            uint256[] memory strategyDetails,
            bool[] memory profitData
        )
    {
        // strategyDetails array mapping:
        // strategyDetails[0]: executedAt
        // strategyDetails[1]: exitedAt
        // strategyDetails[2]: updatedAt
        // strategyDetails[3]: enteredAt
        // strategyDetails[4]: totalPositiveVotes
        // strategyDetails[5]: totalNegativeVotes
        // strategyDetails[6]: capitalAllocated
        // strategyDetails[7]: capitalReturned
        // strategyDetails[8]: expectedReturn
        // strategyDetails[9]: strategyRewards
        // strategyDetails[10]: profitValue
        // strategyDetails[11]: distanceValue
        // strategyDetails[12]: startingGardenSupply
        // strategyDetails[13]: endingGardenSupply
        // profitData array mapping:
        // profitData[0]: profit
        // profitData[1]: distance

        (strategist, strategyDetails, profitData) = IStrategy(_strategy).getStrategyRewardsContext();
        if (strategyDetails[9] != 0 || strategyDetails[0] == 0) {
            // Already finished and got rewards or not executed yet (not active)
            return (strategist, strategyDetails, profitData);
        }
        // Strategy has not finished yet, lets try to estimate its mining rewards
        // As the strategy has not ended we replace the capital returned value by the NAV
        strategyDetails[7] = IStrategy(_strategy).getNAV();
        profitData[0] = strategyDetails[7] >= strategyDetails[6];
        profitData[1] = strategyDetails[7] >= strategyDetails[8];
        strategyDetails[10] = profitData[0] ? strategyDetails[7].sub(strategyDetails[6]) : 0; // no profit
        // We consider that it potentially will have profits so the protocol will take profitFee
        // If 0 it does nothing
        strategyDetails[11] = profitData[1]
            ? strategyDetails[7].sub(strategyDetails[8])
            : strategyDetails[8].sub(strategyDetails[7]);
        // miningData[1]: miningUpdatedAt
        // miningData[2]: miningProtocolPrincipal
        // miningData[5]: strategyPrincipal[_strategy]
        // miningData[17]: strategyPerQuarter[_strategy][1].betaInitializedAt
        uint256[18] memory miningData = rewardsDistributor.checkMining(1, _strategy);
        // We take care about beta live strategies as they have a different start mining time != executedAt
        (uint256 numQuarters, uint256 startingQuarter) =
            _getRewardsWindow(
                ((strategyDetails[0] > START_TIME) ? strategyDetails[0] : miningData[17]),
                block.timestamp
            );
        // We create an array of quarters since the begining of the strategy
        // We then fill with known + unknown data that has to be figured out
        uint256[] memory strategyPower = new uint256[](numQuarters);
        uint256[] memory protocolPower = new uint256[](numQuarters);
        (strategyPower, protocolPower) = rewardsDistributor.getInitialStrategyPower(
            _strategy,
            numQuarters,
            startingQuarter
        );
        strategyPower = _updatePendingPower(
            strategyPower,
            numQuarters,
            startingQuarter,
            strategyDetails[2],
            miningData[5]
        );
        protocolPower = _updatePendingPower(protocolPower, numQuarters, startingQuarter, miningData[1], miningData[2]);
        strategyDetails[9] = getBenchmarkRewards(
            strategyDetails[7],
            strategyDetails[6],
            _harvestStrategyRewards(strategyPower, protocolPower, startingQuarter, numQuarters),
            strategyDetails[0]
        );
    }

    function _harvestStrategyRewards(
        uint256[] memory _strategyPower,
        uint256[] memory _protocolPower,
        uint256 _startingQuarter,
        uint256 _numQuarters
    ) internal view returns (uint256) {
        uint256 strategyRewards;
        uint256 percentage = 1e18;
        for (uint256 i = 0; i < _numQuarters; i++) {
            if (i.add(1) == _numQuarters) {
                // last quarter - we need to take proportional supply for that timeframe despite
                // the epoch has not finished yet
                uint256 slotEnding = START_TIME.add(_startingQuarter.add(i).mul(EPOCH_DURATION));
                percentage = block.timestamp.sub(slotEnding.sub(EPOCH_DURATION)).preciseDiv(
                    slotEnding.sub(slotEnding.sub(EPOCH_DURATION))
                );
            }
            uint256 rewardsPerQuarter =
                _strategyPower[i]
                    .preciseDiv(_protocolPower[i] == 0 ? 1 : _protocolPower[i])
                    .preciseMul(_tokenSupplyPerQuarter(_startingQuarter.add(i)))
                    .preciseMul(percentage);
            strategyRewards = strategyRewards.add(rewardsPerQuarter);
        }
        return strategyRewards;
    }

    function _updatePendingPower(
        uint256[] memory _powerToUpdate,
        uint256 _numQuarters,
        uint256 _startingQuarter,
        uint256 _updatedAt,
        uint256 _principal
    ) internal view returns (uint256[] memory) {
        uint256 lastQuarter = _getQuarter(_updatedAt); // quarter of last update
        uint256 currentQuarter = _getQuarter(block.timestamp); // current quarter
        uint256 timeDiff = block.timestamp.sub(_updatedAt); // 1sec to avoid division by zero
        // We check the pending power to be accounted until now, since last update for protocol and strategy
        uint256 powerDebt = _principal.mul(timeDiff);
        if (powerDebt > 0) {
            for (uint256 i = 0; i < _numQuarters; i++) {
                uint256 slotEnding = START_TIME.add(_startingQuarter.add(i).mul(EPOCH_DURATION));
                if (i == 0 && lastQuarter == _startingQuarter && lastQuarter < currentQuarter) {
                    // We are in the first quarter to update, we add the proportional pending part
                    _powerToUpdate[i] = _powerToUpdate[i].add(powerDebt.mul(slotEnding.sub(_updatedAt)).div(timeDiff));
                } else if (i > 0 && i.add(1) < _numQuarters && lastQuarter <= _startingQuarter.add(i)) {
                    // We are updating an intermediate quarter
                    // Should have 0 inside before updating
                    _powerToUpdate[i] = _powerToUpdate[i].add(powerDebt.mul(EPOCH_DURATION).div(timeDiff));
                } else if (_startingQuarter.add(i) == currentQuarter) {
                    // We are updating the current quarter of this strategy checkpoint or the last to update
                    // It can be a multiple quarter strategy or the only one that need proportional time
                    if (lastQuarter == currentQuarter) {
                        // Just add the powerDebt being in the same epoch, no need to get proportional
                        _powerToUpdate[i] = _powerToUpdate[i].add(powerDebt);
                    } else {
                        // should have 0 inside before updating in case of different epoch since last update
                        _powerToUpdate[i] = _powerToUpdate[i].add(
                            powerDebt.mul(block.timestamp.sub(slotEnding.sub(EPOCH_DURATION))).div(timeDiff)
                        );
                    }
                }
            }
        }
        return _powerToUpdate;
    }
}

contract RewardsAssistantV1 is RewardsAssistant {}
