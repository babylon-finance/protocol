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

//import 'hardhat/console.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {ERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {IBabController} from '../interfaces/IBabController.sol';
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
    event ReserveAssetChanged(address indexed _reserveAsset);
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
        require(balanceOf(msg.sender) > 0, 'G01'); // Only Contributor
        _;
    }

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyProtocol() {
        require(msg.sender == controller, 'G02'); // Only controller
        _;
    }

    /**
     * Throws if the sender is not the garden creator
     */
    modifier onlyCreator() {
        require(msg.sender == creator, 'G03'); // Only creator
        _;
    }

    /**
     * Throws if the sender is not a keeper in the protocol
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     */
    modifier onlyKeeper(uint256 _fee) {
        require(IBabController(controller).isValidKeeper(msg.sender), 'G04'); // Only keeper
        // We assume that calling keeper functions should be less expensive than 1 million gas and the gas price should be lower than 1000 gwei.
        require(_fee < MAX_KEEPER_FEE, 'G05'); // Fee is too high
        _;
    }

    /**
     * Throws if the sender is not an investment strategy of this garden
     */
    modifier onlyStrategy() {
        require(
            strategyMapping[msg.sender] && IStrategy(msg.sender).garden() == address(this),
            'G06' // Only a strategy of this garden
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
            'G07' // Only the strategy or the protocol
        );
        _;
    }

    /**
     * Throws if the garden is not active
     */
    modifier onlyActive() {
        require(active == true, 'G08'); // Only active garden
        _;
    }

    /**
     * Throws if the garden is not disabled
     */
    modifier onlyInactive() {
        require(active == false, 'G09'); // Only inactive garden
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
        uint256 claimedBABL;
        uint256 claimedProfits;
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

    // Keeps track of the reserve balance. In case we receive some through other means
    uint256 public principal;
    int256 public absoluteReturns; // Total profits or losses of this garden

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

    address[] public strategies; // Strategies that are either in candidate or active state
    address[] public finalizedStrategies; // Strategies that have finalized execution
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
     * @param _weth                   Address of the WETH ERC20
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _controller             Address of the controller
     * @param _creator                Address of the creator
     * @param _name                   Name of the Garden
     * @param _symbol                 Symbol of the Garden
     */
    function initialize(
        address _weth,
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol
    ) public virtual initializer {
        require(_creator != address(0), 'G10');
        require(_controller != address(0), 'G11');
        require(_reserveAsset != address(0), 'G12');
        __ERC20_init(_name, _symbol);

        controller = _controller;
        weth = _weth;
        reserveAsset = _reserveAsset;
        creator = _creator;
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
            'G13' // Garden cooldown not within range
        );
        require(_minVotersQuorum >= TEN_PERCENT, 'G14'); // You need at least 10%
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
        require(!active, 'G15'); // Garden already active
        active = true;
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Garden is disabled, deposits are disabled.
     */
    function setDisabled() external onlyProtocol {
        require(active, 'G16'); // Garden is not active
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
     * @param _integration                   Address of the integration
     * @param _maxCapitalRequested           Max Capital requested denominated in the reserve asset (0 to be unlimited)
     * @param _stake                         Stake with garden participations absolute amounts 1e18
     * @param _investmentDuration            Investment duration in seconds
     * @param _expectedReturn                Expected return
     * @param _minRebalanceCapital           Min capital that is worth it to deposit into this strategy
     */
    function addStrategy(
        uint8 _strategyKind,
        address _integration,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _investmentDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital
    ) external onlyContributor onlyActive {
        require(strategies.length < MAX_TOTAL_IDEAS, 'G17'); // reached limit of strategies
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
     * @param _fee                     The fee paid to keeper to compensate the gas cost for each strategy executed
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
                strategy.executeInvestment(toAllocate, _fee);
            }
        }
    }

    /**
     * Allocates garden capital to an investment
     *
     * @param _capital        Amount of capital to allocate to the investment
     */
    function allocateCapitalToInvestment(uint256 _capital) external onlyStrategy onlyActive {
        uint256 liquidReserveAsset = ERC20Upgradeable(reserveAsset).balanceOf(address(this));
        uint256 protocolMgmtFee = IBabController(controller).getProtocolManagementFee().preciseMul(_capital);
        require(_capital.add(protocolMgmtFee) <= liquidReserveAsset, 'G18'); // not enough capital

        // Take protocol mgmt fee
        require(
            ERC20Upgradeable(reserveAsset).transfer(IBabController(controller).getTreasury(), protocolMgmtFee),
            'G19' // failed to pay mgmt fee
        );

        // Send Capital to strategy
        require(
            ERC20Upgradeable(reserveAsset).transfer(msg.sender, _capital),
            'G20' // fail to allocate capital to strategy
        );
    }

    // Any tokens (other than the target) that are sent here by mistake are recoverable by contributors
    // Exchange for WETH
    function sweep(address _token) external onlyContributor {
        require(_token != reserveAsset, 'G21'); // token is reserve asset
        uint256 balance = ERC20Upgradeable(_token).balanceOf(address(this));
        require(balance > 0, 'G26'); // nothing to sweep
        ERC20Upgradeable(_token).transfer(msg.sender, balance);
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
    }

    /*
     * Remove an expire candidate from the strategy Array
     * @param _strategy      Strategy to remove
     */
    function expireCandidateStrategy(address _strategy) external onlyStrategy {
        strategies = strategies.remove(_strategy);
    }

    function burnStrategistStake(address _strategist, uint256 _amount) external onlyStrategy {
        _burn(_strategist, _amount);
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

    /**
     * Gets finalized investment strategies
     *
     * @return  address[]        Returns list of addresses
     */

    function getFinalizedStrategies() public view returns (address[] memory) {
        return finalizedStrategies;
    }

    function isStrategy(address _strategy) external view returns (bool) {
        return strategyMapping[_strategy];
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
     * Function that allows the reserve balance to be updated
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
     */
    function payProtocolFeeFromGarden(address _token, uint256 _feeQuantity) internal {
        if (_feeQuantity > 0) {
            require(
                ERC20Upgradeable(_token).transfer(IBabController(controller).getTreasury(), _feeQuantity),
                'G22' // Failed to pay protocol fee
            );
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
            'G26' // garden transfers are disabled
        );
    }
}
