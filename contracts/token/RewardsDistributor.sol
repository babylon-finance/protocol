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
 * Rewards Distributor contract is a smart contract used to calculate and distribute all the BABL rewards of the BABL Mining Program
 * along the time reserved for executed strategies. It implements a supply curve to distribute 500K BABL along the time.
 * The supply curve is designed to optimize the long-term sustainability of the protocol.
 * The rewards are front-loaded but they last for more than 10 years, slowly decreasing quarter by quarter.
 * For that, it houses the state of the protocol power along the time as each strategy power is compared to the whole protocol usage.
 * Rewards Distributor also is responsible for the calculation and delivery of other rewards as bonuses to specific profiles
 * which are actively contributing to the protocol growth and their communities (Garden creators, Strategists and Stewards).
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
    modifier onlyStrategy {
        address garden = address(IStrategy(msg.sender).garden());
        _require(controller.isSystemContract(garden), Errors.ONLY_STRATEGY);
        _require(IGarden(garden).isGardenStrategy(msg.sender), Errors.STRATEGY_GARDEN_MISMATCH);
        _;
    }
    /**
     * Throws if the call is not from a valid active garden
     */
    modifier onlyActiveGarden() {
        _require(IBabController(controller).isGarden(msg.sender), Errors.ONLY_ACTIVE_GARDEN);
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
    modifier onlyUnpaused() {
        // Do not execute if Globally or individually paused
        _require(!IBabController(controller).isPaused(address(this)), Errors.ONLY_UNPAUSED);
        _;
    }

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
        // DEPRECATED
        uint256 principal;
        uint256 time;
        uint256 quarterBelonging;
        uint256 timeListPointer;
        uint256 power;
    }

    struct ProtocolPerQuarter {
        // Protocol allocation checkpoints per timestamp per each quarter along the time
        uint256 quarterPrincipal; // DEPRECATED
        uint256 quarterNumber; // DEPRECATED
        uint256 quarterPower; //  Accumulated Protocol power for each quarter
        uint96 supplyPerQuarter; // DEPRECATED
    }

    struct GardenPowerByTimestamp {
        // DEPRECATED TODO Pending backward compatibility
        // Garden allocation checkpoints per timestamp per each garden
        uint256 supply; // Checkpoint to keep track on garden supply
        uint256 timestamp; // Checkpoint timestamps
        uint256 power; // Garden power checkpoint (power is proportional to = principal * duration)
    }
    struct ContributorPerGarden {
        // DEPRECATED TODO Pending backward compatibility
        // Checkpoints to keep track on the evolution of each contributor vs. each garden
        uint256 lastDepositAt; // Last deposit timestamp of each contributor in each garden
        uint256 initialDepositAt; // Checkpoint of the initial deposit
        uint256[] timeListPointer; // Array of timestamps for each user in each garden
        uint256 pid; // Garden contributor checkpoints counter to enable iteration
        mapping(uint256 => TimestampContribution) tsContributions; // Sub-mapping all the contributor checkpoints
    }

    struct TimestampContribution {
        // DEPRECATED TODO Pending backward compatibility
        // Sub-mapping with all checkpoints for deposits and withdrawals of garden users
        uint256 supply; // Garden token balance of user in each garden along the time
        uint256 timestamp; // Checkpoint time
        uint256 timePointer; // Pointer
        uint256 power; // Contributor power per checkpoint
    }
    struct Checkpoints {
        // DEPRECATED
        // Checkpoints for contributor power calculations where a certain window (from -> to) is queried
        uint256 fromDepositAt; // First contributor checkpoint within the provided window
        uint256 lastDepositAt; // Last contributor checkpoint within the provided window
        uint256 gardenFromDepositAt; // First contributor checkpoint within the provided window
        uint256 gardenLastDepositAt; // Last garden checkpoint within the provided window
    }

    /* ============ State Variables ============ */

    // Instance of the Controller contract
    IBabController private controller;

    // BABL Token contract
    TimeLockedToken private babltoken;

    // Protocol total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all ongoing strategies during mining program.
    uint256 private miningProtocolPrincipal; // Protocol principal (only related to mining program)
    mapping(uint256 => ProtocolPerTimestamp) private protocolPerTimestamp; // DEPRECATED
    uint256[] private timeList; // DEPRECATED
    uint256 private miningProtocolPower; // Mining protocol power along the time

    mapping(uint256 => ProtocolPerQuarter) private protocolPerQuarter; // Mapping of the accumulated protocol per each active quarter
    mapping(uint256 => bool) private isProtocolPerQuarter; // Check if the protocol per quarter data has been initialized

    mapping(address => mapping(uint256 => uint256)) private rewardsPowerOverhead; // DEPRECATED
    // Contributor power control
    mapping(address => mapping(address => ContributorPerGarden)) private contributorPerGarden; // DEPRECATED
    mapping(address => mapping(address => Checkpoints)) private checkpoints; // DEPRECATED
    // Garden power control
    mapping(address => mapping(uint256 => GardenPowerByTimestamp)) private gardenPowerByTimestamp; // DEPRECATED
    mapping(address => uint256[]) private gardenTimelist; // DEPRECATED
    mapping(address => uint256) private gardenPid; // DEPRECATED

    struct StrategyPerQuarter {
        // Acumulated strategy power per each quarter along the time
        uint256 quarterPrincipal; // DEPRECATED
        uint256 quarterNumber; // DEPRECATED
        uint256 quarterPower; //  Accumulated strategy power for each quarter
        bool initialized; // True if the strategy has checkpoints in that quarter already
    }
    struct StrategyPricePerTokenUnit {
        // Take control over the price per token changes along the time when normalizing into DAI
        uint256 preallocated; // Strategy capital preallocated before each checkpoint
        uint256 pricePerTokenUnit; // Last average price per allocated tokens per strategy normalized into DAI
    }
    mapping(address => mapping(uint256 => StrategyPerQuarter)) public strategyPerQuarter; // Acumulated strategy power per each quarter along the time
    mapping(address => StrategyPricePerTokenUnit) public strategyPricePerTokenUnit; // Pro-rata oracle price allowing re-allocations and unwinding of any capital value

    // Reentrancy guard countermeasure
    uint256 private status;

    // Customized profit sharing (if any)
    // [0]: _strategistProfit , [1]: _stewardsProfit, [2]: _lpProfit
    mapping(address => uint256[3]) private gardenProfitSharing;
    mapping(address => bool) private gardenCustomProfitSharing;

    uint256 private miningUpdatedAt; // Timestamp of last checkpoint update
    mapping(address => uint256) private strategyPrincipal; // Last known strategy principal normalized into DAI

    /* ============ Constructor ============ */

    function initialize(TimeLockedToken _bablToken, IBabController _controller) public {
        OwnableUpgradeable.__Ownable_init();
        _require(address(_bablToken) != address(0), Errors.ADDRESS_IS_ZERO);
        _require(address(_controller) != address(0), Errors.ADDRESS_IS_ZERO);
        babltoken = _bablToken;
        controller = _controller;

        (BABL_STRATEGIST_SHARE, BABL_STEWARD_SHARE, BABL_LP_SHARE, CREATOR_BONUS) = controller.getBABLSharing();
        (PROFIT_STRATEGIST_SHARE, PROFIT_STEWARD_SHARE, PROFIT_LP_SHARE) = controller.getProfitSharing();
        PROFIT_PROTOCOL_FEE = controller.protocolPerformanceFee();

        status = NOT_ENTERED;
    }

    /* ============ External Functions ============ */

    /**
     * Function that adds/substract the capital received to the total principal of the protocol per timestamp
     * @param _capital                Amount of capital in any type of asset to be normalized into DAI
     * @param _addOrSubstract         Whether we are adding or substracting capital
     */
    function updateProtocolPrincipal(uint256 _capital, bool _addOrSubstract)
        external
        override
        onlyStrategy
        onlyMiningActive
    {
        IStrategy strategy = IStrategy(msg.sender);
        if (strategy.enteredAt() >= START_TIME) {
            // onlyMiningActive control, it does not create a checkpoint if the strategy is not part of the Mining Program
            _updateProtocolPrincipal(address(strategy), _capital, _addOrSubstract);
        }
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
        if ((strategy.enteredAt() >= START_TIME) && (START_TIME != 0)) {
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
                    // last quarter - we need to take proportional supply for that timeframe despite the epoch has not finished yet
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
            uint256 mantissa = uint256(18).sub(ERC20(IGarden(strategy.garden()).reserveAsset()).decimals());
            // Babl rewards will be proportional to the total return (profits) with a max cap of x2
            // PercentageMul must always have 18 decimals
            uint256 percentageMul = str[1].mul(10**mantissa).preciseDiv(str[0].mul(10**mantissa));

            console.log('---CHECK STRATEGY percentageMul---', _strategy, percentageMul);
            console.log('---CHECK STRATEGY rewards before---', _strategy, rewards);

            if (percentageMul > 2e18) percentageMul = 2e18;
            rewards = rewards.preciseMul(percentageMul);
            console.log('---CHECK STRATEGY rewards after---', _strategy, rewards);
            return Safe3296.safe96(rewards, 'overflow 96 bits');
        } else {
            return 0;
        }
    }

    /**
     * Sends BABL tokens rewards to a contributor after a claim is requested to the protocol.
     * @param _to                Address to send the tokens to
     * @param _amount            Amount of tokens to send the address to
     */
    function sendTokensToContributor(address _to, uint256 _amount)
        external
        override
        nonReentrant
        onlyMiningActive
        onlyUnpaused
    {
        // TODO Make it more restrictive e.g. only Gardens and contributor part of the Garden
        _require(controller.isSystemContract(msg.sender), Errors.NOT_A_SYSTEM_CONTRACT);
        uint96 amount = Safe3296.safe96(_amount, 'overflow 96 bits');
        _safeBABLTransfer(_to, amount);
    }

    /**
     * Starts BABL Rewards Mining Program from the controller.
     */
    function startBABLRewards() external override onlyController onlyUnpaused {
        if (START_TIME == 0) {
            // It can only be activated once to avoid overriding START_TIME
            START_TIME = block.timestamp;
        }
    }

    /**
     * Function that set the babl Token address as it is going to be released in a future date
     * @param _bablToken BABLToken address
     */
    function setBablToken(TimeLockedToken _bablToken) external onlyOwner onlyUnpaused {
        _require(address(_bablToken) != address(0) && _bablToken != babltoken, Errors.INVALID_ADDRESS);
        babltoken = _bablToken;
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
        _require(IBabController(controller).isGarden(address(_garden)), Errors.ONLY_ACTIVE_GARDEN);
        uint256[] memory totalRewards = new uint256[](7);
        uint256 initialDepositAt;
        uint256 claimedAt;
        // uint256 contributorPower;
        (, initialDepositAt, claimedAt, , , , , , , , ) = IGarden(_garden).getContributor(_contributor);
        // update contributor power
        // contributorPower = _getContributorPower(_garden, _contributor, 0, block.timestamp);
        for (uint256 i = 0; i < _finalizedStrategies.length; i++) {
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
    function tokenSupplyPerQuarter(uint256 _quarter) external pure override returns (uint96) {
        return _tokenSupplyPerQuarter(_quarter);
    }

    /**
     * Set customized profit shares for a specific garden by the gardener
     * @param _strategistShare      New % of strategistShare
     * @param _stewardsShare        New % of stewardsShare
     * @param _lpShare              New % of lpShare
     */
    function setProfitRewards(
        address _garden,
        uint256 _strategistShare,
        uint256 _stewardsShare,
        uint256 _lpShare
    ) external override onlyController {
        _require(IBabController(controller).isGarden(_garden), Errors.ONLY_ACTIVE_GARDEN);
        _setProfitRewards(_garden, _strategistShare, _stewardsShare, _lpShare);
    }

    /**
     * Check the protocol state in a certain timestamp
     * @param time      Timestamp
     */
    /**
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
        ProtocolPerTimestamp storage protocolCheckpoint = protocolPerTimestamp[_time];

        return (
            protocolCheckpoint.principal,
            protocolCheckpoint.time,
            protocolCheckpoint.quarterBelonging,
            protocolCheckpoint.timeListPointer,
            protocolCheckpoint.power
        );
    }
    */
    /**
     * Check the quarter power for a specific quarter
     * @param _num     Number of quarter
     */

    function checkQuarterPower(uint256 _num) external view override returns (uint256 quarterPower) {
        return (protocolPerQuarter[_num].quarterPower);
    }

    /**
     * Check the strategy data for a specific quarter
     * @param _num     Number of quarter
     */

    function checkStrategy(uint256 _num, address _strategy)
        external
        view
        override
        returns (
            uint256 quarterPower,
            bool initialized,
            uint256 principal,
            uint256 preallocated,
            uint256 pricePerTokenUnit
        )
    {
        return (
            strategyPerQuarter[_strategy][_num].quarterPower,
            strategyPerQuarter[_strategy][_num].initialized,
            strategyPrincipal[_strategy],
            strategyPricePerTokenUnit[_strategy].preallocated,
            strategyPricePerTokenUnit[_strategy].pricePerTokenUnit
        );
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

    function getStrategyPricePerTokenUnit(address _strategy) external view override returns (uint256, uint256) {
        StrategyPricePerTokenUnit storage strPpt = strategyPricePerTokenUnit[_strategy];
        return (strPpt.preallocated, strPpt.pricePerTokenUnit);
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
        // The following function call _updatePrincipal must be always executed after _updateProtocolPowerPerQuarter and _updateStrategyPowerPerQuarter
        _updatePrincipal(_strategy, _capital, _addOrSubstract);
        // The following time set should always be executed at the end
        miningUpdatedAt = block.timestamp;
    }

    /**
     * Update the principal considered part of the mining program either Protocol or Strategies
     * @param _strategy         Strategy address
     * @param _capital          Capital normalized into DAI to add or substract for accurate comparisons between strategies
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
                //We use the previous pricePerToken in a substract instead of a new price (as allocated capital used previous prices not the current one)
                strPpt.preallocated = strPpt.preallocated.sub(_capital);
            }
            return strPpt.pricePerTokenUnit;
        }
    }

    /**
     * Get the rewards for a specific contributor activately contributing in strategies of a specific garden
     * @param _garden               Garden address responsible of the strategies to calculate rewards
     * @param _strategy             Strategy address
     * @param _contributor          Contributor address
     * @param _initialDepositAt     User initial deposit timestamp
     * @param _claimedAt            User last claim timestamp

     * @return Array of size 7 with the following distribution:
     * rewards[0]: Strategist BABL , rewards[1]: Strategist Profit, rewards[2]: Steward BABL, rewards[3]: Steward Profit, rewards[4]: LP BABL, rewards[5]: total BABL, rewards[6]: total Profits
     */
    function _getStrategyProfitsAndBABL(
        address _garden,
        address _strategy,
        address _contributor,
        uint256 _initialDepositAt,
        uint256 _claimedAt
    ) private view returns (uint256[] memory) {
        _require(address(IStrategy(_strategy).garden()) == _garden, Errors.STRATEGY_GARDEN_MISMATCH);
        // rewards[0]: Strategist BABL , rewards[1]: Strategist Profit, rewards[2]: Steward BABL, rewards[3]: Steward Profit, rewards[4]: LP BABL, rewards[5]: total BABL, rewards[6]: total Profits
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
        // strategyDetails[10]: normalizedCapitalAllocated
        // strategyDetails[11]: profitValue
        // strategyDetails[12]: distanceValue
        // profitData array mapping:
        // profitData[0]: profit
        // profitData[1]: distance

        // Positive strategies not yet claimed
        if (strategyDetails[1] > _claimedAt && strategyDetails[0] >= _initialDepositAt) {
            // In case of profits, the distribution of profits might substract the protocol fee beforehand:
            strategyDetails[11] = profitData[0] == true
                ? strategyDetails[11].sub(strategyDetails[11].multiplyDecimal(PROFIT_PROTOCOL_FEE))
                : 0;
            // Get the contributor power until the the strategy exit timestamp
            uint256 contributorPower = _getContributorPower(_garden, _contributor, 0, strategyDetails[1]);
            // Get strategist BABL rewards in case the contributor is also the strategist of the strategy
            rewards[0] = strategist == _contributor ? _getStrategyStrategistBabl(strategyDetails, profitData) : 0;
            // Get strategist profit rewards if profits
            rewards[1] = (strategist == _contributor && profitData[0] == true)
                ? _getStrategyStrategistProfits(_garden, strategyDetails[11])
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
        // It executes in all cases as non profited strategies give BABL rewards to those who voted against

        int256 userVotes = IStrategy(_strategy).getUserVotes(_contributor);
        uint256 totalVotes = _strategyDetails[4].add(_strategyDetails[5]);

        uint256 bablCap;

        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        uint256 babl;
        if (userVotes > 0 && _profitData[0] == true && _profitData[1] == true) {
            // Voting in favor of the execution of the strategy with profits and positive distance
            babl = _strategyDetails[9].multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
                uint256(userVotes).preciseDiv(totalVotes)
            );
        } else if (userVotes > 0 && _profitData[0] == true && _profitData[1] == false) {
            // Voting in favor positive profits but below expected return
            babl = _strategyDetails[9].multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
                uint256(userVotes).preciseDiv(totalVotes)
            );
            // We discount the error of expected return vs real returns
            babl = babl.sub(babl.preciseMul(_strategyDetails[12].preciseDiv(_strategyDetails[8])));
        } else if (userVotes > 0 && _profitData[0] == false) {
            // Voting in favor of a non profitable strategy get nothing
            babl = 0;
        } else if (userVotes < 0 && _profitData[1] == false) {
            // Voting against a strategy that got results below expected return provides rewards
            // to the voter (helping the protocol to only have good strategies)
            uint256 votesAccounting = _profitData[0] ? totalVotes : _strategyDetails[5];
            babl = _strategyDetails[9].multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
                uint256(Math.abs(userVotes)).preciseDiv(votesAccounting)
            );

            bablCap = babl.mul(2); // Max cap
            // We add a bonus inverse to the error of expected return vs real returns
            babl = babl.add(babl.preciseMul(_strategyDetails[12].preciseDiv(_strategyDetails[8])));
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
        // Assumption that the strategy got profits. Should not execute otherwise.
        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        int256 userVotes = IStrategy(_strategy).getUserVotes(_contributor);
        uint256 totalVotes = _strategyDetails[4].add(_strategyDetails[5]);

        uint256 profitShare =
            gardenCustomProfitSharing[_garden] ? gardenProfitSharing[_garden][1] : PROFIT_STEWARD_SHARE;
        if (userVotes > 0) {
            return
                _strategyDetails[11].multiplyDecimal(profitShare).preciseMul(uint256(userVotes)).preciseDiv(totalVotes);
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
        // We assume that the contributor is the strategist. Should not execute otherwise.
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
            // No positive profit
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
        // We take care of normalization into 18 decimals for capital allocated in less decimals than 18
        // This is due to BABL has 18 decimals
        babl = _strategyRewards.multiplyDecimal(BABL_LP_SHARE).preciseMul(_contributorPower);
        return babl;
    }

    /**
     * Add protocol power timestamps for each quarter
     */
    function _updateProtocolPowerPerQuarter() private {
        uint256[] memory data = new uint256[](4);
        // data[0]: prevQuarter, data[1]: current quarter, data[2]: timeDifference, data[3]: debtPower
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
                    // We re-initialize the protocol power in the new epoch adding only the corresponding to its duration
                    protocolCheckpoint.quarterPower = data[3]
                        .mul(block.timestamp.sub(START_TIME.add(data[1].mul(EPOCH_DURATION).sub(EPOCH_DURATION))))
                        .div(data[2]);
                    // We now update the previous quarter with its proportional pending debtPower
                    protocolPerQuarter[data[1].sub(1)].quarterPower = protocolPerQuarter[data[1].sub(1)]
                        .quarterPower
                        .add(data[3].sub(protocolCheckpoint.quarterPower));
                } else {
                    // There were some intermediate epochs without checkpoints - we need to create missing checkpoints and update the last (current) one
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
            // We update the power of the quarter by adding the new difference between last quarter checkpoint and this checkpoint
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
        data[2] = block.timestamp.sub(data[1]);
        data[3] = _getQuarter(block.timestamp);
        StrategyPerQuarter storage strategyCheckpoint = strategyPerQuarter[_strategy][data[3]];
        // We calculate the debt Power since last checkpoint (if any)
        data[4] = strategyPrincipal[_strategy].mul(data[2]);
        if (!strategyCheckpoint.initialized) {
            // The strategy quarter is not yet initialized then we create it
            // If it the first checkpoint in the first executing epoch - keep power 0
            if (data[3] > _getQuarter(data[0])) {
                // Each time a running strategy has a new checkpoint on a new (different) epoch than previous checkpoints
                // debtPower is the proportional power of the strategy for this quarter from previous checkpoint
                // We need to iterate since last checkpoint
                (uint256 numQuarters, uint256 startingQuarter) = _getRewardsWindow(data[1], block.timestamp);

                // There were intermediate epochs without checkpoints - we need to create their corresponding checkpoints and update the last one
                // We have to update all the quarters including where the previous checkpoint is and the one where we are now
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
            // We update the power of the quarter by adding the new difference between last quarter checkpoint and this checkpoint
            strategyCheckpoint.quarterPower = strategyCheckpoint.quarterPower.add(data[4]);
        }
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
        // Check to avoid out of bounds
        _require(_to >= IGarden(_garden).gardenInitializedAt() && _to >= _from, Errors.CONTRIBUTOR_POWER_CHECK_WINDOW);
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
        (powerData[0], powerData[1], , , , , powerData[2], , powerData[3], , powerData[4]) = IGarden(_garden)
            .getContributor(_contributor);
        console.log('conditional', powerData[1] == 0 || powerData[1] > _to || powerData[2] == 0);
        if (powerData[1] == 0 || powerData[1] > _to || powerData[2] == 0) {
            return 0;
        } else {
            // Safe check, time travel only works for a past date, avoid underflow
            if (_to > block.timestamp) {
                console.log('cannot go to the future', _to, block.timestamp);
                _to = block.timestamp;
            }
            (powerData[5], powerData[6], powerData[7], powerData[8]) = IGarden(_garden).getGardenPower();
            console.log('powerData[0]', powerData[0]);
            console.log('powerData[1]', powerData[1]);
            console.log('powerData[2]', powerData[2]);
            console.log('powerData[3]', powerData[3]);
            console.log('powerData[4]', powerData[4]);
            console.log('powerData[5]', powerData[5]);
            console.log('powerData[6]', powerData[6]);
            console.log('powerData[7]', powerData[7]);
            console.log('powerData[8]', powerData[8]);

            // First we update contributor and garden power as of block.timestamp values
            // We then time travel back to when the strategy exitedAt
            // TODO
            // a) CALCULATE UPDATED VALUES FOR EITHER CONTRIBUTOR AND GARDEN (GARDEN DATA COULD BE RETRIEVED FROM getContributor if needed to avoid more remote calls)
            // b) check time window
            // c) if needed, calculate new time.
            // First we need to get an updatedValue of user and garden power since lastDeposits
            // console.log('CHECK user power', powerData[3]);
            uint256 updatedPower = powerData[3].add((block.timestamp.sub(powerData[0])).mul(powerData[2]));
            console.log('CHECK updated user power', powerData[3]);
            // console.log('CHECK garden power', powerData[6]);
            // console.log('BOOLEAN time check _to', _to == block.timestamp);
            // console.log('---CHECK time',block.timestamp.sub(powerData[5]));
            // console.log('---CHECK time',block.timestamp, powerData[5]);

            uint256 updatedGardenPower = powerData[6].add((block.timestamp.sub(powerData[5])).mul(powerData[8]));
            console.log('CHECK updated garden power', updatedGardenPower);

            // Calculate the power at "_to" timestamp
            uint256 timeDiff = block.timestamp.sub(_to);
            uint256 userPowerDiff = powerData[4].mul(timeDiff);
            uint256 gardenPowerDiff = powerData[7].mul(timeDiff);
            console.log('timeDiff', timeDiff);
            // console.log('SUBSTRACT CONTRIBUTOR', powerData[4], powerData[4].mul(timeDiff));
            // console.log('SUBSTRACT GARDEN', powerData[7], powerData[7].mul(timeDiff));
            // Avoid underflow conditions
            updatedPower = updatedPower > userPowerDiff ? updatedPower.sub(userPowerDiff) : 0;
            updatedGardenPower = updatedGardenPower > gardenPowerDiff ? updatedGardenPower.sub(gardenPowerDiff) : 1;

            console.log('--- BACK TO THE POWER CONTRIBUTOR ---', updatedPower);
            console.log('--- BACK TO THE POWER GARDEN ---', updatedGardenPower);

            uint256 balancePower = powerData[2].preciseDiv(powerData[8]);
            uint256 virtualPower = updatedPower.preciseDiv(updatedGardenPower);
            console.log('CHECK balance Power', balancePower);
            console.log('CHECK virtual Power', virtualPower);
            return virtualPower;
        }
    }

    /**
        console.log('CHECK');
        // Out of bounds
        _require(_to >= IGarden(_garden).gardenInitializedAt() && _to >= _from, Errors.CONTRIBUTOR_POWER_CHECK_WINDOW);
        (, uint256 initialDepositAt, , , , , , , , ) = IGarden(_garden).getContributor(_contributor);
        console.log('CHECK 1', initialDepositAt);

        if (initialDepositAt == 0 || initialDepositAt > _to) {
            return 0;
       
        } else {
            uint256 userLiquidity;
            uint256 gardenLiquidity;
            console.log('CHECK 2 length', depositInfo[_garden].length);

            for (uint256 i = 0; i < depositInfo[_garden].length; i++) {
                DepositInfo storage userDeposit = depositInfo[_garden][i];
                if (userDeposit.timestamp > _to) {
                    continue;
                }

                if (userDeposit.contributor == _contributor) {
                    console.log('userLiquidity', userLiquidity);
                    userLiquidity = userDeposit.depositOrWithdraw == true ? userLiquidity.add(userDeposit.amount) : userLiquidity.sub(userDeposit.amount);
                }
                console.log('gardenLiquidity', gardenLiquidity);
                gardenLiquidity = userDeposit.depositOrWithdraw == true ? gardenLiquidity.add(userDeposit.amount) : gardenLiquidity.sub(userDeposit.amount);
            }
            console.log('EO');
            console.log('TOTAL userLiquidity', userLiquidity);
            console.log('TOTAL gardenLiquidity', gardenLiquidity);
            console.log('contributor power', userLiquidity.preciseDiv(gardenLiquidity));

            return userLiquidity.preciseDiv(gardenLiquidity);
        }
    }
     */

    /**
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
    */

    /**
     * Gets the earlier and closest (deposit/withdrawal) checkpoints of a contributor in a specific range
     * @param _garden      Address of the garden
     * @param _contributor Address if the contributor
     * @param _from        Initial timestamp
     * @param _to          End timestamp
     * @return uint256     Contributor power during that period
     */
    /**
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
            for (uint256 i = 0; i < contributor.timeListPointer.length; i++) {
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
     */
    /**
     * Gets the earlier and closest (deposit/withdrawal) checkpoints of a garden in a specific range
     * @param _garden      Address of the garden
     * @param _from        Initial timestamp
     * @param _to          End timestamp
     * @return uint256     Contributor power during that period
     */
    /**
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
     */
    /**
     * Function that keeps checkpoints of the garden power (deposits and withdrawals) per timestamp
     * @param _garden               Garden address
     */
    /**
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
     */

    /**
     * Updates contributor timestamps params
     * @param _garden               Garden address
     * @param _contributor          Contributor address
     * @param _previousBalance      Previous balance
     * @param _depositOrWithdraw    Whether it is a deposit or a withdraw
     */
    /**
    function _setContributorTimestampParams(
        address _garden,
        address _contributor,
        uint256 _previousBalance,
        bool _depositOrWithdraw
    ) private {
        // We make checkpoints around contributor deposits to give the right rewards afterwards
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
     */
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
}

contract RewardsDistributorV5 is RewardsDistributor {}
