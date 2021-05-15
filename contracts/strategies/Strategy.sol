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
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/Initializable.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';

import {Errors, _require} from '../lib/BabylonErrors.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {Math} from '../lib/Math.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';

import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {ITradeIntegration} from '../interfaces/ITradeIntegration.sol';
import {IOperation} from '../interfaces/IOperation.sol';
import {IIntegration} from '../interfaces/IIntegration.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IStrategyNFT} from '../interfaces/IStrategyNFT.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';

/**
 * @title Strategy
 * @author Babylon Finance
 *
 * Base Strategy contract. Belongs to a garden. Abstract.
 * Will be extended from specific strategy contracts.
 */
contract Strategy is ReentrancyGuard, IStrategy, Initializable {
    using SignedSafeMath for int256;
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for int256;
    using SafeDecimalMath for uint256;
    using Math for int256;
    using Math for uint256;
    using AddressArrayUtils for address[];
    using Address for address;
    using SafeERC20 for IERC20;

    /* ============ Events ============ */
    event Invoked(address indexed _target, uint256 indexed _value, bytes _data, bytes _returnValue);
    event StrategyVoted(address indexed _garden, uint256 _absoluteVotes, int256 _totalVotes, uint256 _timestamp);
    event StrategyExecuted(address indexed _garden, uint256 _capital, uint256 _fee, uint256 timestamp);
    event StrategyFinalized(address indexed _garden, uint256 _capitalReturned, uint256 _fee, uint256 timestamp);
    event StrategyReduced(address indexed _garden, uint256 _amountReduced, uint256 timestamp);
    event StrategyExpired(address indexed _garden, uint256 _timestamp);
    event StrategyDeleted(address indexed _garden, uint256 _timestamp);
    event StrategyDurationChanged(uint256 _newDuration, uint256 _oldDuration);

    /* ============ Modifiers ============ */
    /**
     * Throws if the sender is not the creator of the strategy
     */
    modifier onlyGovernorOrGarden {
        _require(msg.sender == address(garden) || msg.sender == controller.owner(), Errors.ONLY_PROTOCOL_OR_GARDEN);
        _;
    }

    modifier onlyStrategist {
        _require(msg.sender == strategist, Errors.ONLY_STRATEGIST);
        _;
    }

    modifier onlyContributor {
        _require(IERC20(address(garden)).balanceOf(msg.sender) > 0, Errors.ONLY_CONTRIBUTOR);
        _;
    }

    /**
     * Throws if the sender is not a Garden's integration or integration not enabled
     */
    modifier onlyIntegration() {
        // Internal function used to reduce bytecode size
        _require(
            controller.isValidIntegration(IIntegration(msg.sender).getName(), msg.sender),
            Errors.ONLY_INTEGRATION
        );
        _;
    }

    /**
     * Throws if the sender is not a Garden's integration or integration not enabled
     */
    modifier onlyOperation() {
        bool found = false;
        for (uint8 i = 0; i < opTypes.length; i++) {
            found = found || msg.sender == controller.enabledOperations(opTypes[i]);
        }
        // Internal function used to reduce bytecode size
        _require(found, Errors.ONLY_OPERATION);
        _;
    }

    /**
     * Throws if the garden is not the caller or data is already set
     */
    modifier onlyGardenAndNotSet() {
        _require(msg.sender == address(garden) && !dataSet, Errors.ONLY_GARDEN_AND_DATA_NOT_SET);
        _;
    }

    /**
     * Throws if the garden is not active
     */
    modifier onlyActiveGarden() {
        _require(garden.active() == true, Errors.ONLY_ACTIVE_GARDEN);
        _;
    }

    /**
     * Throws if the sender is not a keeper in the protocol
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     */
    modifier onlyKeeper(uint256 _fee) {
        _require(controller.isValidKeeper(msg.sender), Errors.ONLY_KEEPER);
        // We assume that calling keeper functions should be less expensive than 1 million gas and the gas price should be lower than 1000 gwei.
        _require(_fee <= MAX_KEEPER_FEE, Errors.FEE_TOO_HIGH);
        _;
    }

    /* ============ Constants ============ */

    uint256 internal constant SLIPPAGE_ALLOWED = 5e16; // 1%
    uint256 internal constant HUNDRED_PERCENT = 1e18; // 100%
    uint256 internal constant MAX_CANDIDATE_PERIOD = 7 days;
    uint256 internal constant MIN_VOTERS_TO_BECOME_ACTIVE = 2;
    uint256 internal constant ABSOLUTE_MIN_REBALANCE = 1e18;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Max Operations
    uint256 internal constant MAX_OPERATIONS = 6;

    // Keeper max fee
    uint256 internal constant MAX_KEEPER_FEE = (1e6 * 1e3 gwei);

    // Quadratic penalty for looses
    uint256 internal constant STAKE_QUADRATIC_PENALTY_FOR_LOSSES = 175e16; // 1.75e18

    /* ============ Structs ============ */

    /* ============ State Variables ============ */

    // Babylon Controller Address
    IBabController public controller;

    // Type of operation.
    // 0 = BuyOperation
    // 1 = LiquidityOperation
    // 2 = VaultOperation
    // 3 = LendOperation

    // Asset Status
    // 0 = Liquid
    // 1 = Put as collateral
    // 2 = Borrowed
    // 3 = staked

    // Types and data for the operations of this strategy
    uint8[] public override opTypes;
    address[] public override opIntegrations;
    address[] public override opDatas;

    // Garden that these strategies belong to
    IGarden public override garden;

    address public override strategist; // Address of the strategist that submitted the bet
    address public override strategyNft; // Address of the strategy nft

    uint256 public override enteredAt; // Timestamp when the strategy was submitted
    uint256 public override enteredCooldownAt; // Timestamp when the strategy reached quorum
    uint256 public override executedAt; // Timestamp when the strategy was executed
    uint256 public override updatedAt; // Timestamp of last capital allocation update
    uint256 public override exitedAt; // Timestamp when the strategy was submitted

    address[] public voters; // Addresses with the voters
    int256 public override totalVotes; // Total votes staked
    uint256 public override absoluteTotalVotes; // Absolute number of votes staked
    uint256 public override totalPositiveVotes; // Total positive votes endorsing the strategy execution
    uint256 public override totalNegativeVotes; // Total negative votes against the strategy execution
    bool public override finalized; // Flag that indicates whether we exited the strategy
    bool public override active; // Whether the strategy has met the voting quorum
    bool public dataSet;

    uint256 public override duration; // Duration of the bet
    uint256 public override stake; // Amount of stake by the strategist (in reserve asset) needs to be positive
    uint256 public override maxCapitalRequested; // Amount of max capital to allocate
    uint256 public override capitalAllocated; // Current amount of capital allocated
    uint256 public override expectedReturn; // Expect return by this strategy
    uint256 public override capitalReturned; // Actual return by this strategy
    uint256 public override minRebalanceCapital; // Min amount of capital so that it is worth to rebalance the capital here
    address[] public tokensNeeded; // Positions that need to be taken prior to enter the strategy
    uint256[] public tokenAmountsNeeded; // Amount of these positions

    uint256 public override strategyRewards; // Rewards allocated for this strategy updated on finalized
    uint256 public override rewardsTotalOverhead; // Potential extra amount we are giving in BABL rewards

    // Voters mapped to their votes.
    mapping(address => int256) public votes;

    /* ============ Constructor ============ */

    /**
     * Initializes the strategy for a garden
     *
     * @param _strategist                    Address of the strategist
     * @param _garden                        Address of the garden
     * @param _controller                    Address of the controller
     * @param _maxCapitalRequested           Max Capital requested denominated in the reserve asset (0 to be unlimited)
     * @param _stake                         Stake with garden participations absolute amounts 1e18
     * @param _strategyDuration              Strategy duration in seconds
     * @param _expectedReturn                Expected return
     * @param _minRebalanceCapital           Min capital that makes executing the strategy worth it
     * @param _strategyNft                   Address of the strategy nft
     */
    function initialize(
        address _strategist,
        address _garden,
        address _controller,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _strategyDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital,
        address _strategyNft
    ) external override initializer {
        controller = IBabController(_controller);

        _require(controller.isSystemContract(_garden), Errors.NOT_A_GARDEN);
        garden = IGarden(_garden);
        uint256 strategistUnlockedBalance =
            IERC20(address(garden)).balanceOf(_strategist).sub(garden.getLockedBalance(_strategist));
        _require(IERC20(address(garden)).balanceOf(_strategist) > 0, Errors.STRATEGIST_TOKENS_TOO_LOW);
        _require(strategistUnlockedBalance >= _stake, Errors.TOKENS_STAKED);
        // TODO: adjust this calc
        _require(_stake > 0, Errors.STAKE_HAS_TO_AT_LEAST_ONE);
        _require(
            _strategyDuration >= garden.minStrategyDuration() && _strategyDuration <= garden.maxStrategyDuration(),
            Errors.DURATION_MUST_BE_IN_RANGE
        );
        _require(_minRebalanceCapital >= ABSOLUTE_MIN_REBALANCE, Errors.MIN_REBALANCE_CAPITAL);
        _require(_maxCapitalRequested >= _minRebalanceCapital, Errors.MAX_CAPITAL_REQUESTED);
        _require(_strategyNft != address(0), Errors.NOT_STRATEGY_NFT);

        strategyNft = _strategyNft;

        strategist = _strategist;
        enteredAt = block.timestamp;
        stake = _stake;
        duration = _strategyDuration;
        expectedReturn = _expectedReturn;
        capitalAllocated = 0;
        minRebalanceCapital = _minRebalanceCapital;
        maxCapitalRequested = _maxCapitalRequested;
        totalVotes = _stake.toInt256();
        votes[_strategist] = _stake.toInt256();
        absoluteTotalVotes = _stake;
        dataSet = false;
    }

    /* ============ External Functions ============ */

    /**
     * Sets the data for the operations of this strategy
     * @param _opTypes                    An array with the op types
     * @param _opIntegrations             Addresses with the integration for each op
     * @param _opDatas                    Bytes with the params for the op in the same position in the opTypes array
     */
    function setData(
        uint8[] calldata _opTypes,
        address[] calldata _opIntegrations,
        address[] calldata _opDatas
    ) external override onlyGardenAndNotSet {
        _require(
            (_opTypes.length == _opIntegrations.length) && (_opIntegrations.length == _opDatas.length),
            Errors.TOO_MANY_OPS
        );
        _require(_opDatas.length < MAX_OPERATIONS && _opDatas.length > 0, Errors.TOO_MANY_OPS);
        for (uint256 i = 0; i < _opTypes.length; i++) {
            IOperation(controller.enabledOperations(_opTypes[i])).validateOperation(
                _opDatas[i],
                garden,
                _opIntegrations[i],
                i
            );
            _require(
                controller.isValidIntegration(IIntegration(_opIntegrations[i]).getName(), _opIntegrations[i]),
                Errors.ONLY_INTEGRATION
            );
        }

        opTypes = _opTypes;
        opIntegrations = _opIntegrations;
        opDatas = _opDatas;
        dataSet = true;
    }

    /**
     * Adds off-chain voting results on-chain.
     * @param _voters                  An array of garden member who voted on strategy.
     * @param _votes                   An array of votes by on strategy by garden members.
     *                                 Votes can be positive or negative.
     * @param _absoluteTotalVotes      Absolute number of votes. _absoluteTotalVotes = abs(upvotes) + abs(downvotes).
     * @param _totalVotes              Total number of votes. _totalVotes = upvotes + downvotes.
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     */
    function resolveVoting(
        address[] calldata _voters,
        int256[] calldata _votes,
        uint256 _absoluteTotalVotes,
        int256 _totalVotes,
        uint256 _fee
    ) external override onlyKeeper(_fee) onlyActiveGarden {
        _require(
            _voters.length >= (garden.totalContributors() == 1 ? 1 : MIN_VOTERS_TO_BECOME_ACTIVE),
            Errors.MIN_VOTERS_CHECK
        );
        _require(!active && !finalized, Errors.VOTES_ALREADY_RESOLVED);
        _require(block.timestamp.sub(enteredAt) <= MAX_CANDIDATE_PERIOD, Errors.VOTING_WINDOW_IS_OVER);
        active = true;

        // Set votes data
        for (uint256 i = 0; i < _voters.length; i++) {
            votes[_voters[i]] = _votes[i];
        }
        totalPositiveVotes = _absoluteTotalVotes.toInt256().add(_totalVotes).div(2).toUint256();
        totalNegativeVotes = _absoluteTotalVotes.toInt256().sub(_totalVotes).div(2).toUint256();
        voters = _voters;
        absoluteTotalVotes = absoluteTotalVotes + _absoluteTotalVotes;
        totalVotes = totalVotes + _totalVotes;

        // Initializes cooldown
        enteredCooldownAt = block.timestamp;
        emit StrategyVoted(address(garden), _absoluteTotalVotes, _totalVotes, block.timestamp);
        garden.payKeeper(msg.sender, _fee);
    }

    /**
     * Executes an strategy that has been activated and gone through the cooldown period.
     * Keeper will validate that quorum is reached, cacluates all the voting data and push it.
     * @param _capital                  The capital to allocate to this strategy.
     * @param _fee                      The fee paid to keeper to compensate the gas cost.
     */
    function executeStrategy(uint256 _capital, uint256 _fee)
        external
        override
        onlyKeeper(_fee)
        nonReentrant
        onlyActiveGarden
    {
        _require(active, Errors.STRATEGY_NEEDS_TO_BE_ACTIVE);
        _require(capitalAllocated.add(_capital) <= maxCapitalRequested, Errors.MAX_CAPITAL_REACHED);
        _require(_capital >= minRebalanceCapital, Errors.CAPITAL_IS_LESS_THAN_REBALANCE);
        _require(
            block.timestamp.sub(enteredCooldownAt) >= garden.strategyCooldownPeriod(),
            Errors.STRATEGY_IN_COOLDOWN
        );

        // Execute enter operation
        garden.allocateCapitalToStrategy(_capital);
        capitalAllocated = capitalAllocated.add(_capital);
        _enterStrategy(_capital);

        // Add to Rewards Distributor an update of the Protocol Principal for BABL Mining Rewards calculations
        IRewardsDistributor rewardsDistributor = IRewardsDistributor(IBabController(controller).rewardsDistributor());
        // Sets the executed timestamp on first execution
        if (executedAt == 0) {
            executedAt = block.timestamp;
        } else {
            // Updating allocation - we need to consider the difference for the calculation
            // We control the potential overhead in BABL Rewards calculations to keep control
            // and avoid distributing a wrong number (e.g. flash loans)
            if (_hasMiningStarted()) {
                // The Mining program has not started on time for this strategy
                rewardsTotalOverhead = rewardsTotalOverhead.add(_capital.mul(block.timestamp.sub(updatedAt)));
            }
        }
        if (_hasMiningStarted()) {
            // The Mining program has not started on time for this strategy
            rewardsDistributor.addProtocolPrincipal(_capital);
        }
        garden.payKeeper(msg.sender, _fee);
        updatedAt = block.timestamp;
        emit StrategyExecuted(address(garden), _capital, _fee, block.timestamp);
    }

    /**
     * Exits from an executed strategy.
     * Returns balance back to the garden and sets the capital aside for withdrawals in ETH.
     * Pays the keeper.
     * Updates the reserve asset position accordingly.
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     * @param _tokenURI                URL with the JSON for the strategy
     */
    function finalizeStrategy(uint256 _fee, string memory _tokenURI)
        external
        override
        onlyKeeper(_fee)
        nonReentrant
        onlyActiveGarden
    {
        _require(executedAt > 0, Errors.STRATEGY_IS_NOT_EXECUTED);
        _require(block.timestamp > executedAt.add(duration), Errors.STRATEGY_IS_NOT_OVER_YET);
        _require(!finalized, Errors.STRATEGY_IS_ALREADY_FINALIZED);
        // Execute exit operations
        _exitStrategy(HUNDRED_PERCENT);
        // Mark as finalized
        finalized = true;
        active = false;
        exitedAt = block.timestamp;
        updatedAt = exitedAt;
        // Mint NFT
        IStrategyNFT(strategyNft).grantStrategyNFT(strategist, _tokenURI);
        // Pay Keeper Fee
        garden.payKeeper(msg.sender, _fee);
        // Transfer rewards
        _transferStrategyPrincipal(_fee);
        // Send rest to garden if any
        _sendReserveAssetToGarden();
        emit StrategyFinalized(address(garden), capitalReturned, _fee, block.timestamp);
    }

    /**
     * Partially unwinds an strategy.
     * Triggered from an immediate withdraw in the Garden.
     * @param _amountToUnwind              The amount of capital to unwind
     */
    function unwindStrategy(uint256 _amountToUnwind) external override onlyGovernorOrGarden nonReentrant {
        _require(active && !finalized, Errors.STRATEGY_NEEDS_TO_BE_ACTIVE);
        _require(_amountToUnwind <= capitalAllocated.sub(minRebalanceCapital), Errors.STRATEGY_NO_CAPITAL_TO_UNWIND);
        // Exits and enters the strategy
        _exitStrategy(_amountToUnwind.preciseDiv(capitalAllocated));
        updatedAt = block.timestamp;
        capitalAllocated = capitalAllocated.sub(_amountToUnwind);
        // Removes protocol principal for the calculation of rewards
        IRewardsDistributor rewardsDistributor = IRewardsDistributor(IBabController(controller).rewardsDistributor());
        if (_hasMiningStarted()) {
            // Only if the Mining program started on time for this strategy
            rewardsDistributor.substractProtocolPrincipal(_amountToUnwind);
        }
        // Send the amount back to the warden for the immediate withdrawal
        // TODO: Transfer the precise value; not entire balance
        IERC20(garden.reserveAsset()).safeTransfer(
            address(garden),
            IERC20(garden.reserveAsset()).balanceOf(address(this))
        );
        emit StrategyReduced(address(garden), _amountToUnwind, block.timestamp);
    }

    /**
     * Expires a candidate that has spent more than CANDIDATE_PERIOD without
     * reaching quorum
     * @param _fee              The keeper fee
     */
    function expireStrategy(uint256 _fee) external onlyKeeper(_fee) nonReentrant onlyActiveGarden {
        _require(!active, Errors.STRATEGY_NEEDS_TO_BE_INACTIVE);
        _require(block.timestamp.sub(enteredAt) > MAX_CANDIDATE_PERIOD, Errors.VOTING_WINDOW_IS_OPENED);
        // pay keeper before expiring strategy
        garden.payKeeper(msg.sender, _fee);
        _deleteCandidateStrategy();
        emit StrategyExpired(address(garden), block.timestamp);
    }

    /**
     * Delete a candidate strategy by the strategist
     */
    function deleteCandidateStrategy() external onlyStrategist {
        _deleteCandidateStrategy();
        emit StrategyDeleted(address(garden), block.timestamp);
    }

    /**
     * Lets the strategist change the duration of the strategy
     * @param _newDuration            New duration of the strategy
     */
    function changeStrategyDuration(uint256 _newDuration) external override onlyStrategist {
        _require(!finalized, Errors.STRATEGY_IS_ALREADY_FINALIZED);
        _require(_newDuration < duration, Errors.DURATION_NEEDS_TO_BE_LESS);
        _require(_newDuration >= garden.minStrategyDuration(), Errors.DURATION_NEEDS_TO_BE_LESS);
        emit StrategyDurationChanged(_newDuration, duration);
        duration = _newDuration;
    }

    /**
     * Any tokens (other than the target) that are sent here by mistake are recoverable by contributors
     * Converts it to the reserve asset and sends it to the garden.
     * @param _token             Address of the token to sweep
     */
    function sweep(address _token) external onlyContributor {
        _require(_token != garden.reserveAsset(), Errors.CANNOT_SWEEP_RESERVE_ASSET);
        _require(!active, Errors.STRATEGY_NEEDS_TO_BE_INACTIVE);

        uint256 balance = IERC20(_token).balanceOf(address(this));
        _require(balance > 0, Errors.BALANCE_TOO_LOW);

        _trade(_token, balance, garden.reserveAsset());
        // Send reserve asset to garden
        _sendReserveAssetToGarden();
    }

    /**
     * Helper to invoke Approve on ERC20 from integrations in the strategy context
     */
    function invokeApprove(
        address _spender,
        address _asset,
        uint256 _quantity
    ) external override onlyIntegration {
        IERC20(_asset).approve(_spender, _quantity);
    }

    /**
     * Helper to invoke a call to an external contract from integrations in the strategy context
     * @param _target                 Address of the smart contract to call
     * @param _value                  Quantity of Ether to provide the call (typically 0)
     * @param _data                   Encoded function selector and arguments
     * @return _returnValue           Bytes encoded return value
     */
    function invokeFromIntegration(
        address _target,
        uint256 _value,
        bytes calldata _data
    ) external override onlyIntegration returns (bytes memory) {
        return _invoke(_target, _value, _data);
    }

    /**
     * Function that calculates the price using the oracle and executes a trade.
     * Must call the exchange to get the price and pass minReceiveQuantity accordingly.
     * @param _sendToken                    Token to exchange
     * @param _sendQuantity                 Amount of tokens to send
     * @param _receiveToken                 Token to receive
     */
    function trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken
    ) external override onlyOperation returns (uint256) {
        return _trade(_sendToken, _sendQuantity, _receiveToken);
    }

    /**
     * Deposits or withdraws weth from an operation in this context
     * @param _isDeposit                    Wether is a deposit or withdraw
     * @param _wethAmount                   Amount to deposit or withdraw
     */
    function handleWeth(bool _isDeposit, uint256 _wethAmount) external override onlyOperation {
        if (_isDeposit) {
            IWETH(WETH).deposit{value: _wethAmount}();
            return;
        }
        IWETH(WETH).withdraw(_wethAmount);
    }

    /* ============ External Getter Functions ============ */

    /**
     * Returns whether this strategy is currently active or not
     */
    function isStrategyActive() public view override returns (bool) {
        return executedAt > 0 && exitedAt == 0;
    }

    /**
     * Returns the number of operations in this strategy
     */
    function getOperationsCount() external view override returns (uint256) {
        return opTypes.length;
    }

    /**
     * Get the non-state related details of a Strategy
     *
     */
    function getStrategyDetails()
        external
        view
        override
        returns (
            address,
            address,
            uint256,
            uint256,
            uint256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            address,
            uint256
        )
    {
        return (
            address(this),
            strategist,
            opIntegrations.length,
            stake,
            absoluteTotalVotes,
            totalVotes,
            capitalAllocated,
            capitalReturned,
            duration,
            expectedReturn,
            maxCapitalRequested,
            minRebalanceCapital,
            strategyNft,
            enteredAt
        );
    }

    /**
     * Get the state of a Strategy
     *
     */
    function getStrategyState()
        external
        view
        override
        returns (
            address,
            bool,
            bool,
            bool,
            uint256,
            uint256,
            uint256
        )
    {
        return (address(this), active, dataSet, finalized, executedAt, exitedAt, updatedAt);
    }

    /**
     * Get the operation params by index
     *
     */
    function getOperationByIndex(uint8 _index)
        external
        view
        override
        returns (
            uint8,
            address,
            address
        )
    {
        return (opTypes[_index], opIntegrations[_index], opDatas[_index]);
    }

    /**
     * Gets the NAV of assets under management.
     * It is the sum of the NAV of all the operations
     *
     * @return _nav           NAV of the strategy
     */
    function getNAV() public view override returns (uint256) {
        uint256 nav = 0;
        for (uint256 i = 0; i < opTypes.length; i++) {
            IOperation operation = IOperation(IBabController(controller).enabledOperations(uint256(opTypes[i])));
            nav = nav.add(operation.getNAV(opDatas[i], garden, opIntegrations[i]));
        }
        return nav;
    }

    /**
     * Gets the votes casted by the contributor in this strategy
     *
     * @param _address           Address of the contributor
     * @return _votes            Number of votes cast
     */
    function getUserVotes(address _address) external view override returns (int256) {
        return votes[_address];
    }

    /* ============ Internal Functions ============ */

    /**
     * Enters the strategy.
     * Executes all the operations in order
     * @param _capital  Amount of capital that the strategy receives
     */
    function _enterStrategy(uint256 _capital) internal {
        uint256 capitalForNexOperation = _capital;
        address assetAccumulated = garden.reserveAsset();
        uint8 assetStatus = 0; // liquid
        for (uint256 i = 0; i < opTypes.length; i++) {
            IOperation operation = IOperation(IBabController(controller).enabledOperations(opTypes[i]));
            (assetAccumulated, capitalForNexOperation, assetStatus) = operation.executeOperation(
                assetAccumulated,
                capitalForNexOperation,
                assetStatus,
                opDatas[i],
                garden,
                opIntegrations[i]
            );
        }
    }

    /**
     * Exits the strategy.
     * Exists all the operations starting by the end.
     * @param _percentage of capital to exit from the strategy
     */
    function _exitStrategy(uint256 _percentage) internal {
        for (uint256 i = opTypes.length; i > 0; i--) {
            IOperation operation = IOperation(IBabController(controller).enabledOperations(opTypes[i - 1]));
            operation.exitOperation(_percentage, opDatas[i - 1], garden, opIntegrations[i - 1]);
        }
    }

    /**
     * Deletes this strategy and returns the stake to the strategist
     */
    function _deleteCandidateStrategy() internal {
        _require(executedAt == 0, Errors.STRATEGY_IS_EXECUTED);
        _require(!finalized, Errors.STRATEGY_IS_ALREADY_FINALIZED);

        IGarden(garden).expireCandidateStrategy(address(this));
        // TODO: Call selfdestruct??
    }

    /**
     * Low level function that allows an integration to make an arbitrary function
     * call to any contract from the garden (garden as msg.sender).
     *
     * @param _target                 Address of the smart contract to call
     * @param _value                  Quantity of Ether to provide the call (typically 0)
     * @param _data                   Encoded function selector and arguments
     * @return _returnValue           Bytes encoded return value
     */
    function _invoke(
        address _target,
        uint256 _value,
        bytes memory _data
    ) internal returns (bytes memory _returnValue) {
        _returnValue = _target.functionCallWithValue(_data, _value);
        emit Invoked(_target, _value, _data, _returnValue);
        return _returnValue;
    }

    function _sendReserveAssetToGarden() private {
        uint256 remainingReserve = IERC20(garden.reserveAsset()).balanceOf(address(this));
        // Sends the rest back if any
        IERC20(garden.reserveAsset()).safeTransfer(address(garden), remainingReserve);
    }

    /**
     * Function that calculates the price using the oracle and executes a trade.
     * Must call the exchange to get the price and pass minReceiveQuantity accordingly.
     * @param _sendToken                    Token to exchange
     * @param _sendQuantity                 Amount of tokens to send
     * @param _receiveToken                 Token to receive
     */
    function _trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken
    ) internal returns (uint256) {
        address tradeIntegration = IBabController(controller).defaultTradeIntegration();
        // Uses on chain oracle for all internal strategy operations to avoid attacks        // Updates UniSwap TWAP
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        oracle.updateAdapters(_sendToken, _receiveToken);
        uint256 pricePerTokenUnit = oracle.getPrice(_sendToken, _receiveToken);
        uint256 exactAmount = _sendQuantity.preciseMul(pricePerTokenUnit);
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
        ITradeIntegration(tradeIntegration).trade(
            address(this),
            _sendToken,
            _sendQuantity,
            _receiveToken,
            minAmountExpected
        );
        return minAmountExpected;
    }

    function _transferStrategyPrincipal(uint256 _fee) internal {
        capitalReturned = IERC20(garden.reserveAsset()).balanceOf(address(this)).sub(_fee);
        address reserveAsset = garden.reserveAsset();
        int256 reserveAssetDelta = capitalReturned.toInt256().sub(capitalAllocated.toInt256());
        uint256 protocolProfits = 0;
        // Strategy returns were positive
        uint256 profits = capitalReturned > capitalAllocated ? capitalReturned.sub(capitalAllocated) : 0; // in reserve asset (weth)
        if (capitalReturned >= capitalAllocated) {
            // Send weth performance fee to the protocol
            protocolProfits = IBabController(controller).protocolPerformanceFee().preciseMul(profits);
            IERC20(reserveAsset).safeTransferFrom(
                address(this),
                IBabController(controller).treasury(),
                protocolProfits
            );
            reserveAssetDelta = reserveAssetDelta.add(int256(-protocolProfits));
        } else {
            // Returns were negative
            // Burn strategist stake and add the amount to the garden
            uint256 burningAmount =
                (stake.sub(capitalReturned.preciseDiv(capitalAllocated).preciseMul(stake))).multiplyDecimal(
                    STAKE_QUADRATIC_PENALTY_FOR_LOSSES
                );
            if (IERC20(address(garden)).balanceOf(strategist) < burningAmount) {
                // Avoid underflow burning more than its balance
                burningAmount = IERC20(address(garden)).balanceOf(strategist);
            }

            garden.burnStrategistStake(strategist, burningAmount);
            reserveAssetDelta = reserveAssetDelta.add(int256(burningAmount));
        }
        // Return the balance back to the garden
        IERC20(reserveAsset).safeTransferFrom(address(this), address(garden), capitalReturned.sub(protocolProfits));
        // Start a redemption window in the garden with the capital plus the profits for the lps
        (, , uint256 lpsProfitSharing) = IBabController(controller).getProfitSharing();
        garden.startWithdrawalWindow(
            capitalReturned.sub(profits).add((profits).preciseMul(lpsProfitSharing)),
            profits.sub(profits.preciseMul(lpsProfitSharing)).sub(protocolProfits),
            reserveAssetDelta,
            address(this)
        );
        IRewardsDistributor rewardsDistributor = IRewardsDistributor(IBabController(controller).rewardsDistributor());
        // Substract the Principal in the Rewards Distributor to update the Protocol power value
        if (_hasMiningStarted()) {
            // Only if the Mining program started on time for this strategy
            rewardsDistributor.substractProtocolPrincipal(capitalAllocated);
        }
        strategyRewards = rewardsDistributor.getStrategyRewards(address(this)); // Must be zero in case the mining program didnt started on time
    }

    function _getPrice(address _assetOne, address _assetTwo) internal view returns (uint256) {
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        return oracle.getPrice(_assetOne, _assetTwo);
    }

    function _hasMiningStarted() internal view returns (bool) {
        IRewardsDistributor rewardsDistributor = IRewardsDistributor(IBabController(controller).rewardsDistributor());
        uint256 rewardsStartTime = rewardsDistributor.START_TIME();
        bool miningStarted = ((enteredAt > rewardsStartTime) && (rewardsStartTime != 0));
        return miningStarted;
    }

    // solhint-disable-next-line
    receive() external payable {}
}
