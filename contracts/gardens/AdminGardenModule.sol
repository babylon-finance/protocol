// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {ECDSA} from '@openzeppelin/contracts/cryptography/ECDSA.sol';
import {ERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';

import {Errors, _require, _revert} from '../lib/BabylonErrors.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';

import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IStrategyFactory} from '../interfaces/IStrategyFactory.sol';
import {IGardenValuer} from '../interfaces/IGardenValuer.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IGardenNFT} from '../interfaces/IGardenNFT.sol';
import {IMardukGate} from '../interfaces/IMardukGate.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IAdminGarden} from '../interfaces/IGarden.sol';
import {IVoteToken} from '../interfaces/IVoteToken.sol';

import {VTableBeaconProxy} from '../proxy/VTableBeaconProxy.sol';
import {VTableBeacon} from '../proxy/VTableBeacon.sol';
import {ControllerLib} from '../lib/ControllerLib.sol';
import {BaseGardenModule} from './BaseGardenModule.sol';

/**
 * @title AdminGardenModule
 *
 * Class that holds common garden-related state and functions
 */
contract AdminGardenModule is BaseGardenModule, IAdminGarden {
    using SafeCast for int256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using SafeDecimalMath for int256;

    using SafeCast for uint256;
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    using Address for address;
    using AddressArrayUtils for address[];

    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    using ControllerLib for IBabController;

    /* ============ Events ============ */

    /* ============ Constants ============ */

    // Strategy cooldown period
    uint256 private constant MIN_COOLDOWN_PERIOD = 60 seconds;
    uint256 private constant MAX_COOLDOWN_PERIOD = 7 days;

    uint256 private constant TEN_PERCENT = 1e17;

    /* ============ Structs ============ */

    /* ============ State Variables ============ */

    /* ============ Modifiers ============ */

    /**
     * Checks if the address passed is a creator in the garden
     */
    function _onlyCreator(address _creator) private view {
        _require(_isCreator(_creator), Errors.ONLY_CREATOR);
    }

    function _onlyNonZero(address _address) private pure {
        _require(_address != address(0), Errors.ADDRESS_IS_ZERO);
    }

    /* ============ Constructor ============ */

    /**
     * When a new Garden is created.
     * All parameter validations are on the BabController contract. Validations are performed already on the
     * BabController.
     * WARN: If the reserve Asset is different than WETH the gardener needs to have approved the controller.
     *
     * @param _reserveAsset                     Address of the reserve asset ERC20
     * @param _controller                       Address of the controller
     * @param _creator                          Address of the creator
     * @param _name                             Name of the Garden
     * @param _symbol                           Symbol of the Garden
     * @param _gardenParams                     Array of numeric garden params
     * @param _initialContribution              Initial Contribution by the Gardener
     * @param _publicGardenStrategistsStewards  Public garden, public strategists rights and public stewards rights
     */
    function initialize(
        address _reserveAsset,
        IBabController _controller,
        address _creator,
        string memory _name,
        string memory _symbol,
        uint256[] calldata _gardenParams,
        uint256 _initialContribution,
        bool[] memory _publicGardenStrategistsStewards
    ) public payable override initializer {
        __ERC20_init(_name, _symbol);

        controller = _controller;
        reserveAsset = _reserveAsset;
        creator = _creator;

        rewardsDistributor = IRewardsDistributor(controller.rewardsDistributor());

        _onlyNonZero(address(rewardsDistributor));

        privateGarden = !(controller.allowPublicGardens() && _publicGardenStrategistsStewards[0]);
        publicStrategists = !privateGarden && _publicGardenStrategistsStewards[1];
        publicStewards = !privateGarden && _publicGardenStrategistsStewards[2];

        _require(
            _gardenParams[3] > 0 &&
                _initialContribution >= _gardenParams[3] &&
                _initialContribution <= _gardenParams[0],
            Errors.MIN_CONTRIBUTION
        );

        gardenInitializedAt = block.timestamp;

        _updateGardenParams(
            _gardenParams[0],
            _gardenParams[1],
            _gardenParams[2],
            _gardenParams[3],
            _gardenParams[4],
            _gardenParams[5],
            _gardenParams[6],
            _gardenParams[7],
            _gardenParams[8],
            _gardenParams[9],
            _gardenParams[10],
            0 // stack overflow otherwise
        );
        canMintNftAfter = _gardenParams[11];
    }

    /* ============ External Functions ============ */

    /*
     * Creator transfer his creator rights to another account.
     * Must be a creator or an aux creator
     * @param _newCreator  New creator address
     * @param _index       Index of the creator if it is in the extra
     */
    function transferCreatorRights(address _newCreator, uint8 _index) external override {
        _onlyCreator(msg.sender);
        _require(!_isCreator(_newCreator), Errors.NEW_CREATOR_MUST_NOT_EXIST);
        // Make sure creator can still have normal permissions after renouncing
        // Creator can only renounce to 0x in public gardens
        _require(_newCreator != address(0) || !privateGarden, Errors.CREATOR_CANNOT_RENOUNCE);
        if (msg.sender == creator) {
            creator = _newCreator;
            return;
        }
        _require(extraCreators[_index] == msg.sender, Errors.ONLY_CREATOR);
        extraCreators[_index] = _newCreator;
    }

    /*
     * Governance can transfer garden owners to a different owner if original creator renounced
     * Must be a creator or an aux creator
     * @param _newCreator   New creator address
     * @param _newCreators  Addresses of the new creators
     */
    function updateCreators(address _newCreator, address[MAX_EXTRA_CREATORS] memory _newCreators) external override {
        controller.onlyGovernanceOrEmergency();
        // Make sure creator can still have normal permissions after renouncing
        // Creator can only renounce to 0x in public gardens
        _require(_newCreator != address(0) && creator == address(0), Errors.CREATOR_CANNOT_RENOUNCE);
        creator = _newCreator;
        extraCreators[0] = _newCreators[0];
        extraCreators[1] = _newCreators[1];
        extraCreators[2] = _newCreators[2];
        extraCreators[3] = _newCreators[3];
    }

    /*
     * Governance can mark a garden as verified
     * @param _verifiedCategory   New verified category
     */
    function verifyGarden(uint256 _verifiedCategory) external override {
        controller.onlyGovernanceOrEmergency();
        verifiedCategory = _verifiedCategory;
    }

    /*
     * Creator can reset the garden hardlock for all users
     * @param _hardlockStartsAt       New global hardlock starts at
     */
    function resetHardlock(uint256 _hardlockStartsAt) external override {
        _onlyCreator(msg.sender);
        _require(_hardlockStartsAt <= block.timestamp, Errors.RESET_HARDLOCK_INVALID);
        hardlockStartsAt = _hardlockStartsAt;
    }

    /**
     * Makes a previously private garden public
     */
    function makeGardenPublic() external override {
        _onlyCreator(msg.sender);
        _require(privateGarden && controller.allowPublicGardens(), Errors.GARDEN_ALREADY_PUBLIC);
        privateGarden = false;
    }

    /**
     * Gives the right to create strategies and/or voting power to garden users
     */
    function setPublicRights(bool _publicStrategists, bool _publicStewards) external override {
        _onlyCreator(msg.sender);
        _require(!privateGarden, Errors.GARDEN_IS_NOT_PUBLIC);
        publicStrategists = _publicStrategists;
        publicStewards = _publicStewards;
    }

    /*
     * Adds extra creators. Only the original creator can call this.
     * Can only be called if all the addresses are zero
     * @param _newCreators  Addresses of the new creators
     */
    function addExtraCreators(address[MAX_EXTRA_CREATORS] memory _newCreators) external override {
        _require(msg.sender == creator, Errors.ONLY_FIRST_CREATOR_CAN_ADD);
        _assignExtraCreator(0, _newCreators[0]);
        _assignExtraCreator(1, _newCreators[1]);
        _assignExtraCreator(2, _newCreators[2]);
        _assignExtraCreator(3, _newCreators[3]);
    }

    /**
     * Updates Garden Params
     * Can only be called by the creator
     * @param _newParams  New params
     */
    function updateGardenParams(uint256[12] memory _newParams) external override {
        _onlyCreator(msg.sender);
        _updateGardenParams(
            _newParams[0], // uint256 _maxDepositLimit
            _newParams[1], // uint256 _minLiquidityAsset,
            _newParams[2], // uint256 _depositHardlock,
            _newParams[3], // uint256 _minContribution,
            _newParams[4], // uint256 _strategyCooldownPeriod,
            _newParams[5], // uint256 _minVotesQuorum,
            _newParams[6], // uint256 _minStrategyDuration,
            _newParams[7], // uint256 _maxStrategyDuration,
            _newParams[8], // uint256 _minVoters
            _newParams[9], // uint256 _pricePerShareDecayRate
            _newParams[10], // uint256 _pricePerShareDelta
            _newParams[11] //  uint256 _canMintNftAfter
        );
    }

    /**
     * PRIVILEGE FUNCTION to delegate Garden voting power itself into a delegatee
     * To be used by Garden Creator only.
     * Compatible with BABL and COMP and few others ERC20Comp related tokens
     * @param _token         Address of BABL or any other ERC20Comp related governance token
     * @param _delegatee     Address to delegate token voting power into
     */
    function delegateVotes(address _token, address _delegatee) external override {
        _onlyCreator(msg.sender);
        _require(_token != address(0) && _delegatee != address(0), Errors.ADDRESS_IS_ZERO);
        IVoteToken(_token).delegate(_delegatee);
    }

    /* ============ External Getter Functions ============ */

    /* ============ Internal Functions ============ */

    /**
     *  Updates Garden params
     *
     * @param _maxDepositLimit             Max deposit limit
     * @param _minLiquidityAsset           Number that represents min amount of liquidity denominated in ETH
     * @param _depositHardlock             Number that represents the time deposits are locked for
     *                                     an user after he deposits
     * @param _minContribution             Min contribution to the garden
     * @param _strategyCooldownPeriod      How long after the strategy has been activated, will it be ready
     *                                     to be executed
     * @param _minVotesQuorum              Percentage of votes needed to activate an strategy (0.01% = 1e14, 1% = 1e16)
     * @param _minStrategyDuration         Min duration of an strategy
     * @param _maxStrategyDuration         Max duration of an strategy
     * @param _minVoters                   The minimum amount of voters needed for quorum
     * @param _pricePerShareDecayRate      Decay rate of price per share
     * @param _pricePerShareDelta          Base slippage for price per share
     * @param _canMintNftAfter             Can mint nft after secs
     */
    function _updateGardenParams(
        uint256 _maxDepositLimit,
        uint256 _minLiquidityAsset,
        uint256 _depositHardlock,
        uint256 _minContribution,
        uint256 _strategyCooldownPeriod,
        uint256 _minVotesQuorum,
        uint256 _minStrategyDuration,
        uint256 _maxStrategyDuration,
        uint256 _minVoters,
        uint256 _pricePerShareDecayRate,
        uint256 _pricePerShareDelta,
        uint256 _canMintNftAfter
    ) private {
        _require(
            _minLiquidityAsset >= controller.minLiquidityPerReserve(reserveAsset) && _minLiquidityAsset > 0,
            Errors.MIN_LIQUIDITY
        );
        _require(_depositHardlock > 0, Errors.DEPOSIT_HARDLOCK);
        _require(
            _strategyCooldownPeriod <= MAX_COOLDOWN_PERIOD && _strategyCooldownPeriod >= MIN_COOLDOWN_PERIOD,
            Errors.NOT_IN_RANGE
        );
        _require(_minVotesQuorum >= TEN_PERCENT.div(2) && _minVotesQuorum <= TEN_PERCENT.mul(5), Errors.VALUE_TOO_LOW);
        _require(
            _maxStrategyDuration >= _minStrategyDuration &&
                _minStrategyDuration >= 1 days &&
                _maxStrategyDuration <= 500 days,
            Errors.DURATION_RANGE
        );
        _require(_minVoters >= 1 && _minVoters < 10, Errors.MIN_VOTERS_CHECK);

        maxDepositLimit = _maxDepositLimit;
        minContribution = _minContribution;
        strategyCooldownPeriod = _strategyCooldownPeriod;
        minVotesQuorum = _minVotesQuorum;
        minVoters = _minVoters;
        minStrategyDuration = _minStrategyDuration;
        maxStrategyDuration = _maxStrategyDuration;
        minLiquidityAsset = _minLiquidityAsset;
        depositHardlock = _depositHardlock;
        pricePerShareDecayRate = _pricePerShareDecayRate;
        pricePerShareDelta = _pricePerShareDelta;
        canMintNftAfter = _canMintNftAfter;
    }

    // Checks if an address is a creator
    function _isCreator(address _creator) private view returns (bool) {
        return
            _creator != address(0) &&
            (extraCreators[0] == _creator ||
                extraCreators[1] == _creator ||
                extraCreators[2] == _creator ||
                extraCreators[3] == _creator ||
                _creator == creator);
    }

    // Assign extra creators
    function _assignExtraCreator(uint8 _index, address _newCreator) private {
        _require(!_isCreator(_newCreator), Errors.NEW_CREATOR_MUST_NOT_EXIST);
        _require(extraCreators[_index] == address(0), Errors.NEW_CREATOR_MUST_NOT_EXIST);
        extraCreators[_index] = _newCreator;
    }
}
