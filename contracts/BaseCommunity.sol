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
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { AddressArrayUtils } from "./lib/AddressArrayUtils.sol";
import { IBabController } from "./interfaces/IBabController.sol";
import { IIntegration } from "./interfaces/IIntegration.sol";
import { ITradeIntegration } from "./interfaces/ITradeIntegration.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { ICommunity } from "./interfaces/ICommunity.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";

/**
 * @title BaseCommunity
 * @author Babylon Finance
 *
 * Abstract Class that holds common community-related state and functions
 */
abstract contract BaseCommunity is ERC20 {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for uint256;
    using Address for address;
    using AddressArrayUtils for address[];

    /* ============ Events ============ */
    event Invoked(address indexed _target, uint indexed _value, bytes _data, bytes _returnValue);
    event IntegrationAdded(address indexed _integration);
    event IntegrationRemoved(address indexed _integration);
    event IntegrationInitialized(address indexed _integration);
    event PendingIntegrationRemoved(address indexed _integration);
    event ReserveAssetChanged(address indexed _integration);
    event ReserveBalanceChanged(uint256 _newAmount, uint256 _oldAmount);

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not a Communities's integration or integration not enabled
     */
    modifier onlyIntegration() {
      // Internal function used to reduce bytecode size
      _validateOnlyIntegration(msg.sender);
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
     * Throws if the sender is not a keeper in the protocol
     */
    modifier onlyInvestmentIdea() {
      require(msg.sender == communityIdeas, "Only the community ideas contract can call this");
      _;
    }

    /**
     * Throws if the sender is not an investment idea or owner (for testing)
     * TODO: Remove when deploying
     */
    modifier onlyInvestmentIdeaOrOwner() {
      require(msg.sender == communityIdeas || msg.sender == IBabController(controller).owner(), "Only the community ideas contract can call this");
      _;
    }

    /**
     * Throws if the sender is not an investment idea or integration
     */
    modifier onlyInvestmentAndIntegration() {
      require(msg.sender == communityIdeas || isValidIntegration(msg.sender), "Only the community ideas contract can call this");
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

    // Wrapped ETH address
    address public immutable weth;

    // Reserve Asset of the community
    address public reserveAsset;

    // Address of the controller
    address public controller;
    // The person that creates the community
    address public creator;
    // Whether the community is currently active or not
    bool public active;

    // CommunityIdeas
    address public communityIdeas;

    // List of initialized Integrations; Integrations connect with other money legos
    address[] public integrations;

    // Keeps track of the reserve balance. In case we receive some through other means
    uint256 reserveBalance;

    // Indicates the minimum liquidity the asset needs to have to be tradable by this community
    uint256 public minLiquidityAsset;

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

    constructor(
        address[] memory _integrations,
        address _weth,
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        require(_creator != address(0), "Creator must not be empty");

        controller = _controller;
        weth = _weth;
        reserveAsset = _reserveAsset;
        creator = _creator;

        for (uint i = 0; i < _integrations.length; i++) {
          _addIntegration(_integrations[i]);
        }

        active = false;
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

    function invokeApprove(address _spender, address _asset, uint256 _quantity) external onlyIntegration {
      ERC20(_asset).approve(_spender, 0);
      ERC20(_asset).approve(_spender, _quantity);
    }

    function invokeFromIntegration(
      address _target,
      uint256 _value,
      bytes calldata _data
    ) external onlyIntegration returns (bytes memory) {
      return _invoke(_target, _value, _data);
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

    /* ============ Trade Integration hooks ============ */

    /**
     * Function that allows the manager to call an integration
     *
     * @param _integration            Address of the integration to call
     * @param _value                  Quantity of Ether to provide the call (typically 0)
     * @param _data                   Encoded function selector and arguments
     * @param _tokensNeeded           Tokens that we need to acquire more of before executing the investment
     * @param _tokenAmountsNeeded     Tokens amounts that we need. Same index.
     * @return _returnValue           Bytes encoded return value
     */
    function callIntegration(
      address _integration,
      uint256 _value,
      bytes memory _data,
      address[] memory _tokensNeeded,
      uint256[] memory _tokenAmountsNeeded
    )
    public onlyInvestmentIdeaOrOwner returns (bytes memory _returnValue) {
      require(_tokensNeeded.length == _tokenAmountsNeeded.length);
      _validateOnlyIntegration(_integration);
      // Exchange the tokens needed
      for (uint i = 0; i < _tokensNeeded.length; i++) {
        if (_tokensNeeded[i] != reserveAsset) {
          uint pricePerTokenUnit = _getPrice(reserveAsset, _tokensNeeded[i]);
          uint slippageAllowed = 1e16; // 1%
          uint exactAmount = _tokenAmountsNeeded[i].preciseDiv(pricePerTokenUnit);
          uint amountOfReserveAssetToAllow = exactAmount.add(exactAmount.preciseMul(slippageAllowed));
          require(ERC20(reserveAsset).balanceOf(address(this)) >= amountOfReserveAssetToAllow, "Need enough liquid reserve asset");
          _trade("kyber", reserveAsset, amountOfReserveAssetToAllow,_tokensNeeded[i], _tokenAmountsNeeded[i], _data);
        }
      }
      return _invoke(_integration, _value, _data);
    }

    /* ============ External Getter Functions ============ */

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

    function tradeFromInvestmentIdea(
      string memory _integrationName,
      address _sendToken,
      uint256 _sendQuantity,
      address _receiveToken,
      uint256 _minReceiveQuantity,
      bytes memory _data) external onlyInvestmentIdea
    {
      _trade(_integrationName, _sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity, _data);
    }

    /* ============ Internal Functions ============ */

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
      _validateOnlyIntegration(tradeIntegration);
      // Updates UniSwap TWAP
      IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
      oracle.updateAdapters(_sendToken, _receiveToken);
      return ITradeIntegration(tradeIntegration).trade(_sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity, _data);
    }

    function _getPrice(address _assetOne, address _assetTwo) internal returns (uint256) {
      IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
      // Updates UniSwap TWAP
      oracle.updateAdapters(_assetOne, _assetTwo);
      return oracle.getPrice(_assetOne, _assetTwo);
    }

    /**
     * Low level function that allows an integration to make an arbitrary function
     * call to any contract from the community (community as msg.sender).
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
    )
        internal
        returns (bytes memory _returnValue)
    {
        _returnValue = _target.functionCallWithValue(_data, _value);
        emit Invoked(_target, _value, _data, _returnValue);
        return _returnValue;
    }

    /**
     * Pays the _feeQuantity from the _community denominated in _token to the protocol fee recipient
     */
    function payProtocolFeeFromCommunity(address _token, uint256 _feeQuantity)
        internal
    {
        if (_feeQuantity > 0) {
            require(ERC20(_token).transfer(
                IBabController(controller).getTreasury(),
                _feeQuantity
            ), "Protocol fee failed");
        }
    }

    /**
     * Due to reason error bloat, internal functions are used to reduce bytecode size
     *
     * Integration must be initialized on the Community and enabled by the controller
     */
    function _validateOnlyIntegration(address _integration) internal view {
        require(
            isValidIntegration(_integration),
            "Integration needs to be added to the community and controller"
        );
    }

    function _validateOnlyActive() internal view {
        require(active == true, "Community must be active");
    }

    function _validateOnlyInactive() internal view {
        require(active == false, "Community must be disabled");
    }

    // Disable community token transfers. Allow minting and burning.
    function _beforeTokenTransfer(address from, address to, uint256 /* amount */) override view internal {
      require(from == address(0) || to == address(0) || IBabController(controller).communityTokensTransfersEnabled(), "Community token transfers are disabled");
    }
}
