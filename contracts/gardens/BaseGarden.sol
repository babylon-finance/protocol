/*
    Copyright 2020 Babylon Finance.

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

import 'hardhat/console.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {ERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IIntegration} from '../interfaces/IIntegration.sol';
import {ITradeIntegration} from '../interfaces/ITradeIntegration.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IStrategyFactory} from '../interfaces/IStrategyFactory.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';

/**
 * @title BaseGarden
 * @author Babylon Finance
 *
 * Abstract Class that holds common garden-related state and functions
 */
abstract contract BaseGarden is ERC20Upgradeable {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for uint256;
    using Address for address;
    using AddressArrayUtils for address[];

    /* ============ Events ============ */
    event IntegrationAdded(address indexed _integration);
    event IntegrationRemoved(address indexed _integration);
    event IntegrationInitialized(address indexed _integration);
    event PendingIntegrationRemoved(address indexed _integration);
    event ReserveAssetChanged(address indexed _integration);
    event PrincipalChanged(uint256 _newAmount, uint256 _oldAmount);
    event GardenTokenDeposited(
        address indexed _to,
        uint256 reserveDeposited,
        uint256 gardenTokenQuantity,
        uint256 protocolFees,
        uint256 timestamp
    );
    event GardenTokenWithdrawn(
        address indexed _from,
        address indexed _to,
        uint256 reserveReceived,
        uint256 gardenTokenQuantity,
        uint256 protocolFees,
        uint256 timestamp
    );

    /* ============ Modifiers ============ */
    modifier onlyContributor {
        _validateOnlyContributor(msg.sender);
        _;
    }

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyProtocol() {
        require(msg.sender == controller, 'Only the controller can call this');
        _;
    }

    /**
     * Throws if the sender is not the garden creator
     */
    modifier onlyCreator() {
        require(msg.sender == creator, 'Only the creator can call this');
        _;
    }

    /**
     * Throws if the sender is not a keeper in the protocol
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     */
    modifier onlyKeeper(uint256 _fee) {
        require(IBabController(controller).isValidKeeper(msg.sender), 'Only a keeper can call this');
        // We assume that calling keeper functions should be less expensive than 1 million gas and the gas price should be lower than 1000 gwei.
        require(_fee < MAX_KEEPER_FEE, 'Fee is too high');
        _;
    }

    /**
     * Throws if the sender is not an investment strategy of this garden
     */
    modifier onlyStrategy() {
        require(
            strategyMapping[msg.sender] && IStrategy(msg.sender).garden() == address(this),
            'Only a strategy of this community'
        );
        _;
    }

    /**
     * Throws if the sender is not an investment strategy or the protocol
     */
    modifier onlyStrategyOrOwner() {
        require(
            (strategyMapping[msg.sender] && IStrategy(msg.sender).garden() == address(this)) ||
                msg.sender == controller,
            'Only the garden strategies or owner can call this'
        );
        _;
    }

    /**
     * Throws if the garden is not active
     */
    modifier onlyActive() {
        _validateOnlyActive();
        _;
    }

    /**
     * Throws if the garden is not disabled
     */
    modifier onlyInactive() {
        _validateOnlyInactive();
        _;
    }

    /* ============ State Constants ============ */

    uint256 public constant MAX_DEPOSITS_FUND_V1 = 1e21; // Max deposit per garden is 1000 eth for v1
    uint256 public constant MAX_TOTAL_IDEAS = 20; // Max number of ideas
    uint256 internal constant TEN_PERCENT = 1e17;
    uint256 internal constant MAX_KEEPER_FEE = (1e6 * 1e3 gwei);

    /* ============ Structs ============ */

    struct Contributor {
        uint256 lastDepositAt;
        uint256 initialDepositAt;
        uint256 claimedAt;
        uint256 numberOfOps;
        uint256 gardenAverageOwnership;
    }

    /* ============ State Variables ============ */

    // Wrapped ETH address
    address public weth;

    // Reserve Asset of the garden
    address public reserveAsset;

    // Address of the controller
    address public controller;
    // The person that creates the garden
    address public creator;
    // Whether the garden is currently active or not
    bool public active;

    // List of initialized Integrations; Integrations connect with other money legos
    address[] public integrations;

    // Keeps track of the reserve balance. In case we receive some through other means
    uint256 principal;
    int256 absoluteReturns; // Total profits or losses of this garden

    // Indicates the minimum liquidity the asset needs to have to be tradable by this garden
    uint256 public minLiquidityAsset;

    // Contributors
    mapping(address => Contributor) public contributors;
    uint256 public totalContributors;
    uint256 public maxDepositLimit; // Limits the amount of deposits

    uint256 public gardenInitializedAt; // Garden Initialized at timestamp

    // Min contribution in the garden
    uint256 public minContribution = 1e18; //wei
    uint256 public minGardenTokenSupply;

    // Investment strategies variables
    uint256 public totalStake = 0;
    uint256 public minVotersQuorum = TEN_PERCENT; // 10%. (0.01% = 1e14, 1% = 1e16)
    uint256 public minIdeaDuration; // Min duration for an investment Idea
    uint256 public maxIdeaDuration; // Max duration for an investment strategy
    uint256 public strategyCooldownPeriod; // Window for the strategy to cooldown after approval before receiving capital

    address[] strategies; // Strategies that are either in candidate or active state
    address[] finalizedStrategies; // Strategies that have finalized execution
    mapping(address => bool) public strategyMapping;

    uint256 public strategyCreatorProfitPercentage = 13e16; // (0.01% = 1e14, 1% = 1e16)
    uint256 public strategyVotersProfitPercentage = 5e16; // (0.01% = 1e14, 1% = 1e16)
    uint256 public gardenCreatorProfitPercentage = 2e16; //

    /* ============ Constructor ============ */

    /**
     * When a new Garden is created.
     * All parameter validations are on the BabController contract. Validations are performed already on the
     * BabController.
     *
     * @param _integrations           List of integrations to enable. All integrations must be approved by the Controller
     * @param _weth                   Address of the WETH ERC20
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _controller             Address of the controller
     * @param _creator                Address of the creator
     * @param _name                   Name of the Garden
     * @param _symbol                 Symbol of the Garden
     */
    function initialize(
        address[] memory _integrations,
        address _weth,
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol
    ) public virtual initializer {
        require(_creator != address(0), 'Creator must not be empty');
        require(_controller != address(0), 'Controller must not be empty');
        require(_reserveAsset != address(0), 'Reserve asset must exist');
        __ERC20_init(_name, _symbol);

        controller = _controller;
        weth = _weth;
        reserveAsset = _reserveAsset;
        creator = _creator;

        for (uint256 i = 0; i < _integrations.length; i++) {
            _addIntegration(_integrations[i]);
        }
        principal = 0;
        active = false;
    }

    /**
     * Virtual function that assigns several garden params. Must be overriden
     *
     * @param _minContribution                  Min contribution to participate in this garden
     * @param _strategyCooldownPeriod               How long after the strategy has been activated, will it be ready to be executed
     * @param _strategyCreatorProfitPercentage      What percentage of the profits go to the strategy creator
     * @param _strategyVotersProfitPercentage       What percentage of the profits go to the strategy curators
     * @param _gardenCreatorProfitPercentage What percentage of the profits go to the creator of the garden
     * @param _minVotersQuorum                  Percentage of votes needed to activate an investment strategy (0.01% = 1e14, 1% = 1e16)
     * @param _minIdeaDuration                  Min duration of an investment strategy
     * @param _maxIdeaDuration                  Max duration of an investment strategy
     */
    function startCommon(
        uint256 _minContribution,
        uint256 _strategyCooldownPeriod,
        uint256 _strategyCreatorProfitPercentage,
        uint256 _strategyVotersProfitPercentage,
        uint256 _gardenCreatorProfitPercentage,
        uint256 _minVotersQuorum,
        uint256 _minIdeaDuration,
        uint256 _maxIdeaDuration
    ) internal {
        require(
            _strategyCooldownPeriod <= IBabController(controller).getMaxCooldownPeriod() &&
                _strategyCooldownPeriod >= IBabController(controller).getMinCooldownPeriod(),
            'Garden cooldown must be within the range allowed by the protocol'
        );
        require(_minVotersQuorum >= TEN_PERCENT, 'You need at least 10% votes');
        minContribution = _minContribution;
        strategyCreatorProfitPercentage = _strategyCreatorProfitPercentage;
        strategyVotersProfitPercentage = _strategyVotersProfitPercentage;
        gardenCreatorProfitPercentage = _gardenCreatorProfitPercentage;
        strategyCooldownPeriod = _strategyCooldownPeriod;
        minVotersQuorum = _minVotersQuorum;
        minIdeaDuration = _minIdeaDuration;
        maxIdeaDuration = _maxIdeaDuration;
    }

    /* ============ External Functions ============ */

    /**
     * PRIVILEGED Manager, protocol FUNCTION. Changes the reserve asset
     *
     * @param _reserveAsset                 Address of the new reserve asset
     */
    function editReserveAsset(address _reserveAsset) external onlyProtocol {
        reserveAsset = _reserveAsset;

        emit ReserveAssetChanged(_reserveAsset);
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Garden is disabled, deposits are disabled.
     */
    function setActive() external onlyProtocol {
        require(!active && integrations.length > 0, 'Must have active integrations to enable a garden');
        active = true;
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Garden is disabled, deposits are disabled.
     */
    function setDisabled() external onlyProtocol {
        require(active, 'The garden must be active');
        active = false;
    }

    /**
     * Function that allows the reserve balance to be updated
     *
     * @param _amount             Amount of the reserve balance
     */
    function updatePrincipal(uint256 _amount) external onlyStrategy {
        _updatePrincipal(_amount);
    }

    /* ============ Investment Idea Functions ============ */
    /**
     * Creates a new investment strategy calling the factory and adds it to the array
     * @param _strategyKind                  Int representing kind of strategy
     * @param _maxCapitalRequested           Max Capital requested denominated in the reserve asset (0 to be unlimited)
     * @param _stake                         Stake with garden participations absolute amounts 1e18
     * @param _investmentDuration            Investment duration in seconds
     * @param _expectedReturn                Expected return
     * @param _minRebalanceCapital           Min capital that is worth it to deposit into this strategy
     */
    function addStrategy(
        uint8 _strategyKind,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _investmentDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital
    ) external onlyContributor onlyActive {
        require(strategies.length < MAX_TOTAL_IDEAS, 'Reached the limit of strategies');
        IStrategyFactory strategyFactory = IStrategyFactory(IBabController(controller).getStrategyFactory());
        address strategy =
            strategyFactory.createStrategy(
                _strategyKind,
                msg.sender,
                address(this),
                controller,
                _maxCapitalRequested,
                _stake,
                _investmentDuration,
                _expectedReturn,
                _minRebalanceCapital
            );
        strategyMapping[strategy] = true;
        totalStake = totalStake.add(_stake);
        strategies.push(strategy);
    }

    /**
     * Rebalances available capital of the garden between the investment strategies that are active.
     * We enter into the investment and add it to the executed strategies array.
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     */
    function rebalanceInvestments(uint256 _fee) external onlyKeeper(_fee) onlyActive {
        uint256 liquidReserveAsset = ERC20Upgradeable(reserveAsset).balanceOf(address(this));
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            uint256 percentage = strategy.totalVotes().toUint256().preciseDiv(totalStake);
            uint256 toAllocate = liquidReserveAsset.preciseMul(percentage);
            if (
                toAllocate >= strategy.minRebalanceCapital() &&
                toAllocate.add(strategy.capitalAllocated()) <= strategy.maxCapitalRequested()
            ) {
                strategy.executeInvestment(toAllocate, 0);
            }
        }
        _payKeeper(msg.sender, _fee);
    }

    /**
     * Pays gas cost back to the keeper from executing a transaction
     * @param _keeper             Keeper that executed the transaction
     * @param _fee                The fee paid to keeper to compensate the gas cost
     */
    function payKeeper(address payable _keeper, uint256 _fee) external onlyStrategy onlyActive {
        _payKeeper(_keeper, _fee);
    }

    /**
     * Allocates garden capital to an investment
     *
     * @param _capital        Amount of capital to allocate to the investment
     */
    function allocateCapitalToInvestment(uint256 _capital) external onlyStrategy onlyActive {
        uint256 liquidReserveAsset = ERC20Upgradeable(reserveAsset).balanceOf(address(this));
        uint256 protocolMgmtFee = IBabController(controller).getProtocolManagementFee().preciseMul(_capital);
        require(_capital.add(protocolMgmtFee) <= liquidReserveAsset, 'Not enough capital');

        // Take protocol mgmt fee
        require(
            ERC20Upgradeable(reserveAsset).transfer(IBabController(controller).getTreasury(), protocolMgmtFee),
            'Protocol Mgmt fee failed'
        );

        // Send Capital to strategy
        require(
            ERC20Upgradeable(reserveAsset).transfer(msg.sender, _capital),
            'Failed to allocate capital to the investment'
        );
    }

    // Any tokens (other than the target) that are sent here by mistake are recoverable by contributors
    // Exchange for WETH
    function sweep(address _token) external onlyContributor {
        require(_token != reserveAsset, 'Token is not the reserve asset');
        uint256 balance = ERC20Upgradeable(_token).balanceOf(address(this));
        require(balance > 0, 'Token balance > 0');
        bytes memory _emptyTradeData;
        ERC20Upgradeable(_token).transfer(msg.sender, balance);
    }

    /*
     * Moves an estrategy from the active array to the finalized array
     * @param _returns       Positive or negative returns of the strategy
     * @param _strategy      Strategy to move from active to finalized
     */
    function moveStrategyToFinalized(int256 _returns, address _strategy) external onlyStrategy {
        absoluteReturns.add(_returns);
        strategies.remove(_strategy);
        finalizedStrategies.push(_strategy);
    }

    /*
     * Remove an expire candidate from the strategy Array
     * @param _strategy      Strategy to remove
     */
    function expireCandidateStrategy(address _strategy) external onlyStrategy {
        strategies.remove(_strategy);
    }

    /* ============ External Getter Functions ============ */

    /**
     * Gets current investment strategies
     *
     * @return  address[]        Returns list of addresses
     */

    function getStrategies() public view returns (address[] memory) {
        return strategies;
    }

    function isStrategy(address _strategy) external view returns (bool) {
        return strategyMapping[_strategy];
    }

    function getPrincipal() external view returns (uint256) {
        return principal;
    }

    function getReserveAsset() external view returns (address) {
        return reserveAsset;
    }

    function getIntegrations() external view returns (address[] memory) {
        return integrations;
    }

    /**
     * Check if this garden has this integration
     */
    function hasIntegration(address _integration) external view returns (bool) {
        return integrations.contains(_integration);
    }

    function isValidIntegration(address _integration) public view returns (bool) {
        return
            integrations.contains(_integration) &&
            IBabController(controller).isValidIntegration(IIntegration(_integration).getName(), _integration);
    }

    function getContributor(address _contributor)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        Contributor memory contributor = contributors[_contributor];
        return (
            contributor.lastDepositAt,
            contributor.initialDepositAt,
            contributor.claimedAt,
            contributor.numberOfOps,
            contributor.gardenAverageOwnership
        );
    }

    /* ============ Internal Functions ============ */

    /**
     * Updates the TWAP prices for the garden positions
     *
     */
    function updatePositionTWAPPrices() public {
        // Updates UniSwap TWAP
        address oracle = IBabController(controller).getPriceOracle();
        address[] memory strategiesC = getStrategies();
        for (uint256 j = 0; j < strategiesC.length; j++) {
            IStrategy strategy = IStrategy(strategiesC[j]);
            address[] memory components = strategy.getPositions();
            if (strategy.active()) {
                for (uint256 i = 0; i < components.length; i++) {
                    if (components[i] != reserveAsset) {
                        IPriceOracle(oracle).updateAdapters(reserveAsset, components[i]);
                    }
                }
            }
        }
    }

    /**
     * Function that allows the reserve balance to be updated
     *
     * @param _amount             Amount of the reserve balance
     */
    function _updatePrincipal(uint256 _amount) internal {
        uint256 oldAmount = principal;
        principal = _amount;
        emit PrincipalChanged(_amount, oldAmount);
    }

    function _addIntegration(address _integration) internal {
        require(!integrations.contains(_integration), 'Integration already added');

        integrations.push(_integration);

        emit IntegrationAdded(_integration);
    }

    function _getPrice(address _assetOne, address _assetTwo) internal view returns (uint256) {
        IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
        return oracle.getPrice(_assetOne, _assetTwo);
    }

    /**
     * Pays the _feeQuantity from the _garden denominated in _token to the protocol fee recipient
     */
    function payProtocolFeeFromGarden(address _token, uint256 _feeQuantity) internal {
        if (_feeQuantity > 0) {
            require(
                ERC20Upgradeable(_token).transfer(IBabController(controller).getTreasury(), _feeQuantity),
                'Protocol fee failed'
            );
        }
    }

    function _validateOnlyActive() internal view {
        require(active == true, 'Garden must be active');
    }

    function _validateOnlyInactive() internal view {
        require(active == false, 'Garden must be disabled');
    }

    function _validateOnlyContributor(address _caller) internal view {
        require(balanceOf(_caller) > 0, 'Only participant can withdraw');
    }

    /**
     * Pays gas cost back to the keeper from executing a transaction
     * @param _keeper             Keeper that executed the transaction
     * @param _fee                The fee paid to keeper to compensate the gas cost
     */
    function _payKeeper(address payable _keeper, uint256 _fee) internal {
        require(IBabController(controller).isValidKeeper(_keeper), 'Only a keeper can call this');
        require(ERC20Upgradeable(reserveAsset).balanceOf(address(this)) >= _fee, 'Not enough WETH for gas subsidy');
        // TODO: This assumes reserve asset is WETH
        // TODO: This assume garden have enought WETH
        // Pay Keeper in WETH
        if (_fee > 0) {
            require(ERC20Upgradeable(reserveAsset).transfer(_keeper, _fee), 'Not enough WETH for gas subsidy');
        }
    }

    // Disable garden token transfers. Allow minting and burning.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 /* amount */
    ) internal view override {
        require(
            from == address(0) || to == address(0) || IBabController(controller).gardenTokensTransfersEnabled(),
            'Garden token transfers are disabled'
        );
    }

    function abs(int256 x) private pure returns (int256) {
        return x >= 0 ? x : -x;
    }
}
