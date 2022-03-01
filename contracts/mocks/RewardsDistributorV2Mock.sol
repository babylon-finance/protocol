// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;

import {TimeLockedToken} from '../token/TimeLockedToken.sol';

import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

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

contract RewardsDistributorV2Mock is OwnableUpgradeable {
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

    // Only for beta gardens and users as they need migration into new gas-optimized data structure
    // Boolean check to control users and garden migration into to new mapping architecture without checkpoints
    mapping(address => mapping(address => bool)) private betaAddressMigrated;
    mapping(address => bool) private betaGardenMigrated; // DEPRECATED

    uint256 private bablProfitWeight;
    uint256 private bablPrincipalWeight;

    // A record of garden token checkpoints for each address of each garden, by index
    // garden -> address -> index checkpoint -> checkpoint struct data
    mapping(address => mapping(address => mapping(uint256 => Checkpoints))) private gardenCheckpoints;

    // The number of checkpoints for each address of each garden
    // garden -> address -> number of checkpoints
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
        // BABL Mining program was started by bip#1
        START_TIME = block.timestamp;
    }

    /* ============ External Functions ============ */

    function newMethod() public pure returns (string memory) {
        return 'foobar';
    }
}
