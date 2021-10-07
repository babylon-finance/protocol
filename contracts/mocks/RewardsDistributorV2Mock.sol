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

import {TimeLockedToken} from '../token/TimeLockedToken.sol';

import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/proxy/ProxyAdmin.sol';

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
contract RewardsDistributorV2Mock is OwnableUpgradeable {
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

    /* ============ Constants ============ */
    // 500K BABL allocated to this BABL Mining Program, the first quarter is Q1_REWARDS
    // and the following quarters will follow the supply curve using a decay rate
    uint256 public constant Q1_REWARDS = 53_571_428_571_428_600e6; // First quarter (epoch) BABL rewards
    // 12% quarterly decay rate (each 90 days)
    // (Rewards on Q1 = 1,12 * Rewards on Q2) being Q1= Quarter 1, Q2 = Quarter 2
    uint256 public constant DECAY_RATE = 12e16;
    // Duration of its EPOCH in days  // BABL & profits split from the protocol
    uint256 public constant EPOCH_DURATION = 90 days;

    // solhint-disable-next-line
    uint256 public START_TIME; // Starting time of the rewards distribution

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
    uint256 public protocolPrincipal;
    mapping(uint256 => ProtocolPerTimestamp) public protocolPerTimestamp; // Mapping of all protocol checkpoints
    uint256[] public timeList; // Array of all protocol checkpoints
    uint256 public pid; // Initialization of the ID assigning timeListPointer to the checkpoint number

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

    struct StrategyPerQuarter {
        // Acumulated strategy power per each quarter along the time
        uint256 quarterPrincipal;
        uint256 quarterNumber; // # Quarter since START_TIME
        uint256 quarterPower; //  Accumulated strategy power for each quarter
        bool initialized;
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

        _require(address(_bablToken) != address(0), Errors.ADDRESS_IS_ZERO);
        _require(address(_controller) != address(0), Errors.ADDRESS_IS_ZERO);
        babltoken = _bablToken;
        controller = _controller;

        (
            BABL_STRATEGIST_SHARE,
            BABL_STEWARD_SHARE,
            BABL_LP_SHARE,
            CREATOR_BONUS,
            BABL_PROFIT_WEIGHT,
            BABL_PRINCIPAL_WEIGHT
        ) = controller.getBABLMiningParameters();
        (PROFIT_STRATEGIST_SHARE, PROFIT_STEWARD_SHARE, PROFIT_LP_SHARE) = controller.getProfitSharing();
        PROFIT_PROTOCOL_FEE = controller.protocolPerformanceFee();

        status = NOT_ENTERED;
    }

    /* ============ External Functions ============ */

    function newMethod() public pure returns (string memory) {
        return 'foobar';
    }
}
