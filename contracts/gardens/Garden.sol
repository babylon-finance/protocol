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

pragma solidity 0.7.4;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {ERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import {SafeERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {Safe3296} from '../lib/Safe3296.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';

import {Errors, _require} from '../lib/BabylonErrors.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';

import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IStrategyFactory} from '../interfaces/IStrategyFactory.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';

/**
 * @title BaseGarden
 * @author Babylon Finance
 *
 * Class that holds common garden-related state and functions
 */
contract Garden is ERC20Upgradeable, ReentrancyGuard {
    using SafeCast for int256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using SafeDecimalMath for int256;

    using SafeCast for uint256;
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    using Address for address;
    using AddressArrayUtils for address[];

    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ============ Events ============ */
    event ReserveAssetChanged(address indexed _reserveAsset, address _oldReserve);
    event PrincipalChanged(uint256 _newAmount, uint256 _oldAmount);
    event GardenDeposit(
        address indexed _to,
        uint256 reserveDeposited,
        uint256 gardenTokenQuantity,
        uint256 protocolFees,
        uint256 timestamp
    );
    event GardenWithdrawal(
        address indexed _from,
        address indexed _to,
        uint256 reserveReceived,
        uint256 gardenTokenQuantity,
        uint256 protocolFees,
        uint256 timestamp
    );

    event ProfitsForContributor(address indexed _contributor, uint256 indexed _amount);
    event BABLRewardsForContributor(address indexed _contributor, uint96 _rewards);

    /* ============ Modifiers ============ */
    modifier onlyContributor {
        _require(balanceOf(msg.sender) > 0, Errors.ONLY_CONTRIBUTOR);
        _;
    }

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyProtocol() {
        _require(msg.sender == controller, Errors.ONLY_CONTROLLER);
        _;
    }

    /**
     * Throws if the sender is not the garden creator
     */
    modifier onlyCreator() {
        _require(msg.sender == creator, Errors.ONLY_CREATOR);
        _;
    }

    /**
     * Throws if the sender is not a keeper in the protocol
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     */
    modifier onlyKeeper(uint256 _fee) {
        _require(IBabController(controller).isValidKeeper(msg.sender), Errors.ONLY_KEEPER);
        // We assume that calling keeper functions should be less expensive
        // than 1 million gas and the gas price should be lower than 1000 gwei.
        _require(_fee < MAX_KEEPER_FEE, Errors.FEE_TOO_HIGH);
        _;
    }

    /**
     * Throws if the sender is not an strategy of this garden
     */
    modifier onlyStrategy() {
        _require(strategyMapping[msg.sender], Errors.ONLY_STRATEGY);
        _;
    }

    /**
     * Throws if the sender is not an strategy or the protocol
     */
    modifier onlyStrategyOrProtocol() {
        _require(
            (strategyMapping[msg.sender] && IStrategy(msg.sender).garden() == address(this)) ||
                msg.sender == controller,
            Errors.ONLY_STRATEGY_OR_CONTROLLER
        );
        _;
    }

    /**
     * Throws if the garden is not active
     */
    modifier onlyActive() {
        _require(active, Errors.ONLY_ACTIVE);
        _;
    }

    /**
     * Throws if the garden is not disabled
     */
    modifier onlyInactive() {
        _require(!active, Errors.ONLY_INACTIVE);
        _;
    }

    /* ============ State Constants ============ */

    uint256 public constant MAX_DEPOSITS_FUND_V1 = 1e21; // Max deposit per garden is 1000 eth for v1
    uint256 public constant MAX_TOTAL_STRATEGIES = 20; // Max number of strategies
    uint256 internal constant TEN_PERCENT = 1e17;
    uint256 internal constant MAX_KEEPER_FEE = (1e6 * 1e3 gwei);

    /* ============ Structs ============ */

    struct Contributor {
        uint256 lastDepositAt;
        uint256 initialDepositAt;
        uint256 claimedAt;
        uint256 claimedBABL;
        uint256 claimedProfits;
        uint256[] timeListPointer;
        uint256 pid;
        uint256 lastUpdated;
        mapping(uint256 => TimestampContribution) tsContributions;
    }

    struct TimestampContribution {
        uint256 principal;
        uint256 timestamp;
        uint256 timePointer;
        uint256 power;
    }

    struct ActionInfo {
        // During withdrawal, represents post-premium value
        uint256 protocolFees; // Total protocol fees (direct + manager revenue share)
        uint256 netFlowQuantity; // When issuing, quantity of reserve asset sent to Garden
        // When withdrawaling, quantity of reserve asset sent to withdrawaler
        uint256 gardenTokenQuantity; // When issuing, quantity of Garden tokens minted to mintee
        // When withdrawaling, quantity of Garden tokens withdrawaled
        uint256 newGardenTokenSupply; // Garden token supply after deposit/withdrawal action
    }

    /* ============ State Variables ============ */

    // Wrapped ETH address
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 public constant EARLY_WITHDRAWAL_PENALTY = 15e16;

    // Reserve Asset of the garden
    address public reserveAsset;

    // Address of the controller
    address public controller;
    // The person that creates the garden
    address public creator;
    // Whether the garden is currently active or not
    bool public active;

    // Keeps track of the reserve balance. In case we receive some through other means
    uint256 public principal;
    int256 public absoluteReturns; // Total profits or losses of this garden

    // Indicates the minimum liquidity the asset needs to have to be tradable by this garden
    uint256 public minLiquidityAsset;

    uint256 public depositHardlock; // Window of time after deposits when withdraws are disabled for that user
    // Window of time after an investment strategy finishes when the capital is available for withdrawals
    uint256 public withdrawalWindowAfterStrategyCompletes;
    uint256 public withdrawalsOpenUntil; // Indicates until when the withdrawals are open and the ETH is set aside

    // Contributors
    mapping(address => Contributor) public contributors;
    uint256 public totalContributors;
    uint256 public maxDepositLimit; // Limits the amount of deposits

    uint256 public gardenInitializedAt; // Garden Initialized at timestamp

    // Min contribution in the garden
    uint256 public minContribution = 1e18; //wei
    uint256 public minGardenTokenSupply;

    // Strategies variables
    uint256 public totalStake = 0;
    uint256 public minVotersQuorum = TEN_PERCENT; // 10%. (0.01% = 1e14, 1% = 1e16)
    uint256 public minStrategyDuration; // Min duration for an strategy
    uint256 public maxStrategyDuration; // Max duration for an strategy
    uint256 public strategyCooldownPeriod; // Window for the strategy to cooldown after approval before receiving capital

    address[] public strategies; // Strategies that are either in candidate or active state
    address[] public finalizedStrategies; // Strategies that have finalized execution
    mapping(address => bool) public strategyMapping;

    /* ============ Constructor ============ */

    /**
     * When a new Garden is created.
     * All parameter validations are on the BabController contract. Validations are performed already on the
     * BabController.
     *
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _controller             Address of the controller
     * @param _creator                Address of the creator
     * @param _name                   Name of the Garden
     * @param _symbol                 Symbol of the Garden
     */
    function initialize(
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol
    ) public virtual initializer {
        _require(_creator != address(0), Errors.ADDRESS_IS_ZERO);
        _require(_controller != address(0), Errors.ADDRESS_IS_ZERO);
        _require(_reserveAsset != address(0), Errors.ADDRESS_IS_ZERO);
        _require(IBabController(_controller).isValidReserveAsset(_reserveAsset), Errors.MUST_BE_RESERVE_ASSET);
        __ERC20_init(_name, _symbol);

        controller = _controller;
        reserveAsset = _reserveAsset;
        creator = _creator;
        principal = 0;
        active = false;
        totalContributors = 0;
    }

    /* ============ External Functions ============ */

    /**
     * FUND LEAD ONLY.  Starts the Garden with allowed reserve assets,
     * fees and issuance premium. Only callable by the Garden's creator
     *
     * @param _maxDepositLimit                     Max deposit limit
     * @param _minGardenTokenSupply             Min garden token supply
     * @param _minLiquidityAsset                   Number that represents min amount of liquidity denominated in ETH
     * @param _depositHardlock                     Number that represents the time deposits are locked for an user after he deposits
     * @param _minContribution        Min contribution to the garden
     * @param _strategyCooldownPeriod               How long after the strategy has been activated, will it be ready to be executed
     * @param _minVotersQuorum                  Percentage of votes needed to activate an strategy (0.01% = 1e14, 1% = 1e16)
     * @param _minStrategyDuration                  Min duration of an strategy
     * @param _maxStrategyDuration                  Max duration of an strategy
     */
    function start(
        uint256 _maxDepositLimit,
        uint256 _minGardenTokenSupply,
        uint256 _minLiquidityAsset,
        uint256 _depositHardlock,
        uint256 _minContribution,
        uint256 _strategyCooldownPeriod,
        uint256 _minVotersQuorum,
        uint256 _minStrategyDuration,
        uint256 _maxStrategyDuration
    ) external payable onlyCreator onlyInactive {
        _require(_maxDepositLimit <= MAX_DEPOSITS_FUND_V1, Errors.MAX_DEPOSIT_LIMIT);

        _require(msg.value >= minContribution, Errors.MIN_CONTRIBUTION);
        IBabController babController = IBabController(controller);
        _require(_minGardenTokenSupply > 0, Errors.MIN_TOKEN_SUPPLY);
        _require(_depositHardlock > 0, Errors.DEPOSIT_HARDLOCK);
        _require(_minLiquidityAsset >= babController.minRiskyPairLiquidityEth(), Errors.MIN_LIQUIDITY);
        // make initial deposit
        _require(msg.value >= _minGardenTokenSupply, Errors.MIN_LIQUIDITY);
        _require(msg.value <= _maxDepositLimit, Errors.MAX_DEPOSIT_LIMIT);
        _require(
            _strategyCooldownPeriod <= IBabController(controller).getMaxCooldownPeriod() &&
                _strategyCooldownPeriod >= IBabController(controller).getMinCooldownPeriod(),
            Errors.NOT_IN_RANGE
        );
        _require(_minVotersQuorum >= TEN_PERCENT, Errors.VALUE_TOO_LOW);
        minContribution = _minContribution;
        strategyCooldownPeriod = _strategyCooldownPeriod;
        minVotersQuorum = _minVotersQuorum;
        minStrategyDuration = _minStrategyDuration;
        maxStrategyDuration = _maxStrategyDuration;
        minGardenTokenSupply = _minGardenTokenSupply;
        maxDepositLimit = _maxDepositLimit;
        gardenInitializedAt = block.timestamp;
        minLiquidityAsset = _minLiquidityAsset;
        depositHardlock = _depositHardlock;
        withdrawalWindowAfterStrategyCompletes = 7 days;

        // Deposit
        IWETH(WETH).deposit{value: msg.value}();

        uint256 previousBalance = balanceOf(msg.sender);
        _mint(creator, msg.value);
        _updateContributorDepositInfo(previousBalance);
        _updatePrincipal(msg.value);

        _require(totalSupply() > 0, Errors.MIN_LIQUIDITY);
        active = true;
        emit GardenDeposit(msg.sender, msg.value, msg.value, 0, block.timestamp);
    }

    /**
     * Deposits the reserve asset into the garden and mints the Garden token of the given quantity
     * to the specified _to address.
     *
     * @param _reserveAssetQuantity  Quantity of the reserve asset that are received
     * @param _minGardenTokenReceiveQuantity   Min quantity of Garden token to receive after issuance
     * @param _to                   Address to mint Garden tokens to
     */
    function deposit(
        uint256 _reserveAssetQuantity,
        uint256 _minGardenTokenReceiveQuantity,
        address _to
    ) public payable nonReentrant onlyActive {
        _require(msg.value >= minContribution, Errors.MIN_CONTRIBUTION);
        // if deposit limit is 0, then there is no deposit limit
        if (maxDepositLimit > 0) {
            _require(principal.add(msg.value) <= maxDepositLimit, Errors.MAX_DEPOSIT_LIMIT);
        }
        _require(msg.value == _reserveAssetQuantity, Errors.MSG_VALUE_DO_NOT_MATCH);
        // Always wrap to WETH
        IWETH(WETH).deposit{value: msg.value}();
        // Check this here to avoid having relayers
        reenableEthForStrategies();

        _validateReserveAsset(reserveAsset, _reserveAssetQuantity);

        ActionInfo memory depositInfo = _createIssuanceInfo(_reserveAssetQuantity);

        // Check that total supply is greater than min supply needed for issuance
        // TODO: A min supply amount is needed to avoid division by 0 when Garden token supply is 0
        _require(totalSupply() >= minGardenTokenSupply, Errors.MIN_TOKEN_SUPPLY);

        // gardenTokenQuantity has to be at least _minGardenTokenReceiveQuantity
        _require(depositInfo.gardenTokenQuantity >= _minGardenTokenReceiveQuantity, Errors.MIN_TOKEN_SUPPLY);

        // Send Protocol Fee
        payProtocolFeeFromGarden(reserveAsset, depositInfo.protocolFees);

        // Updates Reserve Balance and Mint
        uint256 previousBalance = balanceOf(msg.sender);
        _mint(_to, depositInfo.gardenTokenQuantity);
        _updateContributorDepositInfo(previousBalance);
        _updatePrincipal(principal.add(depositInfo.netFlowQuantity));
        emit GardenDeposit(_to, msg.value, depositInfo.gardenTokenQuantity, depositInfo.protocolFees, block.timestamp);
    }

    /**
     * Withdraws the ETH relative to the token participation in the garden and sends it back to the sender.
     *
     * @param _gardenTokenQuantity             Quantity of the garden token to withdrawal
     * @param _minReserveReceiveQuantity     Min quantity of reserve asset to receive
     * @param _to                            Address to send component assets to
     */
    function withdraw(
        uint256 _gardenTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) external nonReentrant onlyContributor {
        _withdraw(_gardenTokenQuantity, _minReserveReceiveQuantity, _to);
    }

    /**
     * Requests an immediate withdrawal taking the EARLY_WITHDRAWAL_PENALTY that stays invested.
     *
     * @param _gardenTokenQuantity              Quantity of the garden token to withdrawal
     * @param _to                               Address to send component assets to
     */
    function withdrawWithPenalty(uint256 _gardenTokenQuantity, address payable _to)
        external
        nonReentrant
        onlyContributor
    {
        // Check that cannot do a normal withdrawal
        _require(!canWithdrawEthAmount(msg.sender, _gardenTokenQuantity), Errors.NORMAL_WITHDRAWAL_POSSIBLE);
        uint256 netReserveFlows = _gardenTokenQuantity.sub(_gardenTokenQuantity.preciseMul(EARLY_WITHDRAWAL_PENALTY));
        (, uint256 largestCapital, address maxStrategy) = getActiveCapital();
        // Check that strategy has enough capital to support the withdrawal
        require(IStrategy(maxStrategy).minRebalanceCapital() <= largestCapital.sub(netReserveFlows));
        IStrategy(maxStrategy).unwindStrategy(netReserveFlows);
        // We burn their penalty
        _burn(msg.sender, _gardenTokenQuantity.preciseMul(EARLY_WITHDRAWAL_PENALTY));
        _withdraw(_gardenTokenQuantity, netReserveFlows, _to);
    }

    /**
     * User can claim the profits from the strategies that his principal
     * was invested in.
     */
    function claimReturns(address[] calldata _finalizedStrategies) external nonReentrant onlyContributor {
        Contributor storage contributor = contributors[msg.sender];
        _require(block.timestamp > contributor.claimedAt, Errors.ALREADY_CLAIMED); // race condition check

        (uint256 totalProfits, uint256 bablRewards) = getProfitsAndBabl(_finalizedStrategies);

        if (totalProfits > 0 && address(this).balance > 0) {
            contributor.claimedProfits = contributor.claimedProfits.add(totalProfits); // Profits claimed properly
            // Send ETH
            Address.sendValue(msg.sender, totalProfits);
            emit ProfitsForContributor(msg.sender, totalProfits);
        }
        if (bablRewards > 0) {
            contributor.claimedBABL = contributor.claimedBABL.add(bablRewards); // BABL Rewards claimed properly
            contributor.claimedAt = block.timestamp; // Checkpoint of this claim
            // Send BABL rewards
            IRewardsDistributor rewardsDistributor =
                IRewardsDistributor(IBabController(controller).rewardsDistributor());
            rewardsDistributor.sendTokensToContributor(msg.sender, uint96(bablRewards));
            emit BABLRewardsForContributor(msg.sender, uint96(bablRewards));
        }
    }

    /**
     * When an strategy finishes execution, we want to make that eth available for withdrawals
     * from members of the garden.
     *
     * @param _amount                        Amount of WETH to convert to ETH to set aside
     */
    function startWithdrawalWindow(uint256 _amount) external onlyStrategyOrProtocol {
        if (withdrawalsOpenUntil > block.timestamp) {
            withdrawalsOpenUntil = block.timestamp.add(
                withdrawalWindowAfterStrategyCompletes.sub(withdrawalsOpenUntil.sub(block.timestamp))
            );
        } else {
            withdrawalsOpenUntil = block.timestamp.add(withdrawalWindowAfterStrategyCompletes);
        }
        IWETH(WETH).withdraw(_amount);
    }

    /**
     * When the window of withdrawals finishes, we need to make the capital available again for investments
     *
     */
    function reenableEthForStrategies() public {
        if (block.timestamp >= withdrawalsOpenUntil && address(this).balance > minContribution) {
            withdrawalsOpenUntil = 0;
            IWETH(WETH).deposit{value: address(this).balance}();
        }
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. Changes the reserve asset
     *
     * @param _reserveAsset                 Address of the new reserve asset
     */
    function editReserveAsset(address _reserveAsset) external onlyProtocol {
        address oldReserve = reserveAsset;
        reserveAsset = _reserveAsset;

        emit ReserveAssetChanged(_reserveAsset, oldReserve);
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Garden is active, deposits are enabled.
     */
    function setActive() external onlyProtocol {
        _require(!active, Errors.ONLY_INACTIVE);
        active = true;
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Garden is disabled, deposits are disabled.
     */
    function setDisabled() external onlyProtocol {
        _require(active, Errors.ONLY_ACTIVE);
        active = false;
    }

    /**
     * Function that allows the principal of the garden to be updated by strategies
     *
     * @param _amount             Amount of the reserve balance
     */
    function updatePrincipal(uint256 _amount) external onlyStrategy {
        _updatePrincipal(_amount);
    }

    /* ============ Strategy Functions ============ */
    /**
     * Creates a new strategy calling the factory and adds it to the array
     * @param _strategyKind                  Int representing kind of strategy
     * @param _integration                   Address of the integration
     * @param _maxCapitalRequested           Max Capital requested denominated in the reserve asset (0 to be unlimited)
     * @param _stake                         Stake with garden participations absolute amounts 1e18
     * @param _strategyDuration              Strategy duration in seconds
     * @param _expectedReturn                Expected return
     * @param _minRebalanceCapital           Min capital that is worth it to deposit into this strategy
     * @param _strategyData                  Param of strategy to add
     */
    function addStrategy(
        uint8 _strategyKind,
        address _integration,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _strategyDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital,
        address _strategyData
    ) external onlyContributor onlyActive {
        _require(strategies.length < MAX_TOTAL_STRATEGIES, Errors.VALUE_TOO_HIGH);
        IStrategyFactory strategyFactory =
            IStrategyFactory(IBabController(controller).getStrategyFactory(_strategyKind));
        address strategy =
            strategyFactory.createStrategy(
                msg.sender,
                address(this),
                controller,
                _integration,
                _maxCapitalRequested,
                _stake,
                _strategyDuration,
                _expectedReturn,
                _minRebalanceCapital
            );
        strategyMapping[strategy] = true;
        totalStake = totalStake.add(_stake);
        strategies.push(strategy);
        IStrategy(strategy).setData(_strategyData);
    }

    /**
     * Rebalances available capital of the garden between the strategies that are active.
     * We enter into the strategy and add it to the executed strategies array.
     * @param _fee                     The fee paid to keeper to compensate the gas cost for each strategy executed
     */
    function rebalanceStrategies(uint256 _fee) external onlyKeeper(_fee) onlyActive {
        uint256 liquidReserveAsset = ERC20Upgradeable(reserveAsset).balanceOf(address(this));
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            uint256 percentage = strategy.totalVotes().toUint256().preciseDiv(totalStake);
            uint256 toAllocate = liquidReserveAsset.preciseMul(percentage);
            if (
                toAllocate >= strategy.minRebalanceCapital() &&
                toAllocate.add(strategy.capitalAllocated()) <= strategy.maxCapitalRequested()
            ) {
                strategy.executeStrategy(toAllocate, _fee);
            }
        }
    }

    /**
     * Allocates garden capital to an strategy
     *
     * @param _capital        Amount of capital to allocate to the strategy
     */
    function allocateCapitalToStrategy(uint256 _capital) external onlyStrategy onlyActive {
        uint256 liquidReserveAsset = ERC20Upgradeable(reserveAsset).balanceOf(address(this));
        uint256 protocolMgmtFee = IBabController(controller).protocolManagementFee().preciseMul(_capital);
        _require(_capital.add(protocolMgmtFee) <= liquidReserveAsset, Errors.MIN_LIQUIDITY);

        // Take protocol mgmt fee
        IERC20Upgradeable(reserveAsset).safeTransfer(IBabController(controller).treasury(), protocolMgmtFee);

        // Send Capital to strategy
        IERC20Upgradeable(reserveAsset).safeTransfer(msg.sender, _capital);
    }

    // Any tokens (other than the target) that are sent here by mistake are recoverable by the protocol
    // Exchange for WETH
    function sweep(address _token) external onlyContributor {
        _require(_token != reserveAsset, Errors.MUST_BE_RESERVE_ASSET);
        uint256 balance = IERC20Upgradeable(_token).balanceOf(address(this));
        _require(balance > 0, Errors.BALANCE_TOO_LOW);
        IERC20Upgradeable(_token).safeTransfer(IBabController(controller).treasury(), balance);
    }

    /*
     * Moves an estrategy from the active array to the finalized array
     * @param _returns       Positive or negative returns of the strategy
     * @param _strategy      Strategy to move from active to finalized
     */
    function moveStrategyToFinalized(int256 _returns, address _strategy) external onlyStrategy {
        absoluteReturns.add(_returns);
        strategies = strategies.remove(_strategy);
        finalizedStrategies.push(_strategy);
        strategyMapping[_strategy] = false;
    }

    /*
     * Remove an expire candidate from the strategy Array
     * @param _strategy      Strategy to remove
     */
    function expireCandidateStrategy(address _strategy) external onlyStrategy {
        strategies = strategies.remove(_strategy);
        strategyMapping[_strategy] = false;
    }

    /*
     * Burns the stake of the strategist of a given strategy
     * @param _strategy      Strategy
     */
    function burnStrategistStake(address _strategist, uint256 _amount) external onlyStrategy {
        _burn(_strategist, _amount);
    }

    /* ============ External Getter Functions ============ */

    /**
     * Gets current strategies
     *
     * @return  address[]        Returns list of addresses
     */

    function getStrategies() external view returns (address[] memory) {
        return strategies;
    }

    /**
     * Gets finalized strategies
     *
     * @return  address[]        Returns list of addresses
     */

    function getFinalizedStrategies() external view returns (address[] memory) {
        return finalizedStrategies;
    }

    function isStrategy(address _strategy) external view returns (bool) {
        return strategyMapping[_strategy];
    }

    /**
     * When an strategy finishes execution, contributors might want
     * to know the profits and BABL rewards for their participation in the different strategies
     *
     * @param _finalizedStrategies       Array of the finalized strategies
     */

    function getProfitsAndBabl(address[] calldata _finalizedStrategies)
        public
        view
        onlyContributor
        returns (uint256, uint96)
    {
        IRewardsDistributor rewardsDistributor = IRewardsDistributor(IBabController(controller).rewardsDistributor());
        return rewardsDistributor.getProfitsAndBabl(msg.sender, _finalizedStrategies);
    }

    function getContributor(address _contributor)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256[] memory,
            uint256,
            uint256
        )
    {
        Contributor storage contributor = contributors[_contributor];
        return (
            contributor.lastDepositAt,
            contributor.initialDepositAt,
            contributor.claimedAt,
            contributor.claimedBABL,
            contributor.claimedProfits,
            contributor.timeListPointer,
            contributor.pid,
            contributor.lastUpdated
        );
    }

    /**
     * Check if the fund has ETH amount available for withdrawals.
     * If it returns false, reserve pool would be available.
     * @param _contributor                   Address of the contributors
     * @param _amount                        Amount of ETH to withdraw
     */
    function canWithdrawEthAmount(address _contributor, uint256 _amount) public view returns (bool) {
        uint256 ethAsideBalance = address(this).balance;
        uint256 liquidWeth = IERC20Upgradeable(reserveAsset).balanceOf(address(this));

        // Weth already available
        if (liquidWeth >= _amount) {
            return true;
        }

        // Withdrawal open
        if (block.timestamp <= withdrawalsOpenUntil) {
            // Pro rata withdrawals
            uint256 contributorPower =
                _getContributorPower(_contributor, contributors[_contributor].initialDepositAt, block.timestamp);
            return ethAsideBalance.preciseMul(contributorPower) >= _amount;
        }
        return false;
    }

    /**
     * Get the expected reserve asset to be withdrawaled
     *
     * @param _gardenTokenQuantity             Quantity of Garden tokens to withdrawal
     *
     * @return  uint256                     Expected reserve asset quantity withdrawaled
     */
    function getExpectedReserveWithdrawalQuantity(uint256 _gardenTokenQuantity) external view returns (uint256) {
        (, uint256 netReserveFlows) = _getFees(_gardenTokenQuantity, false);

        return netReserveFlows;
    }

    /**
     * Checks if deposit is valid
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _reserveAssetQuantity         Quantity of the reserve asset to deposit with
     *
     * @return  bool                        Returns true if deposit is valid
     */
    function isDepositValid(address _reserveAsset, uint256 _reserveAssetQuantity) external view returns (bool) {
        return
            _reserveAssetQuantity != 0 &&
            IBabController(controller).isValidReserveAsset(_reserveAsset) &&
            totalSupply() >= minGardenTokenSupply;
    }

    /**
     * Checks if withdrawal is valid
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _gardenTokenQuantity             Quantity of garden tokens to withdrawal
     *
     * @return  bool                        Returns true if withdrawal is valid
     */
    function isWithdrawalValid(address _reserveAsset, uint256 _gardenTokenQuantity) external view returns (bool) {
        if (
            _gardenTokenQuantity == 0 ||
            !IBabController(controller).isValidReserveAsset(_reserveAsset) ||
            totalSupply() < minGardenTokenSupply.add(_gardenTokenQuantity)
        ) {
            return false;
        } else {
            uint256 totalWithdrawalValue = _gardenTokenQuantity;

            (, uint256 expectedWithdrawalQuantity) = _getFees(totalWithdrawalValue, false);

            return principal >= expectedWithdrawalQuantity;
        }
    }

    /**
     * Checks balance locked for strategists and voters in active strategies
     *
     * @param _contributor                 Address of the account
     *
     * @return  uint256                    Returns the amount of locked garden tokens for the account
     */
    function getLockedBalance(address _contributor) external view returns (uint256) {
        uint256 lockedAmount;
        for (uint256 i = 0; i <= strategies.length - 1; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            uint256 votes = uint256(Math.abs(strategy.getUserVotes(_contributor)));
            if (votes > 0) {
                lockedAmount += votes;
            }
            if (_contributor == strategy.strategist()) {
                lockedAmount += strategy.stake();
            }
        }
        if (balanceOf(_contributor) < lockedAmount) lockedAmount = balanceOf(_contributor); // TODO Remove when implementing locked stake in voting and strategy creation - Now this avoid overflows
        return lockedAmount;
    }

    /**
     * Gets the contributor power from one timestamp to the other
     * @param _contributor Address if the contributor
     * @param _from        Initial timestamp
     * @param _to          End timestamp
     * @return uint256     Contributor power during that period
     */
    function getContributorPower(
        address _contributor,
        uint256 _from,
        uint256 _to
    ) external view returns (uint256) {
        return _getContributorPower(_contributor, _from, _to);
    }

    /**
     * Gets the total active capital currently invested in strategies
     *
     * @return uint256       Total amount active
     * @return uint256       Total amount active in the largest strategy
     * @return address       Address of the largest strategy
     */
    function getActiveCapital()
        public
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        uint256 totalActiveCapital = 0;
        uint256 maxAllocation = 0;
        address maxStrategy = address(0);
        for (uint8 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            if (strategy.isStrategyActive()) {
                uint256 allocation = strategy.capitalAllocated();
                totalActiveCapital = totalActiveCapital.add(allocation);
                if (allocation > maxAllocation) {
                    maxAllocation = allocation;
                    maxStrategy = strategies[i];
                }
            }
        }
        return (totalActiveCapital, maxAllocation, maxStrategy);
    }

    // solhint-disable-next-line
    receive() external payable {}

    /* ============ Internal Functions ============ */

    /**
     * Function that allows the principal to be updated
     *
     * @param _amount             Amount of the reserve balance
     */
    function _updatePrincipal(uint256 _amount) internal {
        uint256 oldAmount = principal;
        principal = _amount;
        emit PrincipalChanged(_amount, oldAmount);
    }

    /**
     * Pays the _feeQuantity from the _garden denominated in _token to the protocol fee recipient
     * @param _token                   Address of the token to pay with
     * @param _feeQuantity             Fee to transfer
     */
    function payProtocolFeeFromGarden(address _token, uint256 _feeQuantity) internal {
        if (_feeQuantity > 0) {
            IERC20Upgradeable(_token).safeTransfer(IBabController(controller).treasury(), _feeQuantity);
        }
    }

    // Disable garden token transfers. Allow minting and burning.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 /* amount */
    ) internal view override {
        _require(
            from == address(0) || to == address(0) || IBabController(controller).gardenTokensTransfersEnabled(),
            Errors.TOKENS_TIMELOCKED
        );
    }

    /**
     * Aux function to withdraw from a garden
     */
    function _withdraw(
        uint256 _gardenTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) private {
        // Withdrawal amount has to be equal or less than msg.sender balance
        _require(_gardenTokenQuantity <= balanceOf(msg.sender), Errors.MSG_SENDER_TOKENS_DO_NOT_MATCH);
        // Flashloan protection
        _require(
            block.timestamp.sub(contributors[msg.sender].lastDepositAt) >= depositHardlock,
            Errors.TOKENS_TIMELOCKED
        );
        _require(
            _gardenTokenQuantity <= balanceOf(msg.sender).sub(this.getLockedBalance(msg.sender)),
            Errors.TOKENS_TIMELOCKED
        ); // Strategists and Voters cannot withdraw locked stake while in active strategies

        // Check this here to avoid having relayers
        reenableEthForStrategies();
        ActionInfo memory withdrawalInfo = _createRedemptionInfo(_gardenTokenQuantity);
        _require(canWithdrawEthAmount(msg.sender, withdrawalInfo.netFlowQuantity), Errors.MIN_LIQUIDITY);

        _validateReserveAsset(reserveAsset, withdrawalInfo.netFlowQuantity);

        _validateRedemptionInfo(_minReserveReceiveQuantity, _gardenTokenQuantity, withdrawalInfo);

        _burn(msg.sender, _gardenTokenQuantity);

        // Check that the withdrawal is possible
        // Unwrap WETH if ETH balance lower than netFlowQuantity
        if (address(this).balance < withdrawalInfo.netFlowQuantity) {
            IWETH(WETH).withdraw(withdrawalInfo.netFlowQuantity);
        }
        _updateContributorWithdrawalInfo();
        // Send ETH
        Address.sendValue(_to, withdrawalInfo.netFlowQuantity);
        payProtocolFeeFromGarden(reserveAsset, withdrawalInfo.protocolFees);

        uint256 outflow = withdrawalInfo.netFlowQuantity.add(withdrawalInfo.protocolFees);

        // Required withdrawable quantity is greater than existing collateral
        _require(principal >= outflow, Errors.BALANCE_TOO_LOW);
        _updatePrincipal(principal.sub(outflow));

        emit GardenWithdrawal(
            msg.sender,
            _to,
            withdrawalInfo.netFlowQuantity,
            withdrawalInfo.gardenTokenQuantity,
            withdrawalInfo.protocolFees,
            block.timestamp
        );
    }

    /**
     * Returns the losses of a garden since a timestamp
     *
     * @param _since                        Timestamp since when we should calculate the losses
     * @return  uint256                     Losses of a garden since a timestamp
     */
    function _getLossesGarden(uint256 _since) private view returns (uint256) {
        uint256 totalLosses = 0;
        for (uint256 i = 0; i < finalizedStrategies.length; i++) {
            if (IStrategy(finalizedStrategies[i]).executedAt() >= _since) {
                totalLosses = totalLosses.add(IStrategy(finalizedStrategies[i]).getLossesStrategy());
            }
        }
        for (uint256 i = 0; i < strategies.length; i++) {
            if (IStrategy(strategies[i]).executedAt() >= _since) {
                totalLosses = totalLosses.add(IStrategy(strategies[i]).getLossesStrategy());
            }
        }

        return totalLosses;
    }

    function _validateReserveAsset(address _reserveAsset, uint256 _quantity) private view {
        _require(_quantity > 0, Errors.GREATER_THAN_ZERO);
        _require(IBabController(controller).isValidReserveAsset(_reserveAsset), Errors.MUST_BE_RESERVE_ASSET);
    }

    function _validateRedemptionInfo(
        uint256 _minReserveReceiveQuantity,
        uint256, /* _gardenTokenQuantity */
        ActionInfo memory _withdrawalInfo
    ) private view {
        // Check that new supply is more than min supply needed for withdrawal
        // Note: A min supply amount is needed to avoid division by 0 when withdrawaling garden token to 0
        _require(_withdrawalInfo.newGardenTokenSupply >= minGardenTokenSupply, Errors.MIN_TOKEN_SUPPLY);

        _require(_withdrawalInfo.netFlowQuantity >= _minReserveReceiveQuantity, Errors.MIN_TOKEN_SUPPLY);
    }

    function _createIssuanceInfo(uint256 _reserveAssetQuantity) private view returns (ActionInfo memory) {
        ActionInfo memory depositInfo;

        (depositInfo.protocolFees, depositInfo.netFlowQuantity) = _getFees(_reserveAssetQuantity, true);

        depositInfo.gardenTokenQuantity = depositInfo.netFlowQuantity;

        depositInfo.newGardenTokenSupply = depositInfo.gardenTokenQuantity.add(totalSupply());

        return depositInfo;
    }

    function _createRedemptionInfo(uint256 _gardenTokenQuantity) private view returns (ActionInfo memory) {
        ActionInfo memory withdrawalInfo;

        withdrawalInfo.gardenTokenQuantity = _gardenTokenQuantity;

        (withdrawalInfo.protocolFees, withdrawalInfo.netFlowQuantity) = _getFees(_gardenTokenQuantity, false);

        withdrawalInfo.newGardenTokenSupply = totalSupply().sub(_gardenTokenQuantity);

        return withdrawalInfo;
    }

    /**
     * Returns the fees attributed to the manager and the protocol. The fees are calculated as follows:
     *
     * Protocol Fee = (% direct fee %) * reserveAssetQuantity
     *
     * @param _reserveAssetQuantity         Quantity of reserve asset to calculate fees from
     * @param _isDeposit                    Boolean that is true when it is a deposit
     *
     * @return  uint256                     Fees paid to the protocol in reserve asset
     * @return  uint256                     Net reserve to user net of fees
     */
    function _getFees(uint256 _reserveAssetQuantity, bool _isDeposit) private view returns (uint256, uint256) {
        // Get protocol fee percentages
        uint256 protocolFeePercentage =
            _isDeposit
                ? IBabController(controller).protocolDepositGardenTokenFee()
                : IBabController(controller).protocolWithdrawalGardenTokenFee();

        uint256 reserveAssetReal = _reserveAssetQuantity;
        // If there is a withdrawal, we adjust for losses
        if (!_isDeposit) {
            uint256 losses = _getLossesGarden(contributors[msg.sender].initialDepositAt);
            // // If there are losses we need to adjust them down
            if (losses > 0) {
                reserveAssetReal = reserveAssetReal.sub(
                    losses.preciseMul(
                        _getContributorPower(msg.sender, contributors[msg.sender].initialDepositAt, block.timestamp)
                    )
                );
            }
        }
        // Calculate total notional fees
        uint256 protocolFees = protocolFeePercentage.preciseMul(reserveAssetReal);

        uint256 netReserveFlow = reserveAssetReal.sub(protocolFees);

        return (protocolFees, netReserveFlow);
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorDepositInfo(uint256 previousBalance) internal {
        Contributor storage contributor = contributors[msg.sender];

        // If new contributor, create one, increment count, and set the current TS
        if (previousBalance == 0) {
            totalContributors = totalContributors.add(1);
            contributor.initialDepositAt = block.timestamp;
        }
        // We make checkpoints around contributor deposits to avoid fast loans and give the right rewards afterwards
        _setContributorTimestampParams();

        contributor.lastDepositAt = block.timestamp;
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorWithdrawalInfo() internal {
        Contributor storage contributor = contributors[msg.sender];
        // If sold everything
        if (balanceOf(msg.sender) == 0) {
            contributor.lastDepositAt = 0;
            contributor.initialDepositAt = 0;
            delete contributor.timeListPointer;
            totalContributors = totalContributors.sub(1);
            contributor.lastUpdated = block.timestamp;
        } else {
            _setContributorTimestampParams();
        }
    }

    /**
     * Gets the contributor power from one timestamp to the other
     * @param _contributor Address if the contributor
     * @param _from        Initial timestamp
     * @param _to          End timestamp
     * @return uint256     Contributor power during that period
     */
    function _getContributorPower(
        address _contributor,
        uint256 _from,
        uint256 _to
    ) internal view returns (uint256) {
        Contributor storage contributor = contributors[_contributor];
        // Find closest point to _from and goes until the last
        uint256 contributorPower;
        uint256 lastDepositAt = contributor.timeListPointer[contributor.timeListPointer.length.sub(1)];

        if (lastDepositAt > _to) {
            // We go to find the last deposit before the strategy ends
            for (uint256 i = 0; i <= contributor.timeListPointer.length.sub(1); i++) {
                if (contributor.timeListPointer[i] <= _to) {
                    lastDepositAt = contributor.timeListPointer[i];
                }
            }
        }
        TimestampContribution memory tsContribution = contributor.tsContributions[lastDepositAt];
        contributorPower = tsContribution.power.add((_to.sub(lastDepositAt)).mul(tsContribution.principal));
        contributorPower = contributorPower.add(tsContribution.principal).div(_to.sub(contributor.initialDepositAt));

        return contributorPower.preciseDiv(totalSupply());
    }

    /**
     * Updates contributor timestamps params
     */
    function _setContributorTimestampParams() private {
        Contributor storage contributor = contributors[msg.sender];
        contributor.tsContributions[block.timestamp].principal = balanceOf(msg.sender);
        contributor.tsContributions[block.timestamp].timestamp = block.timestamp;
        contributor.tsContributions[block.timestamp].timePointer = contributor.pid;

        if (contributor.pid == 0) {
            // The very first strategy of all strategies in the mining program
            contributor.tsContributions[block.timestamp].power = 0;
        } else {
            // Any other strategy different from the very first one (will have an antecesor)

            TimestampContribution memory tsContribution = contributor.tsContributions[contributor.lastUpdated];
            uint256 timestampPower =
                tsContribution.power.add(
                    contributor.tsContributions[block.timestamp].timestamp.sub(tsContribution.timestamp).mul(
                        tsContribution.principal
                    )
                );

            contributor.tsContributions[block.timestamp].power = timestampPower;
        }
        contributor.timeListPointer.push(block.timestamp);
        contributor.pid++;
        contributor.lastUpdated = block.timestamp;
    }
}
