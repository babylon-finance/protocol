/*
    Copyright 2020 DFolio

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
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ClosedFund } from "./funds/ClosedFund.sol";
import { IFund } from "./interfaces/IFund.sol";
import { AddressArrayUtils } from "./lib/AddressArrayUtils.sol";

/**
 * @title FolioController
 * @author dFolio Protocol
 *
 * FolioController is a smart contract used to deploy new funds contracts and house the
 * integrations and resources of the system.
 */
contract FolioController is Ownable {
    using AddressArrayUtils for address[];
    using SafeMath for uint256;

    /* ============ Events ============ */

    event FundCreated(address indexed _fund, address _manager, string _name, string _symbol);
    event FundAdded(address indexed _setToken, address indexed _factory);
    event FundRemoved(address indexed _setToken);

    event ControllerIntegrationAdded(address indexed _fund, address indexed _integration, string _integrationName);
    event ControllerIntegrationRemoved(address indexed _fund, address indexed _integration, string _integrationName);
    event ControllerIntegrationEdited(
        address indexed _fund,
        address _newIntegration,
        string _integrationName
    );

    event ReserveAssetAdded(address indexed _reserveAsset);
    event ReserveAssetRemoved(address indexed _reserveAsset);

    event FeeEdited(address indexed _fund, uint256 indexed _feeType, uint256 _feePercentage);
    event FeeRecipientChanged(address _newFeeRecipient);

    event ModuleAdded(address indexed _module);
    event ModuleRemoved(address indexed _module);
    event PriceOracleChanged(address indexed _resource);
    event FundValuerChanged(address indexed _resource);

    /* ============ Modifiers ============ */


    /* ============ State Variables ============ */

    // List of enabled Funds
    address[] public funds;
    address[] public reserveAssets;
    address public fundValuer;
    address public priceOracle;
    // Mapping of fund => integration identifier => integration address
   mapping(bytes32 => address) private integrations;

    // Mappings to check whether address is valid Fund or Reserve Asset
    mapping(address => bool) public isFund;
    mapping(address => bool) public validReserveAsset;

    // Recipient of protocol fees
    address public feeRecipient;

    //Maximum fees a manager is allowed
    uint256 public maxManagerDepositFee;
    uint256 public maxManagerWithdrawalFee;
    uint256 public maxManagerPerformanceFee; // on redeem
    // Max Premium percentage (0.01% = 1e14, 1% = 1e16). This premium is a buffer around oracle
    // prices paid by user to the SetToken, which prevents arbitrage and oracle front running
    uint256 public maxFundPremiumPercentage;

    uint256 public protocolPerformanceFee; // (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolFundCreationFee; // (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolDepositFundTokenFee; // (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolWithdrawalFundTokenFee; // (0.01% = 1e14, 1% = 1e16)

    /* ============ Functions ============ */

    /**
     * Initializes the initial fee recipient on deployment.
     *
     * @param _feeRecipient           Address of the initial protocol fee recipient
     * @param _fundValuer             Address of the initial fundValuer
     * @param _priceOracle            Address of the initial _priceOracle
     */
    constructor(
      address _feeRecipient,
      address _fundValuer,
      address _priceOracle
      ) public {
        feeRecipient = _feeRecipient;
        fundValuer = _fundValuer;
        priceOracle = _priceOracle;
    }

    /* ============ External Functions ============ */

    /**
     * Creates a Fund smart contract and registers the Fund with the controller. The Funds are composed
     * of positions that are instantiated as DEFAULT (positionState = 0) state.
     *
     * @param _components             List of addresses of components for initial Positions
     * @param _units                  List of units. Each unit is the # of components per 10^18 of a Fund
     * @param _manager                Address of the manager
     * @param _name                   Name of the Fund Token
     * @param _symbol                 Symbol of the Fund Token
     * @return address                Address of the newly created Fund
     */
    function createFund(
        address[] memory _components,
        int256[] memory _units,
        address _manager,
        string memory _name,
        string memory _symbol
    )
        external
        returns (address)
    {
        require(_components.length > 0, "Must have at least 1 component");
        require(_components.length == _units.length, "Component and unit lengths must be the same");
        require(!_components.hasDuplicate(), "Components must not have a duplicate");
        require(_manager != address(0), "Manager must not be empty");

        for (uint256 i = 0; i < _components.length; i++) {
            require(_components[i] != address(0), "Component must not be null address");
            require(_units[i] > 0, "Units must be greater than 0");
        }

        // Creates a new Fund instance
        ClosedFund fund = new ClosedFund(
            _components,
            _units,
            address(this),
            _manager,
            _name,
            _symbol
        );

        addFund(address(fund));

        emit FundCreated(address(fund), _manager, _name, _symbol);

        return address(fund);
    }

    /**
     * PRIVILEGED FACTORY FUNCTION. Adds a newly deployed Fund as an enabled Fund.
     *
     * @param _fund Address of the Fund contract to add
     */
    function addFund(
      address _fund
    ) internal onlyOwner {
      require(!isFund[_fund], "Fund already exists");
      isFund[_fund] = true;
      funds.push(_fund);
      emit FundAdded(_fund, msg.sender);
    }


    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to remove a Fund
     *
     * @param _fund               Address of the Fund contract to remove
     */
    function removeFund(address _fund) external onlyOwner {
      require(isFund[_fund], "Fund does not exist");

      funds = funds.remove(_fund);

      isFund[_fund] = false;

      emit FundRemoved(_fund);
    }

    /**
     * PRIVILEGED FACTORY FUNCTION. Adds a new valid reserve asset for funds
     *
     * @param _reserveAsset Address of the reserve assset
     */
    function addReserveAsset(
      address _reserveAsset
    ) internal onlyOwner {
      require(!validReserveAsset[_reserveAsset], "Reserve asset already added");
      validReserveAsset[_reserveAsset] = true;
      reserveAssets.push(_reserveAsset);
      emit ReserveAssetAdded(_reserveAsset);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to remove a reserve asset
     *
     * @param _reserveAsset               Address of the reserve asset to remove
     */
    function removeReserveAsset(address _reserveAsset) external onlyOwner {
      require(validReserveAsset[_reserveAsset], "Reserve asset does not exist");

      reserveAssets = reserveAssets.remove(_reserveAsset);

      validReserveAsset[_reserveAsset] = false;

      emit ReserveAssetRemoved(_reserveAsset);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to disable a fund
     *
     * @param _fund               Address of the fund
     */
    function disableFund(address _fund) external onlyOwner {
        require(isFund[_fund], "Fund does not exist");
        IFund fund = IFund(funds[_fund]);
        require(
            fund.active(),
            "The fund needs to be active."
        );
        fund.setActive(false);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to disable a fund
     *
     * @param _fund               Address of the fund
     */
    function reenableFund(address _fund) external onlyOwner {
        require(isFund[_fund], "Fund does not exist");
        IFund fund = IFund(funds[_fund]);
        require(
            !fund.active(),
            "The fund needs to be disabled."
        );
        fund.setActive(false);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the price oracle
     *
     * @param _priceOracle               Address of the new price oracle
     */
    function editPriceOracle(address _priceOracle) external onlyOwner {
       require(_priceOracle != priceOracle, "Price oracle already exists");

       require(_priceOracle != address(0), "Price oracle must exist");

       priceOracle = _priceOracle;

       emit PriceOracleChanged(_priceOracle);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the integration registry
     *
     * @param _fundValuer Address of the new price oracle
     */
    function editFundvaluer(address _fundValuer) external onlyOwner {
       require(_fundValuer != fundValuer, "Fund Valuer already exists");

       require(_fundValuer != address(0), "Fund Valuer must exist");

       fundValuer = _fundValuer;

       emit FundValuerChanged(_fundValuer);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit the protocol fee recipient
     *
     * @param _newFeeRecipient      Address of the new protocol fee recipient
     */
    function editFeeRecipient(address _newFeeRecipient) external onlyOwner {
        require(_newFeeRecipient != address(0), "Address must not be 0");

        feeRecipient = _newFeeRecipient;

        emit FeeRecipientChanged(_newFeeRecipient);
    }

    /**
     * GOVERNANCE FUNCTION: Add a new integration to the registry
     *
     * @param  _name         Human readable string identifying the integration
     * @param  _integration      Address of the integration contract to add
     */
    function addIntegration(
        string memory _name,
        address _integration
    )
        public
        onlyOwner
    {
        bytes32 hashedName = _nameHash(_name);
        require(integrations[hashedName] == address(0), "Integration exists already.");
        require(_integration != address(0), "Integration address must exist.");

        integrations[hashedName] = _integration;

        emit ControllerIntegrationAdded(_integration, _name);
    }

    /**
     * GOVERNANCE FUNCTION: Batch add new integrations. Reverts if exists on any fund and name
     *
     * @param  _names        Array of human readable strings identifying the integration
     * @param  _integrations     Array of addresses of the integration contracts to add
     */
    function batchAddIntegration(
        string[] memory _names,
        address[] memory _integrations
    )
        external
        onlyOwner
    {
        // Storing funds count to local variable to save on invocation
        require(_names.length == _integrations.length, "Names and integration addresses lengths mismatch");

        for (uint256 i = 0; i < _integrations.length; i++) {
            // Add integrations to the specified fund. Will revert if fund and name combination exists
            addIntegration(
                _names[i],
                _integrations[i]
            );
        }
    }

    /**
     * GOVERNANCE FUNCTION: Edit an existing integration on the registry
     *
     * @param  _name         Human readable string identifying the integration
     * @param  _integration      Address of the integration contract to edit
     */
    function editIntegration(
        string memory _name,
        address _integration
    )
        public
        onlyOwner
    {
        bytes32 hashedName = _nameHash(_name);

        require(integrations[hashedName] != address(0), "Integration does not exist.");
        require(_integration != address(0), "Integration address must exist.");

        integrations[hashedName] = _integration;

        emit ControllerIntegrationEdited(_integration, _name);
    }

    /**
     * GOVERNANCE FUNCTION: Batch edit integrations for funds. Reverts if fund and
     * integration name don't map to an integration address
     *
     * @param  _names        Array of human readable strings identifying the integration
     * @param  _integrations     Array of addresses of the integration contracts to add
     */
    function batchEditIntegration(
        string[] memory _names,
        address[] memory _integrations
    )
        external
        onlyOwner
    {
        // Storing name count to local variable to save on invocation
        uint256 fundsCount = funds.length;

        require(_names.length == _integrations.length, "Names and integration addresses lengths mismatch");


        for (uint256 i = 0; i < _integrations.length; i++) {
            // Edits integrations to the specified fund. Will revert if fund and name combination does not exist
            editIntegration(
                _names[i],
                _integrations[i]
            );
        }
    }

    /**
     * GOVERNANCE FUNCTION: Remove an existing integration on the registry
     *
     * @param  _name         Human readable string identifying the integration
     */
    function removeIntegration(string memory _name) external onlyOwner {
        bytes32 hashedName = _nameHash(_name);
        require(integrations[hashedName] != address(0), "Integration does not exist.");

        address oldIntegration = integrations[hashedName];
        delete integrations[hashedName];

        emit ControllerIntegrationRemoved(oldIntegration, _name);
    }


    /* ============ External Getter Functions ============ */

    function getPriceOracle() external view returns (address) {
        return priceOracle;
    }

    function getFundValuer() external view returns (address) {
        return fundValuer;
    }

    function getFunds() external view returns (address[] memory) {
        return funds;
    }

    function isValidReserveAsset(address _reserveAsset) external view returns (address[] memory) {
      return validReserveAsset[_reserveAsset];
    }

    /**
     * Get integration integration address associated with passed human readable name
     *
     * @param  _name         Human readable integration name
     *
     * @return               Address of integration
     */
    function getIntegrationByName(string memory _name) external view returns (address) {
        return integrations[_nameHash(_name)];
    }

    /**
     * Get integration integration address associated with passed hashed name
     *
     * @param  _nameHashP     Hash of human readable integration name
     *
     * @return               Address of integration
     */
    function getIntegrationWithHash(bytes32 _nameHashP) external view returns (address) {
        return integrations[_nameHashP];
    }

    /**
     * Check if integration name is valid
     *
     * @param  _name         Human readable string identifying the integration
     *
     * @return               Boolean indicating if valid
     */
    function isValidIntegration(string memory _name) external view returns (bool) {
        return integrations[_nameHash(_name)] != address(0);
    }

    /**
     * Check if a contract address is a fund or one of the system contracts
     *
     * @param  _contractAddress           The contract address to check
     */
    function isSystemContract(address _contractAddress) external view returns (bool) {
        return (
            isFund[_contractAddress] ||
            fundValuer ||
            priceOracle ||
            _contractAddress == address(this)
        );
    }

    /* ============ Internal Only Function ============ */

    /**
     * Hashes the string and returns a bytes32 value
     */
    function _nameHash(string memory _name) internal pure returns(bytes32) {
        return keccak256(bytes(_name));
    }
}
