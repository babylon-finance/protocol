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
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ClosedFund} from "./ClosedFund.sol";
import {IFund} from "./interfaces/IFund.sol";
import {IIntegration} from "./interfaces/IIntegration.sol";
import {AddressArrayUtils} from "./lib/AddressArrayUtils.sol";

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

    event FundCreated(
        address indexed _fund,
        address _manager,
        string _name,
        string _symbol
    );
    event FundAdded(address indexed _setToken, address indexed _factory);
    event FundRemoved(address indexed _setToken);

    event ControllerIntegrationAdded(
        address indexed _integration,
        string _integrationName
    );
    event ControllerIntegrationRemoved(
        address indexed _integration,
        string _integrationName
    );
    event ControllerIntegrationEdited(
        address _newIntegration,
        string _integrationName
    );

    event ReserveAssetAdded(address indexed _reserveAsset);
    event ReserveAssetRemoved(address indexed _reserveAsset);

    event FeeEdited(
        address indexed _fund,
        uint256 indexed _feeType,
        uint256 _feePercentage
    );
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
     * @param _priceOracle            Address of the initial priceOracle
     */
    constructor(
        address _feeRecipient,
        address _fundValuer,
        address _priceOracle
    ) {
        feeRecipient = _feeRecipient;
        fundValuer = _fundValuer;
        priceOracle = _priceOracle;
    }

    /* ============ External Functions ============ */

    /**
     * Creates a Fund smart contract and registers the Fund with the controller. The Funds are composed
     * of positions that are instantiated as DEFAULT (positionState = 0) state.
     *
     * @param _integrations           List of integrations to enable. All integrations must be approved by the Controller
     * @param _weth                   Address of the WETH ERC20
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _manager                Address of the manager
     * @param _managerFeeRecipient    Address where the manager will receive the fees
     * @param _name                   Name of the Fund
     * @param _symbol                 Symbol of the Fund
     * @param _minContribution        Min contribution to the fund
     */
    function createFund(
        address[] memory _integrations,
        address _weth,
        address _reserveAsset,
        address _manager,
        address _managerFeeRecipient,
        string memory _name,
        string memory _symbol,
        uint256 _minContribution
    ) external returns (address) {
        require(_manager != address(0), "Manager must not be empty");
        require(
            _managerFeeRecipient != address(0),
            "Manager must not be empty"
        );

        for (uint256 i = 0; i < _integrations.length; i++) {
          require(
              _integrations[i] != address(0),
              "Component must not be null address"
          );
        }

        // Creates a new Fund instance
        ClosedFund fund =
            new ClosedFund(
                _integrations,
                _weth,
                _reserveAsset,
                address(this),
                _manager,
                _managerFeeRecipient,
                _name,
                _symbol,
                _minContribution
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
    function addFund(address _fund) internal onlyOwner {
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
    function addReserveAsset(address _reserveAsset) external onlyOwner {
        require(
            !validReserveAsset[_reserveAsset],
            "Reserve asset already added"
        );
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
        require(
            validReserveAsset[_reserveAsset],
            "Reserve asset does not exist"
        );

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
        IFund fund = IFund(_fund);
        require(!!fund.active(), "The fund needs to be active.");
        fund.setActive();
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to enable a fund
     *
     * @param _fund               Address of the fund
     */
    function enableFund(address _fund) external onlyOwner {
        require(isFund[_fund], "Fund does not exist");
        IFund fund = IFund(_fund);
        require(!fund.active(), "The fund needs to be disabled.");
        fund.setDisabled();
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
    function editFundValuer(address _fundValuer) external onlyOwner {
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
    function addIntegration(string memory _name, address _integration)
        public
        onlyOwner
    {
        bytes32 hashedName = _nameHash(_name);
        require(
            integrations[hashedName] == address(0),
            "Integration exists already."
        );
        require(_integration != address(0), "Integration address must exist.");

        integrations[hashedName] = _integration;

        emit ControllerIntegrationAdded(_integration, _name);
    }

    /**
     * GOVERNANCE FUNCTION: Initializes an integration in a fund
     *
     * @param  _integration       Address of the integration contract to add
     * @param  _fund              Address of the fund
     */
    function initializeIntegration(address _integration, address _fund)
        public
        onlyOwner
    {
      IIntegration(_integration).initialize(_fund);
    }

    /**
     * GOVERNANCE FUNCTION: Edit an existing integration on the registry
     *
     * @param  _name         Human readable string identifying the integration
     * @param  _integration      Address of the integration contract to edit
     */
    function editIntegration(string memory _name, address _integration)
        public
        onlyOwner
    {
        bytes32 hashedName = _nameHash(_name);

        require(
            integrations[hashedName] != address(0),
            "Integration does not exist."
        );
        require(_integration != address(0), "Integration address must exist.");

        integrations[hashedName] = _integration;

        emit ControllerIntegrationEdited(_integration, _name);
    }

    /**
     * GOVERNANCE FUNCTION: Remove an existing integration on the registry
     *
     * @param  _name         Human readable string identifying the integration
     */
    function removeIntegration(string memory _name) external onlyOwner {
        bytes32 hashedName = _nameHash(_name);
        require(
            integrations[hashedName] != address(0),
            "Integration does not exist."
        );

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

    function getReserveAssets() external view returns (address[] memory) {
        return reserveAssets;
    }

    function getProtocolDepositFundTokenFee() external view returns (uint256) {
        return protocolDepositFundTokenFee;
    }

    function getProtocolWithdrawalFundTokenFee()
        external
        view
        returns (uint256)
    {
        return protocolWithdrawalFundTokenFee;
    }

    function getFeeRecipient() external view returns (address) {
        return feeRecipient;
    }

    function getMaxManagerDepositFee() external view returns (uint256) {
        return maxManagerDepositFee;
    }

    function getMaxManagerWithdrawalFee() external view returns (uint256) {
        return maxManagerWithdrawalFee;
    }

    function getMaxManagerPerformanceFee() external view returns (uint256) {
        return maxManagerPerformanceFee;
    }

    function getMaxFundPremiumPercentage() external view returns (uint256) {
        return maxFundPremiumPercentage;
    }

    function isValidReserveAsset(address _reserveAsset)
        external
        view
        returns (bool)
    {
        return validReserveAsset[_reserveAsset];
    }

    /**
     * Get integration integration address associated with passed human readable name
     *
     * @param  _name         Human readable integration name
     *
     * @return               Address of integration
     */
    function getIntegrationByName(string memory _name)
        external
        view
        returns (address)
    {
        return integrations[_nameHash(_name)];
    }

    /**
     * Get integration integration address associated with passed human readable name
     *
     * @param  _integration         Address of the integration
     *
     * @return                  Integration fee
     */
    function getIntegrationFee(address _integration)
        external
        view
        returns (uint256)
    {
        return 0;
    }

    /**
     * Get integration integration address associated with passed hashed name
     *
     * @param  _nameHashP     Hash of human readable integration name
     *
     * @return               Address of integration
     */
    function getIntegrationWithHash(bytes32 _nameHashP)
        external
        view
        returns (address)
    {
        return integrations[_nameHashP];
    }

    /**
     * Check if integration name is valid
     *
     * @param  _name         Human readable string identifying the integration
     *
     * @return               Boolean indicating if valid
     */
    function isValidIntegration(string memory _name)
        external
        view
        returns (bool)
    {
        return integrations[_nameHash(_name)] != address(0);
    }

    /**
     * Check if a contract address is a fund or one of the system contracts
     *
     * @param  _contractAddress           The contract address to check
     */
    function isSystemContract(address _contractAddress)
        external
        view
        returns (bool)
    {
        return (isFund[_contractAddress] ||
            fundValuer == address(this) ||
            priceOracle == address(this) ||
            _contractAddress == address(this));
    }

    /* ============ Internal Only Function ============ */

    /**
     * Hashes the string and returns a bytes32 value
     */
    function _nameHash(string memory _name) internal pure returns (bytes32) {
        return keccak256(bytes(_name));
    }
}
