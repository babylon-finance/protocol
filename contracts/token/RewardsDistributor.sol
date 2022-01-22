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
import {IProphets} from '../interfaces/IProphets.sol';

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
        _require(controller.isGarden(garden), Errors.ONLY_ACTIVE_GARDEN);
        _require(IGarden(garden).isGardenStrategy(_strategy), Errors.STRATEGY_GARDEN_MISMATCH);
    }

    /**
     * Throws if the sender is not the controller
     */
    function _onlyGovernanceOrEmergency() private view {
        _require(
            msg.sender == controller.owner() ||
                msg.sender == owner() ||
                msg.sender == controller.EMERGENCY_OWNER() ||
                msg.sender == address(controller),
            Errors.ONLY_GOVERNANCE_OR_EMERGENCY
        );
    }

    /**
     * Throws if Rewards Distributor is paused
     */
    function _onlyUnpaused() private view {
        // Do not execute if Globally or individually paused
        _require(!controller.isPaused(address(this)), Errors.ONLY_UNPAUSED);
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
    // DAI normalize asset
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Reentrancy guard countermeasure
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    // NFT Prophets
    IProphets private constant PROPHETS_NFT = IProphets(0x26231A65EF80706307BbE71F032dc1e5Bf28ce43);

    /* ============ State Variables ============ */

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
        uint256 tokens; // User garden tokens in the checkpoint
        uint256 supply; // DEPRECATED
        uint256 prevBalance; // Previous user balance (backward compatibility for beta users)
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

    // Mapping re-used to trigger governance migrations into checkpoints for an address
    // Address can be garden or an individual user
    // Usage:
    // a) to migrate the whole garden => betaAddressMigrated[_garden][_garden] = true
    // b) to migrate a user for all gardens at once => betaAddressMigrated[_contributor][_contributor] = true
    // Note: do not re-use it in the following format => [_garden][_contributor] as it was previously used for another older migration to avoid issues.
    mapping(address => mapping(address => bool)) private betaAddressMigrated;
    mapping(address => bool) private betaOldMigrations; // DEPRECATED

    uint256 private bablProfitWeight;
    uint256 private bablPrincipalWeight;

    // A record of garden token checkpoints for each address of each garden, by index
    // garden -> address -> index checkpoint -> checkpoint struct data
    mapping(address => mapping(address => mapping(uint256 => Checkpoints))) private gardenCheckpoints;

    // The number of checkpoints for each address of each garden
    // garden -> address -> number of checkpoints
    mapping(address => mapping(address => uint256)) private numCheckpoints;
    // Benchmark creates up to 3 segments to differentiate between cool strategies and bad strategies
    // First 2 values benchmark[0] and benchmark[1] represent returned/allocated % min and max thresholds to create 3 segments
    // benchmark[0] value: Used to define the threshold between very bad strategies and not cool strategies
    // benchmark[0] = minThreshold default 0 (e.g. 90e16 represents profit of -10 %)
    // It separates segment 1 (very bad strategies) and segment 2 (not cool strategies)
    // benchmark[1] value: Used to define the threshold between not good/cool strategies and cool/good strategies
    // benchmark[1] = maxThreshold default 0 (e.g. 103e16 represents profit of +3 %)
    // It separates segment 2 (not cool strategies) and segment 3 (cool strategies)
    // benchmark[2] value: Used to set a penalty (if any) for very bad strategies (segment 1)
    // benchmark[2] = Segment1 Penalty default 0 (e.g. 50e16 represents 1/2 = 50% = half rewards penalty)
    // benchmark[3] value: Used to set a penalty (if any) for not cool strategies (segment 2)
    // benchmark[3] = Segment 2 Penalty/Boost default 0 (e.g. 1e18 represents 1 = 100% = no rewards penalty)
    // becnhmark[4] value: Used to set a boost (if any) for cool strategies (segment 3)
    // becnhmark[4] = Segment 3 Boost default 1e18 (e.g. 2e18 represents 2 = 200% = rewards boost x2)
    uint256[5] private benchmark;

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

        bablProfitWeight = 65e16; // 65% (BIP-7 will change it into 95%)
        bablPrincipalWeight = 35e16; // 35% (BIP-7 will change it into 5%)

        status = NOT_ENTERED;
        // BABL Mining program was started by bip#1
        START_TIME = block.timestamp;
        // Benchmark conditions to apply to BABL rewards are initialized as 0
        // Backward compatibility manages benchmark[4] value that must be always >= 1e18
        benchmark[4] = 1e18; // default value
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
     * Function used by each garden to signal each deposit and withdrawal in checkpoints to be used for rewards
     * @param _garden                Address of the garden
     * @param _contributor           Address of the contributor
     * @param _previousBalance       Previous balance of the contributor
     * @param _tokenDiff             Amount difference in this deposit/withdraw
     * @param _addOrSubstract        Whether the contributor is adding (true) or withdrawing capital (false)
     */
    function updateGardenPowerAndContributor(
        address _garden,
        address _contributor,
        uint256 _previousBalance,
        uint256 _tokenDiff,
        bool _addOrSubstract
    ) external override nonReentrant {
        _require(controller.isGarden(msg.sender), Errors.ONLY_ACTIVE_GARDEN);
        uint256 newBalance = _addOrSubstract ? _previousBalance.add(_tokenDiff) : _previousBalance.sub(_tokenDiff);
        // Creates a new user checkpoint
        _writeCheckpoint(_garden, _contributor, newBalance, _previousBalance);
    }

    /**
     * Sending BABL as part of the claim process (either by sig or standard claim)
     *
     */
    function sendBABLToContributor(address _to, uint256 _babl) external override nonReentrant returns (uint256) {
        _require(controller.isGarden(msg.sender), Errors.ONLY_ACTIVE_GARDEN);
        return _sendBABLToContributor(_to, _babl);
    }

    /** PRIVILEGE FUNCTION
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
        _onlyGovernanceOrEmergency();
        _require(controller.isGarden(_garden), Errors.ONLY_ACTIVE_GARDEN);
        _setProfitRewards(_garden, _strategistShare, _stewardsShare, _lpShare);
    }

    /** PRIVILEGE FUNCTION
     * Migrates by governance: (2 options)
     * a) the whole garden or a user for all gardens into checkpoints deprecating c-power
     * @param _address              Array of Address to migrate (garden or user)
     * @param _toMigrate            Bool to migrate (true) or redo (false)
     */
    function migrateAddressToCheckpoints(address[] memory _address, bool _toMigrate) external override {
        _onlyGovernanceOrEmergency();
        for (uint256 i = 0; i < _address.length; i++) {
            betaAddressMigrated[_address[i]][_address[i]] = _toMigrate;
        }
    }

    /** PRIVILEGE FUNCTION
     * Change default BABL shares % by the governance
     * @param _newMiningParams      Array of new mining params to be set by government
     */
    function setBABLMiningParameters(uint256[11] memory _newMiningParams) external override {
        // _newMiningParams[0]: _strategistShare
        // _newMiningParams[1]: _stewardsShare
        // _newMiningParams[2]: _lpShare
        // _newMiningParams[3]: _creatorBonus
        // _newMiningParams[4]: _profitWeight
        // _newMiningParams[5]: _principalWeight
        // _newMiningParams[6]: _benchmark[0] to differentiate from very bad strategies and not cool strategies
        // _newMiningParams[7]: _benchmark[1] to differentiate from not cool strategies and cool strategies
        // _newMiningParams[8]: _benchmark[2] penalty to be applied to very bad strategies in benchmark segment 1
        // _newMiningParams[9]: _benchmark[3] penalty to be applied to not cool strategies in benchmark segment 2
        // _newMiningParams[10]: _benchmark[4] boost/bonus to be applied to cool strategies in benchmark segment 3
        _onlyGovernanceOrEmergency();
        _require(
            _newMiningParams[0].add(_newMiningParams[1]).add(_newMiningParams[2]) == 1e18 &&
                _newMiningParams[3] <= 1e18 &&
                _newMiningParams[4].add(_newMiningParams[5]) == 1e18 &&
                _newMiningParams[6] <= _newMiningParams[7] &&
                _newMiningParams[8] <= _newMiningParams[9] &&
                _newMiningParams[9] <= _newMiningParams[10] &&
                _newMiningParams[10] >= 1e18,
            Errors.INVALID_MINING_VALUES
        );
        strategistBABLPercentage = _newMiningParams[0];
        stewardsBABLPercentage = _newMiningParams[1];
        lpsBABLPercentage = _newMiningParams[2];
        gardenCreatorBonus = _newMiningParams[3];
        bablProfitWeight = _newMiningParams[4];
        bablPrincipalWeight = _newMiningParams[5];
        benchmark[0] = _newMiningParams[6]; // minThreshold dividing segment 1 and 2 (if any)
        benchmark[1] = _newMiningParams[7]; // maxThreshold dividing segment 2 and 3 (if any)
        benchmark[2] = _newMiningParams[8]; // penalty for segment 1
        benchmark[3] = _newMiningParams[9]; // penalty/boost for segment 2
        benchmark[4] = _newMiningParams[10]; // boost for segment 3
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
     * Gets the baseline amount of BABL rewards for a given strategy
     * @param _strategy     Strategy to check
     */
    function getStrategyRewards(address _strategy) external view override returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        // ts[0]: executedAt, ts[1]: exitedAt, ts[2]: updatedAt
        uint256[] memory ts = new uint256[](3);
        (, , , , ts[0], ts[1], ts[2]) = strategy.getStrategyState();
        _require(ts[1] != 0, Errors.STRATEGY_IS_NOT_OVER_YET);
        if (strategy.enteredAt() >= START_TIME || ts[1] >= START_TIME) {
            // We avoid gas consuming once a strategy got its BABL rewards during its finalization
            uint256 rewards = strategy.strategyRewards();
            if (rewards != 0) {
                return rewards;
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
                        .preciseMul(_tokenSupplyPerQuarter(startingQuarter.add(i)))
                        .preciseMul(percentage);
                rewards = rewards.add(rewardsPerQuarter);
            }
            // Apply rewards weight related to principal and profit and related to benchmark
            return _getBenchmarkRewards(str[1], str[0], rewards, ts[0]);
        } else {
            return 0;
        }
    }

    /**
     * Get token power at a specific block for an account
     *
     * @param _garden       Address of the garden
     * @param _address      Address to get prior balance for
     * @param _blockTime  Block timestamp to get token power at
     * @return Token power for an account at specific block
     */
    function getPriorBalance(
        address _garden,
        address _address,
        uint256 _blockTime
    )
        public
        view
        virtual
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // We get the previous (prior) balance to _blockTime timestamp
        // Actually it also acts as a flashloan protection along the time
        _blockTime = _blockTime.sub(1);
        uint256 nCheckpoints = numCheckpoints[_garden][_address];
        ContributorPerGarden storage contributor = contributorPerGarden[_garden][_address];
        // beta user if initializedAt > 0
        uint256 initializedAt = contributor.initialDepositAt;
        uint256 balance = ERC20(_garden).balanceOf(_address);
        if (nCheckpoints == 0 && !(initializedAt > 0)) {
            return (0, 0, 0);
        } else if (nCheckpoints == 0 && initializedAt > 0) {
            // Backward compatible for beta users, initial deposit > 0 but still no checkpoints
            // It also consider burning for bad strategist
            return (initializedAt, balance, 0);
        }
        // There are at least one checkpoint from this point
        // First check most recent balance
        if (gardenCheckpoints[_garden][_address][nCheckpoints - 1].fromTime <= _blockTime) {
            // Burning security protection at userTokens
            // It only limit the balance in case of burnt tokens and only if using last checkpoint
            return (
                gardenCheckpoints[_garden][_address][nCheckpoints - 1].fromTime,
                gardenCheckpoints[_garden][_address][nCheckpoints - 1].tokens > balance
                    ? balance
                    : gardenCheckpoints[_garden][_address][nCheckpoints - 1].tokens,
                nCheckpoints - 1
            );
        }
        // Next check implicit zero balance
        if (gardenCheckpoints[_garden][_address][0].fromTime > _blockTime && !(initializedAt > 0)) {
            // backward compatible
            return (0, 0, 0);
        } else if (gardenCheckpoints[_garden][_address][0].fromTime > _blockTime && initializedAt > 0) {
            // Backward compatible for beta users, initial deposit > 0 but lost initial checkpoints
            // First checkpoint stored its previous balance so we use it to guess the user past
            return (initializedAt, gardenCheckpoints[_garden][_address][0].prevBalance, 0);
        }
        // It has more checkpoints but the time is between different checkpoints, we look for it
        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoints memory cp = gardenCheckpoints[_garden][_address][center];
            if (cp.fromTime == _blockTime) {
                return (cp.fromTime, cp.tokens, center);
            } else if (cp.fromTime < _blockTime) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return (
            gardenCheckpoints[_garden][_address][lower].fromTime,
            gardenCheckpoints[_garden][_address][lower].tokens,
            lower
        );
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
        returns (uint256[17] memory miningData)
    {
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
        miningData[10] = bablProfitWeight;
        miningData[11] = bablPrincipalWeight;
        miningData[12] = benchmark[0];
        miningData[13] = benchmark[1];
        miningData[14] = benchmark[2];
        miningData[15] = benchmark[3];
        miningData[16] = benchmark[4];
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
            uint256 contributorShare = _getSafeUserSharePerStrategy(garden, _contributor, strategyDetails);
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
        (, uint256[] memory strategyDetails, ) = IStrategy(_strategy).getStrategyRewardsContext();
        return _getSafeUserSharePerStrategy(_garden, _contributor, strategyDetails);
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

    /* ============ Internal Functions ============ */

    /**
     * @dev internal function to write a checkpoint for contributor token power
     * @param _garden        Address of the garden
     * @param _address       Address for the checkpoint
     * @param _newBalance    The new token balance
     * @param _prevBalance   The previous user token balance
     */
    function _writeCheckpoint(
        address _garden,
        address _address,
        uint256 _newBalance,
        uint256 _prevBalance
    ) internal {
        uint256 blockTime = block.timestamp;
        uint256 nCheckpoints = numCheckpoints[_garden][_address];
        if (nCheckpoints > 0 && gardenCheckpoints[_garden][_address][nCheckpoints - 1].fromTime == blockTime) {
            gardenCheckpoints[_garden][_address][nCheckpoints - 1].tokens = _newBalance;
        } else {
            // We only store previous Balance in case of the first checkpoint
            // to get backward compatibility for beta addresses
            if (nCheckpoints == 0) {
                gardenCheckpoints[_garden][_address][nCheckpoints] = Checkpoints(
                    blockTime,
                    _newBalance,
                    0,
                    _prevBalance
                );
            } else {
                gardenCheckpoints[_garden][_address][nCheckpoints] = Checkpoints(blockTime, _newBalance, 0, 0);
            }
            numCheckpoints[_garden][_address] = nCheckpoints + 1;
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
     * Sends profits and BABL tokens rewards to a contributor after a claim is requested to the protocol.
     * @param _to        Address to send the profit and tokens to
     * @param _babl      Amount of BABL to send
     *
     */
    function _sendBABLToContributor(address _to, uint256 _babl) internal returns (uint256) {
        _onlyUnpaused();
        uint256 bablBal = babltoken.balanceOf(address(this));
        uint256 bablToSend = _babl > bablBal ? bablBal : _babl;
        SafeERC20.safeTransfer(babltoken, _to, Safe3296.safe96(bablToSend, 'overflow 96 bits'));
        return bablToSend;
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

    /* ========== Internal View functions ========== */

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
        IPriceOracle oracle = IPriceOracle(controller.priceOracle());
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
        // Contributor share is fluctuating along the way in each new deposit
        rewards[4] = _getStrategyLPBabl(_strategyDetails[9], _contributorShare);
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
     * Gets the contributor power from one timestamp to the other
     * @param _garden       Address of the garden where the contributor belongs to
     * @param _contributor  Address of the contributor
     * @param _time         Timestamp to check power
     * @return uint256      Contributor power during that period
     */
    function _getContributorPower(
        address _garden,
        address _contributor,
        uint256 _time,
        uint256 _gardenSupply
    ) internal view returns (uint256) {
        ContributorPerGarden storage contributor = contributorPerGarden[_garden][_contributor];
        GardenPowerByTimestamp storage gardenData = gardenPowerByTimestamp[_garden][0];
        if (contributor.initialDepositAt == 0 || contributor.initialDepositAt > _time) {
            return 0;
        } else {
            (, uint256 balance, ) = getPriorBalance(_garden, _contributor, contributor.lastDepositAt);
            uint256 supply = _gardenSupply > 0 ? _gardenSupply : ERC20(_garden).totalSupply();
            // First we need to get an updatedValue of user and garden power since lastDeposits as of block.timestamp
            uint256 updatedPower =
                contributor.tsContributions[0].power.add((block.timestamp.sub(contributor.lastDepositAt)).mul(balance));
            uint256 updatedGardenPower =
                gardenData.accGardenPower.add((block.timestamp.sub(gardenData.lastDepositAt)).mul(supply));
            // We then time travel back to when the strategy exitedAt
            // Calculate the power at "_time" timestamp
            uint256 timeDiff = block.timestamp.sub(_time);
            uint256 userPowerDiff = contributor.tsContributions[0].avgBalance.mul(timeDiff);
            uint256 gardenPowerDiff = gardenData.avgGardenBalance.mul(timeDiff);
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
     * @param _strategyDetails Strategy details rewards context
     * @return % deserved share per user
     */
    function _getSafeUserSharePerStrategy(
        address _garden,
        address _contributor,
        uint256[] memory _strategyDetails
    ) internal view returns (uint256) {
        // strategyDetails array mapping:
        // strategyDetails[0]: executedAt
        // strategyDetails[1]: exitedAt
        // strategyDetails[12]: startingGardenSupply
        // strategyDetails[13]: endingGardenSupply
        uint256 endTime = _strategyDetails[1] > 0 ? _strategyDetails[1] : block.timestamp;
        uint256 cp = numCheckpoints[_garden][_contributor];
        bool betaUser =
            !betaAddressMigrated[_contributor][_contributor] &&
                (cp == 0 || (cp > 0 && gardenCheckpoints[_garden][_contributor][0].fromTime >= endTime)) &&
                contributorPerGarden[_garden][_contributor].initialDepositAt > 0;
        bool oldStrategy = _strategyDetails[0] < gardenPowerByTimestamp[_garden][0].lastDepositAt;
        if (betaUser && oldStrategy && !betaAddressMigrated[_garden][_garden]) {
            // Backward compatibility for old strategies
            return _getContributorPower(_garden, _contributor, endTime, _strategyDetails[13]);
        }
        // Take the closest position prior to _endTime
        (uint256 timestamp, uint256 balanceEnd, uint256 cpEnd) = getPriorBalance(_garden, _contributor, endTime);
        if (balanceEnd < 1e10) {
            // zero or dust balance
            // Avoid gas consuming
            return 0;
        }
        uint256 startTime = _strategyDetails[0];
        uint256 finalSupplyEnd =
            (_strategyDetails[1] > 0 && _strategyDetails[13] > 0) ? _strategyDetails[13] : ERC20(_garden).totalSupply();
        // At this point, all strategies must be started or even finished startTime != 0
        if (timestamp > startTime) {
            if (cp > 0) {
                // User has any checkpoint
                // If the user balance fluctuated during the strategy duration, we take real average balance
                uint256 avgBalance = _getAvgBalance(_garden, _contributor, startTime, cpEnd, endTime);
                // Avoid specific malicious attacks
                balanceEnd = avgBalance > balanceEnd ? balanceEnd : avgBalance;
            } else {
                // no checkpoints
                // if deposited before endTime, take proportional
                // if deposited after endTime, take nothing
                balanceEnd = timestamp < endTime
                    ? balanceEnd.mul(endTime.sub(timestamp)).div(endTime.sub(startTime))
                    : 0;
            }
        }
        return balanceEnd.preciseDiv(finalSupplyEnd);
    }

    /**
     * Get Avg Address Balance in a garden between two points
     * Address represents any user but it can also be the garden itself
     * @param _garden           Garden address
     * @param _address          Address to get avg balance
     * @param _start            Start timestamp
     * @param _cpEnd            End time checkpoint number
     * @param _endTime          End timestamp
     * @return Avg address token balance within a garden
     */
    function _getAvgBalance(
        address _garden,
        address _address,
        uint256 _start,
        uint256 _cpEnd,
        uint256 _endTime
    ) internal view returns (uint256) {
        (, uint256 prevBalance, uint256 cpStart) = getPriorBalance(_garden, _address, _start);
        if (_start == _endTime) {
            // Avoid underflow
            return prevBalance;
        } else {
            uint256 addressPower;
            uint256 timeDiff;
            // We calculate the avg balance of an address within a time range
            // avg balance = addressPower / total period considered
            // addressPower = sum(balance x time of each period between checkpoints)
            // Initializing addressPower since the last known checkpoint _endTime
            // addressPower since _cpEnd checkpoint is "balance x time difference (endTime - checkpoint timestamp)"
            addressPower = gardenCheckpoints[_garden][_address][_cpEnd].tokens.mul(
                _endTime.sub(gardenCheckpoints[_garden][_address][_cpEnd].fromTime)
            );
            // Then, we add addressPower data from periods between all intermediate checkpoints (if any)
            // periods between starting checkpoint and ending checkpoint (if any)
            // We go from the newest checkpoint to the oldest
            for (uint256 i = _cpEnd; i > cpStart; i--) {
                // We only take proportional addressPower of cpStart checkpoint (from _start onwards)
                // Usually [cpStart].fromTime <= _start except when cpStart == 0 AND beta addresses
                // Those cases are handled below to add previous address power happening before the first checkpoint
                Checkpoints memory userPrevCheckpoint = gardenCheckpoints[_garden][_address][i.sub(1)];
                timeDiff = gardenCheckpoints[_garden][_address][i].fromTime.sub(
                    userPrevCheckpoint.fromTime > _start ? userPrevCheckpoint.fromTime : _start
                );
                addressPower = addressPower.add(userPrevCheckpoint.tokens.mul(timeDiff));
            }
            // We now handle the previous addressPower of beta addresses (if applicable)
            uint256 fromTimeCp0 = gardenCheckpoints[_garden][_address][0].fromTime;
            if (cpStart == 0 && fromTimeCp0 > _start) {
                // Beta address with previous balance before _start
                addressPower = addressPower.add(prevBalance.mul(fromTimeCp0.sub(_start)));
            }
            // avg balance = addressPower / total period of the "strategy" considered
            return addressPower.div(_endTime.sub(_start));
        }
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
            uint256 contributorShare = _getSafeUserSharePerStrategy(_garden, _contributor, strategyDetails);
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
     * @param _strategy             Strategy address
     * @param _contributor          Contributor address
     * @param _strategyDetails      Strategy details data
     * @param _profitData           Strategy profit data
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
     * @param _strategyDetails          Strategy details data
     * @param _profitData               Strategy details data
     */
    function _getStrategyStrategistBabl(uint256[] memory _strategyDetails, bool[] memory _profitData)
        private
        view
        returns (uint256)
    {
        // Assumptions:
        // We assume that the contributor is the strategist. Should not execute this function otherwise.
        uint256 babl;
        babl = _strategyDetails[9].multiplyDecimal(strategistBABLPercentage); // Standard calculation to be ponderated
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
     * @param _contributorShare     Contributor share in the period
     */
    function _getStrategyLPBabl(uint256 _strategyRewards, uint256 _contributorShare) private view returns (uint256) {
        uint256 babl;
        // All params must have 18 decimals precision
        babl = _strategyRewards.multiplyDecimal(lpsBABLPercentage).preciseMul(_contributorShare);
        return babl;
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
        // We take care about beta live strategies as they have a different start mining time != executedAt
        (uint256 numQuarters, uint256 startingQuarter) =
            _getRewardsWindow(
                (
                    (strategyDetails[0] > START_TIME)
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
        strategyDetails[9] = _getBenchmarkRewards(
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

    /**
     * Apply specific BABL mining weights to baseline BABL mining rewards based on mining benchmark params
     * @param _returned           Strategy capital returned
     * @param _allocated          Strategy capital allocated
     * @param _rewards            Strategy baseline BABL rewards
     * @param _executedAt         Strategy timestamp of initial execution
     */
    function _getBenchmarkRewards(
        uint256 _returned,
        uint256 _allocated,
        uint256 _rewards,
        uint256 _executedAt
    ) private view returns (uint256) {
        // We categorize the strategy APY profits into one of the 3 segments (very bad, regular and cool strategies)
        // Bad and regular will be penalized from bigger penalization to lower
        // Cool strategies will be boosted
        // As we get real time profit (returned / allocated) we need to annualize the strategy profits (APY)
        // Real time profit
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
            _rewards.preciseMul(bablPrincipalWeight).add(
                _rewards.preciseMul(bablProfitWeight).preciseMul(percentageProfit).preciseMul(rewardsFactor)
            );
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

contract RewardsDistributorV13 is RewardsDistributor {}
