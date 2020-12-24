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
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { FundToken } from "./FundToken.sol";
import { Investment } from "./investments/Investment.sol"

import { IFolioController } from "./interfaces/IFolioController.sol";
import { INAVIssuanceHook } from "./interfaces/IManagerIssuanceHook.sol";
import { IIntegration } from "./interfaces/IIntegration.sol";
import { IFund } from "./interfaces/IFund.sol";
import { Position } from "./lib/Position.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";
import { AddressArrayUtils } from "./lib/AddressArrayUtils.sol";


/**
 * @title Fund
 * @author DFolio
 *
 * ERC20 Token contract that allows privileged modules to make modifications to its positions and invoke function calls
 * from the Fund.
 */
contract Fund is ERC20, ReentrancyGuard {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using Address for address;
    using AddressArrayUtils for address[];

    /* ============ Events ============ */
    event FundTokenIssued(
        address indexed _setToken,
        address indexed _to,
        address _hookContract,
        uint256 _quantity
    );
    event FundTokenRedeemed(
        address indexed _setToken,
        address indexed _redeemer,
        address indexed _to,
        uint256 _quantity
    );


    event ContributionLog(address indexed contributor,uint256 amount,uint256 timestamp);
    event WithdrawalLog(address indexed sender, uint amount, uint timestamp);
    event ClaimLog(address indexed sender, uint originalAmount, uint amount, uint timestamp);
    event Invoked(address indexed _target, uint indexed _value, bytes _data, bytes _returnValue);
    event IntegrationAdded(address indexed _integration);
    event IntegrationRemoved(address indexed _integration);
    event IntegrationInitialized(address indexed _integration);
    event PendingIntegrationRemoved(address indexed _integration);
    event ManagerEdited(address _newManager, address _oldManager);
    event PositionMultiplierEdited(int256 _newMultiplier);
    event InvestmentAdded(address indexed _component);
    event InvestmentRemoved(address indexed _component);
    event DefaultInvestmentUnitEdited(address indexed _component, int256 _realUnit);

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not a Funds's integration or module not enabled
     */
    modifier onlyIntegration() {
        // Internal function used to reduce bytecode size
        _validateOnlyIntegration();
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

    modifier onlyContributor(address payable _caller) {
      _validateOnlyContributor();
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

    INAVIssuanceHook managerIssuanceHook;      // Issuance hook configurations
    INAVIssuanceHook managerRedemptionHook;    // Redemption hook configurations

    // Wrapped ETH address
    IWETH public immutable weth;

    // Reserve Asset of the fund
    IERC20 public reserveAsset;

    uint256 managerIssueFee;  // % of the issuance denominated in the reserve asset
    uint256 managerWithdrawalFee; // % of the redemption denominated in the reserve asset,  charged in withdrawal
    uint256 managerPerformanceFee; // % of the profits denominated in the reserve asset, charged in withdrawal
    uint256 premiumPercentage; // Premium percentage (0.01% = 1e14, 1% = 1e16). This premium is a buffer around oracle
                                // prices paid by user to the SetToken, which prevents arbitrage and oracle front running
    // Address of the controller
    IController public controller;
    // The manager has the privelege to add modules, remove, and set a new manager
    address public manager;
    address public managerFeeRecipient;
    // Whether the fund is currently active or not
    bool public active;
    // Public name of the fund
    string public name;

    // List of initialized Integrations; Integrations connect with other money legos
    address[] public integrations;

    // Integrations are initialized from NONE -> PENDING -> INITIALIZED through the
    // addModule (called by manager) and initialize  (called by module) functions
    mapping(address => IFund.IntegrationState) public integrationStates;

    // List of investments
    address[] public investments;
    mapping (address => Investment) public investment;
    uint public investmentsCount;

    // List of contributors
    struct Contributor {
        uint256 amount; //wei
        uint256 timestamp;
        bool claimed;
    }
    mapping(address => Contributor) public contributors;
    uint256 public totalContributors;
    uint256 public totalFundsDepsited;

    // The multiplier applied to the virtual position unit to achieve the real/actual unit.
    // This multiplier is used for efficiently modifying the entire position units (e.g. streaming fee)
    int256 public positionMultiplier;

    // Min contribution in the fund
    uint256 public minContribution = 1000000000000; //wei


    /* ============ Constructor ============ */

    /**
     * When a new Fund is created, initializes Investments are set to empty.
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
        IWETH _weth,
        IController _controller,
        address _manager,
        address _managerFeeRecipient,
        address _reserveAsset,
        string memory _name,
        string memory _symbol
    ) public ERC20(_name, _symbol){
      require(_managerFeeRecipient != address(0), "Fee Recipient must be non-zero address.");

      controller = _controller;
      weth = _weth;
      reserveAsset = _reserveAsset;
      manager = _manager;
      managerFeeRecipient = _managerFeeRecipient;
      positionMultiplier = PreciseUnitMath.preciseUnitInt();
      components = _components;

      // Integrations are put in PENDING state, as they need to be individually initialized by the Module
      for (uint256 i = 0; i < _modules.length; i++) {
          integrationStates[_modules[i]] = ISetToken.IntegrationState.PENDING;
      }

      investments = [];
      investmentsCount = 0;
      active = false;
    }

    /* ============ External Functions ============ */

    uint256 managerIssueFee;  // % of the issuance denominated in the reserve asset
    uint256 managerWithdrawalFee; // % of the redemption denominated in the reserve asset,  charged in withdrawal
    uint256 managerPerformanceFee; // % of the profits denominated in the reserve asset, charged in withdrawal
    uint256 premiumPercentage;

    /**
     * SET MANAGER ONLY. Initializes this module to the Fund with hooks, allowed reserve assets,
     * fees and issuance premium. Only callable by the Fund's manager. Hook addresses are optional.
     * Address(0) means that no hook will be called.
     *
     * @param _managerIssueFee
     * @param _managerWithdrawalFee
     * @param _managerPerformanceFee
     * @param _premiumPercentage
     */
    function initialize(
        uint256 _managerIssueFee,
        uint256 _managerWithdrawalFee,
        uint256 _managerPerformanceFee,
        uint256 _premiumPercentage,
        INAVIssuanceHook _managerIssuanceHook,
        INAVIssuanceHook _managerRedeemHook,
    )
        external
        onlyManager
        onlyInactive
    {
        require(_managerIssueFee <= IFolioController(controller).maxManagerIssueFee, "Manager issue fee must be less than max");
        require(_managerRedeemFee <= IFolioController(controller).maxManagerRedeemFee, "Manager redeem fee must be less than max");
        require(_managerPerformanceFee <= IFolioController(controller).maxManagerPerformanceFee, "Manager performance fee must be less than max");
        require(_premiumPercentage <= IFolioController(controller).maxFundPremiumPercentage, "Premium must be less than max");
        // require(_navIssuanceSettings.minSetTokenSupply > 0, "Min SetToken supply must be greater than 0");

        managerIssueFee = _managerIssueFee;
        managerWithdrawalFee = _managerWithdrawalFee;
        managerPerformanceFee = _managerPerformanceFee;
        premiumPercentage = _premiumPercentage;
        managerIssuanceHook = _managerIssuanceHook;
        maangerRedeemHook = _managerRedeemHook;
        active = true;
    }

    /**
     * Deposits the Fund's position components into the SetToken and mints the Fund token of the given quantity
     * to the specified _to address. This function only handles Default Positions (positionState = 0).
     *
     * @param _reserveAssetQuantity  Quantity of the reserve asset that are received
     * @param _minSetTokenReceiveQuantity   Min quantity of SetToken to receive after issuance
     * @param _to                   Address to mint Fund tokens to
     */
    function deposit(
        uint256 _reserveAssetQuantity,
        uint256 _minSetTokenReceiveQuantity,
        address _to
    )
        external
        payable
        nonReentrant
        onlyActive
    {
        require(
            msg.value >= minContribution,
            "Send at least 1000000000000 wei"
        );
        weth.deposit{ value: msg.value }();

        _validateCommon(_setToken, _reserveAsset, _reserveAssetQuantity);

        _callPreIssueHooks(_setToken, _reserveAsset, _reserveAssetQuantity, msg.sender, _to);

        ActionInfo memory issueInfo = _createIssuanceInfo(_setToken, _reserveAsset, _reserveAssetQuantity);

        _validateIssuanceInfo(_setToken, _minSetTokenReceiveQuantity, issueInfo);

        _transferCollateralAndHandleFees(_setToken, IERC20(_reserveAsset), issueInfo);

        Contributor storage contributor = contributors[msg.sender];

        // If new contributor, create one, increment count, and set the current TS
        if (contributor.amount == 0) {
          totalContributors = totalContributors.add(1);
          contributor.timestamp = block.timestamp;
        }

        totalFunds = totalFunds.add(msg.value);
        contributor.amount = contributor.amount.add(msg.value);
        emit ContributionLog(msg.sender, msg.value, block.timestamp);

        _handleIssueStateUpdates(_setToken, _reserveAsset, _to, issueInfo);
    }


    /**
     * Redeems the SetToken's positions and sends the components of the given
     * quantity to the caller. This function only handles Default Positions (positionState = 0).
     *
     * @param _setToken             Instance of the SetToken contract
     * @param _quantity             Quantity of the SetToken to redeem
     * @param _minReserveReceiveQuantity    Min quantity of reserve asset to receive
     * @param _to                   Address to send component assets to
     */
    function withdraw(
        ISetToken _setToken,
        uint256 _fundTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address _to
    )
        external
        nonReentrant
        onlyContributor(msg.sender)
    {
      Contributor storage contributor = contributors[msg.sender];
      require(_amount <= contributor.amount, 'Withdrawl amount must be less than or equal to deposited amount');

      _validateCommon(_setToken, _reserveAsset, _setTokenQuantity);

      _callPreRedeemHooks(_setToken, _setTokenQuantity, msg.sender, _to);

      ActionInfo memory redeemInfo = _createRedemptionInfo(_setToken, _reserveAsset, _setTokenQuantity);

      _validateRedemptionInfo(_setToken, _minReserveReceiveQuantity, _setTokenQuantity, redeemInfo);

      _setToken.burn(msg.sender, _setTokenQuantity);

      contributor.amount = contributor.amount.sub(_amount);
      totalFunds = totalFunds.sub(_amount);
      if (contributor.amount == 0) {
        totalContributors = totalContributors.sub(1);
      }
      token.burn(msg.sender, _amount.div(minContribution));
      Address(this).sendValue(msg.sender, _amount);
      emit WithdrawalLog(msg.sender, _amount, block.timestamp);


      // Instruct the SetToken to transfer the reserve asset back to the user
      _setToken.strictInvokeTransfer(
          _reserveAsset,
          _to,
          redeemInfo.netFlowQuantity
      );

      weth.withdraw(redeemInfo.netFlowQuantity);

      _to.transfer(redeemInfo.netFlowQuantity);

      _handleRedemptionFees(_setToken, _reserveAsset, redeemInfo);

      _handleRedeemStateUpdates(_setToken, _reserveAsset, _to, redeemInfo);
    }

    /**
     * SET MANAGER ONLY. Changes the reserve asset
     *
     * @param _reserveAsset                 Address of the new reserve asset
     */
    function editReserveAsset(address _reserveAsset) external onlyManager {
        reserveAsset = _reserveAsset;

        emit ReserveAssetChange(address(this), _reserveAsset);
    }

    /**
     * SET MANAGER ONLY. Edit the premium percentage
     *
     * @param _premiumPercentage            Premium percentage in 10e16 (e.g. 10e16 = 1%)
     */
    function editPremium(uint256 _premiumPercentage) external onlyManager {
        require(_premiumPercentage <= IFolioController(controller).maxPremiumPercentage, "Premium must be less than maximum allowed");

        premiumPercentage = _premiumPercentage;

        emit PremiumEdited(address(this), _premiumPercentage);
    }

    /**
     * Fund MANAGER ONLY. Edit manager issue fee
     *
     * @param _managerIssueFee         Manager issue fee percentage in 10e16 (e.g. 10e16 = 1%)
     */
    function editManagerIssueFee(
        ISetToken _setToken,
        uint256 _managerIssueFee
    )
        external
        onlyManager
        onlyInactive
    {
        require(_managerIssueFee <= IFolioController(controller).maxManagerIssueFee, "Manager fee must be less than maximum allowed");
        managerIssueFee = _managerIssueFee;
        emit ManagerFeeEdited(address(this), _managerIssueFee, "Manager Issue Fee");
    }

    /**
     * Fund MANAGER ONLY. Edit manager issue fee
     *
     * @param _managerRedeemFee         Manager redeem fee percentage in 10e16 (e.g. 10e16 = 1%)
     */
    function editManagerRedeemFee(
        ISetToken _setToken,
        uint256 _managerRedeemFee
    )
        external
        onlyManager
        onlyInactive
    {
        require(_managerRedeemFee <= IFolioController(controller).maxManagerRedeemFee, "Manager fee must be less than maximum allowed");
        managerRedeemFee = _managerRedeemFee;
        emit ManagerFeeEdited(address(this), _managerRedeemFee, "Manager Redeem Fee");
    }

    /**
     * Fund MANAGER ONLY. Edit manager issue fee
     *
     * @param _managerFeePercentage         Manager performance fee percentage in 10e16 (e.g. 10e16 = 1%)
     */
    function editManagerPerformanceFee(
        ISetToken _setToken,
        uint256 _managerPerformanceFee
    )
        external
        onlyManager
        onlyInactive
    {
        require(_managerPerformanceFee <= IFolioController(controller).maxManagerPerformanceFee, "Manager fee must be less than maximum allowed");
        managerPerformanceFee = _managerPerformanceFee;
        emit ManagerFeeEdited(address(this), _managerPerformanceFee, "Manager Performance Fee");
    }

    /**
     * SET MANAGER ONLY. Edit the manager fee recipient
     *
     * @param _managerFeeRecipient          Manager fee recipient
     */
    function editManagerFeeRecipient(address _managerFeeRecipient) external onlyManager onlyActive {
        require(_managerFeeRecipient != address(0), "Fee recipient must not be 0 address");

        managerFeeRecipient = _managerFeeRecipient;

        emit FeeRecipientEdited(address(this), _managerFeeRecipient);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Low level function that allows a module to make an arbitrary function
     * call to any contract.
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
     * PRIVELEGED MODULE FUNCTION. Low level function that adds a component to the components array.
     */
    function addInvestment(address _investment) external onlyIntegration onlyActive{
      components.push(_investment);
      investmentsCount ++;
      emit InvestmentAdded(_investment);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Low level function that removes a component from the components array.
     */
    function removeInvestment(address _investment) external onlyIntegration onlyActive{
        components = components.remove(_component);
        investmentsCount --;
        emit InvestmentRemoved(_component);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Low level function that edits a component's virtual unit. Takes a real unit
     * and converts it to virtual before committing.
     */
    function editInvestmentUnit(address _investment, int256 _realUnit) external onlyIntegration onlyActive{
        int256 virtualUnit = _convertRealToVirtualUnit(_realUnit);

        investmentPositions[_investment].virtualUnit = virtualUnit;

        emit DefaultInvestmentUnitEdited(_component, _realUnit);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Modifies the position multiplier. This is typically used to efficiently
     * update all the Positions' units at once in applications where inflation is awarded (e.g. subscription fees).
     */
    function editPositionMultiplier(int256 _newMultiplier) external onlyIntegration onlyActive{
        require(_newMultiplier > 0, "Must be greater than 0");

        positionMultiplier = _newMultiplier;

        emit PositionMultiplierEdited(_newMultiplier);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Increases the "account" balance by the "quantity".
     */
    function mint(address _account, uint256 _quantity) external onlyIntegration onlyActive {
        _mint(_account, _quantity);
    }

    /**
     * PRIVELEGED MODULE FUNCTION. Decreases the "account" balance by the "quantity".
     * _burn checks that the "account" already has the required "quantity".
     */
    function burn(address _account, uint256 _quantity) external onlyIntegration onlyActive {
        _burn(_account, _quantity);
    }

    /**
     * MANAGER ONLY. Adds a module into a PENDING state; Module must later be initialized via
     * module's initialize function
     */
    function addIntegration(address _integration) external onlyManager {
        require(integrationStates[_integration] == IFund.IntegrationState.NONE, "Integration must not be added");
        require(controller.isIntegration(_integration), "Must be enabled on Controller");

        integrationStates[_integration] = IFund.IntegrationState.PENDING;

        emit IntegrationAdded(_integration);
    }

    /**
     * MANAGER ONLY. Removes a module from the SetToken. SetToken calls removeModule on module itself to confirm
     * it is not needed to manage any remaining positions and to remove state.
     */
    function removeIntegration(address _integration) external onlyManager {
        require(integrationStates[_module] == IFund.IntegrationState.PENDING, "Integration must be pending");

        IIntegration(_integration).removeIntegration();

        integrationStates[_integration] = IFund.IntegrationState.NONE;

        integrations = integrations.remove(_integration);

        emit IntegrationRemoved(_integration);
    }

    /**
     * Initializes an added integration from PENDING to INITIALIZED state. Can only call when active.
     * An address can only enter a PENDING state if it is an enabled module added by the manager.
     * Only callable by the module itself, hence msg.sender is the subject of update.
     */
    function initializeIntegration() external {
        require(integrationStates[msg.sender] == IFund.IntegrationState.PENDING, "Integration must be pending");

        integrationStates[msg.sender] = IFund.IntegrationState.INITIALIZED;
        integrations.push(msg.sender);

        emit IntegrationInitialized(msg.sender);
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Fund is disable, deposits and withdrawals are disabled
     */
    function setActive(bool _active) external onlyManagerOrProtocol {
      if (active) {
        require(integrations.length > 0, "Need to have active integrations");
      }
      active = _active;
    }
    /**
     * MANAGER ONLY. Changes manager; We allow null addresses in case the manager wishes to wind down the SetToken.
     * Modules may rely on the manager state, so only changable when unlocked
     */
    function setManager(address _manager) external onlyManagerOrProtocol {
      address oldManager = manager;
      manager = _manager;

      emit ManagerEdited(_manager, oldManager);
    }


    /* ============ External Getter Functions ============ */

    function getInvestments() external view returns(address[] memory) {
      return investments;
    }

    function getReserveAsset() external view returns (address memory) {
      return reserveAsset;
    }

    function getDefaultInvestmentRealUnit(address _integration) public view returns(int256) {
      return _convertVirtualToRealUnit(_defaultInvestmentVirtualUnit(_integration));
    }

    function getIntegrations() external view returns (address[] memory) {
      return integrations;
    }

    function isInvestment(address _investment) external view returns(bool) {
      return investments.contains(_investment);
    }

    /**
     * Only ModuleStates of INITIALIZED modules are considered enabled
     */
    function isInitializedIntegration(address _integration) external view returns (bool) {
      return integrationStates[_integration] == IFund.IntegrationState.INITIALIZED;
    }

    /**
     * Returns whether the module is in a pending state
     */
    function isPendingIntegration(address _integration) external view returns (bool) {
      return integrationStates[_integration] == IFund.IntegrationState.PENDING;
    }

    /**
     * Gets the total number of investments
     */
    function getPositionCount() external view returns (uint256) {
      return investmentsCount;
    }

    // /**
    //  * Returns a list of Positions, through traversing the components. Each component with a non-zero virtual unit
    //  * is considered a Default Position, and each externalPositionModule will generate a unique position.
    //  * Virtual units are converted to real units. This function is typically used off-chain for data presentation purposes.
    //  */
    // function getPositions() external view returns (ISetToken.Position[] memory) {
    //     ISetToken.Position[] memory positions = new ISetToken.Position[](_getPositionCount());
    //     uint256 positionCount = 0;
    //
    //     for (uint256 i = 0; i < components.length; i++) {
    //         address component = components[i];
    //
    //         // A default position exists if the default virtual unit is > 0
    //         if (_defaultPositionVirtualUnit(component) > 0) {
    //             positions[positionCount] = ISetToken.Position({
    //                 component: component,
    //                 module: address(0),
    //                 unit: getDefaultPositionRealUnit(component),
    //                 positionState: DEFAULT,
    //                 data: ""
    //             });
    //
    //             positionCount++;
    //         }
    //
    //         address[] memory externalModules = _externalPositionModules(component);
    //         for (uint256 j = 0; j < externalModules.length; j++) {
    //             address currentModule = externalModules[j];
    //
    //             positions[positionCount] = ISetToken.Position({
    //                 component: component,
    //                 module: currentModule,
    //                 unit: getExternalPositionRealUnit(component, currentModule),
    //                 positionState: EXTERNAL,
    //                 data: _externalPositionData(component, currentModule)
    //             });
    //
    //             positionCount++;
    //         }
    //     }
    //
    //     return positions;
    // }

    /**
     * Returns the total Real Units for a given component, summing the default and external position units.
     */
    function getTotalInvestmentRealUnits(address _investment) external view returns(int256) {
      int256 totalUnits = getDefaultInvestmentRealUnit(_investment);

      return totalUnits;
    }

    receive() external payable {} // solium-disable-line quotes

    /* ============ Internal Functions ============ */

    function _defaultInvestmentVirtualUnit(address _component) internal view returns(int256) {
      return componentPositions[_component].virtualUnit;
    }

    /**
     * Takes a real unit and divides by the position multiplier to return the virtual unit
     */
    function _convertRealToVirtualUnit(int256 _realUnit) internal view returns(int256) {
        int256 virtualUnit = _realUnit.conservativePreciseDiv(positionMultiplier);

        // These checks ensure that the virtual unit does not return a result that has rounded down to 0
        if (_realUnit > 0 && virtualUnit == 0) {
            revert("Virtual unit conversion invalid");
        }

      return virtualUnit;
    }

    /**
     * Takes a virtual unit and multiplies by the position multiplier to return the real unit
     */
    function _convertVirtualToRealUnit(int256 _virtualUnit) internal view returns(int256) {
      return _virtualUnit.conservativePreciseMul(positionMultiplier);
    }

    /**
     * Due to reason error bloat, internal functions are used to reduce bytecode size
     *
     * Module must be initialized on the Fund and enabled by the controller
     */
    function _validateOnlyIntegration() internal view {
        require(
            integrationStates[msg.sender] == IFund.IntegrationState.INITIALIZED,
            "Only the module can call"
        );

        require(
            controller.isIntegration(msg.sender),
            "Integration must be enabled on controller"
        );
    }

    function _validateOnlyManager() internal view {
      require(msg.sender == manager, "Only manager can call");
    }

    function _validateOnlyActive() internal view {
      require(
          active == true,
          "Fund must be active"
      );
    }

    function _validateOnlyInactive() internal view {
      require(
          active == false,
          "Fund must be disabled"
      );
    }

    function _validateOnlyContributor(address _caller) internal view {
      require(
          contributors[_caller].amount > 0,
          "Only the contributor can withdraw their funds"
      );
    }

    function _validateOnlyManagerOrProtocol() internal view {
      require(
          msg.sender == manager || msg.sender == protocol,
          "Only the fund manager or the protocol can modify fund state"
      );
    }

    /**
     * If a pre-issue hook has been configured, call the external-protocol contract. Pre-issue hook logic
     * can contain arbitrary logic including validations, external function calls, etc.
     */
    function _callPreIssueHooks(
        uint256 _reserveAssetQuantity,
        address _caller,
        address _to
    )
        internal
    {
        if (address(managerIssuanceHook) != address(0)) {
            managerIssuanceHook.invokePreIssueHook(address(this), reserveAsset, _reserveAssetQuantity, _caller, _to);
        }
    }

    /**
     * If a pre-redeem hook has been configured, call the external-protocol contract.
     */
    function _callPreRedeemHooks(uint256 _fundTokenQuantity, address _caller, address _to) internal {
        if (address(managerRedemptionHook) != address(0)) {
            managerRedemptionHook.invokePreRedeemHook(address(this), _fundTokenQuantity, _caller, _to);
        }
    }

}
