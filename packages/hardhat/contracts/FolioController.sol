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
import { SafeMath } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Fund } from "./Fund.sol";
import { AddressArrayUtils } from "../lib/AddressArrayUtils.sol";

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

    event FeeEdited(address indexed _fund, uint256 indexed _feeType, uint256 _feePercentage);
    event FeeRecipientChanged(address _newFeeRecipient);

    event ModuleAdded(address indexed _module);
    event ModuleRemoved(address indexed _module);
    event PriceOracleChanged(address indexed _resource);
    event FundValuerChanged(address indexed _resource);
    event IntegrationRegistryChanged(address indexed _resource);

    /* ============ Modifiers ============ */


    /* ============ State Variables ============ */

    // List of enabled Funds
    address[] public funds;
    address public integrationRegistry;
    address public fundValuer;
    address public priceOracle;

    // Mappings to check whether address is valid Set, Factory, Module or Resource
    mapping(address => bool) public isFund;

    // Mapping of modules to fee types to fee percentage. A module can have multiple feeTypes
    // Fee is denominated in precise unit percentages (100% = 1e18, 1% = 1e16)
    mapping(address => mapping(uint256 => uint256)) public fees;

    // Recipient of protocol fees
    address public feeRecipient;

    // Total funds in the system
    uint256 public totalFunds = 0;
    uint256 public totalActiveFunds = 0;

    /* ============ Functions ============ */

    /**
     * Initializes the initial fee recipient on deployment.
     *
     * @param _feeRecipient           Address of the initial protocol fee recipient
     * @param _integrationRegistry    Address of the initial integration registry
     * @param _fundValuer             Address of the initial fundValuer
     * @param _priceOracle            Address of the initial _priceOracle
     */
    constructor(
      address _feeRecipient,
      address _integrationRegistry,
      address _fundValuer,
      address _priceOracle
      ) public {
        feeRecipient = _feeRecipient;
        integrationRegistry = _integrationRegistry;
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
        Fund fund = new Fund(
            _components,
            _units,
            address(this),
            _manager,
            _name,
            _symbol
        );

        addSet(address(fund));

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
      emit FundAdded(_setToken, msg.sender);
      totalFunds++;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to remove a Fund
     *
     * @param _fund               Address of the Fund contract to remove
     */
    function removeSet(address _fund) external onlyOwner {
      require(isFund[_fund], "Fund does not exist");

      funds = funds.remove(_fund);

      isFund[_fund] = false;

      emit FundRemoved(_fund);
      totalFunds--;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to disable a fund
     *
     * @param _fund               Address of the fund
     */
    function disableFund(address _fund) external onlyOwner {
        require(isFund[_fund], "Fund does not exist");
        Fund memory fund = funds[_fund];
        require(
            fund.active(),
            "The fund needs to be active."
        );
        fund.hedgeFund.setActive(false);
        totalActiveFunds--;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to disable a fund
     *
     * @param _fund               Address of the fund
     */
    function reenableFund(address _fund) external onlyOwner {
        require(isFund[_fund], "Fund does not exist");
        Fund memory fund = funds[_fund];
        require(
            !fund.active(),
            "The fund needs to be disabled."
        );
        fund.hedgeFund.setActive(false);
        totalActiveFunds++;
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
     * @param _integrationRegistry Address of the new price oracle
     */
    function editIntegrationRegistry(address _integrationRegistry) external onlyOwner {
       require(_integrationRegistry != integrationRegistry, "Integration Registry already exists");

       require(_integrationRegistry != address(0), "Integration Registry must exist");

       integrationRegistry = _integrationRegistry;

       emit IntegrationRegistryChanged(_integrationRegistry);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the integration registry
     *
     * @param _fundValuer Address of the new price oracle
     */
    function editFundvaluer(address _fundValuer) external onlyOwner {
       require(_fundvaluer != fundValuer, "Fund Valuer already exists");

       require(_fundvaluer != address(0), "Fund Valuer must exist");

       fundValuer = _fundvaluer;

       emit FundValuerChanged(_fundvaluer);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to add a fee to a module
     *
     * @param _module               Address of the module contract to add fee to
     * @param _feeType              Type of the fee to add in the module
     * @param _newFeePercentage     Percentage of fee to add in the module (denominated in preciseUnits eg 1% = 1e16)
     */
    function addFee(address _fund, uint256 _feeType, uint256 _newFeePercentage) external onlyOwner {
        require(isFund[_fund], "Fund does not exist");

        require(fees[_fund][_feeType] == 0, "Fee type already exists on module");

        fees[_fund][_feeType] = _newFeePercentage;

        emit FeeEdited(_fund, _feeType, _newFeePercentage);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit a fee in an existing module
     *
     * @param _module               Address of the module contract to edit fee
     * @param _feeType              Type of the fee to edit in the module
     * @param _newFeePercentage     Percentage of fee to edit in the module (denominated in preciseUnits eg 1% = 1e16)
     */
    function editFee(address _module, uint256 _feeType, uint256 _newFeePercentage) external onlyOwner {
        require(isFund[_fund], "Fund does not exist");

        require(fees[_fund][_feeType] != 0, "Fee type does not exist on module");

        fees[_module][_feeType] = _newFeePercentage;

        emit FeeEdited(_fund, _feeType, _newFeePercentage);
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

    /* ============ External Getter Functions ============ */

    function getModuleFee(
        address _moduleAddress,
        uint256 _feeType
    )
        external
        view
        returns (uint256)
    {
        return fees[_moduleAddress][_feeType];
    }

    function getIntegrationRegistry() external view returns (address memory) {
        return integrationRegistry;
    }

    function getPriceOracle() external view returns (address memory) {
        return priceOracle;
    }

    function getFundValuer() external view returns (address memory) {
        return fundValuer;
    }

    function getFunds() external view returns (address[] memory) {
        return funds;
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
            integrationRegistry ||
            _contractAddress == address(this)
        );
    }
}
