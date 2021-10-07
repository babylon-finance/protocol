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
     * Throws if the BABL Rewards mining program is not active
     */
    function _onlyMiningActive() private view {
        _require(IBabController(controller).bablMiningProgramEnabled(), Errors.ONLY_MINING_ACTIVE);
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
    uint256 public override START_TIME; // Starting time of the rewards distribution

    // solhint-disable-next-line
    uint256 private BABL_STRATEGIST_SHARE;
    // solhint-disable-next-line
    uint256 private BABL_STEWARD_SHARE;
    // solhint-disable-next-line
    uint256 private BABL_LP_SHARE;
    // solhint-disable-next-line
    uint256 private PROFIT_STRATEGIST_SHARE;
    // solhint-disable-next-line
    uint256 private PROFIT_STEWARD_SHARE;
    // solhint-disable-next-line
    uint256 private PROFIT_LP_SHARE;
    // solhint-disable-next-line
    uint256 private PROFIT_PROTOCOL_FEE;
    // solhint-disable-next-line
    uint256 private CREATOR_BONUS;

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
        uint256 fromDepositAt; // DEPRECATED
        uint256 lastDepositAt; // DEPRECATED
        uint256 gardenFromDepositAt; // DEPRECATED
        uint256 gardenLastDepositAt; // DEPRECATED
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
    mapping(address => mapping(address => bool)) private betaUserMigrated;
    mapping(address => bool) private betaGardenMigrated;

    uint256 private BABL_PROFIT_WEIGHT;
    uint256 private BABL_PRINCIPAL_WEIGHT;

    /* ============ Constructor ============ */

    function initialize(TimeLockedToken _bablToken, IBabController _controller) public {
        OwnableUpgradeable.__Ownable_init();
        _require(address(_bablToken) != address(0) && address(_controller) != address(0), Errors.ADDRESS_IS_ZERO);
        babltoken = _bablToken;
        controller = _controller;

        (
            BABL_STRATEGIST_SHARE,
            BABL_STEWARD_SHARE,
            BABL_LP_SHARE,
            CREATOR_BONUS,
            BABL_PROFIT_WEIGHT,
            BABL_PRINCIPAL_WEIGHT
        ) = controller.getBABLSharing();
        (PROFIT_STRATEGIST_SHARE, PROFIT_STEWARD_SHARE, PROFIT_LP_SHARE) = controller.getProfitSharing();
        PROFIT_PROTOCOL_FEE = controller.protocolPerformanceFee();

        status = NOT_ENTERED;
    }

    /* ============ External Functions ============ */

    /**
     * Add protocol live strategies to the mining program (if any)
     * @param _strategies         Array of live strategies during mining program activation
     */
    function addLiveStrategies(address[] memory _strategies) external override {
        // Strategies must be "active"
        uint256[] memory capitalAllocated = new uint256[](_strategies.length);
        bool[] memory isBetaStrategy = new bool[](_strategies.length);
        // We check if strategies are protocol strategies by controller external validation
        // We also check that they deserve activation on the mining program (need to be live)
        (isBetaStrategy, capitalAllocated) = controller.isBetaStrategy(_strategies);
        for (uint256 i = 0; i < _strategies.length; i++) {
            if (strategyPrincipal[_strategies[i]] != 0) {
                // Already updated, do nothing
                continue;
            }
            // Only pending updated strategies can be set
            // If the strategy exited already or was previously updated, it does not create new checkpoint
            if (isBetaStrategy[i]) {
                _updateProtocolPrincipal(_strategies[i], capitalAllocated[i], true);
            }
        }
    }

    /**
     * Function that adds/substract the capital received to the total principal of the protocol per timestamp
     * @param _capital                Amount of capital in any type of asset to be normalized into DAI
     * @param _addOrSubstract         Whether we are adding or substracting capital
     */
    function updateProtocolPrincipal(uint256 _capital, bool _addOrSubstract) external override {
        _onlyMiningActive();
        _onlyStrategy(msg.sender);
        // ts[0]: executedAt, ts[1]: exitedAt
        uint256[] memory ts = new uint256[](2);
        (, , , , ts[0], ts[1], ) = IStrategy(msg.sender).getStrategyState();
        if ((ts[0] >= START_TIME || ts[1] >= START_TIME) && START_TIME != 0) {
            // onlyMiningActive control, it does not create a checkpoint if the strategy is not part of the Mining Program
            _updateProtocolPrincipal(msg.sender, _capital, _addOrSubstract);
        }
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
        // Temporal beta migrations for beta gardens and beta users
        // If already migrated, it does nothing
        address[] memory betaContributor = new address[](1);
        betaContributor[0] = _contributor;
        _migrateBetaUsers(_garden, betaContributor);
        // End of temporal beta migrations for users and gardens
        _updateGardenPower(_garden, _previousSupply, newSupply);
        _updateContributorPower(_garden, _contributor, _previousBalance, newBalance);
    }

    /**
     * Sends BABL tokens rewards to a contributor after a claim is requested to the protocol.
     * @param _to                Address to send the tokens to
     * @param _amount            Amount of tokens to send the address to
     */
    function sendTokensToContributor(address _to, uint256 _amount) external override nonReentrant {
        _onlyUnpaused();
        _onlyMiningActive();
        // Restrictive only to gardens when claiming BABL
        _require(IBabController(controller).isGarden(msg.sender), Errors.ONLY_ACTIVE_GARDEN);
        uint96 amount = Safe3296.safe96(_amount, 'overflow 96 bits');
        _safeBABLTransfer(_to, amount);
    }

    /**
     * Starts BABL Rewards Mining Program from the controller.
     */
    function startBABLRewards() external override {
        _onlyUnpaused();
        _onlyController();
        if (START_TIME == 0) {
            // It can only be activated once to avoid overriding START_TIME
            START_TIME = block.timestamp;
        }
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
     */
    function setBABLRewards(
        uint256 _strategistShare,
        uint256 _stewardsShare,
        uint256 _lpShare,
        uint256 _creatorBonus,
        uint256 _profitWeight,
        uint256 _principalWeight
    ) external override {
        _onlyController();
        BABL_STRATEGIST_SHARE = _strategistShare;
        BABL_STEWARD_SHARE = _stewardsShare;
        BABL_LP_SHARE = _lpShare;
        CREATOR_BONUS = _creatorBonus;
        BABL_PROFIT_WEIGHT = _profitWeight;
        BABL_PRINCIPAL_WEIGHT = _principalWeight;
    }

    /**
     * PRIVILEGE FUNCTION to migrate beta users of each garden into the new optimized gas data structure
     * without checkpoints.
     * @dev Can be called by anyone, should be called AFTER migrating gardens once for each user and
     * can be removed after all beta garden users data of all gardens are migrated
     * @param _garden       Address of a protocol beta garden whose contributors belong to
     * @param _contributors Array of beta contributor addresses to migrate data
     */
    function migrateBetaUsers(address _garden, address[] memory _contributors) external override onlyOwner {
        _migrateBetaUsers(_garden, _contributors);
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
     */
    function getRewards(
        address _garden,
        address _contributor,
        address[] calldata _finalizedStrategies
    ) external view override returns (uint256[] memory) {
        _require(IBabController(controller).isGarden(address(_garden)), Errors.ONLY_ACTIVE_GARDEN);
        uint256[] memory totalRewards = new uint256[](7);
        uint256 initialDepositAt;
        uint256 claimedAt;
        (, initialDepositAt, claimedAt, , , , , , , ) = IGarden(_garden).getContributor(_contributor);
        for (uint256 i = 0; i < _finalizedStrategies.length; i++) {
            // Security check
            _require(IGarden(_garden).isGardenStrategy(_finalizedStrategies[i]), Errors.STRATEGY_GARDEN_MISMATCH);

            uint256[] memory tempRewards = new uint256[](7);

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
            // Backward compatible with default values (avoid division by zero in case it is not set yet)
            uint256 profitWeight = BABL_PROFIT_WEIGHT == 0 ? 60e16 : BABL_PROFIT_WEIGHT;
            uint256 principalWeight = BABL_PRINCIPAL_WEIGHT == 0 ? 40e16 : BABL_PRINCIPAL_WEIGHT;
            // PercentageProfit must always have 18 decimals (capital returned by capital allocated)
            uint256 percentageProfit = str[1].preciseDiv(str[0]);
            // Proportional to returns, it then allow extra bonus with a max cap of x2 (200%)
            if (percentageProfit > 2e18) percentageProfit = 2e18;
            rewards = rewards.preciseMul(principalWeight).add(
                rewards.preciseMul(profitWeight).preciseMul(percentageProfit)
            );
            // Extra bonus proportional to the profit (or penalty if has losses)
            rewards = rewards.preciseMul(percentageProfit);
            return Safe3296.safe96(rewards, 'overflow 96 bits');
        } else {
            return 0;
        }
    }

    /**
     * Gets the contributor power from one timestamp to the other
     * @param _garden      Address of the garden where the contributor belongs to
     * @param _contributor Address of the contributor
     * @param _time        Timestamp to check power
     * @return uint256     Contributor power during that period
     */
    function getContributorPower(
        address _garden,
        address _contributor,
        uint256 _time
    ) public view override returns (uint256) {
        // Check to avoid out of bounds
        _require(_time >= IGarden(_garden).gardenInitializedAt(), Errors.CONTRIBUTOR_POWER_CHECK_WINDOW);
        uint256[] memory powerData = new uint256[](9);
        // powerData[0]: lastDepositAt (contributor)
        // powerData[1]: initialDepositAt (contributor)
        // powerData[2]: balance (contributor)
        // powerData[3]: power (contributor)
        // powerData[4]: avgBalance (contributor)
        // powerData[5]: lastDepositAt (garden)
        // powerData[6]: accGardenPower (garden)
        // powerData[7]: avgGardenBalance (garden)
        // powerData[8]: totalSupply (garden)
        powerData = _getGardenAndContributor(_garden, _contributor);

        if (powerData[1] == 0 || powerData[1] > _time || powerData[2] == 0) {
            return 0;
        } else {
            // Safe check to avoid underflow, time travel only works for a past date
            if (_time > block.timestamp) {
                _time = block.timestamp;
            }

            // Backward compatibility module for beta gardens and beta users
            // First we check the contributor in case of a beta user pending migration
            if (powerData[4] == 0 && gardenPid[_garden] > 0) {
                // pending contributor migration - backward compatible
                (, powerData[3], powerData[4], ) = _getContributorBetaMigrationData(_garden, _contributor);
            }
            // Second we check the garden in case of a beta garden pending migration
            if (powerData[7] == 0 && gardenPid[_garden] > 0) {
                // pending garden migration - backward compatible
                (powerData[5], powerData[6], powerData[7], ) = _getGardenBetaMigrationData(_garden);
            }
            // First we need to get an updatedValue of user and garden power since lastDeposits as of block.timestamp
            uint256 updatedPower = powerData[3].add((block.timestamp.sub(powerData[0])).mul(powerData[2]));
            uint256 updatedGardenPower = powerData[6].add((block.timestamp.sub(powerData[5])).mul(powerData[8]));

            // We then time travel back to when the strategy exitedAt
            // Calculate the power at "_to" timestamp
            uint256 timeDiff = block.timestamp.sub(_time);
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
     * Check the beta migration data state
     * @param _garden       Address of garden
     * @param _contributor  Address of contributor
     */

    function getBetaMigration(address _garden, address _contributor)
        external
        view
        override
        returns (uint256[] memory, bool[] memory)
    {
        uint256[] memory migrationData = new uint256[](6);
        bool[] memory migrationBool = new bool[](2);
        (migrationData[0], migrationData[1], migrationData[2], migrationBool[0]) = _getGardenBetaMigrationData(_garden);
        (migrationData[3], migrationData[4], migrationData[5], migrationBool[1]) = _getContributorBetaMigrationData(
            _garden,
            _contributor
        );
        return (migrationData, migrationBool);
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
            return [PROFIT_STRATEGIST_SHARE, PROFIT_STEWARD_SHARE, PROFIT_LP_SHARE];
        }
    }

    /* ============ Internal Functions ============ */
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
            miningProtocolPrincipal = miningProtocolPrincipal.sub(_capital);
            strategyPrincipal[_strategy] = strategyPrincipal[_strategy].sub(_capital);
        } else {
            // Adding capital
            miningProtocolPrincipal = miningProtocolPrincipal.add(_capital);
            strategyPrincipal[_strategy] = strategyPrincipal[_strategy].add(_capital);
        }
    }

    /**
     * Update the garden power whenever there is a deposit or withdraw
     * @param _garden           Address of the garden
     * @param _previousSupply   Previous garden token supply before minting or burning new user tokens
     */
    function _updateGardenPower(
        address _garden,
        uint256 _previousSupply,
        uint256 _newSupply
    ) internal {
        // We select timestamp [0] to persist the garden power data as we deprecated checkpoints
        GardenPowerByTimestamp storage gardenPower = gardenPowerByTimestamp[_garden][0];
        // The very first deposit takes 0 of power in a garden as power is principal x time and time is 0
        // Power is updated by usign previous totalSupply (before the new mint or burn which is just done
        // as part of deposit/withdraw op)
        gardenPower.accGardenPower = gardenPower.lastDepositAt == 0
            ? 0
            : gardenPower.accGardenPower.add((block.timestamp.sub(gardenPower.lastDepositAt)).mul(_previousSupply));
        // The following call should always go after minting new tokens
        // The reason is that we need an updated totalSupply to update avg garden balance
        gardenPower.avgGardenBalance = gardenPower.lastDepositAt == 0
            ? _newSupply
            : (
                gardenPower.avgGardenBalance.mul(block.timestamp.sub(IGarden(_garden).gardenInitializedAt())).add(
                    _newSupply
                )
            )
                .div(block.timestamp.sub(IGarden(_garden).gardenInitializedAt()));

        gardenPower.lastDepositAt = block.timestamp;

        if (_newSupply == 0) {
            // reset Garden power if all funds are removed
            gardenPower.lastDepositAt = 0;
            gardenPower.avgGardenBalance = 0;
            gardenPower.accGardenPower = 0;
        }
    }

    /**
     * Update the contributor power whenever there is a deposit or withdraw
     * @param _garden           Address of the garden
     * @param _contributor      Address of the contributor
     * @param _previousBalance  Previous balance the user had before minting or burning new tokens
     */

    function _updateContributorPower(
        address _garden,
        address _contributor,
        uint256 _previousBalance,
        uint256 _newBalance
    ) internal {
        ContributorPerGarden storage contributor = contributorPerGarden[_garden][_contributor];
        // We select timestamp [0] to persist the contributor power data as we deprecated checkpoints
        TimestampContribution storage contributorDetail = contributor.tsContributions[0];
        // The very first deposit takes 0 of power
        // Power is updated by usign previous balance (before the new mint or burn which is
        // just done as part of this deposit/withdraw op)
        // Its power is proportional to the time passed by the previous supply during that time
        contributorDetail.power = contributor.lastDepositAt == 0
            ? 0
            : contributorDetail.power.add((block.timestamp.sub(contributor.lastDepositAt)).mul(_previousBalance));
        // The following call should always go after minting new tokens
        // The reason is that we need an updated user balance to update avg contributor balance
        // The new balance of the user takes care of the sharePrice so we use garden tokens count for power
        contributorDetail.avgBalance = contributor.lastDepositAt == 0
            ? _newBalance
            : (contributorDetail.avgBalance.mul(block.timestamp.sub(contributor.initialDepositAt)).add(_newBalance))
                .div(block.timestamp.sub(contributor.initialDepositAt));
        // Initial Deposit
        if (_previousBalance == 0 || contributor.initialDepositAt == 0) {
            contributor.initialDepositAt = block.timestamp;
        }
        contributor.lastDepositAt = block.timestamp;

        // Check for withdrawals of full capital
        if (_newBalance == 0) {
            contributor.lastDepositAt = 0;
            contributor.initialDepositAt = 0;
            contributorDetail.avgBalance = 0;
            contributorDetail.power = 0;
            delete contributor.timeListPointer; // Backward compatible
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
                strPpt.preallocated = strPpt.preallocated.sub(_capital);
            }
            return strPpt.pricePerTokenUnit;
        }
    }

    /**
     * PRIVILEGE FUNCTION to migrate beta gardens into the new optimized gas data structure without checkpoints
     * @dev Can be called by anyone, should be called once for each garden and can be removed after
     * all beta gardens data are migrated
     * @param _gardens     Array of protocol gardens to perform beta data migration
     */
    function _migrateBetaGardens(address[] memory _gardens) internal {
        for (uint256 i = 0; i < _gardens.length; i++) {
            _require(IBabController(controller).isGarden(_gardens[i]), Errors.ONLY_ACTIVE_GARDEN);
            GardenPowerByTimestamp storage gardenPower = gardenPowerByTimestamp[_gardens[i]][0];
            // Check if still migration is pending and it is a beta garden
            if (!betaGardenMigrated[_gardens[i]] && gardenPower.avgGardenBalance == 0) {
                (
                    gardenPower.lastDepositAt,
                    gardenPower.accGardenPower,
                    gardenPower.avgGardenBalance,

                ) = _getGardenBetaMigrationData(_gardens[i]);
                // Special case of abandoned garden without any funds, need reset
                if (ERC20(_gardens[i]).totalSupply() == 0) {
                    // reset Garden power if all funds are removed
                    gardenPower.lastDepositAt = 0;
                    gardenPower.avgGardenBalance = 0;
                    gardenPower.accGardenPower = 0;
                }
                // We set the flag of migration complete to true to avoid new updates that might corrupt data
                betaGardenMigrated[_gardens[i]] = true;
            }
        }
    }

    /**
     * PRIVILEGE FUNCTION to migrate beta users of each garden into the new optimized gas data structure
     * without checkpoints
     * @dev Can be called by anyone, should be called AFTER migrating gardens once for each user and
     * can be removed after all beta garden users data of all gardens are migrated
     * @param _garden       Address of a protocol beta garden whose contributors belong to
     * @param _contributors Array of beta contributor addresses to migrate data
     */
    function _migrateBetaUsers(address _garden, address[] memory _contributors) internal {
        _require(IBabController(controller).isGarden(_garden), Errors.ONLY_ACTIVE_GARDEN);
        if (!betaGardenMigrated[_garden] && gardenPowerByTimestamp[_garden][0].avgGardenBalance == 0) {
            // we need to update the garden first if still not migrated
            address[] memory gardens = new address[](1);
            gardens[0] = _garden;
            _migrateBetaGardens(gardens);
        }
        // Then we migrate users, one by one
        for (uint256 i = 0; i < _contributors.length; i++) {
            ContributorPerGarden storage contributor = contributorPerGarden[_garden][_contributors[i]];
            // We select timestamp [0] to persist the contributor power data as we deprecated checkpoints
            TimestampContribution storage contributorDetail = contributor.tsContributions[0];
            // Check if still migration is pending and it is a beta contributor
            // We consider those who were part of the beta but removed all their funds
            if (
                !betaUserMigrated[_garden][_contributors[i]] &&
                contributorDetail.avgBalance == 0 &&
                (contributor.lastDepositAt > 0 || contributor.pid > 0)
            ) {
                // It is a beta user that need data migration
                (
                    contributor.lastDepositAt,
                    contributorDetail.power,
                    contributorDetail.avgBalance,

                ) = _getContributorBetaMigrationData(_garden, _contributors[i]);
                // Beta user data already migrated
                betaUserMigrated[_garden][_contributors[i]] = true;
            }
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
        if (!isProtocolPerQuarter[data[1].sub(1)]) {
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
            isProtocolPerQuarter[data[1].sub(1)] = true;
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
     */
    function _safeBABLTransfer(address _to, uint96 _amount) private {
        uint256 bablBal = babltoken.balanceOf(address(this));
        if (_amount > bablBal) {
            SafeERC20.safeTransfer(babltoken, _to, bablBal);
        } else {
            SafeERC20.safeTransfer(babltoken, _to, _amount);
        }
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
            _strategistShare != PROFIT_STRATEGIST_SHARE ||
            _stewardsShare != PROFIT_STEWARD_SHARE ||
            _lpShare != PROFIT_LP_SHARE
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
        uint256[] memory rewards = new uint256[](7);

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
        // profitData array mapping:
        // profitData[0]: profit
        // profitData[1]: distance

        // Positive strategies not yet claimed
        if (strategyDetails[1] > _claimedAt && strategyDetails[0] >= _initialDepositAt) {
            // In case of profits, the distribution of profits might substract the protocol fee beforehand:
            strategyDetails[10] = profitData[0] == true
                ? strategyDetails[10].sub(strategyDetails[10].multiplyDecimal(PROFIT_PROTOCOL_FEE))
                : 0;
            // Get the contributor power until the the strategy exit timestamp
            uint256 contributorPower = getContributorPower(_garden, _contributor, strategyDetails[1]);
            // Get strategist BABL rewards in case the contributor is also the strategist of the strategy
            rewards[0] = strategist == _contributor ? _getStrategyStrategistBabl(strategyDetails, profitData) : 0;
            // Get strategist profit rewards if profits
            rewards[1] = (strategist == _contributor && profitData[0] == true)
                ? _getStrategyStrategistProfits(_garden, strategyDetails[10])
                : 0;
            // Get steward rewards
            rewards[2] = _getStrategyStewardBabl(_strategy, _contributor, strategyDetails, profitData);
            // If not profits _getStrategyStewardsProfits should not execute
            rewards[3] = profitData[0] == true
                ? _getStrategyStewardProfits(_garden, _strategy, _contributor, strategyDetails, profitData)
                : 0;
            // Get LP rewards
            rewards[4] = _getStrategyLPBabl(strategyDetails[9], contributorPower);
            // Creator bonus (if any)
            rewards[5] = _getCreatorBonus(_garden, _contributor, rewards[0].add(rewards[2]).add(rewards[4]));
            rewards[6] = rewards[1].add(rewards[3]);
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
            babl = _strategyDetails[9].multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
                uint256(userVotes).preciseDiv(_strategyDetails[4])
            );
        } else if (userVotes > 0 && _profitData[0] == true && _profitData[1] == false) {
            // Voting in favor positive profits but below expected return
            babl = _strategyDetails[9].multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
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
            babl = _strategyDetails[9].multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
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
    ) private view returns (uint256) {
        // Assumptions:
        // Assumption that the strategy got profits. Should not execute otherwise.
        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        int256 userVotes = IStrategy(_strategy).getUserVotes(_contributor);
        uint256 totalVotes = _strategyDetails[4].add(_strategyDetails[5]);

        uint256 profitShare =
            gardenCustomProfitSharing[_garden] ? gardenProfitSharing[_garden][1] : PROFIT_STEWARD_SHARE;
        if (userVotes > 0) {
            // If the strategy got profits equal or above expected return only positive votes counts,
            // so we divide by only positive
            // Otherwise, we divide by all total votes as also voters against will get some profits
            // if the strategy returned less than expected
            uint256 accountingVotes = _profitData[1] ? _strategyDetails[4] : totalVotes;
            return
                _strategyDetails[11].multiplyDecimal(profitShare).preciseMul(uint256(userVotes)).preciseDiv(
                    accountingVotes
                );
        } else if ((userVotes < 0) && _profitData[1] == false) {
            return
                _strategyDetails[11].multiplyDecimal(profitShare).preciseMul(uint256(Math.abs(userVotes))).preciseDiv(
                    totalVotes
                );
        } else if ((userVotes < 0) && _profitData[1] == true) {
            // Voted against a very profit strategy above expected returns, get no profit at all
            return 0;
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
        babl = _strategyDetails[9].multiplyDecimal(BABL_STRATEGIST_SHARE); // Standard calculation to be ponderated
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
            gardenCustomProfitSharing[_garden] ? gardenProfitSharing[_garden][0] : PROFIT_STRATEGIST_SHARE;
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
        babl = _strategyRewards.multiplyDecimal(BABL_LP_SHARE).preciseMul(_contributorPower);
        return babl;
    }

    function _getGardenAndContributor(address _garden, address _contributor) private view returns (uint256[] memory) {
        uint256[] memory powerData = new uint256[](9);
        ContributorPerGarden storage contributor = contributorPerGarden[_garden][_contributor];
        // We take care if a beta user is already migrated or not to the new optimized-gas architecture
        GardenPowerByTimestamp storage garden =
            (!betaGardenMigrated[_garden] && gardenPid[_garden] > 0)
                ? gardenPowerByTimestamp[_garden][gardenTimelist[_garden][gardenPid[_garden].sub(1)]]
                : gardenPowerByTimestamp[_garden][0];

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
        bool stillBetaUser =
            (!betaUserMigrated[_garden][_contributor] && contributor.pid > 0 && contributor.initialDepositAt > 0);

        powerData[3] = stillBetaUser
            ? contributor.tsContributions[contributor.timeListPointer[contributor.pid.sub(1)]].power
            : contributor.tsContributions[0].power;
        powerData[4] = stillBetaUser
            ? contributor.tsContributions[contributor.timeListPointer[contributor.pid.sub(1)]].avgBalance
            : contributor.tsContributions[0].avgBalance;

        powerData[5] = garden.lastDepositAt;
        powerData[6] = garden.accGardenPower;
        powerData[7] = garden.avgGardenBalance;
        powerData[8] = ERC20(_garden).totalSupply();
        return powerData;
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
            // If there is no creator divide the 15% bonus across al members
            return
                _contributorBABL.add(
                    _contributorBABL.multiplyDecimal(CREATOR_BONUS).div(IGarden(_garden).totalContributors())
                );
        } else {
            if (isCreator) {
                // Check other creators and divide by number of creators or members if creator address is 0
                return _contributorBABL.add(_contributorBABL.multiplyDecimal(CREATOR_BONUS).div(creatorCount));
            }
        }
        return _contributorBABL;
    }

    /**
     * Get the garden details of a beta Garden that needs migration into the new optimized-gas structure
     * without checkpoints
     * @dev Once all the beta gardens data are migrated, it will not longer need to execute this code again
     * This code is needed until all beta gardens are migrated into the new optimized-gas structure
     * @param _garden           Address of the beta garden
     * @return all data needed for the migration
     */
    function _getGardenBetaMigrationData(address _garden)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool
        )
    {
        if (gardenPid[_garden] > 0) {
            return (
                betaGardenMigrated[_garden]
                    ? gardenPowerByTimestamp[_garden][0].lastDepositAt
                    : gardenTimelist[_garden][gardenPid[_garden].sub(1)],
                _getGardenBetaPower(_garden),
                _getGardenBetaAvgBalance(_garden),
                betaGardenMigrated[_garden]
            );
        } else {
            return (0, 0, 0, false);
        }
    }

    /**
     * Get the beta contributor details of a beta Garden that needs migration into the new optimized-gas
     * structure without checkpoints
     * @dev Once all the beta contributors of all beta gardens data are migrated, it will not longer need
     * to execute this code again
     * This code is needed until all beta users are migrated into the new optimized-gas structure
     * @param _garden           Address of the beta garden
     * @param _contributor      Address of the beta contributor
     * @return all data needed for the migration
     */
    function _getContributorBetaMigrationData(address _garden, address _contributor)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool
        )
    {
        if (gardenPid[_garden] > 0) {
            return (
                contributorPerGarden[_garden][_contributor].lastDepositAt,
                _getContributorBetaPower(_garden, _contributor),
                _getContributorBetaAvgBalance(_garden, _contributor),
                betaUserMigrated[_garden][_contributor]
            );
        } else {
            return (0, 0, 0, false);
        }
    }

    /**
     * Get the garden power for a beta garden to migrate its power into the new gas-optimized
     * gardenpower structure without checkpoints
     * @dev Once the beta garden data is migrated, it will not longer need to execute this code again
     * This code is needed until all beta gardens are migrated into the new optimized-gas structure
     * @param _garden           Address of the beta garden
     * @return the last power measured in the last checkpoint of a garden
     */
    function _getGardenBetaPower(address _garden) internal view returns (uint256) {
        // Only beta gardens have used gardenPid
        if (gardenPid[_garden] > 0) {
            // Assumes that the garden is a beta garden with checkpoints
            GardenPowerByTimestamp storage garden =
                gardenPowerByTimestamp[_garden][gardenTimelist[_garden][gardenPid[_garden].sub(1)]];
            return garden.accGardenPower;
        } else {
            return 0;
        }
    }

    /**
     * Calculate the garden average balance (totalSupply vs. time) for a beta garden as it is needed
     *  for the new gas-optimized gardenpower structure without checkpoints
     * @dev Once the beta garden data is migrated, it will not longer need to execute this code again
     * This code is needed until all beta gardens are migrated into the new optimized-gas structure
     * @param _garden           Address of the beta garden
     * @return the real average balance of a beta garden until its last checkpoint
     */
    function _getGardenBetaAvgBalance(address _garden) internal view returns (uint256) {
        uint256 avgBalance;
        // Only beta gardens have used gardenPid
        for (uint256 i = 0; i < gardenPid[_garden]; i++) {
            GardenPowerByTimestamp storage garden = gardenPowerByTimestamp[_garden][gardenTimelist[_garden][i]];
            uint256 timeDiff = i > 0 ? gardenTimelist[_garden][i].sub(gardenTimelist[_garden][0]) : 0;

            avgBalance = i == 0
                ? garden.avgGardenBalance
                : (avgBalance.mul(timeDiff)).add(garden.avgGardenBalance).div(timeDiff);
        }
        return avgBalance;
    }

    /**
     * Calculate the contributor power for a beta user by using previous checkpoints as it is
     * needed for the new gas-optimized contributorpower structure without checkpoints
     * The usage of the result will be used to migrate the user, which actually happens only once
     * @dev Once the user data is migrated, it will not longer need to execute this code again
     * This code is needed until all beta users are migrated into the new optimized-gas structure
     * @param _garden             Address of the beta garden
     * @param _contributor        Address of the beta contributor
     * @return the last power measured in the last checkpoint of a beta contributor
     */
    function _getContributorBetaPower(address _garden, address _contributor) internal view returns (uint256) {
        ContributorPerGarden storage contributor = contributorPerGarden[_garden][_contributor];
        // Only beta users have used pid but we also take care of those who removed all their funds
        TimestampContribution storage contributorLastCheckpoint =
            (contributor.pid == 0 || contributor.initialDepositAt == 0)
                ? contributor.tsContributions[contributor.initialDepositAt]
                : contributor.tsContributions[contributor.timeListPointer[contributor.pid.sub(1)]];
        return contributorLastCheckpoint.power;
    }

    /**
     * Calculate the contributor average balance (supply vs. time) for a beta user by using
     * previous checkpoints as it is needed for the new gas-optimized contributorpower structure without checkpoints
     * The usage of the result will be used to migrate the user, which actually happens only once
     * @dev Once the user data is migrated, it will not longer need to execute this code again
     * This code is needed until all beta users are migrated into the new optimized-gas structure
     * @param _garden             Address of the beta garden
     * @param _contributor        Address of the beta contributor
     * @return the real average balance of a beta user until its last checkpoint
     */
    function _getContributorBetaAvgBalance(address _garden, address _contributor) internal view returns (uint256) {
        uint256 avgBalance;
        ContributorPerGarden storage contributor = contributorPerGarden[_garden][_contributor];
        if (contributor.initialDepositAt == 0) {
            // If a beta user has left the garden
            return 0;
        } else {
            // Only beta users have used pid
            for (uint256 i = 0; i < contributor.pid; i++) {
                TimestampContribution storage contributorCheckpoint =
                    contributor.tsContributions[contributor.timeListPointer[i]];
                uint256 timeDiff = contributor.timeListPointer[i].sub(contributor.initialDepositAt);

                avgBalance = i == 0
                    ? contributorCheckpoint.avgBalance
                    : avgBalance.mul(timeDiff).add(contributorCheckpoint.avgBalance).div(timeDiff);
            }
            return avgBalance;
        }
    }
}

contract RewardsDistributorV5 is RewardsDistributor {}
