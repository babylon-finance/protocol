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

// import "hardhat/console.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { AddressArrayUtils } from "../lib/AddressArrayUtils.sol";
import { IBabController } from "../interfaces/IBabController.sol";
import { IIntegration } from "../interfaces/IIntegration.sol";
import { ITradeIntegration } from "../interfaces/ITradeIntegration.sol";
import { IPriceOracle } from "../interfaces/IPriceOracle.sol";
import { ICommunity } from "../interfaces/ICommunity.sol";
import { IIdeaFactory } from "../interfaces/IIdeaFactory.sol";
import { IInvestmentIdea } from "../interfaces/IInvestmentIdea.sol";
import { PreciseUnitMath } from "../lib/PreciseUnitMath.sol";

/**
 * @title BaseCommunity
 * @author Babylon Finance
 *
 * Abstract Class that holds common community-related state and functions
 */
abstract contract BaseCommunity is ERC20Upgradeable {
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
    event ReserveBalanceChanged(uint256 _newAmount, uint256 _oldAmount);
    event CommunityTokenDeposited(
        address indexed _to,
        uint256 communityTokenQuantity,
        uint256 protocolFees
    );
    event CommunityTokenWithdrawn(
        address indexed _from,
        address indexed _to,
        uint256 communityTokenQuantity,
        uint256 protocolFees
    );

    event ContributionLog(
        address indexed contributor,
        uint256 amount,
        uint256 tokensReceived,
        uint256 timestamp
    );
    event WithdrawalLog(
        address indexed sender,
        uint256 amount,
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
      require(msg.sender == controller, "Only the controller can call this");
      _;
    }

    /**
     * Throws if the sender is not the community governance. (Initially protocol)
     */
    modifier onlyGovernanceCommunity() {
      require(msg.sender == creator, "Only the creator can call this");
      _;
    }

    /**
     * Throws if the sender is not the community creator
     */
    modifier onlyCreator() {
      require(msg.sender == creator, "Only the creator can call this");
      _;
    }

    /**
     * Throws if the sender is not a keeper in the protocol
     */
    modifier onlyKeeper() {
      require(IBabController(controller).isValidKeeper(msg.sender), "Only a keeper can call this");
      _;
    }

    /**
     * Throws if the sender is not an investment idea of this community
     */
    modifier onlyInvestmentIdea() {
      require(isInvestmentIdea[msg.sender], "Only the community ideas contract can call this");
      _;
    }

    /**
     * Throws if the sender is not an investment idea or the protocol
     */
    modifier onlyInvestmentIdeaOrOwner() {
      require(isInvestmentIdea[msg.sender] || msg.sender == controller, "Only the community ideas or owner can call this");
      _;
    }

    /**
    * Throws if the community is not active
    */
    modifier onlyActive() {
        _validateOnlyActive();
        _;
    }

    /**
    * Throws if the community is not disabled
    */
    modifier onlyInactive() {
        _validateOnlyInactive();
        _;
    }

    /* ============ Structs ============ */

    struct Contributor {
        uint256 totalDeposit; //wei
        uint256 tokensReceived;
        uint256 timestamp;
    }

    /* ============ State Variables ============ */
    uint256 constant public initialBuyRate = 1000000000000; // Initial buy rate for the manager
    uint256 constant public MAX_DEPOSITS_FUND_V1 = 1e21; // Max deposit per community is 1000 eth for v1
    uint256 constant public MAX_TOTAL_IDEAS = 20; // Max deposit per community is 1000 eth for v1
    // Wrapped ETH address
    address public weth;

    // Reserve Asset of the community
    address public reserveAsset;

    // Address of the controller
    address public controller;
    // The person that creates the community
    address public creator;
    // Whether the community is currently active or not
    bool public active;

    // List of initialized Integrations; Integrations connect with other money legos
    address[] public integrations;

    // Keeps track of the reserve balance. In case we receive some through other means
    uint256 reserveBalance;

    // Indicates the minimum liquidity the asset needs to have to be tradable by this community
    uint256 public minLiquidityAsset;

    // Contributors
    mapping(address => Contributor) public contributors;
    uint256 public totalContributors;
    uint256 public totalFundsDeposited;
    uint256 public totalFunds;
    uint256 public maxDepositLimit;                // Limits the amount of deposits

    uint256 public communityInitializedAt;         // Community Initialized at timestamp

    // Min contribution in the community
    uint256 public minContribution = initialBuyRate; //wei
    uint256 public minCommunityTokenSupply;

    // Investment ideas variables
    uint256 public totalStake = 0;
    uint256 public minVotersQuorum = 1e17;          // 10%. (0.01% = 1e14, 1% = 1e16)
    uint256 public minIdeaDuration;               // Min duration for an investment Idea
    uint256 public maxIdeaDuration;               // Max duration for an investment idea
    uint256 public ideaCooldownPeriod;            // Window for the idea to cooldown after approval before receiving capital

    address[] ideas;
    mapping(address => bool) public isInvestmentIdea;

    uint256 public ideaCreatorProfitPercentage = 13e16; // (0.01% = 1e14, 1% = 1e16)
    uint256 public ideaVotersProfitPercentage = 5e16; // (0.01% = 1e14, 1% = 1e16)
    uint256 public communityCreatorProfitPercentage = 2e16; //

    /* ============ Constructor ============ */

    /**
     * When a new Community is created.
     * All parameter validations are on the BabController contract. Validations are performed already on the
     * BabController.
     *
     * @param _integrations           List of integrations to enable. All integrations must be approved by the Controller
     * @param _weth                   Address of the WETH ERC20
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _controller             Address of the controller
     * @param _creator                Address of the creator
     * @param _name                   Name of the Community
     * @param _symbol                 Symbol of the Community
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
        require(_creator != address(0), "Creator must not be empty");
        __ERC20_init(_name, _symbol);

        controller = _controller;
        weth = _weth;
        reserveAsset = _reserveAsset;
        creator = _creator;

        for (uint i = 0; i < _integrations.length; i++) {
          _addIntegration(_integrations[i]);
        }

        active = false;
    }

    /**
    * Virtual function that assigns several community params. Must be overriden
    *
    * @param _minContribution                  Min contribution to participate in this community
    * @param _ideaCooldownPeriod               How long after the idea has been activated, will it be ready to be executed
    * @param _ideaCreatorProfitPercentage      What percentage of the profits go to the idea creator
    * @param _ideaVotersProfitPercentage       What percentage of the profits go to the idea curators
    * @param _communityCreatorProfitPercentage What percentage of the profits go to the creator of the community
    * @param _minVotersQuorum                  Percentage of votes needed to activate an investment idea (0.01% = 1e14, 1% = 1e16)
    * @param _minIdeaDuration                  Min duration of an investment idea
    * @param _maxIdeaDuration                  Max duration of an investment idea
    */
    function startCommon (
      uint256 _minContribution,
      uint256 _ideaCooldownPeriod,
      uint256 _ideaCreatorProfitPercentage,
      uint256 _ideaVotersProfitPercentage,
      uint256 _communityCreatorProfitPercentage,
      uint256 _minVotersQuorum,
      uint256 _minIdeaDuration,
      uint256 _maxIdeaDuration
    ) internal {
      require(
          _ideaCooldownPeriod <= IBabController(controller).getMaxCooldownPeriod() && _ideaCooldownPeriod >= IBabController(controller).getMinCooldownPeriod() ,
          "Community cooldown must be within the range allowed by the protocol"
      );
      require(_minVotersQuorum >= 1e17, "You need at least 10% votes");
      minContribution = _minContribution;
      ideaCreatorProfitPercentage = _ideaCreatorProfitPercentage;
      ideaVotersProfitPercentage = _ideaVotersProfitPercentage;
      communityCreatorProfitPercentage = _communityCreatorProfitPercentage;
      ideaCooldownPeriod = _ideaCooldownPeriod;
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
     * PRIVILEGED Manager, protocol FUNCTION. When a Community is disabled, deposits are disabled.
     */
    function setActive() external onlyProtocol {
      require(!active && integrations.length > 0,
          "Must have active integrations to enable a community"
      );
      active = true;
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Community is disabled, deposits are disabled.
     */
    function setDisabled() external onlyProtocol {
      require(active, "The community must be active");
      active = false;
    }

    /**
     * MANAGER ONLY. Adds an integration into the list of integrations
     */
    function addIntegration(address _integration)
        public
        onlyGovernanceCommunity
    {
        _addIntegration(_integration);
    }

    /**
     * CREATOR ONLY. Removes an integration from the Community. Community calls removeIntegration on integration itself to confirm
     * it is not needed to manage any remaining positions and to remove state.
     */
    function removeIntegration(address _integration) external onlyGovernanceCommunity {
        require(integrations.contains(_integration), "Integration not found");

        integrations = integrations.remove(_integration);

        emit IntegrationRemoved(_integration);
    }

    /**
     * CREATOR ONLY. Initializes an integration in a community
     *
     * @param  _integration       Address of the integration contract to add
     */
    function initializeIntegration(address _integration)
        public
        onlyGovernanceCommunity
    {
      IIntegration(_integration).initialize(address(this));
    }

    /**
     * Function that allows the reserve balance to be updated
     *
     * @param _amount             Amount of the reserve balance
     */
    function updateReserveBalance(uint256 _amount) external onlyInvestmentIdea {
      _updateReserveBalance(_amount);
    }

    /* ============ Investment Idea Functions ============ */
    /**
     * Creates a new investment idea calling the factory and adds it to the array
     * @param _maxCapitalRequested           Max Capital requested denominated in the reserve asset (0 to be unlimited)
     * @param _stake                         Stake with community participations absolute amounts 1e18
     * @param _investmentDuration            Investment duration in seconds
     * @param _expectedReturn                Expected return
     * @param _minRebalanceCapital           Min capital that is worth it to deposit into this idea
     * TODO: Meta Transaction
     */
    function addInvestmentIdea(
      uint256 _maxCapitalRequested,
      uint256 _stake,
      uint256 _investmentDuration,
      uint256 _expectedReturn,
      uint256 _minRebalanceCapital
    ) external onlyContributor onlyActive {
      require(ideas.length < MAX_TOTAL_IDEAS, "Reached the limit of ideas");
      IIdeaFactory ideaFactory = IIdeaFactory(IBabController(controller).getIdeaFactory());
      address idea = ideaFactory.createInvestmentIdea(
        msg.sender,
        controller,
        _maxCapitalRequested,
        _stake,
        _investmentDuration,
        _expectedReturn,
        _minRebalanceCapital
      );
      isInvestmentIdea[idea] = true;
      totalStake = totalStake.add(_stake);
      ideas.push(idea);
    }

    /**
     * Rebalances available capital of the community between the investment ideas that are active.
     * We enter into the investment and add it to the executed ideas array.
     */
    function rebalanceInvestments() external onlyKeeper onlyActive {
      uint256 liquidReserveAsset = ERC20Upgradeable(reserveAsset).balanceOf(address(this));
      for (uint i = 0; i < ideas.length; i++) {
        IInvestmentIdea idea = IInvestmentIdea(ideas[i]);
        uint256 percentage = idea.totalVotes().toUint256().preciseDiv(totalStake);
        uint256 toAllocate = liquidReserveAsset.preciseMul(percentage);
        if (toAllocate >= idea.minRebalanceCapital() && toAllocate.add(idea.capitalAllocated()) <= idea.maxCapitalRequested()) {
          idea.executeInvestment(toAllocate);
        }
      }
    }

    /**
     * Allocates community capital to an investment
     *
     * @param _capital        Amount of capital to allocate to the investment
     */
    function allocateCapitalToInvestment(uint256 _capital) external onlyInvestmentIdea onlyActive {
      uint256 liquidReserveAsset = ERC20Upgradeable(reserveAsset).balanceOf(address(this));
      require(_capital <= liquidReserveAsset, "Not enough capital");
      require(ERC20Upgradeable(reserveAsset).transfer(
          msg.sender,
          _capital
      ), "Failed to allocate capital to the investment");
    }

    /* ============ External Getter Functions ============ */

    /**
     * Gets current investment ideas
     *
     * @return  address[]        Returns list of addresses
     */

    function getIdeas() public view returns (address[] memory) {
      return ideas;
    }

    function getReserveBalance() external view returns (uint256) {
      return reserveBalance;
    }

    function getReserveAsset() external view returns (address) {
      return reserveAsset;
    }

    function getIntegrations() external view returns (address[] memory) {
        return integrations;
    }

    /**
     * Check if this community has this integration
     */
    function hasIntegration(address _integration)
        external
        view
        returns (bool)
    {
        return integrations.contains(_integration);
    }

    function isValidIntegration(address _integration) public view returns (bool) {
      return integrations.contains(_integration); //IBabController(controller).isValidIntegration(IIntegration(_integration).getName(), _integration);
    }

    /* ============ Internal Functions ============ */

    /**
     * Function that calculates the price using the oracle and executes a trade.
     * Must call the exchange to get the price and pass minReceiveQuantity accordingly.
     * @param _integrationName        Name of the integration to call
     * @param _sendToken              Token to exchange
     * @param _sendQuantity           Amount of tokens to send
     * @param _receiveToken           Token to receive
     * @param _minReceiveQuantity     Min amount of tokens to receive
     * @param _data                   Bytes call data
     */
    function _trade(
      string memory _integrationName,
      address _sendToken,
      uint256 _sendQuantity,
      address _receiveToken,
      uint256 _minReceiveQuantity,
      bytes memory _data) internal
    {
      address tradeIntegration = IBabController(controller).getIntegrationByName(_integrationName);
      require(
          isValidIntegration(tradeIntegration),
          "Integration needs to be added to the community and controller"
      );
      // Updates UniSwap TWAP
      IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
      oracle.updateAdapters(_sendToken, _receiveToken);
      return ITradeIntegration(tradeIntegration).trade(_sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity, _data);
    }

    /**
     * Function that allows the reserve balance to be updated
     *
     * @param _amount             Amount of the reserve balance
     */
    function _updateReserveBalance(uint256 _amount) internal {
      uint256 oldAmount = reserveBalance;
      reserveBalance = _amount;
      emit ReserveBalanceChanged(_amount, oldAmount);
    }

    function _addIntegration(address _integration) internal
    {
        require(!integrations.contains(_integration), "Integration already added");

        integrations.push(_integration);

        emit IntegrationAdded(_integration);
    }

    function _getPrice(address _assetOne, address _assetTwo) view internal returns (uint256) {
      IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
      return oracle.getPrice(_assetOne, _assetTwo);
    }

    /**
     * Pays the _feeQuantity from the _community denominated in _token to the protocol fee recipient
     */
    function payProtocolFeeFromCommunity(address _token, uint256 _feeQuantity)
        internal
    {
        if (_feeQuantity > 0) {
            require(ERC20Upgradeable(_token).transfer(
                IBabController(controller).getTreasury(),
                _feeQuantity
            ), "Protocol fee failed");
        }
    }

    function _validateOnlyActive() internal view {
        require(active == true, "Community must be active");
    }

    function _validateOnlyInactive() internal view {
        require(active == false, "Community must be disabled");
    }

    function _validateOnlyContributor(address _caller) internal view {
        require(
            balanceOf(_caller) > 0,
            "Only participant can withdraw"
        );
    }

    // Disable community token transfers. Allow minting and burning.
    function _beforeTokenTransfer(address from, address to, uint256 /* amount */) override view internal {
      require(from == address(0) || to == address(0) || IBabController(controller).communityTokensTransfersEnabled(), "Community token transfers are disabled");
    }

    function abs(int x) private pure returns (int) {
      return x >= 0 ? x : -x;
    }
}
