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
import 'hardhat/console.sol';
import {TimeLockedToken} from './TimeLockedToken.sol';

import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';
import {Safe3296} from '../lib/Safe3296.sol';
import {Errors, _require} from '../lib/BabylonErrors.sol';

import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {TimeLockedToken} from './TimeLockedToken.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';

/**
 * @title Rewards Distributor implementing the BABL Mining Program and other Rewards to Strategists and Stewards
 * @author Babylon Finance
 * Rewards Distributor contract is a smart contract used to calculate and distribute all the BABL rewards of the BABL Mining Program
 * along the time reserved for executed strategies. It implements a supply curve to distribute 500K BABL along the time.
 * The supply curve is designed to optimize the long-term sustainability of the protocol.
 * The rewards are front-loaded but they last for more than 10 years, slowly decreasing quarter by quarter.
 * For that, it houses the state of the protocol power along the time as each strategy power is compared to the whole protocol usage.
 * Rewards Distributor also is responsible for the calculation and delivery of other rewards as bonuses to specific profiles
 * which are actively contributing to the protocol growth and their communities (Garden creators, Strategists and Stewards).
 */
contract RewardsDistributor is OwnableUpgradeable, IRewardsDistributor {
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
    /**
     * Throws if the call is not from a valid strategy
     */
    modifier onlyStrategy {
        _require(controller.isSystemContract(address(IStrategy(msg.sender).garden())), Errors.ONLY_STRATEGY);
        _;
    }
    /**
     * Throws if the call is not from a valid active garden
     */
    modifier onlyActiveGarden(address _garden, uint256 _pid) {
        if (_pid != 0 || gardenPid[address(_garden)] > 1) {
            // Enable deploying flow with security restrictions
            _require(IBabController(controller).isSystemContract(address(_garden)), Errors.NOT_A_SYSTEM_CONTRACT);
            _require(IBabController(controller).isGarden(address(_garden)), Errors.ONLY_ACTIVE_GARDEN);
        }
        _require(msg.sender == address(_garden), Errors.ONLY_ACTIVE_GARDEN);
        _require(IGarden(_garden).active(), Errors.ONLY_ACTIVE_GARDEN);
        _;
    }

    /**
     * Throws if the BABL Rewards mining program is not active
     */
    modifier onlyMiningActive() {
        _require(IBabController(controller).bablMiningProgramEnabled(), Errors.ONLY_MINING_ACTIVE);
        _;
    }
    /**
     * Throws if the sender is not the controller
     */
    modifier onlyController() {
        _require(IBabController(controller).isSystemContract(msg.sender), Errors.NOT_A_SYSTEM_CONTRACT);
        _require(address(controller) == msg.sender, Errors.ONLY_CONTROLLER);
        _;
    }

    /* ============ Constants ============ */
    // 500K BABL allocated to this BABL Mining Program, the first quarter is Q1_REWARDS
    // and the following quarters will follow the supply curve using a decay rate
    uint256 public override Q1_REWARDS; // First quarter (epoch) BABL rewards
    // 12% quarterly decay rate (each 90 days)
    // (Rewards on Q1 = 1,12 * Rewards on Q2) being Q1= Quarter 1, Q2 = Quarter 2
    uint256 public override DECAY_RATE;
    // Duration of its EPOCH in days  // BABL & profits split from the protocol
    uint256 public override EPOCH_DURATION;

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

    /* ============ Structs ============ */

    struct ProtocolPerTimestamp {
        // Protocol allocation checkpoints per timestamp along the time
        uint256 principal; // Protocol principal allocation in normalized asset (DAI)
        uint256 time; // Time of the checkpoint
        uint256 quarterBelonging; // # Quarter checkpoint belonging since START_TIME
        uint256 timeListPointer; // Pointer to the array of timestamps to enable the possibility of struct iteration
        uint256 power; // Protocol power checkpoint (power is proportional to = principal * duration)
    }

    struct ProtocolPerQuarter {
        // Protocol allocation checkpoints per timestamp per each quarter along the time
        uint256 quarterPrincipal; // Checkpoint to keep track on accumulated protocol principal per quarter in normalized asset (DAI)
        uint256 quarterNumber; // # Quarter since START_TIME
        uint256 quarterPower; //  Accumulated Protocol power for each quarter
        uint96 supplyPerQuarter; // Supply per quarter
    }

    struct GardenPowerByTimestamp {
        // Garden allocation checkpoints per timestamp per each garden
        uint256 supply; // Checkpoint to keep track on garden supply
        uint256 timestamp; // Checkpoint timestamps
        uint256 power; // Garden power checkpoint (power is proportional to = principal * duration)
    }
    struct ContributorPerGarden {
        // Checkpoints to keep track on the evolution of each contributor vs. each garden
        uint256 lastDepositAt; // Last deposit timestamp of each contributor in each garden
        uint256 initialDepositAt; // Checkpoint of the initial deposit
        uint256[] timeListPointer; // Array of timestamps for each user in each garden
        uint256 pid; // Garden contributor checkpoints counter to enable iteration
        mapping(uint256 => TimestampContribution) tsContributions; // Sub-mapping all the contributor checkpoints
    }

    struct TimestampContribution {
        // Sub-mapping with all checkpoints for deposits and withdrawals of garden users
        uint256 supply; // Garden token balance of user in each garden along the time
        uint256 timestamp; // Checkpoint time
        uint256 timePointer; // Pointer
        uint256 power; // Contributor power per checkpoint
    }
    struct Checkpoints {
        // Checkpoints for contributor power calculations where a certain window (from -> to) is queried
        uint256 fromDepositAt; // First contributor checkpoint within the provided window
        uint256 lastDepositAt; // Last contributor checkpoint within the provided window
        uint256 gardenFromDepositAt; // First contributor checkpoint within the provided window
        uint256 gardenLastDepositAt; // Last garden checkpoint within the provided window
    }

    /* ============ State Variables ============ */

    // Instance of the Controller contract
    IBabController public controller;

    // BABL Token contract
    TimeLockedToken public babltoken;

    // Protocol total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all strategy pools.
    uint256 public override protocolPrincipal;
    mapping(uint256 => ProtocolPerTimestamp) public protocolPerTimestamp; // Mapping of all protocol checkpoints
    uint256[] public timeList; // Array of all protocol checkpoints
    uint256 public override pid; // Initialization of the ID assigning timeListPointer to the checkpoint number

    mapping(uint256 => ProtocolPerQuarter) public protocolPerQuarter; // Mapping of the accumulated protocol per each active quarter
    mapping(uint256 => bool) public isProtocolPerQuarter; // Check if the protocol per quarter data has been initialized

    // Strategy overhead control. Only used if each strategy has power overhead due to changes overtime
    mapping(address => mapping(uint256 => uint256)) public rewardsPowerOverhead; // Overhead control to enable high level accuracy calculations for strategy rewards
    // Contributor power control
    mapping(address => mapping(address => ContributorPerGarden)) public contributorPerGarden; // Enable high level accuracy calculations
    mapping(address => mapping(address => Checkpoints)) private checkpoints;
    // Garden power control
    mapping(address => mapping(uint256 => GardenPowerByTimestamp)) public gardenPowerByTimestamp;
    mapping(address => uint256[]) public gardenTimelist;
    mapping(address => uint256) public gardenPid;

    /* ============ Constructor ============ */

    function initialize(TimeLockedToken _bablToken, IBabController _controller) public {
        OwnableUpgradeable.__Ownable_init();

        require(address(_bablToken) != address(0), 'Token needs to exist');
        require(address(_controller) != address(0), 'Controller needs to exist');
        babltoken = _bablToken;
        controller = _controller;

        DECAY_RATE = 12e16;
        EPOCH_DURATION = 90 days;
        Q1_REWARDS = 53_571_428_571_428_600e6; // First quarter (epoch) BABL rewards
        (BABL_STRATEGIST_SHARE, BABL_STEWARD_SHARE, BABL_LP_SHARE, CREATOR_BONUS) = controller.getBABLSharing();
        (PROFIT_STRATEGIST_SHARE, PROFIT_STEWARD_SHARE, PROFIT_LP_SHARE) = controller.getProfitSharing();
        PROFIT_PROTOCOL_FEE = controller.protocolPerformanceFee();
    }

    /* ============ External Functions ============ */

    /**
     * Function that adds the capital received to the total principal of the protocol per timestamp
     * @param _capital                Amount of capital in any type of asset to be normalized into DAI
     */
    function addProtocolPrincipal(uint256 _capital) external override onlyStrategy onlyMiningActive {
        IStrategy strategy = IStrategy(msg.sender);
        if (strategy.enteredAt() >= START_TIME) {
            // onlyMiningActive control, it does not create a checkpoint if the strategy is not part of the Mining Program
            _updateProtocolPrincipal(address(strategy), _capital, true);
        }
    }

    /**
     * Function that removes the capital received to the total principal of the protocol per timestamp
     * @param _capital                Amount of capital in any type of asset to be normalized into DAI
     */
    function substractProtocolPrincipal(uint256 _capital) external override onlyStrategy onlyMiningActive {
        IStrategy strategy = IStrategy(msg.sender);
        if (strategy.enteredAt() >= START_TIME) {
            // onlyMiningActive control, it does not create a checkpoint if the strategy is not part of the Mining Program
            _updateProtocolPrincipal(address(strategy), _capital, false);
        }
    }

    /**
     * Gets the total amount of rewards for a given strategy
     * @param _strategy                Strategy to check
     */
    function getStrategyRewards(address _strategy) external view override returns (uint96) {
        IStrategy strategy = IStrategy(_strategy);
        _require(strategy.exitedAt() != 0, Errors.STRATEGY_IS_NOT_OVER_YET);
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        uint256 pricePerTokenUnit = oracle.getPrice(IGarden(strategy.garden()).reserveAsset(), DAI);
        uint256 allocated = strategy.capitalAllocated().preciseMul(pricePerTokenUnit);
        uint256 returned = strategy.capitalReturned().preciseMul(pricePerTokenUnit);
        if ((strategy.enteredAt() >= START_TIME) && (START_TIME != 0)) {
            // We avoid gas consuming once a strategy got its BABL rewards during its finalization
            uint256 rewards = strategy.strategyRewards();
            if (rewards != 0) {
                return Safe3296.safe96(rewards, 'overflow 96 bits');
            }
            // If the calculation was not done earlier we go for it
            (uint256 numQuarters, uint256 startingQuarter) =
                _getRewardsWindow(strategy.executedAt(), strategy.exitedAt());
            uint256 bablRewards = 0;
            if (numQuarters <= 1) {
                bablRewards = _getStrategyRewardsOneQuarter(_strategy, allocated, startingQuarter); // Proportional supply till that moment within the same epoch
                _require(
                    bablRewards <= protocolPerQuarter[startingQuarter].supplyPerQuarter,
                    Errors.OVERFLOW_IN_SUPPLY
                );
                _require(
                    allocated.mul(strategy.exitedAt().sub(strategy.executedAt())).sub(
                        strategy.rewardsTotalOverhead()
                    ) <= protocolPerQuarter[startingQuarter].quarterPower,
                    Errors.OVERFLOW_IN_POWER
                );
            } else {
                bablRewards = _getStrategyRewardsSomeQuarters(_strategy, allocated, startingQuarter, numQuarters);
            }

            // Babl rewards will be proportional to the total return (profit) with a max cap of x2
            uint256 percentageMul = returned.preciseDiv(allocated);
            if (percentageMul > 2e18) percentageMul = 2e18;
            bablRewards = bablRewards.preciseMul(percentageMul);
            return Safe3296.safe96(bablRewards, 'overflow 96 bits');
        } else {
            return 0;
        }
    }

    /**
     * Sends BABL tokens rewards to a contributor after a claim is requested to the protocol.
     * @param _to                Address to send the tokens to
     * @param _amount            Amount of tokens to send the address to
     */
    function sendTokensToContributor(address _to, uint256 _amount) external override onlyMiningActive {
        _require(controller.isSystemContract(msg.sender), Errors.NOT_A_SYSTEM_CONTRACT);
        uint96 amount = Safe3296.safe96(_amount, 'overflow 96 bits');
        _safeBABLTransfer(_to, amount);
    }

    /**
     * Starts BABL Rewards Mining Program from the controller.
     */
    function startBABLRewards() external onlyController {
        if (START_TIME == 0) {
            // It can only be activated once to avoid overriding START_TIME
            START_TIME = block.timestamp;
        }
    }

    /**
     * Function that set each contributor timestamp per garden
     * @param _garden                Address of the garden the contributor belongs to
     * @param _contributor           Address of the contributor
     * @param _previousBalance       Previous balance of the contributor
     * @param _depositOrWithdraw     If the timestamp is a deposit (true) or a withdraw (false)
     * @param _pid                   The pid # of the Garden timestamps
     */
    function updateGardenPowerAndContributor(
        address _garden,
        address _contributor,
        uint256 _previousBalance,
        bool _depositOrWithdraw,
        uint256 _pid
    ) external override onlyActiveGarden(_garden, _pid) {
        _updateGardenPower(_garden);
        _setContributorTimestampParams(_garden, _contributor, _previousBalance, _depositOrWithdraw);
    }

    /* ========== View functions ========== */

    /**
     * Calculates the profits and BABL that a contributor should receive from a series of finalized strategies
     * @param _garden                   Garden to which the strategies and the user must belong to
     * @param _contributor              Address of the contributor to check
     * @param _finalizedStrategies      List of addresses of the finalized strategies to check
     * @return Array of size 7 with the following distribution:
     * rewards[0]: Strategist BABL , rewards[1]: Strategist Profit, rewards[2]: Steward BABL, rewards[3]: Steward Profit, rewards[4]: LP BABL, rewards[5]: total BABL, rewards[6]: total Profits
     */
    function getRewards(
        address _garden,
        address _contributor,
        address[] calldata _finalizedStrategies
    ) external view override returns (uint256[] memory) {
        uint256[] memory totalRewards = new uint256[](7);
        _require(IBabController(controller).isGarden(address(_garden)), Errors.ONLY_ACTIVE_GARDEN);
        for (uint256 i = 0; i < _finalizedStrategies.length; i++) {
            uint256[] memory tempRewards = new uint256[](7);
            tempRewards = _getStrategyProfitsAndBABL(_garden, _finalizedStrategies[i], _contributor);
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
     * Gets the contributor power from one timestamp to the other
     * @param _garden      Address of the garden where the contributor belongs to
     * @param _contributor Address if the contributor
     * @param _from        Initial timestamp
     * @param _to          End timestamp
     * @return uint256     Contributor power during that period
     */
    function getContributorPower(
        address _garden,
        address _contributor,
        uint256 _from,
        uint256 _to
    ) external view override returns (uint256) {
        return _getContributorPower(_garden, _contributor, _from, _to);
    }

    /**
     * Calculates the BABL rewards supply for each quarter
     * @param _quarter      Number of the epoch (quarter)
     */
    function tokenSupplyPerQuarter(uint256 _quarter) external view override returns (uint96) {
        return _tokenSupplyPerQuarter(_quarter);
    }

    /**
     * Check the protocol state in a certain timestamp
     * @param time      Timestamp
     */
    function checkProtocol(uint256 _time)
        external
        view
        override
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

    /**
     * Check the quarter state for a specific quarter
     * @param _num     Number of quarter
     */
    function checkQuarter(uint256 _num)
        external
        view
        override
        returns (
            uint256 quarterPrincipal,
            uint256 quarterNumber,
            uint256 quarterPower,
            uint96 supplyPerQuarter
        )
    {
        return (
            protocolPerQuarter[_num].quarterPrincipal,
            protocolPerQuarter[_num].quarterNumber,
            protocolPerQuarter[_num].quarterPower,
            protocolPerQuarter[_num].supplyPerQuarter
        );
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
        IStrategy strategy = IStrategy(_strategy);
        // Normalizing into DAI
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        uint256 pricePerTokenUnit = oracle.getPrice(IGarden(strategy.garden()).reserveAsset(), DAI);
        _capital = _capital.preciseMul(pricePerTokenUnit);
        ProtocolPerTimestamp storage protocolCheckpoint = protocolPerTimestamp[block.timestamp];
        if (_addOrSubstract == false) {
            // Substract
            protocolPrincipal = protocolPrincipal.sub(_capital);
        } else {
            protocolPrincipal = protocolPrincipal.add(_capital);
        }
        protocolCheckpoint.principal = protocolPrincipal;
        protocolCheckpoint.time = block.timestamp;
        protocolCheckpoint.quarterBelonging = _getQuarter(block.timestamp);
        protocolCheckpoint.timeListPointer = pid;
        if (pid == 0) {
            // The very first strategy of all strategies in the mining program
            protocolCheckpoint.power = 0;
        } else {
            // Any other strategy different from the very first one (will have an antecesor)
            ProtocolPerTimestamp storage previousProtocolCheckpoint = protocolPerTimestamp[timeList[pid.sub(1)]];
            protocolCheckpoint.power = previousProtocolCheckpoint.power.add(
                protocolCheckpoint.time.sub(previousProtocolCheckpoint.time).mul(previousProtocolCheckpoint.principal)
            );
        }
        timeList.push(block.timestamp); // Register of added strategies timestamps in the array for iteration
        // Here we control the accumulated protocol power per each quarter
        // Create the quarter checkpoint in case the checkpoint is the first in the epoch
        _addProtocolPerQuarter(block.timestamp);
        // We update the rewards overhead if any in normalized DAI
        _updatePowerOverhead(strategy, _capital);
        pid++;
    }

    /**
     * Get the rewards for a specific contributor activately contributing in strategies of a specific garden
     * @param _garden           Garden address responsible of the strategies to calculate rewards
     * @param _strategy         Strategy address
     * @param _contributor      Contributor address
     * @return Array of size 7 with the following distribution:
     * rewards[0]: Strategist BABL , rewards[1]: Strategist Profit, rewards[2]: Steward BABL, rewards[3]: Steward Profit, rewards[4]: LP BABL, rewards[5]: total BABL, rewards[6]: total Profits
     */
    function _getStrategyProfitsAndBABL(
        address _garden,
        address _strategy,
        address _contributor
    ) private view returns (uint256[] memory) {
        IStrategy strategy = IStrategy(_strategy);
        _require(address(strategy.garden()) == _garden, Errors.STRATEGY_GARDEN_MISMATCH);
        _require(IGarden(_garden).isGardenStrategy(_strategy), Errors.STRATEGY_GARDEN_MISMATCH);
        // rewards[0]: Strategist BABL , rewards[1]: Strategist Profit, rewards[2]: Steward BABL, rewards[3]: Steward Profit, rewards[4]: LP BABL, rewards[5]: total BABL, rewards[6]: total Profits
        uint256[] memory rewards = new uint256[](7);
        uint256 contributorProfits = 0;
        uint256 contributorBABL = 0;
        // We get the state of the strategy in terms of profit and distance from expected to accurately calculate profits and rewards
        (bool profit, uint256 profitValue, bool distance, uint256 distanceValue) =
            _getStrategyRewardsContext(address(strategy));

        (, uint256 initialDepositAt, uint256 claimedAt, , , ) = IGarden(_garden).getContributor(_contributor);
        // Positive strategies not yet claimed
        if (
            strategy.exitedAt() > claimedAt &&
            strategy.executedAt() >= initialDepositAt &&
            address(strategy.garden()) == _garden
        ) {
            uint256 contributorPower =
                _getContributorPower(address(_garden), _contributor, strategy.executedAt(), strategy.exitedAt());
            // If strategy returned money we give out the profits
            if (profit == true) {
                // We reserve 5% of profits for performance fees
                profitValue = profitValue.sub(profitValue.multiplyDecimal(PROFIT_PROTOCOL_FEE));
            }
            // Get strategist rewards in case the contributor is also the strategist of the strategy
            rewards[0] = _getStrategyStrategistBabl(
                address(strategy),
                _contributor,
                profit,
                profitValue,
                distance,
                distanceValue
            );
            contributorBABL = contributorBABL.add(rewards[0]);
            rewards[1] = _getStrategyStrategistProfits(address(strategy), _contributor, profit, profitValue);
            contributorProfits = contributorProfits.add(rewards[1]);

            // Get steward rewards
            rewards[2] = _getStrategyStewardBabl(
                address(strategy),
                _contributor,
                profit,
                profitValue,
                distance,
                distanceValue
            );
            contributorBABL = contributorBABL.add(rewards[2]);
            rewards[3] = _getStrategyStewardProfits(
                address(strategy),
                _contributor,
                profit,
                profitValue,
                distance,
                distanceValue
            );
            contributorProfits = contributorProfits.add(rewards[3]);

            // Get LP rewards
            rewards[4] = uint256(strategy.strategyRewards()).multiplyDecimal(BABL_LP_SHARE).preciseMul(
                contributorPower.preciseDiv(strategy.capitalAllocated())
            );
            contributorBABL = contributorBABL.add(rewards[4]);

            // Get a multiplier bonus in case the contributor is the garden creator
            if (_contributor == IGarden(_garden).creator()) {
                contributorBABL = contributorBABL.add(contributorBABL.multiplyDecimal(CREATOR_BONUS));
            }
            rewards[5] = contributorBABL;
            rewards[6] = contributorProfits;
        }
        return rewards;
    }

    /**
     * Get the context of a specific address depending on their expected returns, capital allocated and capital returned
     * @param _strategy         Strategy address
     */
    function _getStrategyRewardsContext(address _strategy)
        private
        view
        returns (
            bool,
            uint256,
            bool,
            uint256
        )
    {
        IStrategy strategy = IStrategy(_strategy);
        uint256 returned = strategy.capitalReturned();
        uint256 expected =
            strategy.capitalAllocated().add(strategy.capitalAllocated().preciseMul(strategy.expectedReturn()));
        uint256 allocated = strategy.capitalAllocated();
        bool profit;
        bool distance;
        uint256 profitValue;
        uint256 distanceValue;
        if (returned > allocated && returned >= expected) {
            // The strategy went equal or above expectations
            profit = true; // positive
            distance = true; // positive
            profitValue = returned.sub(allocated);
            distanceValue = returned.sub(expected);
        } else if (returned >= allocated && returned < expected) {
            // The strategy went worse than expected but with some profits
            profit = true; // positive or zero profits
            distance = false; // negative vs expected return (got less than expected)
            profitValue = returned.sub(allocated);
            distanceValue = expected.sub(returned);
        } else if (returned < allocated && returned < expected) {
            // Negative profits - bad investments has penalties
            profit = false; // negative - loosing capital
            distance = false; // negative vs expected return (got less than expected)
            profitValue = allocated.sub(returned); // Negative number, there were no profits at all
            distanceValue = expected.sub(returned);
        }

        return (profit, profitValue, distance, distanceValue);
    }

    /**
     * Get the BABL rewards (Mining program) for a Steward profile
     * @param _strategy         Strategy address
     * @param _contributor      Contributor address
     * @param _profit           Whether or not the strategy had profits
     * @param _distance         If true the results were above expected returns, false means opposite
     * @param _distanceValue        The distance from/to expected returns for capital returned
     */
    function _getStrategyStewardBabl(
        address _strategy,
        address _contributor,
        bool _profit,
        uint256, /* _profitValue */
        bool _distance,
        uint256 _distanceValue
    ) private view returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        uint256 strategyRewards = strategy.strategyRewards();
        int256 userVotes = strategy.getUserVotes(_contributor);
        uint256 bablCap;
        uint256 expected =
            strategy.capitalAllocated().add(strategy.capitalAllocated().preciseMul(strategy.expectedReturn()));

        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        uint256 babl = 0;
        if (userVotes > 0 && _profit == true && _distance == true) {
            // Voting in favor of the execution of the strategy with profits and positive distance
            babl = strategyRewards.multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
                uint256(userVotes).preciseDiv(strategy.totalPositiveVotes())
            );
        } else if (userVotes > 0 && _profit == true && _distance == false) {
            // Voting in favor positive profits but below expected return
            babl = strategyRewards.multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
                uint256(userVotes).preciseDiv(strategy.totalPositiveVotes())
            );
            babl = babl.sub(babl.preciseMul(_distanceValue.preciseDiv(expected))); // We discount the error of expected return vs real returns
        } else if (userVotes > 0 && _profit == false) {
            // Voting in favor of a non profitable strategy get nothing
            babl = 0;
        } else if (userVotes < 0 && _distance == false) {
            // Voting against a strategy that got results below expected return provides rewards to the voter (helping the protocol to only have good strategies)
            babl = strategyRewards.multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
                uint256(Math.abs(userVotes)).preciseDiv(strategy.totalNegativeVotes())
            );

            bablCap = babl.mul(2); // Max cap
            babl = babl.add(babl.preciseMul(_distanceValue.preciseDiv(expected))); // We add a bonus inverse to the error of expected return vs real returns

            if (babl > bablCap) babl = bablCap; // We limit 2x by a Cap
        } else if (userVotes < 0 && _distance == true) {
            babl = 0;
        }
        return babl;
    }

    /**
     * Get the rewards for a Steward profile
     * @param _strategy         Strategy address
     * @param _contributor      Contributor address
     * @param _profit           Whether or not the strategy had profits
     * @param _profitValue      The value of profits
     * @param _distance         If true the results were above expected returns, false means opposite
     */
    function _getStrategyStewardProfits(
        address _strategy,
        address _contributor,
        bool _profit,
        uint256 _profitValue,
        bool _distance,
        uint256 /* _distanceValue */
    ) private view returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        uint256 profits = 0;
        int256 userVotes = strategy.getUserVotes(_contributor);
        if (_profit == true) {
            if (userVotes > 0) {
                profits = _profitValue.multiplyDecimal(PROFIT_STEWARD_SHARE).preciseMul(uint256(userVotes)).preciseDiv(
                    strategy.totalPositiveVotes()
                );
            } else if ((userVotes < 0) && _distance == false) {
                profits = _profitValue
                    .multiplyDecimal(PROFIT_STEWARD_SHARE)
                    .preciseMul(uint256(Math.abs(userVotes)))
                    .preciseDiv(strategy.totalNegativeVotes());
            } else if ((userVotes < 0) && _distance == true) {
                // Voted against a very profit strategy above expected returns, get no profit at all
                profits = 0;
            }
        } else profits = 0; // No profits at all

        return profits;
    }

    /**
     * Get the BABL rewards (Mining program) for a Strategist profile
     * @param _strategy         Strategy address
     * @param _contributor      Contributor address
     * @param _profit           Whether or not the strategy had profits
     * @param _distance         If true the results were above expected returns, false means opposite
     */
    function _getStrategyStrategistBabl(
        address _strategy,
        address _contributor,
        bool _profit,
        uint256, /* _profitValue */
        bool _distance,
        uint256 /* _distanceValue */
    ) private view returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        uint256 strategyRewards = strategy.strategyRewards();
        uint256 babl;
        uint256 bablCap;
        uint256 expected =
            strategy.capitalAllocated().add(strategy.capitalAllocated().preciseMul(strategy.expectedReturn()));
        if (strategy.strategist() == _contributor) {
            babl = strategyRewards.multiplyDecimal(BABL_STRATEGIST_SHARE); // Standard calculation to be ponderated
            if (_profit == true && _distance == true) {
                // Strategy with equal or higher profits than expected
                bablCap = babl.mul(2); // Max cap
                // The more the results are close to the expected the more bonus will get (limited by a x2 cap)
                babl = babl.add(babl.preciseMul(expected.preciseDiv(strategy.capitalReturned())));
                if (babl > bablCap) babl = bablCap; // We limit 2x by a Cap
            } else if (_profit == true && _distance == false) {
                //under expectations
                // The more the results are close to the expected the less penalization it might have
                babl = babl.sub(babl.sub(babl.preciseMul(strategy.capitalReturned().preciseDiv(expected))));
            } else {
                // No positive profit
                return 0;
            }
        } else {
            return 0;
        }
        return babl;
    }

    /**
     * Get the rewards for a Strategist profile
     * @param _strategy         Strategy address
     * @param _contributor      Contributor address
     * @param _profit           Whether or not the strategy had profits
     * @param _profitValue      The value of profits
     */
    function _getStrategyStrategistProfits(
        address _strategy,
        address _contributor,
        bool _profit,
        uint256 _profitValue
    ) private view returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        uint256 profits;
        if (_profit == true) {
            if (strategy.strategist() == _contributor) {
                // If the contributor was the strategist of the strategy
                profits = _profitValue.multiplyDecimal(PROFIT_STRATEGIST_SHARE);
            }
        } else profits = 0; // No profits at all

        return profits;
    }

    /**
     * Add protocol power timestamps for each quarter
     * @param _time         Timestamp
     */
    function _addProtocolPerQuarter(uint256 _time) private onlyMiningActive {
        uint256 quarter = _getQuarter(_time);
        ProtocolPerQuarter storage protocolCheckpoint = protocolPerQuarter[quarter];

        if (!isProtocolPerQuarter[quarter.sub(1)]) {
            // The quarter is not yet initialized then we create it
            protocolCheckpoint.quarterNumber = quarter;
            if (pid == 0) {
                // The first strategy added in the first epoch
                protocolCheckpoint.quarterPower = 0;
                protocolCheckpoint.supplyPerQuarter = _tokenSupplyPerQuarter(quarter);
            } else {
                // Each time a new epoch starts with either a new strategy execution or finalization
                // We just take the proportional power for this quarter from previous checkpoint
                uint256 powerToSplit =
                    protocolPerTimestamp[_time].power.sub(protocolPerTimestamp[timeList[pid.sub(1)]].power);
                if (protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging == quarter.sub(1)) {
                    // There were no intermediate epochs without checkpoints
                    // We re-initialize the protocol power counting for this new quarter
                    protocolCheckpoint.quarterPower = powerToSplit
                        .mul(_time.sub(START_TIME.add(quarter.mul(EPOCH_DURATION).sub(EPOCH_DURATION))))
                        .div(_time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time));
                    protocolCheckpoint.supplyPerQuarter = _tokenSupplyPerQuarter(quarter);

                    protocolPerQuarter[quarter.sub(1)].quarterPower = protocolPerQuarter[quarter.sub(1)]
                        .quarterPower
                        .add(powerToSplit.sub(protocolCheckpoint.quarterPower));
                } else {
                    // There were intermediate epochs without checkpoints - we need to create their protocolPerQuarter's and update the last one
                    // We have to update all the quarters including where the previous checkpoint is and the one were we are now
                    for (
                        uint256 i = 0;
                        i <= quarter.sub(protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging);
                        i++
                    ) {
                        ProtocolPerQuarter storage newCheckpoint =
                            protocolPerQuarter[protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging.add(i)];
                        uint256 slotEnding =
                            START_TIME.add(
                                protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging.add(i).mul(EPOCH_DURATION)
                            );
                        if (i == 0) {
                            // We are in the first quarter to update, we add the corresponding part

                            newCheckpoint.quarterPower = newCheckpoint.quarterPower.add(
                                powerToSplit.mul(slotEnding.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time)).div(
                                    _time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time)
                                )
                            );
                            newCheckpoint.quarterPrincipal = protocolPerTimestamp[timeList[pid.sub(1)]].principal;
                        } else if (i < quarter.sub(protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging)) {
                            // We are in an intermediate quarter
                            newCheckpoint.quarterPower = powerToSplit.mul(EPOCH_DURATION).div(
                                _time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time)
                            );
                            newCheckpoint.supplyPerQuarter = _tokenSupplyPerQuarter(
                                protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging.add(i)
                            );
                            newCheckpoint.quarterNumber = protocolPerTimestamp[timeList[pid.sub(1)]]
                                .quarterBelonging
                                .add(i);
                            newCheckpoint.quarterPrincipal = protocolPerTimestamp[timeList[pid.sub(1)]].principal;
                        } else {
                            // We are in the last quarter of the strategy
                            protocolCheckpoint.quarterPower = powerToSplit
                                .mul(_time.sub(START_TIME.add(quarter.mul(EPOCH_DURATION).sub(EPOCH_DURATION))))
                                .div(_time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time));
                            protocolCheckpoint.supplyPerQuarter = _tokenSupplyPerQuarter(quarter);
                            protocolCheckpoint.quarterNumber = quarter;
                            protocolCheckpoint.quarterPrincipal = protocolPrincipal;
                        }
                    }
                }
            }
            isProtocolPerQuarter[quarter.sub(1)] = true;
        } else {
            // Quarter checkpoint already created, it must have been filled with general info
            // We update the power of the quarter by adding the new difference between last quarter checkpoint and this checkpoint
            protocolCheckpoint.quarterPower = protocolCheckpoint.quarterPower.add(
                protocolPerTimestamp[_time].power.sub(protocolPerTimestamp[timeList[pid.sub(1)]].power)
            );
        }
        protocolCheckpoint.quarterPrincipal = protocolPrincipal;
    }

    /**
     * Updates the strategy power overhead for rewards calculations of each strategy out of the whole protocol
     * @param _strategy      Strategy
     * @param _capital       New capital normalized in DAI
     */
    function _updatePowerOverhead(IStrategy _strategy, uint256 _capital) private onlyMiningActive {
        if (_strategy.updatedAt() != 0) {
            // There will be overhead after the first execution not before
            if (_getQuarter(block.timestamp) == _getQuarter(_strategy.updatedAt())) {
                // The overhead will remain within the same epoch
                rewardsPowerOverhead[address(_strategy)][_getQuarter(block.timestamp)] = rewardsPowerOverhead[
                    address(_strategy)
                ][_getQuarter(block.timestamp)]
                    .add(_capital.mul(block.timestamp.sub(_strategy.updatedAt())));
            } else {
                // We need to iterate since last update of the strategy capital
                (uint256 numQuarters, uint256 startingQuarter) =
                    _getRewardsWindow(_strategy.updatedAt(), block.timestamp);
                uint256 overheadPerQuarter = _capital.mul(block.timestamp.sub(_strategy.updatedAt())).div(numQuarters);
                for (uint256 i = 0; i <= numQuarters.sub(1); i++) {
                    rewardsPowerOverhead[address(_strategy)][startingQuarter.add(i)] = rewardsPowerOverhead[
                        address(_strategy)
                    ][startingQuarter.add(i)]
                        .add(overheadPerQuarter);
                }
            }
        }
    }

    /**
     * Check the strategy rewards for strategies starting and ending in the same quarter
     * @param _strategy         Strategy
     * @param _startingQuarter  Starting quarter
     */
    function _getStrategyRewardsOneQuarter(
        address _strategy,
        uint256 _allocated,
        uint256 _startingQuarter
    ) private view onlyMiningActive returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        uint256 slotEnding = START_TIME.add(_startingQuarter.mul(EPOCH_DURATION)); // Initialization timestamp at the end of the first slot where the strategy starts its execution
        uint256 slotStarting = slotEnding.sub(EPOCH_DURATION);
        uint256 strategyOverTime =
            _allocated.mul(strategy.exitedAt().sub(strategy.executedAt())).sub(strategy.rewardsTotalOverhead());
        return
            strategyOverTime
                .preciseDiv(protocolPerQuarter[_startingQuarter].quarterPower)
                .preciseMul(uint256(protocolPerQuarter[_startingQuarter].supplyPerQuarter))
                .preciseMul(strategy.exitedAt().sub(slotStarting))
                .preciseDiv(EPOCH_DURATION);
    }

    /**
     * Check the strategy rewards for strategies starting and ending in different quarters and/or more quarters
     * @param _strategy         Strategy
     * @param _allocated        Normalized allocated in DAI
     * @param _startingQuarter  Starting quarter
     * @param _numQuarters      Num of Quarters (in epochs)
     */
    function _getStrategyRewardsSomeQuarters(
        address _strategy,
        uint256 _allocated,
        uint256 _startingQuarter,
        uint256 _numQuarters
    ) private view onlyMiningActive returns (uint256) {
        // The strategy takes longer than one quarter / epoch
        uint256 bablRewards;
        for (uint256 i = 0; i < _numQuarters; i++) {
            uint256 slotEnding = START_TIME.add(_startingQuarter.add(i).mul(EPOCH_DURATION)); // Initialization timestamp at the end of the first slot where the strategy starts its execution
            uint256 powerRatioInQuarter =
                _getStrategyRewardsPerQuarter(_strategy, _allocated, _startingQuarter, i, slotEnding);
            bablRewards = bablRewards.add(powerRatioInQuarter);
        }
        return bablRewards;
    }

    /**
     * Check the strategy rewards for a specific quarter when strategies starting and ending in different quarters and/or more quarters
     * @param _strategy         Strategy
     * @param _allocated        Normalized allocated in DAI
     * @param _startingQuarter  Starting quarter
     * @param _id               Epoch number
     * @param _slotEnding       Ending slot timestamp of current slot (epoch)
     */
    function _getStrategyRewardsPerQuarter(
        address _strategy,
        uint256 _allocated,
        uint256 _startingQuarter,
        uint256 _id,
        uint256 _slotEnding
    ) private view onlyMiningActive returns (uint256) {
        // The strategy takes longer than one quarter / epoch
        // We need to calculate the strategy vs. protocol power ratio per each quarter
        uint256 strategyPower; // Strategy power in each Epoch
        uint256 protocolPower; // Protocol power in each Epoch

        // We iterate all the quarters where the strategy was active
        uint256 percentage = 1e18;

        if (IStrategy(_strategy).executedAt().add(EPOCH_DURATION) > _slotEnding) {
            // We are in the first quarter of the strategy

            strategyPower = _allocated.mul(_slotEnding.sub(IStrategy(_strategy).executedAt())).sub(
                rewardsPowerOverhead[address(_strategy)][_getQuarter(IStrategy(_strategy).executedAt())]
            );
        } else if (
            IStrategy(_strategy).executedAt() < _slotEnding.sub(EPOCH_DURATION) &&
            _slotEnding < IStrategy(_strategy).exitedAt()
        ) {
            // We are in an intermediate quarter different from starting or ending quarters
            strategyPower = _allocated.mul(_slotEnding.sub(_slotEnding.sub(EPOCH_DURATION))).sub(
                rewardsPowerOverhead[address(_strategy)][_getQuarter(_slotEnding.sub(45 days))]
            );
        } else {
            // We are in the last quarter of the strategy

            percentage = block.timestamp.sub(_slotEnding.sub(EPOCH_DURATION)).preciseDiv(
                _slotEnding.sub(_slotEnding.sub(EPOCH_DURATION))
            );
            strategyPower = _allocated.mul(IStrategy(_strategy).exitedAt().sub(_slotEnding.sub(EPOCH_DURATION))).sub(
                rewardsPowerOverhead[address(_strategy)][_getQuarter(IStrategy(_strategy).exitedAt())]
            );
        }
        protocolPower = protocolPerQuarter[_startingQuarter.add(_id)].quarterPower;

        _require(strategyPower <= protocolPower, Errors.OVERFLOW_IN_POWER);

        return
            strategyPower
                .preciseDiv(protocolPower)
                .preciseMul(uint256(protocolPerQuarter[_startingQuarter.add(_id)].supplyPerQuarter))
                .preciseMul(percentage);
    }

    /**
     * Safe BABL rewards (Mining program) token transfer.
     * It handle cases when in case of rounding errors, RewardsDistributor might not have enough BABL.
     * @param _to               The receiver address of the contributor to send
     * @param _amount           The amount of BABL tokens to be rewarded during this claim
     */
    function _safeBABLTransfer(address _to, uint96 _amount) private onlyMiningActive {
        uint256 bablBal = babltoken.balanceOf(address(this));
        if (_amount > bablBal) {
            SafeERC20.safeTransfer(babltoken, _to, bablBal);
        } else {
            SafeERC20.safeTransfer(babltoken, _to, _amount);
        }
    }

    /**
     * Gets the contributor power from a timestamp to a specific timestamp within a garden
     * @param _garden      Address of the garden
     * @param _contributor Address if the contributor
     * @param _from        Initial timestamp
     * @param _to          End timestamp
     * @return uint256     Contributor power during that period
     */
    function _getContributorPower(
        address _garden,
        address _contributor,
        uint256 _from,
        uint256 _to
    ) private view returns (uint256) {
        // Out of bounds
        _require(_to >= IGarden(_garden).gardenInitializedAt() && _to >= _from, Errors.CONTRIBUTOR_POWER_CHECK_WINDOW);
        ContributorPerGarden storage contributor = contributorPerGarden[address(_garden)][address(_contributor)];
        Checkpoints memory powerCheckpoints = checkpoints[address(_garden)][address(_contributor)];

        if (contributor.initialDepositAt == 0 || contributor.initialDepositAt > _to) {
            return 0;
        } else {
            if (_from <= IGarden(_garden).gardenInitializedAt()) {
                // Avoid division by zero in case of _from parameter is not passed
                _from = IGarden(_garden).gardenInitializedAt();
            }
            // Find closest point to _from and _to either contributor and garden checkpoints at their left
            (powerCheckpoints.fromDepositAt, powerCheckpoints.lastDepositAt) = _locateCheckpointsContributor(
                _garden,
                _contributor,
                _from,
                _to
            );
            (powerCheckpoints.gardenFromDepositAt, powerCheckpoints.gardenLastDepositAt) = _locateCheckpointsGarden(
                _garden,
                _from,
                _to
            );

            // origin must be less than end window
            _require(
                powerCheckpoints.fromDepositAt <= powerCheckpoints.lastDepositAt &&
                    powerCheckpoints.gardenFromDepositAt <= powerCheckpoints.gardenLastDepositAt,
                Errors.CONTRIBUTOR_POWER_CHECK_DEPOSITS
            );
            uint256 contributorPower;
            uint256 gardenPower;

            // "FROM power calculations" PART
            // Avoid underflows

            if (_from < powerCheckpoints.fromDepositAt) {
                // Contributor still has no power but _from is later than the start of the garden
                contributorPower = 0;
            } else if (_from > powerCheckpoints.fromDepositAt) {
                contributorPower = contributor.tsContributions[powerCheckpoints.fromDepositAt].power.add(
                    (_from.sub(powerCheckpoints.fromDepositAt)).mul(
                        contributor.tsContributions[powerCheckpoints.fromDepositAt].supply
                    )
                );
            } else {
                // _from == fromDepositAt
                contributorPower = contributor.tsContributions[powerCheckpoints.fromDepositAt].power;
            }
            gardenPower = gardenPowerByTimestamp[address(_garden)][powerCheckpoints.gardenFromDepositAt].power.add(
                (_from.sub(powerCheckpoints.gardenFromDepositAt)).mul(
                    gardenPowerByTimestamp[address(_garden)][powerCheckpoints.gardenFromDepositAt].supply
                )
            );
            // "TO power calculations" PART
            // We go for accurate power calculations avoiding overflows
            // contributor power overflow
            _require(contributorPower <= gardenPower, Errors.CONTRIBUTOR_POWER_OVERFLOW);
            if (_from == _to) {
                // Requested a specific checkpoint calculation (no slot)
                if (gardenPower == 0) {
                    return 0;
                } else {
                    return contributorPower.preciseDiv(gardenPower);
                }
                // Not a checkpoint anymore but a slot
            } else if (_to < powerCheckpoints.lastDepositAt) {
                // contributor has not deposited yet
                return 0;
            } else if (
                _to == powerCheckpoints.lastDepositAt &&
                powerCheckpoints.fromDepositAt == powerCheckpoints.lastDepositAt
            ) {
                // no more contributor checkpoints in the slot
                gardenPower = (
                    gardenPowerByTimestamp[address(_garden)][powerCheckpoints.gardenLastDepositAt].power.add(
                        (_to.sub(powerCheckpoints.gardenLastDepositAt)).mul(
                            gardenPowerByTimestamp[address(_garden)][powerCheckpoints.gardenLastDepositAt].supply
                        )
                    )
                )
                    .sub(gardenPower);
                _require(contributorPower <= gardenPower, Errors.CONTRIBUTOR_POWER_OVERFLOW);
                return contributorPower.preciseDiv(gardenPower);
            } else {
                contributorPower = (
                    contributor.tsContributions[powerCheckpoints.lastDepositAt].power.add(
                        (_to.sub(powerCheckpoints.lastDepositAt)).mul(
                            contributor.tsContributions[powerCheckpoints.lastDepositAt].supply
                        )
                    )
                )
                    .sub(contributorPower);

                gardenPower = (
                    gardenPowerByTimestamp[address(_garden)][powerCheckpoints.gardenLastDepositAt].power.add(
                        (_to.sub(powerCheckpoints.gardenLastDepositAt)).mul(
                            gardenPowerByTimestamp[address(_garden)][powerCheckpoints.gardenLastDepositAt].supply
                        )
                    )
                )
                    .sub(gardenPower);
                _require(contributorPower <= gardenPower, Errors.CONTRIBUTOR_POWER_OVERFLOW);

                return contributorPower.preciseDiv(gardenPower);
            }
        }
    }

    /**
     * Gets the earlier and closest (deposit/withdrawal) checkpoints of a contributor in a specific range
     * @param _garden      Address of the garden
     * @param _contributor Address if the contributor
     * @param _from        Initial timestamp
     * @param _to          End timestamp
     * @return uint256     Contributor power during that period
     */
    function _locateCheckpointsContributor(
        address _garden,
        address _contributor,
        uint256 _from,
        uint256 _to
    ) private view returns (uint256, uint256) {
        ContributorPerGarden storage contributor = contributorPerGarden[address(_garden)][address(_contributor)];

        uint256 lastDepositAt = contributor.timeListPointer[contributor.timeListPointer.length.sub(1)]; // Initialized with lastDeposit
        uint256 fromDepositAt = contributor.timeListPointer[0]; // Initialized with initialDeposit

        if (lastDepositAt > _to || fromDepositAt < _from) {
            // We go to find the closest deposits of the contributor to _from and _to
            for (uint256 i = 0; i <= contributor.timeListPointer.length.sub(1); i++) {
                if (contributor.timeListPointer[i] <= _to) {
                    lastDepositAt = contributor.timeListPointer[i];
                }
                if (contributor.timeListPointer[i] <= _from) {
                    fromDepositAt = contributor.timeListPointer[i];
                }
            }
        }
        return (fromDepositAt, lastDepositAt);
    }

    /**
     * Gets the earlier and closest (deposit/withdrawal) checkpoints of a garden in a specific range
     * @param _garden      Address of the garden
     * @param _from        Initial timestamp
     * @param _to          End timestamp
     * @return uint256     Contributor power during that period
     */
    function _locateCheckpointsGarden(
        address _garden,
        uint256 _from,
        uint256 _to
    ) private view returns (uint256, uint256) {
        uint256 gardenLastCheckpoint = gardenTimelist[address(_garden)].length.sub(1);
        uint256 gardenLastDepositAt = gardenTimelist[address(_garden)][gardenLastCheckpoint]; // Initialized to the last garden checkpoint
        uint256 gardenFromDepositAt = gardenTimelist[address(_garden)][0]; // Initialized to the first garden checkpoint

        if (gardenLastDepositAt > _to || gardenFromDepositAt < _from) {
            // We go for the closest timestamp of garden to _to and _from
            for (uint256 i = 0; i <= gardenLastCheckpoint; i++) {
                uint256 gardenTime = gardenTimelist[address(_garden)][i];
                if (gardenTime <= _to) {
                    gardenLastDepositAt = gardenTime;
                }
                if (gardenTime <= _from) {
                    gardenFromDepositAt = gardenTime;
                }
            }
        }
        return (gardenFromDepositAt, gardenLastDepositAt);
    }

    /**
     * Function that keeps checkpoints of the garden power (deposits and withdrawals) per timestamp
     * @param _garden               Garden address
     */
    function _updateGardenPower(address _garden) private {
        IGarden garden = IGarden(_garden);
        GardenPowerByTimestamp storage gardenTimestamp = gardenPowerByTimestamp[address(garden)][block.timestamp];
        gardenTimestamp.supply = IERC20(address(IGarden(_garden))).totalSupply();

        gardenTimestamp.timestamp = block.timestamp;

        if (gardenPid[address(_garden)] == 0) {
            // The very first deposit of all contributors in the mining program
            gardenTimestamp.power = 0;
        } else {
            // Any other deposit different from the very first one (will have an antecesor)
            GardenPowerByTimestamp storage previousGardenTimestamp =
                gardenPowerByTimestamp[address(garden)][
                    gardenTimelist[address(garden)][gardenPid[address(garden)].sub(1)]
                ];
            gardenTimestamp.power = previousGardenTimestamp.power.add(
                gardenTimestamp.timestamp.sub(previousGardenTimestamp.timestamp).mul(previousGardenTimestamp.supply)
            );
        }

        gardenTimelist[address(garden)].push(block.timestamp); // Register of deposit timestamps in the array for iteration
        gardenPid[address(garden)]++;
    }

    /**
     * Updates contributor timestamps params
     * @param _garden               Garden address
     * @param _contributor          Contributor address
     * @param _previousBalance      Previous balance
     * @param _depositOrWithdraw    Whether it is a deposit or a withdraw
     */
    function _setContributorTimestampParams(
        address _garden,
        address _contributor,
        uint256 _previousBalance,
        bool _depositOrWithdraw
    ) private {
        // We make checkpoints around contributor deposits to avoid fast loans and give the right rewards afterwards
        ContributorPerGarden storage contributor = contributorPerGarden[address(_garden)][_contributor];
        TimestampContribution storage contributorDetail = contributor.tsContributions[block.timestamp];
        contributorDetail.supply = IERC20(address(IGarden(_garden))).balanceOf(address(_contributor));

        contributorDetail.timestamp = block.timestamp;

        contributorDetail.timePointer = contributor.pid;

        if (contributor.pid == 0) {
            // The very first deposit
            contributorDetail.power = 0;
        } else {
            // Any other deposits or withdrawals different from the very first one (will have an antecesor)
            contributorDetail.power = contributor.tsContributions[contributor.lastDepositAt].power.add(
                (block.timestamp.sub(contributor.lastDepositAt)).mul(
                    contributor.tsContributions[contributor.lastDepositAt].supply
                )
            );
        }
        if (_depositOrWithdraw == true) {
            // Deposit
            if (_previousBalance == 0 || contributor.initialDepositAt == 0) {
                contributor.initialDepositAt = block.timestamp;
            }
            contributor.lastDepositAt = block.timestamp;
        } else {
            // Withdrawals
            if (contributorDetail.supply == 0) {
                contributor.lastDepositAt = 0;
                contributor.initialDepositAt = 0;
                delete contributor.timeListPointer;
            }
        }

        contributor.timeListPointer.push(block.timestamp);
        contributor.pid++;
    }

    /**
     * Calculates the BABL rewards supply for each quarter
     * @param _quarter      Number of the epoch (quarter)
     */
    function _tokenSupplyPerQuarter(uint256 _quarter) internal view returns (uint96) {
        _require(_quarter >= 1, Errors.QUARTERS_MIN_1);
        if (_quarter >= 513) {
            return 0;
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
        uint256 quarter = (_now.sub(START_TIME).preciseDivCeil(EPOCH_DURATION)).div(1e18);
        return quarter.add(1);
    }

    /**
     * Calculates the range (starting quarter and ending quarter since START_TIME)
     * @param _from   Starting timestamp
     * @param _to     Ending timestamp
     */
    function _getRewardsWindow(uint256 _from, uint256 _to) internal view returns (uint256, uint256) {
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
}
