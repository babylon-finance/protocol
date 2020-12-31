/*
    Copyright 2020 DFolio.

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

import "hardhat/console.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";

import {AddressArrayUtils} from "./lib/AddressArrayUtils.sol";
import {PreciseUnitMath} from "./lib/PreciseUnitMath.sol";
import {IFolioController} from "./interfaces/IFolioController.sol";
import {IWETH} from "./interfaces/external/weth/IWETH.sol";
import { IStableDebtToken } from './interfaces/external/aave/IStableDebtToken.sol';
import {IIntegration} from "./interfaces/IIntegration.sol";
import {IBorrowIntegration} from "./interfaces/IBorrowIntegration.sol";
import {IBorrowIntegration} from "./interfaces/IBorrowIntegration.sol";
import {IFund} from "./interfaces/IFund.sol";

/**
 * @title BaseFund
 * @author DFolio
 *
 * Abstract Class that holds common fund-related state and functions
 */
abstract contract BaseFund is ERC20 {
    using SafeCast for uint256;
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeCast for int256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using Address for address;
    using AddressArrayUtils for address[];

    /* ============ Events ============ */
    event Invoked(address indexed _target, uint indexed _value, bytes _data, bytes _returnValue);
    event IntegrationInvoked(address indexed _target, uint indexed _value, bytes _data, bytes _returnValue);
    event IntegrationAdded(address indexed _integration);
    event IntegrationRemoved(address indexed _integration);
    event IntegrationInitialized(address indexed _integration);
    event PendingIntegrationRemoved(address indexed _integration);
    event ReserveAssetChanged(address indexed _integration);

    event ManagerEdited(address _newManager, address _oldManager);
    event FeeRecipientEdited(address _newManagerFeeRecipient);
    event PositionMultiplierEdited(int256 _newMultiplier);
    event PositionAdded(address indexed _component);
    event PositionRemoved(address indexed _component);
    event PositionUnitEdited(address indexed _component, int256 _realUnit);

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
     * Throws if the sender is not the Fund's manager
     */
    modifier onlyManager() {
        _validateOnlyManager();
        _;
    }

    modifier onlyManagerOrProtocol {
        _validateOnlyManagerOrProtocol();
        _;
    }

    modifier onlyActive() {
        _validateOnlyActive();
        _;
    }

    modifier onlyInactive() {
        _validateOnlyInactive();
        _;
    }

    /* ============ State Variables ============ */

    // Wrapped ETH address
    address public immutable weth;

    // Reserve Asset of the fund
    address public reserveAsset;

    // Address of the controller
    address public controller;
    // The manager has the privelege to add integrations, remove, and set a new manager
    address public manager;
    address public managerFeeRecipient;
    // Whether the fund is currently active or not
    bool public active;

    // List of initialized Integrations; Integrations connect with other money legos
    address[] public integrations;

    // Integrations are initialized from NONE -> PENDING -> INITIALIZED through the
    // addIntegration (called by manager) and initialize  (called by integration) functions
    mapping(address => IFund.IntegrationState) public integrationStates;
    // integration name => integration address
    mapping(bytes32 => address) private integrationsByName;

    // List of positions
    address[] public positions;
    mapping(address => IFund.Position) public positionsByComponent;

    // The multiplier applied to the virtual position unit to achieve the real/actual unit.
    // This multiplier is used for efficiently modifying the entire position units (e.g. streaming fee)
    int256 public positionMultiplier;

    /* ============ Constructor ============ */

    /**
     * When a new Fund is created, initializes Positions are set to empty.
     * All parameter validations are on the FolioController contract. Validations are performed already on the
     * FolioController. Initiates the positionMultiplier as 1e18 (no adjustments).
     *
     * @param _integrations           List of integrations to enable. All integrations must be approved by the Controller
     * @param _weth                   Address of the WETH ERC20
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _controller             Address of the controller
     * @param _manager                Address of the manager
     * @param _managerFeeRecipient    Address where the manager will receive the fees
     * @param _name                   Name of the Fund
     * @param _symbol                 Symbol of the Fund
     */

    constructor(
        address[] memory _integrations,
        address _weth,
        address _reserveAsset,
        address _controller,
        address _manager,
        address _managerFeeRecipient,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        require(
            _managerFeeRecipient != address(0),
            "Fee Recipient must be non-zero address."
        );

        controller = _controller;
        weth = _weth;
        reserveAsset = _reserveAsset;
        manager = _manager;
        managerFeeRecipient = _managerFeeRecipient;
        positionMultiplier = PreciseUnitMath.preciseUnitInt();

        // Integrations are put in PENDING state, as they need to be individually initialized by the Integration
        for (uint256 i = 0; i < _integrations.length; i++) {
            integrationStates[_integrations[i]] = IFund
                .IntegrationState
                .PENDING;
        }

        active = false;
    }

    /* ============ External Functions ============ */

    /**
     * FUND MANAGER ONLY. Changes the reserve asset
     *
     * @param _reserveAsset                 Address of the new reserve asset
     */
    function editReserveAsset(address _reserveAsset) external onlyManager {
        reserveAsset = _reserveAsset;

        emit ReserveAssetChanged(_reserveAsset);
    }

    /**
     * Fund MANAGER ONLY. Edit the manager fee recipient
     *
     * @param _managerFeeRecipient          Manager fee recipient
     */
    function editManagerFeeRecipient(address _managerFeeRecipient)
        external
        onlyManager
        onlyActive
    {
        require(
            _managerFeeRecipient != address(0),
            "Fee recipient must not be 0 address"
        );

        managerFeeRecipient = _managerFeeRecipient;

        emit FeeRecipientEdited(_managerFeeRecipient);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Low level function that adds a component to the positions array.
     */
    function addPosition(address _component, address _integration)
        public
        onlyIntegration
        onlyActive
    {
      _addPosition(_component, _integration);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Low level function that removes a component from the positions array.
     */
    function removePosition(address _component)
        public
        onlyIntegration
        onlyActive
    {
      _removePosition(_component);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Low level function that edits a component's virtual unit. Takes a real unit
     * and converts it to virtual before committing.
     */
    function editPositionUnit(address _component, int256 _realUnit)
        public
        onlyIntegration
        onlyActive
    {
      editPositionUnit(_component, _realUnit);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Modifies the position multiplier. This is typically used to efficiently
     * update all the Positions' units at once in applications where inflation is awarded (e.g. subscription fees).
     */
    function editPositionMultiplier(int256 _newMultiplier)
        public
        onlyIntegration
        onlyActive
    {
      _editPositionMultiplier(_newMultiplier);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Increases the "account" balance by the "quantity".
     */
    function mint(address _account, uint256 _quantity)
        external
        onlyIntegration
        onlyActive
    {
        _mint(_account, _quantity);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Decreases the "account" balance by the "quantity".
     * _burn checks that the "account" already has the required "quantity".
     */
    function burn(address _account, uint256 _quantity)
        external
        onlyIntegration
        onlyActive
    {
        _burn(_account, _quantity);
    }

    /**
     * MANAGER ONLY. Adds an integration into a PENDING state; Integration must later be initialized via
     * integration's initialize function
     */
    function addIntegration(address _integration, string memory _name)
        external
        onlyManager
    {
        require(
            integrationStates[_integration] == IFund.IntegrationState.NONE,
            "Integration must not be added"
        );
        require(
            IFolioController(controller).isValidIntegration(_name),
            "Integration must be enabled on Controller"
        );

        integrationStates[_integration] = IFund.IntegrationState.PENDING;

        emit IntegrationAdded(_integration);
    }

    /**
     * MANAGER ONLY. Removes an integration from the Fund. Fund calls removeIntegration on integration itself to confirm
     * it is not needed to manage any remaining positions and to remove state.
     */
    function removeIntegration(address _integration) external onlyManager {
        require(
            integrationStates[_integration] == IFund.IntegrationState.PENDING,
            "Integration must be pending"
        );

        integrationStates[_integration] = IFund.IntegrationState.NONE;

        integrations = integrations.remove(_integration);

        emit IntegrationRemoved(_integration);
    }

    /**
     * Initializes an added integration from PENDING to INITIALIZED state. Can only call when active.
     * An address can only enter a PENDING state if it is an enabled integration added by the manager.
     * Only callable by the integration itself, hence msg.sender is the subject of update.
     */
    function initializeIntegration() external {
        require(
            integrationStates[msg.sender] == IFund.IntegrationState.PENDING,
            "Integration must be pending"
        );

        integrationStates[msg.sender] = IFund.IntegrationState.INITIALIZED;
        integrations.push(msg.sender);

        emit IntegrationInitialized(msg.sender);
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Fund is disable, deposits are disabled
     */
    function setActive() external onlyManagerOrProtocol {
      require(!active && integrations.length > 0,
          "Must have active integrations to enable a fund"
      );
      active = true;
    }

    function setDisabled() external onlyManagerOrProtocol {
      // TODO: the fund must be
      require(active, "The fund must be active");
      active = false;
    }

    /**
     * MANAGER ONLY. Changes manager; We allow null addresses in case the manager wishes to wind down the SetToken.
     * Integrations may rely on the manager state, so only changable when unlocked
     */
    function setManager(address _manager) external onlyManagerOrProtocol {
        address oldManager = manager;
        manager = _manager;

        emit ManagerEdited(_manager, oldManager);
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
    function invoke(
        address _target,
        uint256 _value,
        bytes calldata _data
    )
        external
        onlyIntegration
        returns (bytes memory _returnValue)
    {
        _returnValue = _target.functionCallWithValue(_data, _value);
        emit Invoked(_target, _value, _data, _returnValue);
        return _returnValue;
    }


    /**
     * Funciton that allows the manager to call an integration
     *
     * @param _integration            Address of the integration to call
     * @param _value                  Quantity of Ether to provide the call (typically 0)
     * @param _data                   Encoded function selector and arguments
     * @return _returnValue           Bytes encoded return value
     */
    function callIntegration(address _integration, uint256 _value, bytes calldata _data) external onlyManager returns (bytes memory _returnValue) {
      _validateOnlyIntegration(_integration);
      _returnValue = _integration.functionCallWithValue(_data, _value);
      emit IntegrationInvoked(_integration, _value, _data, _returnValue);
      return _returnValue;
    }

    function addAllowanceIntegration(address _integration, address _asset, uint256 _quantity) external onlyManager {
      _validateOnlyIntegration(_integration);
      ERC20(_asset).approve(_integration, 0);
      ERC20(_asset).approve(_integration, _quantity);
    }

    function addAaveBorrowAllowanceIntegration(address _integration, address _asset, uint256 _quantity) external onlyManager {
      _validateOnlyIntegration(_integration);
      address stableDebtTokenAddress = IBorrowIntegration(_integration).getDebtToken(_asset);
      // For stable debt tokens
      IStableDebtToken(stableDebtTokenAddress).approveDelegation(_integration, _quantity);
    }

    /* ============ External Getter Functions ============ */

    function getReserveAsset() external view returns (address) {
        return reserveAsset;
    }

    function getPositionRealUnit(address _component)
        public
        view
        returns (int256)
    {
        return _convertVirtualToRealUnit(_positionVirtualUnit(_component));
    }

    function getIntegrations() external view returns (address[] memory) {
        return integrations;
    }

    function isPosition(address _component) external view returns (bool) {
        return positions.contains(_component);
    }

    /**
     * Only IntegrationStates of INITIALIZED integrations are considered enabled
     */
    function isInitializedIntegration(address _integration)
        external
        view
        returns (bool)
    {
        return
            integrationStates[_integration] ==
            IFund.IntegrationState.INITIALIZED;
    }

    /**
     * Returns whether the integration is in a pending state
     */
    function isPendingIntegration(address _integration)
        external
        view
        returns (bool)
    {
        return
            integrationStates[_integration] == IFund.IntegrationState.PENDING;
    }

    /**
     * Gets the total number of positions
     */
    function getPositionCount() external view returns (uint256) {
        return positions.length;
    }

    /**
     * Returns a list of Positions, through traversing the components.
     * Virtual units are converted to real units. This function is typically used off-chain for data presentation purposes.
     */
    function getPositions() external view returns (address[] memory) {
        return positions;
    }

    /**
     * Returns the total Real Units for a given component, summing the  and external position units.
     */
    function getTotalPositionRealUnits(address _component)
        external
        view
        returns (int256)
    {
        return getPositionRealUnit(_component);
    }

    /**
     * Calculates the new  position unit and performs the edit with the new unit
     *
     * @param _component                Address of the component
     * @param _newBalance               Current balance of the component
     * @return                          Current component balance
     * @return                          Previous position unit
     * @return                          New position unit
     */

    function calculateAndEditPosition(
        address _component,
        uint256 _newBalance
    )
        public
        onlyIntegration
        onlyActive
        returns (
            uint256,
            uint256,
            uint256
        )
    {
      return _calculateAndEditPosition(_component, _newBalance);
    }

    /* ============ Internal Functions ============ */

    function _calculateAndEditPosition(
        address _component,
        uint256 _newBalance
    )
        internal
        returns (
            uint256,
            uint256,
            uint256
        )
    {
      uint256 positionUnit = getPositionRealUnit(_component).toUint256();
      uint256 _componentPreviousBalance = positionUnit.preciseMul(totalSupply());
      uint256 newTokenUnit =
          calculateEditPositionUnit(
              _componentPreviousBalance,
              _newBalance,
              positionUnit
          );
      editPosition(_component, newTokenUnit, msg.sender);

      return (_newBalance, positionUnit, newTokenUnit);
    }

    /**
     * Internal MODULE FUNCTION. Low level function that adds a component to the positions array.
     */
    function _addPosition(address _component, address _integration) internal{
      IFund.Position storage position = positionsByComponent[_component];
      position.positionState = _integration != address(0) ? 1 : 0;
      position.integration = _integration;
      // position.updatedAt = [];
      position.enteredAt = block.timestamp;

      positions.push(_component);
      emit PositionAdded(_component);
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
     * Modifies the position multiplier. This is typically used to efficiently
     * update all the Positions' units at once in applications where inflation is awarded (e.g. subscription fees).
     */
    function _editPositionMultiplier(int256 _newMultiplier) internal
    {
      require(_newMultiplier > 0, "Must be greater than 0");

      positionMultiplier = _newMultiplier;

      emit PositionMultiplierEdited(_newMultiplier);
    }

    /**
     * Internal MODULE FUNCTION. Low level function that edits a component's virtual unit. Takes a real unit
     * and converts it to virtual before committing.
     */
    function _editPositionUnit(address _component, int256 _realUnit) internal {
      int256 virtualUnit = _convertRealToVirtualUnit(_realUnit);

      positionsByComponent[_component].virtualUnit = virtualUnit;
      positionsByComponent[_component].unit = _realUnit;
      positionsByComponent[_component].updatedAt.push(block.timestamp);

      emit PositionUnitEdited(_component, _realUnit);
    }

    /**
     * Calculate the new position unit given total notional values pre and post executing an action that changes Fund state
     * The intention is to make updates to the units without accidentally picking up airdropped assets as well.
     *
     * @param _preTotalNotional   Total notional amount of component prior to executing action
     * @param _postTotalNotional  Total notional amount of component after the executing action
     * @param _prePositionUnit    Position unit of fund prior to executing action
     * @return                    New position unit
     */
    function calculateEditPositionUnit(
        uint256 _preTotalNotional,
        uint256 _postTotalNotional,
        uint256 _prePositionUnit
    ) internal view returns (uint256) {
        // If pre action total notional amount is greater then subtract post action total notional and calculate new position units
        uint256 airdroppedAmount =
            _preTotalNotional.sub(_prePositionUnit.preciseMul(totalSupply()));
        return
            _postTotalNotional.sub(airdroppedAmount).preciseDiv(totalSupply());
    }

    /**
     * Returns whether the fund has a  position for a given component (if the real unit is > 0)
     */
    function hasPosition(address _component) internal view returns (bool) {
        return getPositionRealUnit(_component) > 0;
    }

    /**
     * Returns whether the fund component  position real unit is greater than or equal to units passed in.
     */
    function hasSufficientUnits(address _component, uint256 _unit)
        internal
        view
        returns (bool)
    {
        return getPositionRealUnit(_component) >= _unit.toInt256();
    }

    /**
     * If the position does not exist, create a new Position and add to the fund. If it already exists,
     * then set the position units. If the new units is 0, remove the position. Handles adding/removing of
     * components where needed (in light of potential external positions).
     *
     * @param _component          Address of the component
     * @param _newUnit            Quantity of Position units - must be >= 0
     */
    function editPosition(
        address _component,
        uint256 _newUnit,
        address _integration
    ) internal {
        bool isPositionFound = hasPosition(_component);
        if (!isPositionFound && _newUnit > 0) {
          _addPosition(_component, _integration);
        } else if (isPositionFound && _newUnit == 0) {
          _removePosition(_component);
        }

        _editPositionUnit(_component, _newUnit.toInt256());
    }

    /**
     * Get total notional amount of position
     *
     * @param _positionUnit       Quantity of Position units
     *
     * @return                    Total notional amount of units
     */
    function getTotalNotional(uint256 _positionUnit)
        internal
        view
        returns (uint256)
    {
        return totalSupply().preciseMul(_positionUnit);
    }

    /**
     * Get position unit from total notional amount
     *
     * @param _totalNotional      Total notional amount of component prior to
     * @return                    position unit
     */
    function getPositionUnit(uint256 _totalNotional)
        internal
        view
        returns (uint256)
    {
        return _totalNotional.preciseDiv(totalSupply());
    }

    /**
     * Get the total tracked balance - total supply * position unit
     *
     * @param _component          Address of the component
     * @return                    Notional tracked balance
     */
    function getTrackedBalance(address _component)
        internal
        view
        returns (uint256)
    {
        int256 positionUnit = getPositionRealUnit(_component);
        return totalSupply().preciseMul(positionUnit.toUint256());
    }

    function _positionVirtualUnit(address _component)
        internal
        view
        returns (int256)
    {
        return positionsByComponent[_component].virtualUnit;
    }

    /**
     * Pays the _feeQuantity from the _fund denominated in _token to the protocol fee recipient
     */
    function payProtocolFeeFromFund(address _token, uint256 _feeQuantity)
        internal
    {
        if (_feeQuantity > 0) {
            ERC20(_token).transfer(
                IFolioController(controller).getFeeRecipient(),
                _feeQuantity
            );
        }
    }

    /**
     * Pays the _feeQuantity from the _fund denominated in _token to the manager fee recipient
     */
    function payManagerFeeFromFund(address _token, uint256 _feeQuantity)
        internal
    {
        if (_feeQuantity > 0) {
            ERC20(_token).transfer(managerFeeRecipient, _feeQuantity);
        }
    }

    /**
     * Takes a real unit and divides by the position multiplier to return the virtual unit
     */
    function _convertRealToVirtualUnit(int256 _realUnit)
        internal
        view
        returns (int256)
    {
        int256 virtualUnit =
            _realUnit.conservativePreciseDiv(positionMultiplier);

        // These checks ensure that the virtual unit does not return a result that has rounded down to 0
        if (_realUnit > 0 && virtualUnit == 0) {
            revert("Virtual unit conversion invalid");
        }

        return virtualUnit;
    }

    /**
     * Takes a virtual unit and multiplies by the position multiplier to return the real unit
     */
    function _convertVirtualToRealUnit(int256 _virtualUnit)
        internal
        view
        returns (int256)
    {
        return _virtualUnit.conservativePreciseMul(positionMultiplier);
    }

    /**
     * Due to reason error bloat, internal functions are used to reduce bytecode size
     *
     * Integration must be initialized on the Fund and enabled by the controller
     */
    function _validateOnlyIntegration(address _integration) internal view {
        require(
            integrationStates[_integration] == IFund.IntegrationState.INITIALIZED,
            "Only the integration can call"
        );
        require(
            IFolioController(controller).isValidIntegration(
                IIntegration(_integration).getName()
            ),
            "Integration must be enabled on controller"
        );
    }

    function _validateOnlyManager() internal view {
        require(msg.sender == manager, "Only manager can call");
    }

    function _validateOnlyActive() internal view {
        require(active == true, "Fund must be active");
    }

    function _validateOnlyInactive() internal view {
        require(active == false, "Fund must be disabled");
    }

    function _validateOnlyManagerOrProtocol() internal view {
        require(
            msg.sender == manager || msg.sender == controller,
            "Only the fund manager or the protocol can modify fund state"
        );
    }
}
