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
import {ECDSA} from '@openzeppelin/contracts/cryptography/ECDSA.sol';
import {Errors, _require} from '../lib/BabylonErrors.sol';

import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IProphets} from '../interfaces/IProphets.sol';
import {IRewardsAssistant} from '../interfaces/IRewardsAssistant.sol';

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
    using ECDSA for bytes32;

    /* ========== Events ========== */

    event SentGardenRewards(address _garden, address _user, uint256 _bablSent, uint256 _profitSent);

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
            msg.sender == IBabController(controller).owner() ||
                msg.sender == owner() ||
                msg.sender == IBabController(controller).EMERGENCY_OWNER() ||
                msg.sender == address(controller),
            Errors.ONLY_GOVERNANCE_OR_EMERGENCY
        );
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
    // DAI normalize asset
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Reentrancy guard countermeasure
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    // NFT Prophets
    IProphets private constant PROPHETS_NFT = IProphets(0x26231A65EF80706307BbE71F032dc1e5Bf28ce43);

    bytes32 private constant REWARDS_BY_SIG_TYPEHASH =
        keccak256(
            'RewardsBySig(uint256 _babl,uint256 _profits,uint256 _userRewardsNonce,uint256 _minAmountOut,uint256 _gardenNonce,uint256 _maxFee,bool _mintNft,bool _stakeRewards)'
        );

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

    uint256 public override bablProfitWeight;
    uint256 public override bablPrincipalWeight;

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
    // Rewards Assistant for rewards calculations
    IRewardsAssistant private rewardsAssistant;
    // Heart garden address
    address private heartGarden;
    // User address => rewards nonce
    mapping(address => uint256) private userRewardsNonce;

    /* ============ Constructor ============ */

    function initialize(TimeLockedToken _bablToken, IBabController _controller) public initializer {
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
     * @notice
     *   This method allows users to claim all their rewards from an array of gardens in 1 user tx.
     *   Rewards come from the strategies that his principal
     *   was invested in in each of the gardens.
     * @dev
     *   Users should preferably call `claimAllMyGardenRewardsBySig` instead of this method to save gas due to
     *   getRewards is caculated on-chain in this method.
     *   TODO Pending handling of all profits rewards in reserve assets at RD to remove rewardsSetAside from Gardens
     *
     * @param _myGardens            Array of user gardens (portfolio)
     * @param _stakeInHeart         Whether or not the user wants to stake BABL in the heart garden
     * @param _stakeMinAmountOut    MinAmountOut in case of staking (e.g. hBABL)
     * @param _mintNft              Whether or not the user wants to mintNFT for the stake
     */
    function claimRewards(
        address[] memory _myGardens,
        bool _stakeInHeart,
        uint256 _stakeMinAmountOut,
        bool _mintNft
    ) external override nonReentrant {
        uint256[] memory data = new uint256[](8);
        // data[0]: totalBabl (stakeAmountIn)
        // data[1]: totalProfits
        // data[2]: userRewardsNonce
        // data[3]: stakeMinAmountOut
        // data[4]: heart garden user nonce
        // data[5]: maxFee
        // data[6]: fee
        // data[7]: pricePerShare (it will be overriden if user wants to stake)
        bool[] memory boolData = new bool[](2);
        // boolData[0]: mintNft
        // boolData[1]: stakeInHeart
        (
            address[] memory gardens,
            uint256[] memory babl,
            uint256[] memory profits,
            uint256 totalBabl,
            uint256 totalProfits
        ) = IRewardsAssistant(rewardsAssistant).getAllUserRewards(msg.sender, _myGardens);
        data[0] = totalBabl;
        data[1] = totalProfits;
        data[2] = userRewardsNonce[msg.sender];
        data[3] = _stakeMinAmountOut;
        (, , , , , , , , , data[4]) = IGarden(heartGarden).getContributor(msg.sender);
        data[5] = 0;
        data[6] = 0;
        data[7] = 1e18;
        boolData[0] = _mintNft;
        boolData[1] = _stakeInHeart;
        bool bySig = false;
        address keeper = address(0);
        _handleRewards(gardens, babl, profits, msg.sender, keeper, data, boolData, bySig);
    }

    /**
     * @notice
     *   This method allows users
     *   to claim All their pending rewards either profits or BABL by signature.
     * @dev
     *   Should be called instead of the `claimAllRewards at RD` to save gas due to
     *   getAllUserRewards caculated off-chain.
     *   The Keeper fee is paid out of user's reserveAsset and it is calculated off-chain.
     *   TODO Pending handling of all profits rewards in reserve assets at RD to remove rewardsSetAside from Gardens
     *
     * @param _gardens          Array of gardens
     * @param _babl             Array of BABL rewards from mining program per garden.
     * @param _profits          Array of Profit rewards in reserve asset per garden.
     * @param _signatureData    Array of 5 values with totalBabl, totalProfits, userRewardsNonce, maxFee and Fee.
     * @param _boolSignatureData Array of 2 values mintNft and stakeRewards
     * @param v                 Signature v value
     * @param r                 Signature r value
     * @param s                 Signature s value
     *
     *
     * _signatureData[0]: totalBabl (stakeAmountIn)
     * _signatureData[1]: totalProfits
     * _signatureData[2]: userRewardsNonce
     * _signatureData[3]: stakeMinAmountOut
     * _signatureData[4]: heart garden user nonce
     * _signatureData[5]: maxFee
     * _signatureData[6]: fee
     * _signatureData[7]: pricePerShare
     * _boolSignatureData[0]: _mintNft
     * _boolSignatureData[1]: _stakeInHeart
     */

    function claimRewardsBySig(
        address[] memory _gardens,
        uint256[] memory _babl,
        uint256[] memory _profits,
        uint256[] memory _signatureData,
        bool[] memory _boolSignatureData,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override nonReentrant {
        _require(IBabController(controller).isValidKeeper(msg.sender), Errors.ONLY_KEEPER);
        _require(_signatureData[6] <= _signatureData[5], Errors.FEE_TOO_HIGH);
        _require(_signatureData[6] > 0, Errors.FEE_TOO_LOW);
        address signer = _getSigner(_signatureData, _boolSignatureData, v, r, s);
        bool bySig = true;
        _handleRewards(_gardens, _babl, _profits, signer, msg.sender, _signatureData, _boolSignatureData, bySig);
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

    /** PRIVILEGE FUNCTION
     * Updates Rewards Assistant contract
     * @param _newRewardsAssistant      New Assistant smartcontract address
     */
    function setRewardsAssistant(address _newRewardsAssistant) external override onlyOwner {
        _require(
            _newRewardsAssistant != address(0) && _newRewardsAssistant != address(rewardsAssistant),
            Errors.INVALID_ADDRESS
        );
        rewardsAssistant = IRewardsAssistant(_newRewardsAssistant);
    }

    /** PRIVILEGE FUNCTION
     * Updates Heart Garden contract
     * @param _newHeartGarden      New Heart Garden smartcontract address
     */
    function setHeartGarden(address _newHeartGarden) external override onlyOwner {
        _require(_newHeartGarden != address(0) && _newHeartGarden != address(heartGarden), Errors.INVALID_ADDRESS);
        heartGarden = _newHeartGarden;
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
        return IRewardsAssistant(rewardsAssistant).getRewards(_garden, _contributor, _finalizedStrategies);
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
            return IRewardsAssistant(rewardsAssistant).getBenchmarkRewards(str[1], str[0], rewards, ts[0]);
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
        returns (uint256[18] memory miningData)
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
        miningData[17] = strategyPerQuarter[_strategy][1].betaInitializedAt;
    }

    function getBenchmark() external view override returns (uint256[5] memory data) {
        data = benchmark;
    }

    function getInitialStrategyPower(
        address _strategy,
        uint256 _numQuarters,
        uint256 _startingQuarter
    ) external view override returns (uint256[] memory, uint256[] memory) {
        uint256[] memory strategyPower = new uint256[](_numQuarters);
        uint256[] memory protocolPower = new uint256[](_numQuarters);
        for (uint256 i = 0; i < _numQuarters; i++) {
            // We take the info of each epoch from current checkpoints
            // array[0] for the first quarter power checkpoint of the strategy
            strategyPower[i] = strategyPerQuarter[_strategy][_startingQuarter.add(i)].quarterPower;
            protocolPower[i] = protocolPerQuarter[_startingQuarter.add(i)].quarterPower;
            _require(strategyPower[i] <= protocolPower[i], Errors.OVERFLOW_IN_POWER);
        }
        return (strategyPower, protocolPower);
    }

    // rolesWeight[0]: strategist babl weight
    // rolesWeight[1]: strategist profit weight
    // rolesWeight[2]: stewards babl weight
    // rolesWeight[3]: stewards profit weight
    // rolesWeight[4]: lp babl weight
    // rolesWeight[5]: lp profit weight
    // rolesWeight[6]: garden creator
    function getRoleWeights(address _garden) external view override returns (uint256[7] memory roleWeights) {
        uint256[3] memory profitSharing = getGardenProfitsSharing(_garden);
        roleWeights[0] = strategistBABLPercentage;
        roleWeights[1] = profitSharing[0];
        roleWeights[2] = stewardsBABLPercentage;
        roleWeights[3] = profitSharing[1];
        roleWeights[4] = lpsBABLPercentage;
        roleWeights[5] = profitSharing[2];
        roleWeights[6] = gardenCreatorBonus;
    }

    /**
     * Check the garden profit sharing % if different from default
     * @param _garden     Address of the garden
     */
    function getGardenProfitsSharing(address _garden) public view override returns (uint256[3] memory) {
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
        return IRewardsAssistant(rewardsAssistant).estimateUserRewards(_strategy, _contributor);
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
    ) external view override returns (uint256) {
        (, uint256[] memory strategyDetails, ) = IStrategy(_strategy).getStrategyRewardsContext();
        return _getSafeUserSharePerStrategy(_garden, _contributor, strategyDetails);
    }

    /**
     * Get an estimation of strategy BABL rewards for active strategies in the mining program
     * @param _strategy        Address of the strategy to estimate BABL rewards
     * @return the estimated BABL rewards
     */
    function estimateStrategyRewards(address _strategy) external view override returns (uint256) {
        return IRewardsAssistant(rewardsAssistant).estimateStrategyRewards(_strategy);
    }

    /**
     * Get an estimation of strategy BABL rewards for active strategies in the mining program
     * @param _user        Address of the user
     * @return the user rewards nonce
     */
    function getUserRewardsNonce(address _user) external view override returns (uint256) {
        return userRewardsNonce[_user];
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
        // To avoid rewards replay attacks claim vs deposit/withdraw
        userRewardsNonce[_address]++;
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
     * Recover the signer of a claim by signature.
     * @param _signatureData        Signature metadata
     * @param _boolSignatureData    Boolean signature metadata
     * @param v                 Signature v value
     * @param r                 Signature r value
     * @param s                 Signature s value
     *
     */
    function _getSigner(
        uint256[] memory _signatureData,
        bool[] memory _boolSignatureData,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (address) {
        // signatureData[0]: totalBabl (stakeAmountIn)
        // signatureData[1]: totalProfits
        // signatureData[2]: userRewardsNonce
        // signatureData[3]: stakeMinAmountOut
        // signatureData[4]: heart garden user nonce
        // signatureData[5]: maxFee
        // signatureData[6]: fee
        // signatureData[7]: pricePerShare (it will be overriden if user wants to stake)
        // _boolSignatureData[0]: mintNft
        // _boolSignatureData[1]: stakeInHeart
        bytes32 hash =
            keccak256(
                abi.encode(
                    REWARDS_BY_SIG_TYPEHASH,
                    address(this),
                    _signatureData[0],
                    _signatureData[1],
                    _signatureData[2],
                    _signatureData[3],
                    _signatureData[4],
                    _signatureData[5],
                    _boolSignatureData[0],
                    _boolSignatureData[1]
                )
            )
                .toEthSignedMessageHash();
        address signer = ECDSA.recover(hash, v, r, s);
        // Used in by sig
        _require(signer != address(0), Errors.INVALID_SIGNER);
        // To prevent replay attacks we use nonce at RD level
        // We also save gas avoiding nonce check per garden
        _require(userRewardsNonce[signer] == _signatureData[2], Errors.INVALID_NONCE);
        return signer;
    }

    /**
     * Handle and execute/sends rewards to the user or stake them otherwise depending on user selection
     * @param _gardens        Array of user gardens
     * @param _babl           Array of babl rewards per garden
     * @param _profits        Array of profit rewards per garden
     * @param _contributor    Address of the contributor
     * @param _keeper         Address of the keeper to receive fee payment (in signed tx's)
     * @param _data           Array of rewards metadata
     * @param _boolData       Array of rewards boolean metadata
     * @param _bySig          Whether or not it is a signature based tx
     *
     */
    function _handleRewards(
        address[] memory _gardens,
        uint256[] memory _babl,
        uint256[] memory _profits,
        address _contributor,
        address _keeper,
        uint256[] memory _data,
        bool[] memory _boolData,
        bool _bySig
    ) internal {
        uint256 bablCount;
        uint256 profitsCount;
        uint256 bablSent;
        for (uint256 i = 0; i < _gardens.length; i++) {
            // We do not pay keeper fee in normal user tx (keeper = address(0) && _data[6] == 0)
            // The following check includes flashload security check (vs. depositHardlock) at garden level
            // In case of paying keeper, we only use the first garden to use only one payKeeper to pay all and save gas
            IGarden(_gardens[i]).sendRewardsToContributor(
                _contributor,
                i == 0 ? _keeper : address(0),
                _babl[i],
                _profits[i],
                i == 0 ? _data[6] : 0
            );
            bablCount = bablCount.add(_babl[i]);
            // It will sum different reserveAsset with different decimals
            // to be used only as a total profits lump sum security check
            profitsCount = profitsCount.add(_profits[i]);
        }
        _require(bablCount == _data[0], Errors.NOT_ENOUGH_BABL);
        // We send total BABL in only 1 aggregated tx (if any)
        if (_boolData[1]) {
            // Staking into heart
            // Direct sending RD into Heart Garden on behalf of the user
            bablSent = _sendBABLToContributor(heartGarden, _data[0]);
            // We then make the accounting for the user as a deposit to get hBABL
            // We use 1e18 as default pricePerShare, it will be overriden by real price per share
            IGarden(heartGarden).stakeRewards(
                _contributor,
                heartGarden,
                address(babltoken),
                bablSent,
                _data[3],
                _boolData[0],
                _data[4],
                _data[7],
                _bySig
            );
        } else {
            // Not staking into heart
            // Direct send to user wallet
            bablSent = _sendBABLToContributor(_contributor, _data[0]);
        }
        _require(bablSent == _data[0], Errors.NOT_ENOUGH_BABL);
        _require(profitsCount == _data[1], Errors.NOT_ENOUGH_PROFITS);
    }

    /**
     * Sends profits and BABL tokens rewards to a contributor after a claim is requested to the protocol.
     * @param _to        Address to send the profit and tokens to
     * @param _babl      Amount of BABL to send
     *
     */
    function _sendBABLToContributor(address _to, uint256 _babl) internal returns (uint256) {
        _onlyUnpaused();
        // To avoid replay-attacks
        userRewardsNonce[_to]++;
        uint256 bablBal = babltoken.balanceOf(address(this));
        uint256 bablToSend = _babl > bablBal ? bablBal : _babl;
        if (bablToSend > 0) {
            SafeERC20.safeTransfer(babltoken, _to, bablToSend);
        }
        return bablToSend;
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
}

contract RewardsDistributorV14 is RewardsDistributor {}
