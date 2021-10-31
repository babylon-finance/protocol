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
import {TimeLockedToken} from './TimeLockedToken.sol';

import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';
import {Safe3296} from '../lib/Safe3296.sol';
import {Errors, _require} from '../lib/BabylonErrors.sol';

import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';

/**
 * @title Rewards Distributor implementing the BABL Mining Program and other Rewards to Strategists and Stewards
 * @author Babylon Finance
 * Rewards Distributor contract is a smart contract used to calculate and distribute all the BABL rewards
 * of the BABL Mining Program along the time reserved for executed strategies. It implements a supply curve
 * to distribute 500K BABL along the time.
 * The supply curve is designed to optimize the long-term sustainability of the protocol.
 * The rewards are front-loaded but they last for more than 10 years, slowly decreasing quarter by quarter.
 * For that, it houses the state of the protocol power along the time as each strategy power is compared
 * to the whole protocol usage as well as profits of each strategy counts.
 * Rewards Distributor also is responsible for the calculation and delivery of other rewards as bonuses
 * to specific profiles, which are actively contributing to the protocol growth and their communities
 * (Garden creators, Strategists and Stewards).
 */
contract RewardsDistributor is OwnableUpgradeable, IRewardsDistributor {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
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
    /**
     * Throws if the call is not from a valid strategy
     */
    function _onlyStrategy(address _strategy) private view {
        address garden = address(IStrategy(_strategy).garden());
        _require(IBabController(controller).isGarden(garden), Errors.ONLY_ACTIVE_GARDEN);
        _require(IGarden(garden).isGardenStrategy(_strategy), Errors.STRATEGY_GARDEN_MISMATCH);
    }

    /**
     * Throws if the sender is not the controller
     */
    function _onlyController() private view {
        _require(IBabController(controller).isSystemContract(msg.sender), Errors.NOT_A_SYSTEM_CONTRACT);
        _require(address(controller) == msg.sender, Errors.ONLY_CONTROLLER);
    }

    /**
     * Throws if Rewards Distributor is paused
     */
    function _onlyUnpaused() private view {
        // Do not execute if Globally or individually paused
        _require(!IBabController(controller).isPaused(address(this)), Errors.ONLY_UNPAUSED);
    }

    /**
     * Throws if a malicious reentrant call is detected
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        _require(status != ENTERED, Errors.REENTRANT_CALL);
        // Any calls to nonReentrant after this point will fail
        status = ENTERED;
        _;
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        status = NOT_ENTERED;
    }

    /* ============ Constants ============ */
    // 500K BABL allocated to this BABL Mining Program, the first quarter is Q1_REWARDS
    // and the following quarters will follow the supply curve using a decay rate
    uint256 private constant Q1_REWARDS = 53_571_428_571_428_600e6; // First quarter (epoch) BABL rewards
    // 12% quarterly decay rate (each 90 days)
    // (Rewards on Q1 = 1,12 * Rewards on Q2) being Q1= Quarter 1, Q2 = Quarter 2
    uint256 private constant DECAY_RATE = 12e16;
    // Duration of its EPOCH in days  // BABL & profits split from the protocol
    uint256 private constant EPOCH_DURATION = 90 days;

    // solhint-disable-next-line
    uint256 private START_TIME; // Starting time of the rewards distribution

    // solhint-disable-next-line
    uint256 private strategistBABLPercentage;
    // solhint-disable-next-line
    uint256 private stewardsBABLPercentage;
    // solhint-disable-next-line
    uint256 private lpsBABLPercentage;
    // solhint-disable-next-line
    uint256 private strategistProfitPercentage;
    // solhint-disable-next-line
    uint256 private stewardsProfitPercentage;
    // solhint-disable-next-line
    uint256 private lpsProfitPercentage;
    // solhint-disable-next-line
    uint256 private profitProtocolFee;
    // solhint-disable-next-line
    uint256 private gardenCreatorBonus;

    // DAI normalize asset
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Reentrancy guard countermeasure
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    /* ============ Structs ============ */

    struct ProtocolPerTimestamp {
        uint256 principal; // DEPRECATED
        uint256 time; // DEPRECATED
        uint256 quarterBelonging; // DEPRECATED
        uint256 timeListPointer; // DEPRECATED
        uint256 power; // DEPRECATED
    }

    struct ProtocolPerQuarter {
        // Protocol allocation checkpoints per timestamp per each quarter along the time
        uint256 quarterPrincipal; // DEPRECATED
        uint256 quarterNumber; // DEPRECATED
        uint256 quarterPower; //  Accumulated Protocol power for each quarter
        uint96 supplyPerQuarter; // DEPRECATED
    }

    struct GardenPowerByTimestamp {
        // Garden allocation checkpoints per timestamp per each garden
        uint256 avgGardenBalance; // Checkpoint to keep track on garden supply
        uint256 lastDepositAt; // Checkpoint timestamps
        uint256 accGardenPower; // Garden power checkpoint (power is proportional to = principal * duration)
    }
    struct ContributorPerGarden {
        // Checkpoints to keep track on the evolution of each contributor vs. each garden
        uint256 lastDepositAt; // Last deposit timestamp of each contributor in each garden
        uint256 initialDepositAt; // Checkpoint of the initial deposit
        uint256[] timeListPointer; // DEPRECATED, but still needed during beta gardens migration
        uint256 pid; // DEPRECATED, but still needed during beta gardens migration
        // Sub-mapping of contributor details, updated info after beta will be only at position [0]
        mapping(uint256 => TimestampContribution) tsContributions;
    }

    struct TimestampContribution {
        // Sub-mapping with all checkpoints for deposits and withdrawals of garden users
        uint256 avgBalance; // User avg balance in each garden along the time
        uint256 timestamp; // DEPRECATED
        uint256 timePointer; // DEPRECATED
        uint256 power; // Contributor power
    }
    struct Checkpoints {
        uint256 fromTime; // checkpoint block timestamp
        uint256 userTokens; // User garden tokens in the checkpoint
        uint256 supply; // Total supply in the checkpoint
        uint256 prevBalance; // Previous user balance
    }

    /* ============ State Variables ============ */

    // Instance of the Controller contract
    IBabController private controller;

    // BABL Token contract
    TimeLockedToken private babltoken;

    // Protocol total allocation points. Must be the sum of all allocation points (strategyPrincipal)
    // in all ongoing strategies during mining program.
    uint256 private miningProtocolPrincipal; // Protocol principal (only related to mining program)
    mapping(uint256 => ProtocolPerTimestamp) private protocolPerTimestamp; // DEPRECATED
    uint256[] private timeList; // DEPRECATED
    uint256 private miningProtocolPower; // Mining protocol power along the time

    // Mapping of the accumulated protocol per each active quarter
    mapping(uint256 => ProtocolPerQuarter) private protocolPerQuarter;
    // Check if the protocol per quarter data has been initialized
    mapping(uint256 => bool) private isProtocolPerQuarter;

    mapping(address => mapping(uint256 => uint256)) private rewardsPowerOverhead; // DEPRECATED
    // Contributor power control
    // Contributor details per garden
    mapping(address => mapping(address => ContributorPerGarden)) private contributorPerGarden;
    mapping(address => mapping(address => Checkpoints)) private checkpoints; // DEPRECATED
    // Garden power control
    // Garden power details per garden. Updated info after beta will be only at position [0]
    mapping(address => mapping(uint256 => GardenPowerByTimestamp)) private gardenPowerByTimestamp;
    mapping(address => uint256[]) private gardenTimelist; // DEPRECATED, but still needed during beta gardens migration
    mapping(address => uint256) private gardenPid; // DEPRECATED, but still needed during beta gardens migration

    struct StrategyPerQuarter {
        // Acumulated strategy power per each quarter along the time
        uint256 quarterPrincipal; // DEPRECATED
        uint256 betaInitializedAt; // Only used for beta strategies
        uint256 quarterPower; //  Accumulated strategy power for each quarter
        bool initialized; // True if the strategy has checkpoints in that quarter already
    }
    struct StrategyPricePerTokenUnit {
        // Take control over the price per token changes along the time when normalizing into DAI
        uint256 preallocated; // Strategy capital preallocated before each checkpoint
        uint256 pricePerTokenUnit; // Last average price per allocated tokens per strategy normalized into DAI
    }
    // Acumulated strategy power per each quarter along the time
    mapping(address => mapping(uint256 => StrategyPerQuarter)) private strategyPerQuarter;
    // Pro-rata oracle price allowing re-allocations and unwinding of any capital value
    mapping(address => StrategyPricePerTokenUnit) private strategyPricePerTokenUnit;

    // Reentrancy guard countermeasure
    uint256 private status;

    // Customized profit sharing (if any)
    // [0]: _strategistProfit , [1]: _stewardsProfit, [2]: _lpProfit
    mapping(address => uint256[3]) private gardenProfitSharing;
    mapping(address => bool) private gardenCustomProfitSharing;

    uint256 private miningUpdatedAt; // Timestamp of last strategy capital update
    mapping(address => uint256) private strategyPrincipal; // Last known strategy principal normalized into DAI

    // Only for beta gardens and users as they need migration into new gas-optimized data structure
    // Boolean check to control users and garden migration into to new mapping architecture without checkpoints
    mapping(address => mapping(address => bool)) private betaUserMigrated; // DEPRECATED
    mapping(address => bool) private betaGardenMigrated; // DEPRECATED

    uint256 private bablProfitWeight;
    uint256 private bablPrincipalWeight;

    // A record of garden token checkpoints for each user at each garden, by index
    mapping(address => mapping(address => mapping(uint256 => Checkpoints))) private userCheckpoints;

    // The number of checkpoints for each user at each garden
    mapping(address => mapping(address => uint256)) private numCheckpoints;

    /* ============ Constructor ============ */

    function initialize(TimeLockedToken _bablToken, IBabController _controller) public {
        OwnableUpgradeable.__Ownable_init();
        _require(address(_bablToken) != address(0) && address(_controller) != address(0), Errors.ADDRESS_IS_ZERO);
        babltoken = _bablToken;
        controller = _controller;

        profitProtocolFee = controller.protocolPerformanceFee();

        strategistProfitPercentage = 10e16; // 10%
        stewardsProfitPercentage = 5e16; // 5%
        lpsProfitPercentage = 80e16; // 80%

        strategistBABLPercentage = 10e16; // 10%
        stewardsBABLPercentage = 10e16; // 10%
        lpsBABLPercentage = 80e16; // 80%
        gardenCreatorBonus = 10e16; // 10%

        bablProfitWeight = 65e16; // 65%
        bablPrincipalWeight = 35e16; // 35%

        status = NOT_ENTERED;
        // We start BABL rewards as they were started by bip#1
        START_TIME = block.timestamp;
    }

    /* ============ External Functions ============ */

    /**
     * Function that adds/substract the capital received to the total principal of the protocol per timestamp
     * @param _capital                Amount of capital in any type of asset to be normalized into DAI
     * @param _addOrSubstract         Whether we are adding or substracting capital
     */
    function updateProtocolPrincipal(uint256 _capital, bool _addOrSubstract) external override {
        _onlyStrategy(msg.sender);
        // All strategies are now part of the Mining Program
        _updateProtocolPrincipal(msg.sender, _capital, _addOrSubstract);
    }

    /**
     * PRIVILEGE FUNCTION to update strategy data
     * @param _strategy               Address of the strategy
     * @param _capital                Amount of capital in any type of asset to be normalized into DAI
     * @param _addOrSubstract         Whether we are adding or substracting capital
     */
    function updateStrategyCheckpoint(
        address _strategy,
        uint256 _capital,
        bool _addOrSubstract
    ) external override onlyOwner {
        _onlyUnpaused();
        _onlyStrategy(_strategy);
        _updateProtocolPrincipal(_strategy, _capital, _addOrSubstract);
    }

    function updateGardenPowerAndContributor(
        address _garden,
        address _contributor,
        uint256 _previousBalance,
        uint256 _previousSupply,
        uint256 _tokenDiff,
        bool _addOrSubstract
    ) external override nonReentrant {
        _require(IBabController(controller).isGarden(msg.sender), Errors.ONLY_ACTIVE_GARDEN);
        uint256 newSupply = _addOrSubstract ? _previousSupply.add(_tokenDiff) : _previousSupply.sub(_tokenDiff);
        uint256 newBalance = _addOrSubstract ? _previousBalance.add(_tokenDiff) : _previousBalance.sub(_tokenDiff);
        _writeCheckpoint(_garden, _contributor, newBalance, newSupply, _previousBalance);
    }

    /**
     * Sends BABL tokens rewards to a contributor after a claim is requested to the protocol.
     * @param _to                Address to send the tokens to
     * @param _amount            Amount of tokens to send the address to
     * returns the amount of tokens transferred
     */
    function sendTokensToContributor(address _to, uint256 _amount) external override nonReentrant returns (uint256) {
        _onlyUnpaused();
        // Restrictive only to gardens when claiming BABL
        _require(IBabController(controller).isGarden(msg.sender), Errors.ONLY_ACTIVE_GARDEN);
        uint96 amount = Safe3296.safe96(_amount, 'overflow 96 bits');
        return _safeBABLTransfer(_to, amount);
    }

    /**
     * Set customized profit shares for a specific garden by the gardener
     * @param _garden               Address of the garden
     * @param _strategistShare      New % of strategistShare
     * @param _stewardsShare        New % of stewardsShare
     * @param _lpShare              New % of lpShare
     */
    function setProfitRewards(
        address _garden,
        uint256 _strategistShare,
        uint256 _stewardsShare,
        uint256 _lpShare
    ) external override {
        _onlyController();
        _require(IBabController(controller).isGarden(_garden), Errors.ONLY_ACTIVE_GARDEN);
        _setProfitRewards(_garden, _strategistShare, _stewardsShare, _lpShare);
    }

    /**
     * Change default BABL shares % by the governance
     * @param _strategistShare      New % of BABL strategist share
     * @param _stewardsShare        New % of BABL stewards share
     * @param _lpShare              New % of BABL lp share
     * @param _creatorBonus         New % of creator bonus
     * @param _profitWeight         New % of profit weigth for strategy rewards
     * @param _principalWeight      New % of principal weigth for strategy rewards
     */
    function setBABLMiningParameters(
        uint256 _strategistShare,
        uint256 _stewardsShare,
        uint256 _lpShare,
        uint256 _creatorBonus,
        uint256 _profitWeight,
        uint256 _principalWeight
    ) external override onlyOwner {
        _require(
            _strategistShare.add(_stewardsShare).add(_lpShare) == 1e18 &&
                _creatorBonus <= 1e18 &&
                _profitWeight.add(_principalWeight) == 1e18,
            Errors.INVALID_MINING_VALUES
        );
        strategistBABLPercentage = _strategistShare;
        stewardsBABLPercentage = _stewardsShare;
        lpsBABLPercentage = _lpShare;
        gardenCreatorBonus = _creatorBonus;
        bablProfitWeight = _profitWeight;
        bablPrincipalWeight = _principalWeight;
    }

    /* ========== View functions ========== */

    /**
     * Calculates the profits and BABL that a contributor should receive from a series of finalized strategies
     * @param _garden                   Garden to which the strategies and the user must belong to
     * @param _contributor              Address of the contributor to check
     * @param _finalizedStrategies      List of addresses of the finalized strategies to check
     * @return Array of size 7 with the following distribution:
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
    ) external view override returns (uint256[] memory) {
        _require(IBabController(controller).isGarden(address(_garden)), Errors.ONLY_ACTIVE_GARDEN);
        uint256[] memory totalRewards = new uint256[](8);
        uint256 initialDepositAt;
        uint256 claimedAt;
        (, initialDepositAt, claimedAt, , , , , , , ) = IGarden(_garden).getContributor(_contributor);
        for (uint256 i = 0; i < _finalizedStrategies.length; i++) {
            // Security check
            _require(IGarden(_garden).isGardenStrategy(_finalizedStrategies[i]), Errors.STRATEGY_GARDEN_MISMATCH);

            uint256[] memory tempRewards = new uint256[](8);

            tempRewards = _getStrategyProfitsAndBABL(
                _garden,
                _finalizedStrategies[i],
                _contributor,
                initialDepositAt,
                claimedAt
            );
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
     * Gets the total amount of rewards for a given strategy
     * @param _strategy                Strategy to check
     */
    function getStrategyRewards(address _strategy) external view override returns (uint96) {
        IStrategy strategy = IStrategy(_strategy);
        // ts[0]: executedAt, ts[1]: exitedAt, ts[2]: updatedAt
        uint256[] memory ts = new uint256[](3);
        (, , , , ts[0], ts[1], ts[2]) = strategy.getStrategyState();
        _require(ts[1] != 0, Errors.STRATEGY_IS_NOT_OVER_YET);
        if ((strategy.enteredAt() >= START_TIME || ts[1] >= START_TIME) && START_TIME != 0) {
            // We avoid gas consuming once a strategy got its BABL rewards during its finalization
            uint256 rewards = strategy.strategyRewards();
            if (rewards != 0) {
                return Safe3296.safe96(rewards, 'overflow 96 bits');
            }
            // str[0]: capitalAllocated, str[1]: capitalReturned
            uint256[] memory str = new uint256[](2);
            (, , , , , , str[0], str[1], , , , , , ) = strategy.getStrategyDetails();
            // If the calculation was not done earlier we go for it
            (uint256 numQuarters, uint256 startingQuarter) = _getRewardsWindow(ts[0], ts[1]);
            uint256 percentage = 1e18;

            for (uint256 i = 0; i < numQuarters; i++) {
                // Initialization timestamp at the end of the first slot where the strategy starts its execution
                uint256 slotEnding = START_TIME.add(startingQuarter.add(i).mul(EPOCH_DURATION));
                // We calculate each epoch
                uint256 strategyPower = strategyPerQuarter[_strategy][startingQuarter.add(i)].quarterPower;
                uint256 protocolPower = protocolPerQuarter[startingQuarter.add(i)].quarterPower;
                _require(strategyPower <= protocolPower, Errors.OVERFLOW_IN_POWER);
                if (i.add(1) == numQuarters) {
                    // last quarter - we need to take proportional supply for that timeframe despite
                    // the epoch has not finished yet
                    percentage = block.timestamp.sub(slotEnding.sub(EPOCH_DURATION)).preciseDiv(
                        slotEnding.sub(slotEnding.sub(EPOCH_DURATION))
                    );
                }
                uint256 rewardsPerQuarter =
                    strategyPower
                        .preciseDiv(protocolPower)
                        .preciseMul(uint256(_tokenSupplyPerQuarter(startingQuarter.add(i))))
                        .preciseMul(percentage);
                rewards = rewards.add(rewardsPerQuarter);
            }
            // Governance has decided to have different weights for principal and profit
            // Profit weight must be higher than principal
            // profitWeight + principalWeight must always sum 1e18 (100%)
            // PercentageProfit must always have 18 decimals (capital returned by capital allocated)
            uint256 percentageProfit = str[1].preciseDiv(str[0]);
            // Set the max cap bonus x2
            uint256 maxRewards = rewards.preciseMul(2e18);
            // Apply rewards weight related to principal and profit
            rewards = rewards.preciseMul(bablPrincipalWeight).add(
                rewards.preciseMul(bablProfitWeight).preciseMul(percentageProfit)
            );
            // Check max cap
            if (rewards >= maxRewards) {
                rewards = maxRewards;
            }
            return Safe3296.safe96(rewards, 'overflow 96 bits');
        } else {
            return 0;
        }
    }

    /**
     * Check the mining program state for a specific quarter and strategy
     * @param _quarterNum      Number of quarter
     * @param _strategy        Address of strategy
     */

    function checkMining(uint256 _quarterNum, address _strategy)
        external
        view
        override
        returns (uint256[] memory, bool[] memory)
    {
        uint256[] memory miningData = new uint256[](10);
        bool[] memory miningBool = new bool[](2);
        miningData[0] = START_TIME;
        miningData[1] = miningUpdatedAt;
        miningData[2] = miningProtocolPrincipal;
        miningData[3] = miningProtocolPower;
        miningData[4] = protocolPerQuarter[_quarterNum].quarterPower;
        miningData[5] = strategyPrincipal[_strategy];
        miningData[6] = strategyPricePerTokenUnit[_strategy].preallocated;
        miningData[7] = strategyPricePerTokenUnit[_strategy].pricePerTokenUnit;
        miningData[8] = strategyPerQuarter[_strategy][_quarterNum].quarterPower;
        miningData[9] = _tokenSupplyPerQuarter(_quarterNum);
        miningBool[0] = isProtocolPerQuarter[_quarterNum];
        miningBool[1] = strategyPerQuarter[_strategy][_quarterNum].initialized;
        return (miningData, miningBool);
    }

    /**
     * Check the garden profit sharing % if different from default
     * @param _garden     Address of the garden
     */
    function getGardenProfitsSharing(address _garden) external view override returns (uint256[3] memory) {
        if (gardenCustomProfitSharing[_garden]) {
            // It has customized values
            return gardenProfitSharing[_garden];
        } else {
            return [strategistProfitPercentage, stewardsProfitPercentage, lpsProfitPercentage];
        }
    }

    /**
     * Returns the percentages of BABL Mining program
     *
     * @return   Strategist, Stewards, Lps, creator bonus, bablProfit weight, babl principal weigth
     *
     */
    function getBABLMiningParameters()
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            strategistBABLPercentage,
            stewardsBABLPercentage,
            lpsBABLPercentage,
            gardenCreatorBonus,
            bablProfitWeight,
            bablPrincipalWeight
        );
    }

    /**
     * Get an estimation of user rewards for active strategies
     * @param _strategy        Address of the strategy to estimate BABL rewards
     * @param _contributor     Address of the garden contributor
     * @return Array of size 7 with the following distribution:
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
            // Get the contributor share until the the strategy exit timestamp
            uint256 contributorShare = _getSafeUserSharePerStrategy(garden, _contributor, _strategy);
            _require(contributorShare <= 1e18, Errors.OVERFLOW_IN_POWER);
            rewards = _getRewardsPerRole(
                garden,
                _strategy,
                strategist,
                _contributor,
                contributorShare,
                strategyDetails,
                profitData
            );
        }
        return rewards;
    }

    /**
     * Get a safe user share position within a strategy of a garden
     * @param _garden          Address of the garden
     * @param _contributor     Address of the garden contributor
     * @param _strategy        Address of the strategy
     * @return % deserved share per user
     */
    function getSafeUserSharePerStrategy(
        address _garden,
        address _contributor,
        address _strategy
    ) external view returns (uint256) {
        return _getSafeUserSharePerStrategy(_garden, _contributor, _strategy);
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

    function getContributorPerGarden(
        address _garden,
        address _contributor,
        uint256 _time
    ) public view override returns (uint256[] memory) {
        uint256[] memory powerData = new uint256[](10);
        ContributorPerGarden storage contributor = contributorPerGarden[_garden][_contributor];
        GardenPowerByTimestamp storage garden = gardenPowerByTimestamp[_garden][0];

        // powerData[0]: lastDepositAt (contributor)
        // powerData[1]: initialDepositAt (contributor)
        // powerData[2]: balance (contributor)
        // powerData[3]: power (contributor)
        // powerData[4]: avgBalance (contributor)
        // powerData[5]: lastDepositAt (garden)
        // powerData[6]: accGardenPower (garden)
        // powerData[7]: avgGardenBalance (garden)
        // powerData[8]: totalSupply (garden)
        powerData[0] = contributor.lastDepositAt;
        powerData[1] = contributor.initialDepositAt;
        powerData[2] = ERC20(_garden).balanceOf(_contributor);
        powerData[3] = contributor.tsContributions[0].power;
        powerData[4] = contributor.tsContributions[0].avgBalance;
        powerData[5] = garden.lastDepositAt;
        powerData[6] = garden.accGardenPower;
        powerData[7] = garden.avgGardenBalance;
        powerData[8] = ERC20(_garden).totalSupply();
        (, powerData[9], ) = _getPriorBalance(_garden, _contributor, _time);
        return powerData;
    }

    /* ============ Internal Functions ============ */

    /**
     * @dev internal function to write a checkpoint for contributor token power
     * @param _garden        Address of the garden
     * @param _contributor   Address of the contributor
     * @param _newBalance    The new token balance
     * @param _newSupply     The new garden token supply
     * @param _prevBalance   The previous user token balance
     */
    function _writeCheckpoint(
        address _garden,
        address _contributor,
        uint256 _newBalance,
        uint256 _newSupply,
        uint256 _prevBalance
    ) internal {
        uint256 blockTime = block.timestamp;
        uint256 nCheckpoints = numCheckpoints[_garden][_contributor];
        if (nCheckpoints > 0 && userCheckpoints[_garden][_contributor][nCheckpoints - 1].fromTime == blockTime) {
            userCheckpoints[_garden][_contributor][nCheckpoints - 1].userTokens = _newBalance;
            userCheckpoints[_garden][_contributor][nCheckpoints - 1].supply = _newSupply;
            userCheckpoints[_garden][_contributor][nCheckpoints - 1].prevBalance = _prevBalance;
        } else {
            userCheckpoints[_garden][_contributor][nCheckpoints] = Checkpoints(
                blockTime,
                _newBalance,
                _newSupply,
                _prevBalance
            );
            numCheckpoints[_garden][_contributor] = nCheckpoints + 1;
        }
    }

    /**
     * Update the protocol principal checkpoints
     * @param _strategy         Strategy which is adding/removing principal
     * @param _capital          Capital to update
     * @param _addOrSubstract   Adding (true) or removing (false)
     */
    function _updateProtocolPrincipal(
        address _strategy,
        uint256 _capital,
        bool _addOrSubstract
    ) internal {
        address reserveAsset = IGarden(IStrategy(_strategy).garden()).reserveAsset();
        // To compare strategy power between all strategies we normalize their capital into DAI
        // Then, we need to take control of getPrice fluctuations along the time
        uint256 pricePerTokenUnit = _getStrategyPricePerTokenUnit(reserveAsset, _strategy, _capital, _addOrSubstract);
        _capital = _capital.preciseMul(pricePerTokenUnit).mul(10**uint256(18).sub(ERC20(reserveAsset).decimals()));
        // Create or/and update the protocol quarter checkpoints if mining program is activated
        _updateProtocolPowerPerQuarter();
        // We update the strategy power per quarter normalized in DAI if mining program is activated
        _updateStrategyPowerPerQuarter(_strategy);
        // The following function call _updatePrincipal must be always executed
        // after _updateProtocolPowerPerQuarter and _updateStrategyPowerPerQuarter
        _updatePrincipal(_strategy, _capital, _addOrSubstract);
        // The following time set should always be executed at the end
        miningUpdatedAt = block.timestamp;
    }

    /**
     * Update the principal considered part of the mining program either Protocol or Strategies
     * @param _strategy         Strategy address
     * @param _capital          Capital normalized into DAI to add or substract for accurate
     * comparisons between strategies
     * @param _addOrSubstract   Whether or not we are adding or unwinding capital to the strategy under mining
     */
    function _updatePrincipal(
        address _strategy,
        uint256 _capital,
        bool _addOrSubstract
    ) private {
        if (_addOrSubstract == false) {
            // Substracting capital
            // Failsafe condition
            uint256 amount = _capital > strategyPrincipal[_strategy] ? strategyPrincipal[_strategy] : _capital;
            miningProtocolPrincipal = miningProtocolPrincipal.sub(amount);
            strategyPrincipal[_strategy] = strategyPrincipal[_strategy].sub(amount);
        } else {
            // Adding capital
            miningProtocolPrincipal = miningProtocolPrincipal.add(_capital);
            strategyPrincipal[_strategy] = strategyPrincipal[_strategy].add(_capital);
        }
    }

    /**
     * Add protocol power timestamps for each quarter
     */
    function _updateProtocolPowerPerQuarter() private {
        uint256[] memory data = new uint256[](4);
        // data[0]: previous quarter, data[1]: current quarter, data[2]: timeDifference, data[3]: debtPower
        data[0] = miningUpdatedAt == 0 ? 1 : _getQuarter(miningUpdatedAt);
        data[1] = _getQuarter(block.timestamp);
        data[2] = block.timestamp.sub(miningUpdatedAt);
        ProtocolPerQuarter storage protocolCheckpoint = protocolPerQuarter[data[1]];
        data[3] = miningUpdatedAt == 0 ? 0 : miningProtocolPrincipal.mul(data[2]);
        if (!isProtocolPerQuarter[data[1]]) {
            // The quarter is not initialized yet, we then create it
            if (miningUpdatedAt > 0) {
                // A new epoch has started with either a new strategy execution or finalization checkpoint
                if (data[0] == data[1].sub(1)) {
                    // There were no intermediate epoch without checkpoints, we are in the next epoch
                    // We need to divide the debtPower between previous epoch and current epoch
                    // We re-initialize the protocol power in the new epoch adding only the corresponding
                    // to its duration
                    protocolCheckpoint.quarterPower = data[3]
                        .mul(block.timestamp.sub(START_TIME.add(data[1].mul(EPOCH_DURATION).sub(EPOCH_DURATION))))
                        .div(data[2]);
                    // We now update the previous quarter with its proportional pending debtPower
                    protocolPerQuarter[data[1].sub(1)].quarterPower = protocolPerQuarter[data[1].sub(1)]
                        .quarterPower
                        .add(data[3].sub(protocolCheckpoint.quarterPower));
                } else {
                    // There were some intermediate epochs without checkpoints - we need to create
                    // missing checkpoints and update the last (current) one.
                    // We have to update all the quarters since last update
                    for (uint256 i = 0; i <= data[1].sub(data[0]); i++) {
                        ProtocolPerQuarter storage newCheckpoint = protocolPerQuarter[data[0].add(i)];
                        uint256 slotEnding = START_TIME.add(data[0].add(i).mul(EPOCH_DURATION));
                        if (i == 0) {
                            // We are in the first quarter to update (corresponding to miningUpdatedAt timestamp)
                            // We add the corresponding proportional part
                            newCheckpoint.quarterPower = newCheckpoint.quarterPower.add(
                                data[3].mul(slotEnding.sub(miningUpdatedAt)).div(data[2])
                            );
                        } else if (i < data[1].sub(data[0])) {
                            // We are in an intermediate quarter without checkpoints - need to create and update it
                            newCheckpoint.quarterPower = data[3].mul(EPOCH_DURATION).div(data[2]);
                        } else {
                            // We are in the last (current) quarter
                            // We update its proportional remaining debt power
                            protocolCheckpoint.quarterPower = data[3]
                                .mul(
                                block.timestamp.sub(START_TIME.add(data[1].mul(EPOCH_DURATION).sub(EPOCH_DURATION)))
                            )
                                .div(data[2]);
                        }
                    }
                }
            }
            isProtocolPerQuarter[data[1]] = true;
        } else {
            // Quarter checkpoint already created
            // We update the power of the quarter by adding the new difference between last quarter
            // checkpoint and this checkpoint
            protocolCheckpoint.quarterPower = protocolCheckpoint.quarterPower.add(data[3]);
            miningProtocolPower = miningProtocolPower.add(data[3]);
        }
    }

    /**
     * Updates the strategy power per quarter for rewards calculations of each strategy out of the whole protocol
     * @param _strategy    Strategy address
     */
    function _updateStrategyPowerPerQuarter(address _strategy) private {
        uint256[] memory data = new uint256[](5);
        // data[0]: executedAt, data[1]: updatedAt, data[2]: time difference, data[3]: quarter, data[4]: debtPower
        (, , , , data[0], , data[1]) = IStrategy(_strategy).getStrategyState();
        if (data[1] < START_TIME) {
            // We check the initialization only for beta gardens, quarter = 1
            StrategyPerQuarter storage betaStrategyCheckpoint = strategyPerQuarter[_strategy][1];
            if (betaStrategyCheckpoint.betaInitializedAt == 0) {
                betaStrategyCheckpoint.betaInitializedAt = block.timestamp;
            }
            // Only for strategies starting before mining and still executing, get proportional
            // Exited strategies before the mining starts, are not eligible of this standard setup
            data[1] = betaStrategyCheckpoint.betaInitializedAt;
        }
        data[2] = block.timestamp.sub(data[1]);
        data[3] = _getQuarter(block.timestamp);
        StrategyPerQuarter storage strategyCheckpoint = strategyPerQuarter[_strategy][data[3]];
        // We calculate the debt Power since last checkpoint (if any)
        data[4] = strategyPrincipal[_strategy].mul(data[2]);
        if (!strategyCheckpoint.initialized) {
            // The strategy quarter is not yet initialized then we create it
            // If it the first checkpoint in the first executing epoch - keep power 0
            if (data[3] > _getQuarter(data[0])) {
                // Each time a running strategy has a new checkpoint on a new (different) epoch than
                // previous checkpoints.
                // debtPower is the proportional power of the strategy for this quarter from previous checkpoint
                // We need to iterate since last checkpoint
                (uint256 numQuarters, uint256 startingQuarter) = _getRewardsWindow(data[1], block.timestamp);

                // There were intermediate epochs without checkpoints - we need to create their corresponding
                //  checkpoints and update the last one
                // We have to update all the quarters including where the previous checkpoint is and
                // the one where we are now
                for (uint256 i = 0; i < numQuarters; i++) {
                    StrategyPerQuarter storage newCheckpoint = strategyPerQuarter[_strategy][startingQuarter.add(i)];
                    uint256 slotEnding = START_TIME.add(startingQuarter.add(i).mul(EPOCH_DURATION));
                    if (i == 0) {
                        // We are in the first quarter to update, we add the proportional pending part
                        newCheckpoint.quarterPower = newCheckpoint.quarterPower.add(
                            data[4].mul(slotEnding.sub(data[1])).div(data[2])
                        );
                    } else if (i > 0 && i.add(1) < numQuarters) {
                        // We are updating an intermediate quarter
                        newCheckpoint.quarterPower = data[4].mul(EPOCH_DURATION).div(data[2]);
                        newCheckpoint.initialized = true;
                    } else {
                        // We are updating the current quarter of this strategy checkpoint
                        newCheckpoint.quarterPower = data[4]
                            .mul(block.timestamp.sub(START_TIME.add(data[3].mul(EPOCH_DURATION).sub(EPOCH_DURATION))))
                            .div(data[2]);
                    }
                }
            }
            strategyCheckpoint.initialized = true;
        } else {
            // We are in the same quarter than previous checkpoints for this strategy
            // We update the power of the quarter by adding the new difference between
            // last quarter checkpoint and this checkpoint
            strategyCheckpoint.quarterPower = strategyCheckpoint.quarterPower.add(data[4]);
        }
    }

    /**
     * Safe BABL rewards (Mining program) token transfer.
     * It handle cases when in case of rounding errors, RewardsDistributor might not have enough BABL.
     * @param _to               The receiver address of the contributor to send
     * @param _amount           The amount of BABL tokens to be rewarded during this claim
     * returns the amount of tokens transferred
     */
    function _safeBABLTransfer(address _to, uint96 _amount) private returns (uint256) {
        uint256 bablBal = babltoken.balanceOf(address(this));
        uint256 amountToSend = _amount > bablBal ? bablBal : _amount;
        SafeERC20.safeTransfer(babltoken, _to, amountToSend);
        return amountToSend;
    }

    /**
     * Set a customized profit rewards
     * @param _garden           Address of the garden
     * @param _strategistShare  New sharing profit % for strategist
     * @param _stewardsShare    New sharing profit % for stewards
     * @param _lpShare          New sharing profit % for lp
     */
    function _setProfitRewards(
        address _garden,
        uint256 _strategistShare,
        uint256 _stewardsShare,
        uint256 _lpShare
    ) internal {
        _require(_strategistShare.add(_stewardsShare).add(_lpShare) == 95e16, Errors.PROFIT_SHARING_MISMATCH);
        // [0]: _strategistProfit , [1]: _stewardsProfit, [2]: _lpProfit
        if (
            _strategistShare != strategistProfitPercentage ||
            _stewardsShare != stewardsProfitPercentage ||
            _lpShare != lpsProfitPercentage
        ) {
            // Different from standard %
            gardenCustomProfitSharing[_garden] = true;
            gardenProfitSharing[_garden][0] = _strategistShare;
            gardenProfitSharing[_garden][1] = _stewardsShare;
            gardenProfitSharing[_garden][2] = _lpShare;
        }
    }

    /**
     * Get the price per token to be used in the adding or substraction normalized to DAI (supports multiple asset)
     * @param _reserveAsset     Garden reserve asset address
     * @param _strategy         Strategy address
     * @param _capital          Capital in reserve asset to add or substract
     * @param _addOrSubstract   Whether or not we are adding or unwinding capital to the strategy
     * @return pricePerToken value
     */
    function _getStrategyPricePerTokenUnit(
        address _reserveAsset,
        address _strategy,
        uint256 _capital,
        bool _addOrSubstract
    ) private returns (uint256) {
        // Normalizing into DAI
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        uint256 pricePerTokenUnit = oracle.getPrice(_reserveAsset, DAI);
        StrategyPricePerTokenUnit storage strPpt = strategyPricePerTokenUnit[_strategy];
        if (strPpt.preallocated == 0) {
            // First adding checkpoint
            strPpt.preallocated = _capital;
            strPpt.pricePerTokenUnit = pricePerTokenUnit;
            return pricePerTokenUnit;
        } else {
            // We are controlling pair reserveAsset-DAI fluctuations along the time
            if (_addOrSubstract) {
                strPpt.pricePerTokenUnit = (
                    ((strPpt.pricePerTokenUnit.mul(strPpt.preallocated)).add(_capital.mul(pricePerTokenUnit))).div(1e18)
                )
                    .preciseDiv(strPpt.preallocated.add(_capital));
                strPpt.preallocated = strPpt.preallocated.add(_capital);
            } else {
                // We use the previous pricePerToken in a substract instead of a new price
                // (as allocated capital used previous prices not the current one)
                // Failsafe condition
                uint256 amount = _capital > strPpt.preallocated ? strPpt.preallocated : _capital;
                strPpt.preallocated = strPpt.preallocated.sub(amount);
            }
            return strPpt.pricePerTokenUnit;
        }
    }

    /* ========== Internal View functions ========== */

    /**
     * Get an estimation of user rewards for active strategies
     * @param _garden               Address of the garden
     * @param _strategy             Address of the strategy to estimate rewards
     * @param _strategist           Address of the strategist
     * @param _contributor          Address of the garden contributor
     * @param _contributorPower     Contributor power in a specific time
     * @param _strategyDetails      Details of the strategy in that specific moment
     * @param _profitData           Array of profit Data (if profit as well distance)
     * @return Array of size 7 with the following distribution:
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
        uint256 _contributorPower,
        uint256[] memory _strategyDetails,
        bool[] memory _profitData
    ) internal view returns (uint256[] memory) {
        uint256[] memory rewards = new uint256[](8);
        // Get strategist BABL rewards in case the contributor is also the strategist of the strategy
        rewards[0] = _strategist == _contributor ? _getStrategyStrategistBabl(_strategyDetails, _profitData) : 0;
        // Get strategist profit
        rewards[1] = (_strategist == _contributor && _profitData[0] == true)
            ? _getStrategyStrategistProfits(_garden, _strategyDetails[10])
            : 0;
        // Get steward rewards
        rewards[2] = _getStrategyStewardBabl(_strategy, _contributor, _strategyDetails, _profitData);
        // If not profits _getStrategyStewardsProfits should not execute
        rewards[3] = _profitData[0] == true
            ? _getStrategyStewardProfits(_garden, _strategy, _contributor, _strategyDetails, _profitData)
            : 0;
        // Get LP rewards
        // Contributor power is fluctuating along the way for each new deposit
        rewards[4] = _getStrategyLPBabl(_strategyDetails[9], _contributorPower);
        // Total BABL including creator bonus (if any)
        rewards[5] = _getCreatorBonus(_garden, _contributor, rewards[0].add(rewards[2]).add(rewards[4]));
        // Total profit
        rewards[6] = rewards[1].add(rewards[3]);
        // Creator bonus
        rewards[7] = rewards[5] > (rewards[0].add(rewards[2]).add(rewards[4]))
            ? rewards[5].sub(rewards[0].add(rewards[2]).add(rewards[4]))
            : 0;
        return rewards;
    }

    /**
     * Get token power at a specific block for an account
     *
     * @param _garden       Address of the garden
     * @param _contributor  Address of the contributor
     * @param _blockTime  Block timestamp to get token power at
     * @return Token power for an account at specific block
     */
    function _getPriorBalance(
        address _garden,
        address _contributor,
        uint256 _blockTime
    )
        internal
        view
        virtual
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // flashloan protection along the time
        _blockTime = _blockTime.sub(1);
        uint256 nCheckpoints = numCheckpoints[_garden][_contributor];
        ContributorPerGarden storage contributor = contributorPerGarden[_garden][_contributor];
        bool betaUser = contributor.initialDepositAt > 0 && contributor.initialDepositAt <= _blockTime;
        uint256 balance = ERC20(_garden).balanceOf(_contributor);
        if (nCheckpoints == 0 && !betaUser) {
            return (0, 0, ERC20(_garden).totalSupply());
        } else if (nCheckpoints == 0 && betaUser) {
            // Backward compatible for beta users, initial deposit > 0 but still no checkpoints
            // It also consider burning for bad strategist
            return (contributor.initialDepositAt, balance, ERC20(_garden).totalSupply());
        }
        // There are at least one checkpoint from this point
        // First check most recent balance
        if (userCheckpoints[_garden][_contributor][nCheckpoints - 1].fromTime <= _blockTime) {
            // Burning security protection at userTokens
            // It only limit the balance in case of burnt tokens and only if using last checkpoint
            return (
                userCheckpoints[_garden][_contributor][nCheckpoints - 1].fromTime,
                userCheckpoints[_garden][_contributor][nCheckpoints - 1].userTokens > balance
                    ? balance
                    : userCheckpoints[_garden][_contributor][nCheckpoints - 1].userTokens,
                userCheckpoints[_garden][_contributor][nCheckpoints - 1].supply
            );
        }

        // Next check implicit zero balance
        if (userCheckpoints[_garden][_contributor][0].fromTime > _blockTime && !betaUser) {
            // backward compatible
            return (0, 0, userCheckpoints[_garden][_contributor][0].supply); // avoid div by zero
        } else if (userCheckpoints[_garden][_contributor][0].fromTime > _blockTime && betaUser) {
            // Backward compatible for beta users, initial deposit > 0 but lost initial checkpoints
            // First checkpoint store its previous balance so we use it to guess the user past
            return (
                contributor.initialDepositAt,
                userCheckpoints[_garden][_contributor][0].prevBalance,
                userCheckpoints[_garden][_contributor][0].supply
            );
        }
        // It has more checkpoints but the time is between different checkpoints, we look for it
        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoints memory cp = userCheckpoints[_garden][_contributor][center];
            if (cp.fromTime == _blockTime) {
                return (cp.fromTime, cp.userTokens, cp.supply);
            } else if (cp.fromTime < _blockTime) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return (
            userCheckpoints[_garden][_contributor][lower].fromTime,
            userCheckpoints[_garden][_contributor][lower].userTokens,
            userCheckpoints[_garden][_contributor][lower].supply
        );
    }

    /**
     * Gets the contributor power from one timestamp to the other
     * @param _garden      Address of the garden where the contributor belongs to
     * @param _contributor Address of the contributor
     * @param _time        Timestamp to check power
     * @return uint256     Contributor power during that period
     */
    function _getContributorPower(
        address _garden,
        address _contributor,
        uint256 _time
    ) internal view returns (uint256) {
        // Check to avoid out of bounds
        uint256[] memory powerData = new uint256[](10);
        // powerData[0]: lastDepositAt (contributor)
        // powerData[1]: initialDepositAt (contributor)
        // powerData[2]: balance (contributor)
        // powerData[3]: power (contributor)
        // powerData[4]: avgBalance (contributor)
        // powerData[5]: lastDepositAt (garden)
        // powerData[6]: accGardenPower (garden)
        // powerData[7]: avgGardenBalance (garden)
        // powerData[8]: totalSupply (garden)
        // powerData[9]: getPriorBalance (contributor)
        powerData = getContributorPerGarden(_garden, _contributor, _time);
        if (powerData[1] == 0 || powerData[1] > _time || powerData[2] == 0) {
            return 0;
        } else {
            uint256 maxTime = powerData[5].add(1 days);
            // First we need to get an updatedValue of user and garden power since lastDeposits as of block.timestamp
            uint256 updatedPower = powerData[3].add((maxTime.sub(powerData[0])).mul(powerData[2]));
            uint256 updatedGardenPower = powerData[6].add((maxTime.sub(powerData[5])).mul(powerData[8]));
            // We then time travel back to when the strategy exitedAt
            // Calculate the power at "_to" timestamp
            uint256 timeDiff = maxTime.sub(_time);
            uint256 userPowerDiff = powerData[4].mul(timeDiff);
            uint256 gardenPowerDiff = powerData[7].mul(timeDiff);
            // Avoid underflow conditions 0 at user, 1 at garden
            updatedPower = updatedPower > userPowerDiff ? updatedPower.sub(userPowerDiff) : 0;
            updatedGardenPower = updatedGardenPower > gardenPowerDiff ? updatedGardenPower.sub(gardenPowerDiff) : 1;
            uint256 virtualPower = updatedPower.preciseDiv(updatedGardenPower);
            if (virtualPower > 1e18) {
                virtualPower = 1e18; // Overflow limit
            }
            return virtualPower;
        }
    }

    /**
     * Get a safe user share position within a strategy of a garden
     * @param _garden          Address of the garden
     * @param _contributor     Address of the garden contributor
     * @param _strategy        Address of the strategy
     * @return % deserved share per user
     */
    function _getSafeUserSharePerStrategy(
        address _garden,
        address _contributor,
        address _strategy
    ) internal view returns (uint256) {
        (, uint256[] memory strategyDetails, ) = IStrategy(_strategy).getStrategyRewardsContext();

        // strategyDetails array mapping:
        // strategyDetails[0]: executedAt
        // strategyDetails[1]: exitedAt
        // strategyDetails[12]: startingGardenSupply
        // strategyDetails[13]: endingGardenSupply

        uint256 endTime = strategyDetails[1] > 0 ? strategyDetails[1] : block.timestamp;
        if (endTime <= gardenPowerByTimestamp[_garden][0].lastDepositAt) {
            // Backward compatibility for old strategies
            return _getContributorPower(_garden, _contributor, endTime);
        }
        // Take the closest position prior to _endTime
        (uint256 timestamp, uint256 balanceEnd, uint256 supplyEnd) = _getPriorBalance(_garden, _contributor, endTime);
        // If it finished already and has garden supply checkpoint, then use it
        // If has not finished yet, use current totalSupply
        // If it is an old strategy w/o the garden supply checkpoint, trust getPriorBalance supply guessing
        uint256 finalSupplyEnd =
            (strategyDetails[1] > 0 && strategyDetails[13] > 0)
                ? strategyDetails[13]
                : (endTime == block.timestamp ? ERC20(_garden).totalSupply() : supplyEnd);
        // Security check (avoid flashloans and other position attacks depositing after half of the period)
        uint256 startTime = strategyDetails[0] > 0 ? strategyDetails[0] : block.timestamp;
        uint256 threshold = startTime.add(endTime.sub(startTime).div(2));
        if (timestamp > threshold) {
            // Take the last position closest to _startTime
            (, uint256 balanceStart, ) = _getPriorBalance(_garden, _contributor, startTime);
            // We take the minimum position and override it except if it was the first deposit
            // If first deposit we just take the average
            balanceEnd = balanceStart < balanceEnd
                ? (
                    balanceStart == 0
                        ? balanceEnd.preciseMul(endTime.sub(threshold).preciseDiv(endTime.sub(startTime)))
                        : balanceStart
                )
                : balanceEnd;
        }
        return balanceEnd.preciseDiv(finalSupplyEnd) <= 1e18 ? balanceEnd.preciseDiv(finalSupplyEnd) : 1e18; // Avoid overflow
    }

    /**
     * Get the rewards for a specific contributor activately contributing in strategies of a specific garden
     * @param _garden               Garden address responsible of the strategies to calculate rewards
     * @param _strategy             Strategy address
     * @param _contributor          Contributor address
     * @param _initialDepositAt     User initial deposit timestamp
     * @param _claimedAt            User last claim timestamp

     * @return Array of size 7 with the following distribution:
     * rewards[0]: Strategist BABL 
     * rewards[1]: Strategist Profit
     * rewards[2]: Steward BABL
     * rewards[3]: Steward Profit
     * rewards[4]: LP BABL
     * rewards[5]: total BABL
     * rewards[6]: total Profits
     */
    function _getStrategyProfitsAndBABL(
        address _garden,
        address _strategy,
        address _contributor,
        uint256 _initialDepositAt,
        uint256 _claimedAt
    ) private view returns (uint256[] memory) {
        _require(address(IStrategy(_strategy).garden()) == _garden, Errors.STRATEGY_GARDEN_MISMATCH);
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
        if (strategyDetails[1] > _claimedAt && strategyDetails[1] > _initialDepositAt && _initialDepositAt != 0) {
            // Get the contributor power until the the strategy exit timestamp
            uint256 contributorShare = _getSafeUserSharePerStrategy(_garden, _contributor, _strategy);
            rewards = _getRewardsPerRole(
                _garden,
                _strategy,
                strategist,
                _contributor,
                contributorShare,
                strategyDetails,
                profitData
            );
        }
        return rewards;
    }

    /**
     * Get the BABL rewards (Mining program) for a Steward profile
     * @param _strategy         Strategy address
     * @param _contributor      Contributor address
     * @param _strategyDetails  Strategy details data
     * @param _profitData       Strategy profit data
     */
    function _getStrategyStewardBabl(
        address _strategy,
        address _contributor,
        uint256[] memory _strategyDetails,
        bool[] memory _profitData
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
            babl = _strategyDetails[9].multiplyDecimal(stewardsBABLPercentage).preciseMul(
                uint256(userVotes).preciseDiv(_strategyDetails[4])
            );
        } else if (userVotes > 0 && _profitData[0] == true && _profitData[1] == false) {
            // Voting in favor positive profits but below expected return
            babl = _strategyDetails[9].multiplyDecimal(stewardsBABLPercentage).preciseMul(
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
            babl = _strategyDetails[9].multiplyDecimal(stewardsBABLPercentage).preciseMul(
                uint256(Math.abs(userVotes)).preciseDiv(votesAccounting)
            );

            bablCap = babl.mul(2); // Max cap
            // We add a bonus inverse to the error of expected return vs real returns
            babl = babl.add(babl.preciseMul(_strategyDetails[11].preciseDiv(_strategyDetails[8])));
            if (babl > bablCap) babl = bablCap; // We limit 2x by a Cap
        } else if (userVotes < 0 && _profitData[1] == true) {
            babl = 0;
        }
        return babl;
    }

    /**
     * Get the rewards for a Steward profile
     * @param _garden           Garden address
     * @param _strategy         Strategy address
     * @param _contributor      Contributor address
     * @param _strategyDetails  Strategy details data
     * @param _profitData       Strategy profit data
     */
    function _getStrategyStewardProfits(
        address _garden,
        address _strategy,
        address _contributor,
        uint256[] memory _strategyDetails,
        bool[] memory _profitData
    ) private view returns (uint256 stewardBabl) {
        // Assumptions:
        // Assumption that the strategy got profits. Should not execute otherwise.
        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        int256 userVotes = IStrategy(_strategy).getUserVotes(_contributor);
        uint256 totalVotes = _strategyDetails[4].add(_strategyDetails[5]);

        uint256 profitShare =
            gardenCustomProfitSharing[_garden] ? gardenProfitSharing[_garden][1] : stewardsProfitPercentage;
        if (userVotes > 0) {
            // If the strategy got profits equal or above expected return only positive votes counts,
            // so we divide by only positive
            // Otherwise, we divide by all total votes as also voters against will get some profits
            // if the strategy returned less than expected
            uint256 accountingVotes = _profitData[1] ? _strategyDetails[4] : totalVotes;
            stewardBabl = _strategyDetails[10].multiplyDecimal(profitShare).preciseMul(uint256(userVotes)).preciseDiv(
                accountingVotes
            );
        } else if ((userVotes < 0) && _profitData[1] == false) {
            stewardBabl = _strategyDetails[10]
                .multiplyDecimal(profitShare)
                .preciseMul(uint256(Math.abs(userVotes)))
                .preciseDiv(totalVotes);
        } else if ((userVotes < 0) && _profitData[1] == true) {
            // Voted against a very profit strategy above expected returns, get no profit at all
            stewardBabl = 0;
        }
    }

    /**
     * Get the BABL rewards (Mining program) for a Strategist profile
     * @param _strategyDetails     Strategy details data
     * @param _profitData          Strategy details data
     */
    function _getStrategyStrategistBabl(uint256[] memory _strategyDetails, bool[] memory _profitData)
        private
        view
        returns (uint256)
    {
        // Assumptions:
        // We assume that the contributor is the strategist. Should not execute this function otherwise.
        uint256 babl;
        uint256 bablCap;
        babl = _strategyDetails[9].multiplyDecimal(strategistBABLPercentage); // Standard calculation to be ponderated
        if (_profitData[0] == true && _profitData[1] == true) {
            // Strategy with equal or higher profits than expected
            bablCap = babl.mul(2); // Max cap
            // The more the results are close to the expected the more bonus will get (limited by a x2 cap)
            babl = babl.add(babl.preciseMul(_strategyDetails[8].preciseDiv(_strategyDetails[7])));
            if (babl > bablCap) babl = bablCap; // We limit 2x by a Cap
        } else if (_profitData[0] == true && _profitData[1] == false) {
            //under expectations
            // The more the results are close to the expected the less penalization it might have
            babl = babl.sub(babl.sub(babl.preciseMul(_strategyDetails[7].preciseDiv(_strategyDetails[8]))));
        } else {
            // No positive profit, no BABL assigned to the strategist role
            return 0;
        }
        return babl;
    }

    /**
     * Get the rewards for a Strategist profile
     * @param _garden           Garden address
     * @param _profitValue      Strategy profit value
     */
    function _getStrategyStrategistProfits(address _garden, uint256 _profitValue) private view returns (uint256) {
        // Assumptions:
        // Only executes if the contributor was the strategist of the strategy
        // AND the strategy had profits
        uint256 profitShare =
            gardenCustomProfitSharing[_garden] ? gardenProfitSharing[_garden][0] : strategistProfitPercentage;
        return _profitValue.multiplyDecimal(profitShare);
    }

    /**
     * Get the BABL rewards (Mining program) for a LP profile
     * @param _strategyRewards      Strategy rewards
     * @param _contributorPower     Contributor power
     */
    function _getStrategyLPBabl(uint256 _strategyRewards, uint256 _contributorPower) private view returns (uint256) {
        uint256 babl;
        // All params must have 18 decimals precision
        babl = _strategyRewards.multiplyDecimal(lpsBABLPercentage).preciseMul(_contributorPower);
        return babl;
    }

    /**
     * Calculates the BABL rewards supply for each quarter
     * @param _quarter      Number of the epoch (quarter)
     */
    function _tokenSupplyPerQuarter(uint256 _quarter) internal pure returns (uint96) {
        _require(_quarter >= 1, Errors.QUARTERS_MIN_1);
        if (_quarter >= 513) {
            return 0; // Avoid math overflow
        } else {
            uint256 firstFactor = (SafeDecimalMath.unit().add(DECAY_RATE)).powDecimal(_quarter.sub(1));
            uint256 supplyForQuarter = Q1_REWARDS.divideDecimal(firstFactor);
            return Safe3296.safe96(supplyForQuarter, 'overflow 96 bits');
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
     * @param _garden           Address of the garden
     * @param _contributor      Address of the contributor
     * @param _contributorBABL  BABL obtained in the strategy
     */
    function _getCreatorBonus(
        address _garden,
        address _contributor,
        uint256 _contributorBABL
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
                    _contributorBABL.multiplyDecimal(gardenCreatorBonus).div(IGarden(_garden).totalContributors())
                );
        } else {
            if (isCreator) {
                // Check other creators and divide by number of creators or members if creator address is 0
                return _contributorBABL.add(_contributorBABL.multiplyDecimal(gardenCreatorBonus).div(creatorCount));
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
        // strategyDetails[12]: endBlock
        // strategyDetails[13]: gardenSupply
        // strategyDetails[14]: startingBlock
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
        // We apply a 0.25% rounding error margin at NAV
        strategyDetails[7] = strategyDetails[7].sub(strategyDetails[7].multiplyDecimal(25e14));
        // Failsafe mode in case of wrong NAV (above 300%)
        strategyDetails[7] = strategyDetails[7].preciseDiv(strategyDetails[6]) > 3e18
            ? strategyDetails[6]
            : strategyDetails[7];
        profitData[0] = strategyDetails[7] >= strategyDetails[6] ? true : false;
        profitData[1] = strategyDetails[7] >= strategyDetails[8] ? true : false;
        strategyDetails[10] = profitData[0] ? strategyDetails[7].sub(strategyDetails[6]) : 0; // no profit
        // We consider that it potentially will have profits so the protocol will take profitFee
        // If 0 it does nothing
        strategyDetails[11] = profitData[1]
            ? strategyDetails[7].sub(strategyDetails[8])
            : strategyDetails[8].sub(strategyDetails[7]);
        // We take care about beta live strategies as they have a different start mining time != executedAt
        (uint256 numQuarters, uint256 startingQuarter) =
            _getRewardsWindow(
                (
                    (strategyDetails[0] > START_TIME && START_TIME != 0)
                        ? strategyDetails[0]
                        : strategyPerQuarter[_strategy][1].betaInitializedAt
                ),
                block.timestamp
            );
        // We create an array of quarters since the begining of the strategy
        // We then fill with known + unknown data that has to be figured out
        uint256[] memory strategyPower = new uint256[](numQuarters);
        uint256[] memory protocolPower = new uint256[](numQuarters);
        for (uint256 i = 0; i < numQuarters; i++) {
            // We take the info of each epoch from current checkpoints
            // array[0] for the first quarter power checkpoint of the strategy
            strategyPower[i] = strategyPerQuarter[_strategy][startingQuarter.add(i)].quarterPower;
            protocolPower[i] = protocolPerQuarter[startingQuarter.add(i)].quarterPower;
            _require(strategyPower[i] <= protocolPower[i], Errors.OVERFLOW_IN_POWER);
        }
        strategyPower = _updatePendingPower(
            strategyPower,
            numQuarters,
            startingQuarter,
            strategyDetails[2],
            strategyPrincipal[_strategy]
        );
        protocolPower = _updatePendingPower(
            protocolPower,
            numQuarters,
            startingQuarter,
            miningUpdatedAt,
            miningProtocolPrincipal
        );
        strategyDetails[9] = _harvestStrategyRewards(
            strategyPower,
            protocolPower,
            startingQuarter,
            numQuarters,
            strategyDetails[7].preciseDiv(strategyDetails[6])
        );
    }

    function _harvestStrategyRewards(
        uint256[] memory _strategyPower,
        uint256[] memory _protocolPower,
        uint256 _startingQuarter,
        uint256 _numQuarters,
        uint256 _percentageProfit
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
                    .preciseMul(uint256(_tokenSupplyPerQuarter(_startingQuarter.add(i))))
                    .preciseMul(percentage);
            strategyRewards = strategyRewards.add(rewardsPerQuarter);
        }
        // Set the max cap bonus x2
        uint256 maxRewards = strategyRewards.preciseMul(2e18);
        // Apply rewards weight related to principal and profit
        strategyRewards = strategyRewards.preciseMul(bablPrincipalWeight).add(
            strategyRewards.preciseMul(bablProfitWeight).preciseMul(_percentageProfit)
        );
        // Check max cap
        if (strategyRewards >= maxRewards) {
            strategyRewards = maxRewards;
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

contract RewardsDistributorV9 is RewardsDistributor {}
