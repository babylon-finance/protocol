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
import {IGardenValuer} from '../interfaces/IGardenValuer.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IGardenNFT} from '../interfaces/IGardenNFT.sol';
import {IIshtarGate} from '../interfaces/IIshtarGate.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';

/**
 * @title BaseGarden
 * @author Babylon Finance
 *
 * Class that holds common garden-related state and functions
 */
contract Garden is ERC20Upgradeable, ReentrancyGuard, IGarden {
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
    event PrincipalChanged(uint256 _newAmount, uint256 _oldAmount);
    event GardenDeposit(
        address indexed _to,
        uint256 reserveToken,
        uint256 reserveTokenQuantity,
        uint256 protocolFees,
        uint256 timestamp
    );
    event GardenWithdrawal(
        address indexed _from,
        address indexed _to,
        uint256 reserveToken,
        uint256 reserveTokenQuantity,
        uint256 protocolFees,
        uint256 timestamp
    );

    event RewardsForContributor(address indexed _contributor, uint256 indexed _amount);
    event BABLRewardsForContributor(address indexed _contributor, uint96 _rewards);

    /* ============ Modifiers ============ */
    modifier onlyContributor {
        _require(balanceOf(msg.sender) > 0, Errors.ONLY_CONTRIBUTOR);
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
     * Throws if the garden is not active
     */
    modifier onlyActive() {
        _require(active, Errors.ONLY_ACTIVE);
        _;
    }

    /* ============ State Constants ============ */

    // Wrapped ETH address
    address public constant override WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 public constant EARLY_WITHDRAWAL_PENALTY = 15e16;
    uint256 public constant MAX_DEPOSITS_FUND_V1 = 1e21; // Max deposit per garden is 1000 eth for v1
    uint256 public constant MAX_TOTAL_STRATEGIES = 20; // Max number of strategies
    uint256 internal constant TEN_PERCENT = 1e17;
    uint256 internal constant MAX_KEEPER_FEE = (1e6 * 1e3 gwei);
    uint256 internal constant ABSOLUTE_MIN_CONTRIBUTION = 1e17;

    /* ============ Structs ============ */

    struct Contributor {
        uint256 lastDepositAt;
        uint256 initialDepositAt;
        uint256 claimedAt;
        uint256 claimedBABL;
        uint256 claimedRewards;
        uint256 withdrawnSince;
    }

    /* ============ State Variables ============ */

    // Reserve Asset of the garden
    address public override reserveAsset;

    // Address of the controller
    address public override controller;
    // Address of the nft
    address public override nftAddress;
    // The person that creates the garden
    address public override creator;
    // Whether the garden is currently active or not
    bool public override active;
    bool public override guestListEnabled;

    // Keeps track of the reserve balance. In case we receive some through other means
    uint256 public override principal;
    uint256 public override reserveAssetRewardsSetAside;
    uint256 public override reserveAssetPrincipalWindow;
    int256 public override absoluteReturns; // Total profits or losses of this garden

    // Indicates the minimum liquidity the asset needs to have to be tradable by this garden
    uint256 public override minLiquidityAsset;

    uint256 public depositHardlock; // Window of time after deposits when withdraws are disabled for that user
    // Window of time after an investment strategy finishes when the capital is available for withdrawals
    uint256 public withdrawalWindowAfterStrategyCompletes;
    uint256 public withdrawalsOpenUntil; // Indicates until when the withdrawals are open and the ETH is set aside

    // Contributors
    mapping(address => Contributor) public contributors;
    uint256 public override totalContributors;
    uint256 public override maxContributors;
    uint256 public maxDepositLimit; // Limits the amount of deposits

    uint256 public override gardenInitializedAt; // Garden Initialized at timestamp
    uint256 public pid;

    // Min contribution in the garden
    uint256 public override minContribution; //wei
    uint256 public minGardenTokenSupply;

    // Strategies variables
    uint256 public override totalStake;
    uint256 public override minVotersQuorum = TEN_PERCENT; // 10%. (0.01% = 1e14, 1% = 1e16)
    uint256 public override minStrategyDuration; // Min duration for an strategy
    uint256 public override maxStrategyDuration; // Max duration for an strategy
    // Window for the strategy to cooldown after approval before receiving capital
    uint256 public override strategyCooldownPeriod;

    address[] public override strategies; // Strategies that are either in candidate or active state
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
     * @param _gardenParams           Array of numeric garden params
     * @param _nftAddress             Garden NFT address
     */
    function initialize(
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol,
        uint256[] calldata _gardenParams,
        address _nftAddress
    ) public payable initializer {
        _require(_creator != address(0), Errors.ADDRESS_IS_ZERO);
        _require(_controller != address(0), Errors.ADDRESS_IS_ZERO);
        _require(_reserveAsset != address(0), Errors.ADDRESS_IS_ZERO);
        _require(IBabController(_controller).isValidReserveAsset(_reserveAsset), Errors.MUST_BE_RESERVE_ASSET);
        __ERC20_init(_name, _symbol);

        controller = _controller;
        reserveAsset = _reserveAsset;
        creator = _creator;
        maxContributors = 100;
        nftAddress = _nftAddress;
        guestListEnabled = true;

        _start(
            msg.value,
            _gardenParams[0],
            _gardenParams[1],
            _gardenParams[2],
            _gardenParams[3],
            _gardenParams[4],
            _gardenParams[5],
            _gardenParams[6],
            _gardenParams[7],
            _gardenParams[8]
        );
        active = true;

        // Deposit
        IWETH(WETH).deposit{value: msg.value}();
        _mintGardenTokens(creator, creator, msg.value, msg.value, 0);
    }

    /* ============ External Functions ============ */

    /**
     * FUND LEAD ONLY.  Starts the Garden with allowed reserve assets,
     * fees and issuance premium. Only callable by the Garden's creator
     *
     * @param _creatorDeposit                      Deposit by the creator
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
    function _start(
        uint256 _creatorDeposit,
        uint256 _maxDepositLimit,
        uint256 _minGardenTokenSupply,
        uint256 _minLiquidityAsset,
        uint256 _depositHardlock,
        uint256 _minContribution,
        uint256 _strategyCooldownPeriod,
        uint256 _minVotersQuorum,
        uint256 _minStrategyDuration,
        uint256 _maxStrategyDuration
    ) private {
        _require(_minContribution >= ABSOLUTE_MIN_CONTRIBUTION, Errors.MIN_CONTRIBUTION);
        _require(_creatorDeposit >= _minContribution, Errors.MIN_CONTRIBUTION);
        _require(_creatorDeposit >= _minGardenTokenSupply, Errors.MIN_LIQUIDITY);
        _require(_creatorDeposit <= _maxDepositLimit, Errors.MAX_DEPOSIT_LIMIT);
        _require(_maxDepositLimit <= MAX_DEPOSITS_FUND_V1, Errors.MAX_DEPOSIT_LIMIT);
        IBabController babController = IBabController(controller);
        _require(_minGardenTokenSupply > 0, Errors.MIN_TOKEN_SUPPLY);
        _require(_depositHardlock > 0, Errors.DEPOSIT_HARDLOCK);
        _require(_minLiquidityAsset >= babController.minRiskyPairLiquidityEth(), Errors.MIN_LIQUIDITY);
        _require(
            _strategyCooldownPeriod <= IBabController(controller).getMaxCooldownPeriod() &&
                _strategyCooldownPeriod >= IBabController(controller).getMinCooldownPeriod(),
            Errors.NOT_IN_RANGE
        );
        _require(_minVotersQuorum >= TEN_PERCENT && _minVotersQuorum <= TEN_PERCENT.mul(5), Errors.VALUE_TOO_LOW);
        _require(_maxStrategyDuration >= _minStrategyDuration, Errors.DURATION_RANGE);
        _require(_minStrategyDuration >= 1 days && _maxStrategyDuration <= 500 days, Errors.DURATION_RANGE);
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
    ) public payable override nonReentrant onlyActive {
        _require(
            guestListEnabled &&
                IIshtarGate(IBabController(controller).ishtarGate()).canJoinAGarden(address(this), msg.sender),
            Errors.USER_CANNOT_JOIN
        );
        _require(msg.value >= minContribution, Errors.MIN_CONTRIBUTION);
        // if deposit limit is 0, then there is no deposit limit
        if (maxDepositLimit > 0) {
            _require(principal.add(msg.value) <= maxDepositLimit, Errors.MAX_DEPOSIT_LIMIT);
        }
        _require(totalContributors < maxContributors, Errors.MAX_CONTRIBUTORS);
        _require(msg.value == _reserveAssetQuantity, Errors.MSG_VALUE_DO_NOT_MATCH);
        // Always wrap to WETH
        IWETH(WETH).deposit{value: msg.value}();
        // Check this here to avoid having relayers
        reenableEthForStrategies();

        _validateReserveAsset(reserveAsset, _reserveAssetQuantity);

        (uint256 protocolFees, uint256 netFlowQuantity) = _getFees(_reserveAssetQuantity, true);

        // Check that total supply is greater than min supply needed for issuance
        _require(totalSupply() >= minGardenTokenSupply, Errors.MIN_TOKEN_SUPPLY);

        // gardenTokenQuantity has to be at least _minGardenTokenReceiveQuantity
        _require(netFlowQuantity >= _minGardenTokenReceiveQuantity, Errors.MIN_TOKEN_SUPPLY);

        // Send Protocol Fee
        payProtocolFeeFromGarden(reserveAsset, protocolFees);

        // Mint tokens
        _mintGardenTokens(msg.sender, _to, netFlowQuantity, principal.add(netFlowQuantity), protocolFees);
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
    ) external override nonReentrant onlyContributor {
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
        _require(!_canWithdrawEthAmount(msg.sender, _gardenTokenQuantity), Errors.NORMAL_WITHDRAWAL_POSSIBLE);
        uint256 netReserveFlows = _gardenTokenQuantity.sub(_gardenTokenQuantity.preciseMul(EARLY_WITHDRAWAL_PENALTY));
        (, uint256 largestCapital, address maxStrategy) = _getActiveCapital();
        // Check that strategy has enough capital to support the withdrawal
        _require(
            IStrategy(maxStrategy).minRebalanceCapital() <= largestCapital.sub(netReserveFlows),
            Errors.WITHDRAWAL_WITH_PENALTY
        );
        IStrategy(maxStrategy).unwindStrategy(netReserveFlows);
        // We burn their penalty
        _burn(msg.sender, _gardenTokenQuantity.preciseMul(EARLY_WITHDRAWAL_PENALTY));
        // TODO: replace the 1
        _withdraw(netReserveFlows, 1, _to);
    }

    /**
     * User can claim the rewards from the strategies that his principal
     * was invested in.
     */
    function claimReturns(address[] calldata _finalizedStrategies) external override nonReentrant onlyContributor {
        Contributor storage contributor = contributors[msg.sender];
        _require(block.timestamp > contributor.claimedAt, Errors.ALREADY_CLAIMED); // race condition check

        IRewardsDistributor rewardsDistributor = IRewardsDistributor(IBabController(controller).rewardsDistributor());
        (uint256 reserveRewards, uint256 bablRewards) =
            rewardsDistributor.getRewards(address(this), msg.sender, _finalizedStrategies);

        if (reserveRewards > 0 && address(this).balance > 0) {
            contributor.claimedRewards = contributor.claimedRewards.add(reserveRewards); // Rewards claimed properly
            // Send ETH
            Address.sendValue(msg.sender, reserveRewards);
            reserveAssetRewardsSetAside = reserveAssetRewardsSetAside.sub(reserveRewards);
            emit RewardsForContributor(msg.sender, reserveRewards);
            contributor.claimedAt = block.timestamp; // Checkpoint of this claim
        }
        if (bablRewards > 0) {
            contributor.claimedBABL = contributor.claimedBABL.add(bablRewards); // BABL Rewards claimed properly
            // Send BABL rewards

            rewardsDistributor.sendTokensToContributor(msg.sender, uint96(bablRewards));
            emit BABLRewardsForContributor(msg.sender, uint96(bablRewards));
            contributor.claimedAt = block.timestamp; // Checkpoint of this claim
        }
    }

    /**
     * When an strategy finishes execution, we want to make that eth available for withdrawals
     * from members of the garden.
     *
     * @param _amount                        Amount of WETH to convert to ETH to set aside until the window ends
     * @param _rewards                       Amount of WETH to convert to ETH to set aside forever
     * @param _returns                       Profits or losses that the strategy received
     */
    function startWithdrawalWindow(
        uint256 _amount,
        uint256 _rewards,
        int256 _returns,
        address _strategy
    ) external override {
        _require(
            (strategyMapping[msg.sender] && address(IStrategy(msg.sender).garden()) == address(this)) ||
                msg.sender == controller,
            Errors.ONLY_STRATEGY_OR_CONTROLLER
        );
        // Updates reserve asset
        uint256 _newTotal = principal.toInt256().add(_returns).toUint256();
        _updatePrincipal(_newTotal);
        if (withdrawalsOpenUntil > block.timestamp) {
            withdrawalsOpenUntil = block.timestamp.add(
                withdrawalWindowAfterStrategyCompletes.sub(withdrawalsOpenUntil.sub(block.timestamp))
            );
        } else {
            withdrawalsOpenUntil = block.timestamp.add(withdrawalWindowAfterStrategyCompletes);
        }
        reserveAssetRewardsSetAside = reserveAssetRewardsSetAside.add(_rewards);
        reserveAssetPrincipalWindow = reserveAssetPrincipalWindow.add(_amount);
        // Both are converted to weth
        IWETH(WETH).withdraw(_amount.add(_rewards));

        // Mark strategy as finalized
        absoluteReturns.add(_returns);
        strategies = strategies.remove(_strategy);
        finalizedStrategies.push(_strategy);
        strategyMapping[_strategy] = false;
    }

    /**
     * When the window of withdrawals finishes, we need to make the capital available again for investments
     * We still keep the profits aside.
     */
    function reenableEthForStrategies() public override {
        if (
            block.timestamp >= withdrawalsOpenUntil &&
            address(this).balance > minContribution &&
            address(this).balance >= reserveAssetPrincipalWindow
        ) {
            withdrawalsOpenUntil = 0;
            IWETH(WETH).deposit{value: reserveAssetPrincipalWindow}();
            reserveAssetPrincipalWindow = 0;
        }
    }

    /* ============ External Functions ============ */

    /**
     * Makes a previously private garden public
     */
    function makeGardenPublic() external override {
        _require(msg.sender == creator, Errors.ONLY_CREATOR);
        _require(guestListEnabled && IBabController(controller).allowPublicGardens(), Errors.GARDEN_ALREADY_PUBLIC);
        guestListEnabled = false;
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Garden is active, deposits are enabled.
     */
    function setActive(bool _newValue) external override {
        _require(msg.sender == controller, Errors.ONLY_CONTROLLER);
        _require(active != _newValue, Errors.ONLY_INACTIVE);
        active = _newValue;
    }

    /* ============ Strategy Functions ============ */
    /**
     * Creates a new strategy calling the factory and adds it to the array
     * @param _name                          Name of the strategy
     * @param _symbol                        Symbol of the strategy
     * @param _stratParams                   Num params for the strategy
     * @param _opTypes                      Type for every operation in the strategy
     * @param _opIntegrations               Integration to use for every operation
     * @param _opDatas                      Param for every operation in the strategy
     */
    function addStrategy(
        string memory _name,
        string memory _symbol,
        uint256[] calldata _stratParams,
        uint8[] calldata _opTypes,
        address[] calldata _opIntegrations,
        address[] calldata _opDatas
    ) external override onlyContributor onlyActive {
        _require(
            IIshtarGate(IBabController(controller).ishtarGate()).canAddStrategiesInAGarden(address(this), msg.sender),
            Errors.USER_CANNOT_ADD_STRATEGIES
        );
        _require(strategies.length < MAX_TOTAL_STRATEGIES, Errors.VALUE_TOO_HIGH);
        _require(_stratParams.length == 5, Errors.STRAT_PARAMS_LENGTH);
        address strategy =
            IStrategyFactory(IBabController(controller).strategyFactory()).createStrategy(
                _name,
                _symbol,
                msg.sender,
                address(this),
                controller,
                _stratParams
            );
        strategyMapping[strategy] = true;
        totalStake = totalStake.add(_stratParams[1]);
        strategies.push(strategy);
        IStrategy(strategy).setData(_opTypes, _opIntegrations, _opDatas);
    }

    /**
     * Rebalances available capital of the garden between the strategies that are active.
     * We enter into the strategy and add it to the executed strategies array.
     * @param _fee                     The fee paid to keeper to compensate the gas cost for each strategy executed
     */
    function rebalanceStrategies(uint256 _fee) external override onlyKeeper(_fee) onlyActive {
        uint256 liquidReserveAsset = ERC20Upgradeable(reserveAsset).balanceOf(address(this));
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            uint256 percentage = strategy.totalVotes().toUint256().preciseDiv(totalStake);
            uint256 toAllocate = liquidReserveAsset.preciseMul(percentage);
            if (
                block.timestamp < strategy.executedAt().add(strategy.duration()).sub(1 days) &&
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
    function allocateCapitalToStrategy(uint256 _capital) external override onlyStrategy onlyActive {
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
     * Remove an expire candidate from the strategy Array
     * @param _strategy      Strategy to remove
     */
    function expireCandidateStrategy(address _strategy) external override onlyStrategy {
        strategies = strategies.remove(_strategy);
        strategyMapping[_strategy] = false;
    }

    /*
     * Burns the stake of the strategist of a given strategy
     * @param _strategy      Strategy
     */
    function burnStrategistStake(address _strategist, uint256 _amount) external override onlyStrategy {
        if (_amount >= balanceOf(_strategist)) {
            // Avoid underflow condition
            _amount = balanceOf(_strategist);
        }
        _burn(_strategist, _amount);
    }

    /* ============ External Getter Functions ============ */

    /**
     * Gets current strategies
     *
     * @return  address[]        Returns list of addresses
     */

    function getStrategies() external view override returns (address[] memory) {
        return strategies;
    }

    /**
     * Gets finalized strategies
     *
     * @return  address[]        Returns list of addresses
     */

    function getFinalizedStrategies() external view override returns (address[] memory) {
        return finalizedStrategies;
    }

    function isStrategy(address _strategy) external view override returns (bool) {
        return strategyMapping[_strategy];
    }

    function getContributor(address _contributor)
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
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
            contributor.claimedRewards,
            contributor.withdrawnSince
        );
    }

    /**
     * Get the expected reserve asset to be withdrawaled
     *
     * @param _gardenTokenQuantity             Quantity of Garden tokens to withdrawal
     *
     * @return  uint256                     Expected reserve asset quantity withdrawaled
     */
    function getExpectedReserveWithdrawalQuantity(uint256 _gardenTokenQuantity)
        external
        view
        override
        returns (uint256)
    {
        (, uint256 netReserveFlows) =
            _getFees(_getWithdrawalReserveQuantity(reserveAsset, _gardenTokenQuantity), false);

        return netReserveFlows;
    }

    /**
     * Checks balance locked for strategists and voters in active strategies
     *
     * @param _contributor                 Address of the account
     *
     * @return  uint256                    Returns the amount of locked garden tokens for the account
     */
    function getLockedBalance(address _contributor) external view override returns (uint256) {
        uint256 lockedAmount;
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            uint256 votes = uint256(Math.abs(strategy.getUserVotes(_contributor)));
            if (votes > 0) {
                lockedAmount = lockedAmount.add(votes);
            }
        }
        // Avoid overflows if off-chain voting system fails
        if (balanceOf(_contributor) < lockedAmount) lockedAmount = balanceOf(_contributor);
        return lockedAmount;
    }

    function getGardenTokenMintQuantity(
        uint256 _reserveAssetQuantity,
        bool isDeposit // Value of reserve asset net of fees
    ) public view override returns (uint256) {
        // Get valuation of the Garden with the quote asset as the reserve asset.
        // Reverts if price is not found
        uint8 reserveAssetDecimals = ERC20Upgradeable(reserveAsset).decimals();
        uint256 baseUnits = uint256(10)**reserveAssetDecimals;
        uint256 normalizedReserveQuantity = _reserveAssetQuantity.preciseDiv(baseUnits);
        // First deposit
        if (totalSupply() == 0) {
            return normalizedReserveQuantity;
        }
        uint256 gardenValuationPerToken =
            IGardenValuer(IBabController(controller).gardenValuer()).calculateGardenValuation(
                address(this),
                reserveAsset
            );

        gardenValuationPerToken = gardenValuationPerToken.preciseDiv(baseUnits);
        if (isDeposit) {
            gardenValuationPerToken = gardenValuationPerToken.sub(normalizedReserveQuantity.preciseDiv(totalSupply()));
        }
        return normalizedReserveQuantity.preciseDiv(gardenValuationPerToken);
    }

    // solhint-disable-next-line
    receive() external payable {}

    /* ============ Internal Functions ============ */

    /**
     * Function that mints the appropriate garden tokens along with the Garden NFT
     * @param _from                            Address that triggered the transaction
     * @param _to                              Address to mint the tokens
     * @param _reserveAssetQuantity            Amount of garden tokens
     * @param _newPrincipal                    New principal for that user
     * @param _protocolFees                    Protocol Fees Paid
     */
    function _mintGardenTokens(
        address _from,
        address _to,
        uint256 _reserveAssetQuantity,
        uint256 _newPrincipal,
        uint256 _protocolFees
    ) private {
        uint256 previousBalance = balanceOf(_to);
        uint256 amountToMint = getGardenTokenMintQuantity(_reserveAssetQuantity, true);
        _mint(_to, amountToMint);
        _updateContributorDepositInfo(_from, previousBalance);
        _updatePrincipal(_newPrincipal);
        // Mint the garden NFT
        IGardenNFT(nftAddress).grantGardenNFT(_to);
        _require(totalSupply() > 0, Errors.MIN_LIQUIDITY);
        emit GardenDeposit(_to, msg.value, _reserveAssetQuantity, _protocolFees, block.timestamp);
    }

    /**
     * Check if the fund has ETH amount available for withdrawals.
     * If it returns false, reserve pool would be available.
     * @param _contributor                   Address of the contributors
     * @param _amount                        Amount of ETH to withdraw
     */
    function _canWithdrawEthAmount(address _contributor, uint256 _amount) private view returns (bool) {
        // ETH rewards cannot be withdrawn. Only claimed
        _require(address(this).balance >= reserveAssetPrincipalWindow, Errors.NOT_ENOUGH_ETH);
        uint256 liquidWeth = IERC20Upgradeable(reserveAsset).balanceOf(address(this));

        // Weth already available
        if (liquidWeth >= _amount) {
            return true;
        }

        // Withdrawal open
        if (block.timestamp <= withdrawalsOpenUntil) {
            IRewardsDistributor rewardsDistributor =
                IRewardsDistributor(IBabController(controller).rewardsDistributor());
            // Pro rata withdrawals
            uint256 contributorPower =
                rewardsDistributor.getContributorPower(
                    address(this),
                    _contributor,
                    contributors[_contributor].initialDepositAt,
                    block.timestamp
                );
            return reserveAssetPrincipalWindow.preciseMul(contributorPower) >= _amount;
        }
        return false;
    }

    /**
     * Gets the total active capital currently invested in strategies
     *
     * @return uint256       Total amount active
     * @return uint256       Total amount active in the largest strategy
     * @return address       Address of the largest strategy
     */
    function _getActiveCapital()
        private
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        uint256 totalActiveCapital;
        uint256 maxAllocation;
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

    /**
     * Function that allows the principal to be updated
     *
     * @param _amount             Amount of the reserve balance
     */
    function _updatePrincipal(uint256 _amount) private {
        uint256 oldAmount = principal;
        principal = _amount;
        emit PrincipalChanged(_amount, oldAmount);
    }

    /**
     * Pays the _feeQuantity from the _garden denominated in _token to the protocol fee recipient
     * @param _token                   Address of the token to pay with
     * @param _feeQuantity             Fee to transfer
     */
    function payProtocolFeeFromGarden(address _token, uint256 _feeQuantity) private {
        if (_feeQuantity > 0) {
            IERC20Upgradeable(_token).safeTransfer(IBabController(controller).treasury(), _feeQuantity);
        }
    }

    // Disable garden token transfers. Allow minting and burning.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 _amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, _amount);
        _require(
            from == address(0) || to == address(0) || IBabController(controller).gardenTokensTransfersEnabled(),
            Errors.GARDEN_TRANSFERS_DISABLED
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
            Errors.DEPOSIT_HARDLOCK
        );
        _require(
            _gardenTokenQuantity <= balanceOf(msg.sender).sub(this.getLockedBalance(msg.sender)),
            Errors.TOKENS_STAKED
        ); // Strategists and Voters cannot withdraw locked stake while in active strategies

        // Check this here to avoid having relayers
        reenableEthForStrategies();

        uint256 reserveAssetQuantity = _getWithdrawalReserveQuantity(reserveAsset, _gardenTokenQuantity);

        (uint256 protocolFees, uint256 netFlowQuantity) = _getFees(reserveAssetQuantity, false);

        uint256 newGardenTokenSupply = totalSupply().sub(_gardenTokenQuantity);

        _require(_canWithdrawEthAmount(msg.sender, netFlowQuantity), Errors.MIN_LIQUIDITY);

        _validateReserveAsset(reserveAsset, netFlowQuantity);

        // Check that new supply is more than min supply needed for withdrawal
        // Note: A min supply amount is needed to avoid division by 0 when withdrawaling garden token to 0
        _require(newGardenTokenSupply >= minGardenTokenSupply, Errors.MIN_TOKEN_SUPPLY);

        _require(netFlowQuantity >= _minReserveReceiveQuantity, Errors.MIN_TOKEN_SUPPLY);

        _burn(msg.sender, _gardenTokenQuantity);

        // Check that the withdrawal is possible
        // Unwrap WETH if ETH balance lower than netFlowQuantity
        if (address(this).balance < netFlowQuantity) {
            IWETH(WETH).withdraw(netFlowQuantity);
        }
        _updateContributorWithdrawalInfo(netFlowQuantity);
        // Send ETH
        Address.sendValue(_to, netFlowQuantity);
        payProtocolFeeFromGarden(reserveAsset, protocolFees);

        uint256 outflow = netFlowQuantity.add(protocolFees);

        // Required withdrawable quantity is greater than existing collateral
        _require(principal >= outflow, Errors.BALANCE_TOO_LOW);
        _updatePrincipal(principal.sub(outflow));

        emit GardenWithdrawal(msg.sender, _to, netFlowQuantity, _gardenTokenQuantity, protocolFees, block.timestamp);
    }

    function _validateReserveAsset(address _reserveAsset, uint256 _quantity) private view {
        _require(_quantity > 0, Errors.GREATER_THAN_ZERO);
        _require(IBabController(controller).isValidReserveAsset(_reserveAsset), Errors.MUST_BE_RESERVE_ASSET);
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

        // Calculate total notional fees
        uint256 protocolFees = protocolFeePercentage.preciseMul(_reserveAssetQuantity);

        uint256 netReserveFlow = _reserveAssetQuantity.sub(protocolFees);

        return (protocolFees, netReserveFlow);
    }

    function _getWithdrawalReserveQuantity(address _reserveAsset, uint256 _gardenTokenQuantity)
        private
        view
        returns (uint256)
    {
        // Get valuation of the Garden with the quote asset as the reserve asset. Returns value in precise units (10e18)
        // Reverts if price is not found
        uint256 gardenValuationPerToken =
            IGardenValuer(IBabController(controller).gardenValuer()).calculateGardenValuation(
                address(this),
                _reserveAsset
            );

        uint256 totalWithdrawalValueInPreciseUnits = _gardenTokenQuantity.preciseMul(gardenValuationPerToken);
        // Get reserve asset decimals
        uint8 reserveAssetDecimals = ERC20Upgradeable(_reserveAsset).decimals();
        uint256 prePremiumReserveQuantity = totalWithdrawalValueInPreciseUnits.preciseMul(10**reserveAssetDecimals);

        return prePremiumReserveQuantity;
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorDepositInfo(address _contributor, uint256 previousBalance) private {
        Contributor storage contributor = contributors[_contributor];
        // If new contributor, create one, increment count, and set the current TS
        if (previousBalance == 0 || contributor.initialDepositAt == 0) {
            totalContributors = totalContributors.add(1);
            contributor.initialDepositAt = block.timestamp;
        }
        // We make checkpoints around contributor deposits to avoid fast loans and give the right rewards afterwards

        contributor.lastDepositAt = block.timestamp;
        IRewardsDistributor rewardsDistributor = IRewardsDistributor(IBabController(controller).rewardsDistributor());
        rewardsDistributor.updateGardenPower(address(this), pid);
        rewardsDistributor.setContributorTimestampParams(address(this), _contributor, previousBalance, true, pid); // true = deposit
        pid++;
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorWithdrawalInfo(uint256 _netflowQuantity) private {
        Contributor storage contributor = contributors[msg.sender];
        // If sold everything
        if (balanceOf(msg.sender) == 0) {
            contributor.lastDepositAt = 0;
            contributor.initialDepositAt = 0;
            contributor.withdrawnSince = 0;
            //delete contributor.timeListPointer;
            totalContributors = totalContributors.sub(1);
        } else {
            contributor.withdrawnSince = contributor.withdrawnSince.add(_netflowQuantity);
        }
        IRewardsDistributor rewardsDistributor = IRewardsDistributor(IBabController(controller).rewardsDistributor());
        rewardsDistributor.updateGardenPower(address(this), pid);
        rewardsDistributor.setContributorTimestampParams(address(this), msg.sender, 0, false, pid); // false = withdraw
        pid++;
    }
}
