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
import { IFund } from "./interfaces/IFund.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";

/**
 * @title BaseFund
 * @author Babylon Finance
 *
 * Abstract Class that holds common fund-related state and functions
 */
abstract contract BaseFund is ERC20 {
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

    event PositionMultiplierEdited(int256 _newMultiplier);
    event PositionAdded(address indexed _component);
    event PositionRemoved(address indexed _component);
    event PositionBalanceEdited(address indexed _component, int256 _realBalance);

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not a Funds's integration or integration not enabled
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
     * Throws if the sender is not the fund governance. (Initially protocol)
     */
    modifier onlyGovernanceFund() {
      require(msg.sender == controller, "Only the controller can call this");
      _;
    }

    /**
     * Throws if the sender is not the fund creator
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
      require(msg.sender == fundIdeas, "Only the fund ideas contract can call this");
      _;
    }

    /**
     * Throws if the sender is not an investment idea or owner (for testing)
     * TODO: Remove when deploying
     */
    modifier onlyInvestmentIdeaOrOwner() {
      require(msg.sender == fundIdeas || msg.sender == IBabController(controller).owner(), "Only the fund ideas contract can call this");
      _;
    }

    /**
     * Throws if the sender is not an investment idea or integration
     */
    modifier onlyInvestmentAndIntegration() {
      require(msg.sender == fundIdeas || isValidIntegration(msg.sender), "Only the fund ideas contract can call this");
      _;
    }



    /**
    * Throws if the fund is not active
    */
    modifier onlyActive() {
        _validateOnlyActive();
        _;
    }

    /**
    * Throws if the fund is not disabled
    */
    modifier onlyInactive() {
        _validateOnlyInactive();
        _;
    }

    /* ============ State Variables ============ */

    // Subposition constants
    uint8 constant LIQUID_STATUS = 0;
    uint8 constant LOCKED_AS_COLLATERAL_STATUS = 1;
    uint8 constant IN_INVESTMENT_STATUS = 2;
    uint8 constant BORROWED_STATUS = 3;

    // Wrapped ETH address
    address public immutable weth;

    // Reserve Asset of the fund
    address public reserveAsset;

    // Address of the controller
    address public controller;
    // The person that creates the fund
    address public creator;
    // Whether the fund is currently active or not
    bool public active;

    // FundIdeas
    address fundIdeas;

    // List of initialized Integrations; Integrations connect with other money legos
    address[] public integrations;

    // List of positions
    address[] public positions;
    mapping(address => IFund.Position) public positionsByComponent;

    /* ============ Constructor ============ */

    /**
     * When a new Fund is created, initializes Positions are set to empty.
     * All parameter validations are on the BabController contract. Validations are performed already on the
     * BabController. Initiates the positionMultiplier as 1e18 (no adjustments).
     *
     * @param _integrations           List of integrations to enable. All integrations must be approved by the Controller
     * @param _weth                   Address of the WETH ERC20
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _controller             Address of the controller
     * @param _creator                Address of the creator
     * @param _name                   Name of the Fund
     * @param _symbol                 Symbol of the Fund
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
     * PRIVILEGED Manager, protocol FUNCTION. When a Fund is disabled, deposits are disabled.
     */
    function setActive() external onlyProtocol {
      require(!active && integrations.length > 0,
          "Must have active integrations to enable a fund"
      );
      active = true;
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Fund is disabled, deposits are disabled.
     */
    function setDisabled() external onlyProtocol {
      require(active, "The fund must be active");
      active = false;
    }

    /**
     * MANAGER ONLY. Adds an integration into the list of integrations
     */
    function addIntegration(address _integration)
        public
        onlyGovernanceFund
    {
        _addIntegration(_integration);
    }

    /**
     * MANAGER ONLY. Removes an integration from the Fund. Fund calls removeIntegration on integration itself to confirm
     * it is not needed to manage any remaining positions and to remove state.
     */
    function removeIntegration(address _integration) external onlyGovernanceFund {
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
          _trade("kyber", reserveAsset, _tokenAmountsNeeded[i].preciseDiv(pricePerTokenUnit),_tokensNeeded[i], _tokenAmountsNeeded[i], _data);
        }
      }
      return _invoke(_integration, _value, _data);
    }

    /* ============ External Getter Functions ============ */

    function getReserveAsset() external view returns (address) {
      return reserveAsset;
    }

    function getIntegrations() external view returns (address[] memory) {
        return integrations;
    }

    /**
     * Check if this fund has this integration
     */
    function hasIntegration(address _integration)
        external
        view
        returns (bool)
    {
        return integrations.contains(_integration);
    }


    function isPosition(address _component) external view returns (bool) {
      return positions.contains(_component);
    }

    /**
     * Gets the total number of positions
     */
    function getPositionCount() external view returns (uint256) {
        return positions.length;
    }

    /**
     * Returns a list of Positions, through traversing the components.
     * balances are converted to real balances. This function is typically used off-chain for data presentation purposes.
     */
    function getPositions() external view returns (address[] memory) {
        return positions;
    }

    /**
     * Returns whether the fund component  position real balance is greater than or equal to balances passed in.
     */
    function hasSufficientBalance(address _component, uint256 _balance)
        external
        view
        returns (bool)
    {
      return _getPositionBalance(_component).toUint256() >= _balance;
    }

    /**
     * Get the position of a component
     *
     * @param _component          Address of the component
     * @return                    Balance
     */
    function getPositionBalance(address _component)
        external
        view
        returns (int256)
    {
      return _getPositionBalance(_component);
    }

    /**
     * Calculates the new  position balance and performs the edit with new balance
     *
     * @param _component                Address of the component
     * @param _newBalance               Current balance of the component
     * @return                          Current component balance
     * @return                          Previous position balance
     * @return                          New position balance
     */
    function calculateAndEditPosition(
        address _component,
        uint256 _newBalance,
        uint256 _deltaBalance,
        uint8 _subpositionStatus
    )
        public
        onlyInvestmentAndIntegration
        onlyActive
        returns (
            uint256,
            uint256,
            uint256
        )
    {
      return _calculateAndEditPosition(_component, _newBalance, _deltaBalance, _subpositionStatus);
    }

    function isValidIntegration(address _integration) public view returns (bool) {
      return integrations.contains(_integration) &&
        IBabController(controller).isValidIntegration(IIntegration(_integration).getName(), _integration);
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
      return ITradeIntegration(tradeIntegration).trade(_sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity, _data);
    }


    /**
     * Internal MODULE FUNCTION. Low level function that adds a component to the positions array.
     */
    function _addPosition(address _component, address _integration) internal{
      IFund.Position storage position = positionsByComponent[_component];

      position.subpositions.push(IFund.SubPosition({
        integration: _integration,
        balance: 0,
        status: 0
      }));
      position.subpositionsCount ++;
      position.enteredAt = block.timestamp;

      positions.push(_component);
      emit PositionAdded(_component);
    }

    function _getSubpositionIndex(address _component, address _integration) view internal returns (int256) {
      IFund.Position storage position = positionsByComponent[_component];
      for (uint8 i = 0; i < position.subpositionsCount; i++) {
        if (position.subpositions[i].integration == _integration) {
          return i;
        }
      }
      return -1;
    }

    /**
     * Internal MODULE FUNCTION. Low level function that removes a component from the positions array.
     */
    function _removePosition(address _component) internal {
      IFund.Position storage position = positionsByComponent[_component];
      positions = positions.remove(_component);
      position.exitedAt = block.timestamp;
      emit PositionRemoved(_component);
    }

    /**
     * Internal MODULE FUNCTION. Low level function that edits a component's position
     */
    function _editPositionBalance(
      address _component,
      int256 _amount,
      address _integration,
      uint256 _deltaBalance,
      uint8 _subpositionStatus
    ) internal {
      IFund.Position storage position = positionsByComponent[_component];
      position.balance = _amount;
      position.updatedAt.push(block.timestamp);
      int256 subpositionIndex = _getSubpositionIndex(_component, _integration);
      if (subpositionIndex == -1) {
        position.subpositions.push(IFund.SubPosition({
          integration: _integration,
          balance: _deltaBalance,
          status: _subpositionStatus
        }));
      } else {
        position.subpositions[subpositionIndex.toUint256()].balance = _deltaBalance;
        position.subpositions[subpositionIndex.toUint256()].status = _subpositionStatus;
      }

      emit PositionBalanceEdited(_component, _amount);
    }

    function _calculateAndEditPosition(
        address _component,
        uint256 _newBalance,
        uint256 _deltaBalance,
        uint8 _subpositionStatus
    )
        internal
        returns (
            uint256,
            uint256,
            uint256
        )
    {
      uint256 positionBalance = _getPositionBalance(_component).toUint256();
      editPosition(_component, _newBalance, msg.sender, _deltaBalance, _subpositionStatus);

      return (_newBalance, positionBalance, _newBalance);
    }

    /**
     * Returns whether the fund has a position for a given component (if the real balance is > 0)
     */
    function _hasPosition(address _component) internal view returns (bool) {
        return _getPositionBalance(_component) > 0;
    }

    function _getPositionBalance(address _component) internal view returns (int256) {
      return positionsByComponent[_component].balance;
    }

    /**
     * If the position does not exist, create a new Position and add to the fund. If it already exists,
     * then set the position balance. If the new balance is 0, remove the position. Handles adding/removing of
     * components where needed (in light of potential external positions).
     *
     * @param _component          Address of the component
     * @param _newBalance         Mew Balance
     */
    function editPosition(
        address _component,
        uint256 _newBalance,
        address _integration,
        uint256 _deltaBalance,
        uint8 _subpositionStatus
    ) internal {
        bool isPositionFound = _hasPosition(_component);
        if (!isPositionFound && _newBalance > 0) {
          _addPosition(_component, _integration);
        } else if (isPositionFound && _newBalance == 0) {
          _removePosition(_component);
        }
        _editPositionBalance(_component, _newBalance.toInt256(), _integration, _deltaBalance, _subpositionStatus);
    }

    function _getPrice(address _assetOne, address _assetTwo) internal view returns (uint256) {
      IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
      return oracle.getPrice(_assetOne, _assetTwo);
    }

    /**
     * Low level function that allows an integration to make an arbitrary function
     * call to any contract from the fund (fund as msg.sender).
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
     * Pays the _feeQuantity from the _fund denominated in _token to the protocol fee recipient
     */
    function payProtocolFeeFromFund(address _token, uint256 _feeQuantity)
        internal
    {
        if (_feeQuantity > 0) {
            require(ERC20(_token).transfer(
                IBabController(controller).getFeeRecipient(),
                _feeQuantity
            ), "Protocol fee failed");
        }
    }

    /**
     * Due to reason error bloat, internal functions are used to reduce bytecode size
     *
     * Integration must be initialized on the Fund and enabled by the controller
     */
    function _validateOnlyIntegration(address _integration) internal view {
        require(
            isValidIntegration(_integration),
            "Integration needs to be added to the fund and controller"
        );
    }

    function _validateOnlyActive() internal view {
        require(active == true, "Fund must be active");
    }

    function _validateOnlyInactive() internal view {
        require(active == false, "Fund must be disabled");
    }

    // Disable fund token transfers. Allow minting and burning.
    function _beforeTokenTransfer(address from, address to, uint256 /* amount */) override pure internal {
      require(from == address(0) || to == address(0), "Fund token transfers are disabled");
    }
}
