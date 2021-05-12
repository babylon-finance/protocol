/*
    Copyright 2021 Babylon Finance

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

pragma solidity 0.7.6;

import 'hardhat/console.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {RewardsDistributor} from './token/RewardsDistributor.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IGardenFactory} from './interfaces/IGardenFactory.sol';
import {IStrategy} from './interfaces/IStrategy.sol';
import {IIshtarGate} from './interfaces/IIshtarGate.sol';
import {IIntegration} from './interfaces/IIntegration.sol';
import {IBabController} from './interfaces/IBabController.sol';

import {AddressArrayUtils} from './lib/AddressArrayUtils.sol';

/**
 * @title BabController
 * @author Babylon Finance Protocol
 *
 * BabController is a smart contract used to deploy new gardens contracts and house the
 * integrations and resources of the system.
 */
contract BabController is OwnableUpgradeable, IBabController {
    using AddressArrayUtils for address[];
    using AddressUpgradeable for address;
    using SafeMath for uint256;

    /* ============ Events ============ */
    event GardenAdded(address indexed _garden, address indexed _factory);
    event GardenRemoved(address indexed _garden);

    event ControllerIntegrationAdded(address _integration, string indexed _integrationName);
    event ControllerIntegrationRemoved(address _integration, string indexed _integrationName);
    event ControllerIntegrationEdited(address _newIntegration, string indexed _integrationName);
    event ControllerOperationSet(uint8 indexed _kind, address _address);
    event DefaultTradeIntegrationChanged(address indexed _newTradeIntegration, address _oldTradeIntegration);

    event ReserveAssetAdded(address indexed _reserveAsset);
    event ReserveAssetRemoved(address indexed _reserveAsset);
    event LiquidityMinimumEdited(uint256 _minRiskyPairLiquidityEth);

    event PriceOracleChanged(address indexed _priceOracle, address _oldPriceOracle);
    event RewardsDistributorChanged(address indexed _rewardsDistributor, address _oldRewardsDistributor);
    event TreasuryChanged(address _newTreasury, address _oldTreasury);
    event IshtarGateChanged(address _newIshtarGate, address _oldIshtarGate);
    event GardenValuerChanged(address indexed _gardenValuer, address _oldGardenValuer);
    event GardenFactoryChanged(address indexed _gardenFactory, address _oldGardenFactory);

    event StrategyFactoryEdited(address indexed _strategyFactory, address _oldStrategyFactory);

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    address public constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint8 public constant MAX_OPERATIONS = 20;

    // List of enabled Communities
    address[] public gardens;
    address[] public reserveAssets;
    address public override gardenValuer;
    address public override priceOracle;
    address public override gardenFactory;
    address public override rewardsDistributor;
    address public override ishtarGate;
    address public override strategyFactory;

    // Mapping of integration name => integration address
    mapping(bytes32 => address) private enabledIntegrations;
    // Address of the default trade integration used by the protocol
    address public override defaultTradeIntegration;
    // Mapping of valid operations
    address[MAX_OPERATIONS] public override enabledOperations;

    // Mappings to check whether address is valid Garden or Reserve Asset
    mapping(address => bool) public override isGarden;
    mapping(address => bool) public validReserveAsset;

    // Mapping to check whitelisted assets
    mapping(address => bool) public assetWhitelist;

    // Mapping to check keepers
    mapping(address => bool) public keeperList;

    // Recipient of protocol fees
    address public override treasury;

    // Strategy cooldown period
    uint256 public constant MIN_COOLDOWN_PERIOD = 6 hours;
    uint256 public constant MAX_COOLDOWN_PERIOD = 7 days;

    // Strategy Profit Sharing
    uint256 public strategistProfitPercentage; // (0.01% = 1e14, 1% = 1e16)
    uint256 public stewardsProfitPercentage; // (0.01% = 1e14, 1% = 1e16)
    uint256 public lpsProfitPercentage; //

    // Strategy BABL Rewards Sharing
    uint256 public strategistBABLPercentage; // (0.01% = 1e14, 1% = 1e16)
    uint256 public stewardsBABLPercentage; // (0.01% = 1e14, 1% = 1e16)
    uint256 public lpsBABLPercentage; //

    uint256 public gardenCreatorBonus;

    // Assets
    // Absolute Min liquidity of assets for risky gardens 1000 ETH
    uint256 public override minRiskyPairLiquidityEth;

    // Enable Transfer of ERC20 gardenTokens
    // Only members can transfer tokens until the protocol is fully decentralized
    bool public override gardenTokensTransfersEnabled;

    // Enable and starts the BABL Mining program within Rewards Distributor contract
    bool public override bablMiningProgramEnabled;
    // Enable public gardens
    bool public override allowPublicGardens;

    uint256 public override protocolPerformanceFee; // 5% (0.01% = 1e14, 1% = 1e16) on profits
    uint256 public override protocolManagementFee; // 0.5% (0.01% = 1e14, 1% = 1e16)
    uint256 public override protocolDepositGardenTokenFee; // 0 (0.01% = 1e14, 1% = 1e16)
    uint256 public override protocolWithdrawalGardenTokenFee; // 0 (0.01% = 1e14, 1% = 1e16)

    /* ============ Constructor ============ */

    /**
     * Initializes the initial fee recipient on deployment.
     */
    function initialize() public {
        OwnableUpgradeable.__Ownable_init();

        // vars init values has to be set in initialize due to how upgrade proxy pattern works
        protocolManagementFee = 5e15; // 0.5% (0.01% = 1e14, 1% = 1e16)
        protocolPerformanceFee = 5e16; // 5% (0.01% = 1e14, 1% = 1e16) on profits
        protocolDepositGardenTokenFee = 0; // 0% (0.01% = 1e14, 1% = 1e16) on profits
        protocolWithdrawalGardenTokenFee = 0; // 0% (0.01% = 1e14, 1% = 1e16) on profits
        gardenTokensTransfersEnabled = false;
        bablMiningProgramEnabled = false;
        allowPublicGardens = false;
        minRiskyPairLiquidityEth = 100 * 1e18;

        strategistProfitPercentage = 10e16;
        stewardsProfitPercentage = 5e16;
        lpsProfitPercentage = 80e16;

        strategistBABLPercentage = 8e16;
        stewardsBABLPercentage = 17e16;
        lpsBABLPercentage = 75e16;

        gardenCreatorBonus = 15e16;
    }

    /* ============ External Functions ============ */

    // ===========  Garden related Gov Functions ======
    /**
     * Creates a Garden smart contract and registers the Garden with the controller.
     *
     * @param _reserveAsset           Reserve asset of the Garden. Initially just weth
     * @param _name                   Name of the Garden
     * @param _symbol                 Symbol of the Garden
     * @param _gardenParams           Array of numeric garden params
     * @param _tokenURI               Garden NFT token URI
     * @param _seed                   Seed to regenerate the garden NFT
     */
    function createGarden(
        address _reserveAsset,
        string memory _name,
        string memory _symbol,
        string memory _tokenURI,
        uint256 _seed,
        uint256[] calldata _gardenParams
    ) external payable override returns (address) {
        require(defaultTradeIntegration != address(0), 'Need a default trade integration');
        require(enabledOperations.length > 0, 'Need operations enabled');
        require(IIshtarGate(ishtarGate).canCreate(msg.sender), 'User does not have creation permissions');
        address newGarden =
            IGardenFactory(gardenFactory).createGarden{value: msg.value}(
                _reserveAsset,
                address(this),
                msg.sender,
                _name,
                _symbol,
                _tokenURI,
                _seed,
                _gardenParams
            );

        require(!isGarden[newGarden], 'Garden already exists');
        isGarden[newGarden] = true;
        gardens.push(newGarden);
        emit GardenAdded(newGarden, msg.sender);
        return newGarden;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to remove a Garden
     *
     * @param _garden               Address of the Garden contract to remove
     */
    function removeGarden(address _garden) external override onlyOwner {
        require(isGarden[_garden], 'Garden does not exist');
        require(!IGarden(_garden).active(), 'The garden needs to be disabled.');
        gardens = gardens.remove(_garden);

        delete isGarden[_garden];

        emit GardenRemoved(_garden);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to disable a garden
     *
     * @param _garden               Address of the garden
     */
    function disableGarden(address _garden) external override onlyOwner {
        require(isGarden[_garden], 'Garden does not exist');
        IGarden garden = IGarden(_garden);
        require(garden.active(), 'The garden needs to be active.');
        garden.setActive(false);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to enable a garden
     *
     * @param _garden               Address of the garden
     */
    function enableGarden(address _garden) external onlyOwner {
        require(isGarden[_garden], 'Garden does not exist');
        IGarden garden = IGarden(_garden);
        require(!garden.active(), 'The garden needs to be disabled.');
        garden.setActive(true);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows transfers of ERC20 gardenTokens
     * Can only happen after 2021 is finished.
     */
    function enableGardenTokensTransfers() external override onlyOwner {
        require(block.timestamp > 1641024000000, 'Transfers cannot be enabled yet');
        gardenTokensTransfersEnabled = true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows transfers of ERC20 BABL Tokens
     * Can only happen after the protocol is fully decentralized.
     * PRIVILEGED GOVERNANCE FUNCTION. Allows public gardens
     */
    function setAllowPublicGardens() external override onlyOwner {
        allowPublicGardens = true;
    }

    // ===========  Protocol related Gov Functions ======

    /**  PRIVILEGED GOVERNANCE FUNCTION. Enable and starts the BABL Mining program by the Rewards Distributor
     * Can only happen after public launch of the protocol.
     */
    function enableBABLMiningProgram() external override onlyOwner {
        if (bablMiningProgramEnabled == false) {
            // Can only be activated once
            bablMiningProgramEnabled = true;
            RewardsDistributor(rewardsDistributor).startBABLRewards(); // Sets the timestamp
        }
    }

    /**
     * PRIVILEGED FACTORY FUNCTION. Adds a new valid keeper to the list
     *
     * @param _keeper Address of the keeper
     */
    function addKeeper(address _keeper) external override onlyOwner {
        keeperList[_keeper] = true;
    }

    /**
     * PRIVILEGED FACTORY FUNCTION. Removes a keeper
     *
     * @param _keeper Address of the keeper
     */
    function removeKeeper(address _keeper) external override onlyOwner {
        require(keeperList[_keeper], 'Keeper is whitelisted');
        delete keeperList[_keeper];
    }

    /**
     * PRIVILEGED FACTORY FUNCTION. Adds a list of assets to the whitelist
     *
     * @param _keepers List with keeprs of the assets to whitelist
     */
    function addKeepers(address[] memory _keepers) external override onlyOwner {
        for (uint256 i = 0; i < _keepers.length; i++) {
            keeperList[_keepers[i]] = true;
        }
    }

    /**
     * PRIVILEGED FACTORY FUNCTION. Adds a new valid reserve asset for gardens
     *
     * @param _reserveAsset Address of the reserve assset
     */
    function addReserveAsset(address _reserveAsset) external override onlyOwner {
        require(!validReserveAsset[_reserveAsset], 'Reserve asset already added');
        validReserveAsset[_reserveAsset] = true;
        reserveAssets.push(_reserveAsset);
        emit ReserveAssetAdded(_reserveAsset);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to remove a reserve asset
     *
     * @param _reserveAsset               Address of the reserve asset to remove
     */
    function removeReserveAsset(address _reserveAsset) external override onlyOwner {
        require(validReserveAsset[_reserveAsset], 'Reserve asset does not exist');

        reserveAssets = reserveAssets.remove(_reserveAsset);

        delete validReserveAsset[_reserveAsset];

        emit ReserveAssetRemoved(_reserveAsset);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the price oracle
     *
     * @param _priceOracle               Address of the new price oracle
     */
    function editPriceOracle(address _priceOracle) external override onlyOwner {
        require(_priceOracle != priceOracle, 'Price oracle already exists');

        require(_priceOracle != address(0), 'Price oracle must exist');

        address oldPriceOracle = priceOracle;
        priceOracle = _priceOracle;

        emit PriceOracleChanged(_priceOracle, oldPriceOracle);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the Ishtar Gate Address
     *
     * @param _ishtarGate               Address of the new Ishtar Gate
     */
    function editIshtarGate(address _ishtarGate) external override onlyOwner {
        require(_ishtarGate != ishtarGate, 'Ishtar Gate already exists');

        require(_ishtarGate != address(0), 'Ishtar Gate oracle must exist');

        address oldIshtarGate = ishtarGate;
        ishtarGate = _ishtarGate;

        emit IshtarGateChanged(_ishtarGate, oldIshtarGate);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the garden valuer
     *
     * @param _gardenValuer Address of the new garden valuer
     */
    function editGardenValuer(address _gardenValuer) external override onlyOwner {
        require(_gardenValuer != gardenValuer, 'Garden Valuer already exists');

        require(_gardenValuer != address(0), 'Garden Valuer must exist');

        address oldGardenValuer = gardenValuer;
        gardenValuer = _gardenValuer;

        emit GardenValuerChanged(_gardenValuer, oldGardenValuer);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit the protocol fee recipient
     *
     * @param _newTreasury      Address of the new protocol fee recipient
     */
    function editTreasury(address _newTreasury) external override onlyOwner {
        require(_newTreasury != address(0), 'Address must not be 0');

        address oldTreasury = treasury;
        treasury = _newTreasury;

        emit TreasuryChanged(_newTreasury, oldTreasury);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit the rewards distributor
     *
     * @param _newRewardsDistributor      Address of the new rewards distributor
     */
    function editRewardsDistributor(address _newRewardsDistributor) external override onlyOwner {
        require(_newRewardsDistributor != address(0), 'Address must not be 0');

        address oldRewardsDistributor = rewardsDistributor;
        rewardsDistributor = _newRewardsDistributor;

        emit RewardsDistributorChanged(_newRewardsDistributor, oldRewardsDistributor);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit the protocol garden factory
     *
     * @param _newGardenFactory      Address of the new garden factory
     */
    function editGardenFactory(address _newGardenFactory) external override onlyOwner {
        require(_newGardenFactory != address(0), 'Address must not be 0');

        address oldGardenFactory = gardenFactory;
        gardenFactory = _newGardenFactory;

        emit GardenFactoryChanged(_newGardenFactory, oldGardenFactory);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit the protocol strategy factory
     *
     * @param _newStrategyFactory      Address of the new strategy factory
     */
    function editStrategyFactory(address _newStrategyFactory) external override onlyOwner {
        require(_newStrategyFactory != address(0), 'Address must not be 0');

        address oldStrategyFactory = strategyFactory;
        strategyFactory = _newStrategyFactory;

        emit StrategyFactoryEdited(_newStrategyFactory, oldStrategyFactory);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit the protocol default trde integration
     *
     * @param _newDefaultTradeIntegation      Address of the new default trade integration
     */
    function setDefaultTradeIntegration(address _newDefaultTradeIntegation) external override onlyOwner {
        require(_newDefaultTradeIntegation != address(0), 'Address must not be 0');
        require(_newDefaultTradeIntegation != defaultTradeIntegration, 'Address must be different');
        require(
            enabledIntegrations[_nameHash(IIntegration(_newDefaultTradeIntegation).getName())] ==
                _newDefaultTradeIntegation,
            'Integration needs to be valid'
        );
        address oldDefaultTradeIntegration = defaultTradeIntegration;
        defaultTradeIntegration = _newDefaultTradeIntegation;

        emit DefaultTradeIntegrationChanged(_newDefaultTradeIntegation, oldDefaultTradeIntegration);
    }

    /**
     * GOVERNANCE FUNCTION: Add a new integration to the registry
     *
     * @param  _name             Human readable string identifying the integration
     * @param  _integration      Address of the integration contract to add
     */
    function addIntegration(string memory _name, address _integration) public override onlyOwner {
        bytes32 hashedName = _nameHash(_name);
        require(enabledIntegrations[hashedName] == address(0), 'Integration exists already.');
        require(_integration != address(0), 'Integration address must exist.');

        enabledIntegrations[hashedName] = _integration;

        emit ControllerIntegrationAdded(_integration, _name);
    }

    /**
     * GOVERNANCE FUNCTION: Edit an existing integration on the registry
     *
     * @param  _name         Human readable string identifying the integration
     * @param  _integration      Address of the integration contract to edit
     */
    function editIntegration(string memory _name, address _integration) public override onlyOwner {
        bytes32 hashedName = _nameHash(_name);

        require(enabledIntegrations[hashedName] != address(0), 'Integration does not exist.');
        require(_integration != address(0), 'Integration address must exist.');

        enabledIntegrations[hashedName] = _integration;

        emit ControllerIntegrationEdited(_integration, _name);
    }

    /**
     * GOVERNANCE FUNCTION: Remove an existing integration on the registry
     *
     * @param  _name         Human readable string identifying the integration
     */
    function removeIntegration(string memory _name) external override onlyOwner {
        bytes32 hashedName = _nameHash(_name);
        require(enabledIntegrations[hashedName] != address(0), 'Integration does not exist.');

        address oldIntegration = enabledIntegrations[hashedName];
        delete enabledIntegrations[hashedName];

        emit ControllerIntegrationRemoved(oldIntegration, _name);
    }

    /**
     * GOVERNANCE FUNCTION: Edit an existing operation on the registry
     *
     * @param  _kind             Operation kind
     * @param  _operation        Address of the operation contract to set
     */
    function setOperation(uint8 _kind, address _operation) public override onlyOwner {
        require(_kind < MAX_OPERATIONS, 'Max operations reached');
        require(enabledOperations[_kind] != _operation, 'Operation already set');
        require(_operation != address(0), 'Operation address must exist.');
        enabledOperations[_kind] = _operation;

        emit ControllerOperationSet(_kind, _operation);
    }

    /**
     * GOVERNANCE FUNCTION: Edits the minimum liquidity an asset must have on Uniswap
     *
     * @param  _minRiskyPairLiquidityEth       Absolute min liquidity of an asset to grab price
     */
    function editLiquidityMinimum(uint256 _minRiskyPairLiquidityEth) public override onlyOwner {
        require(_minRiskyPairLiquidityEth > 0, '_minRiskyPairLiquidityEth > 0');
        minRiskyPairLiquidityEth = _minRiskyPairLiquidityEth;

        emit LiquidityMinimumEdited(_minRiskyPairLiquidityEth);
    }

    /* ============ External Getter Functions ============ */

    function owner() public view override(IBabController, OwnableUpgradeable) returns (address) {
        return OwnableUpgradeable.owner();
    }

    function getUniswapFactory() external pure override returns (address) {
        return UNISWAP_FACTORY;
    }

    function getGardens() external view override returns (address[] memory) {
        return gardens;
    }

    function getOperations() external view override returns (address[20] memory) {
        return enabledOperations;
    }

    function getReserveAssets() external view returns (address[] memory) {
        return reserveAssets;
    }

    function getMinCooldownPeriod() external pure override returns (uint256) {
        return MIN_COOLDOWN_PERIOD;
    }

    function getMaxCooldownPeriod() external pure override returns (uint256) {
        return MAX_COOLDOWN_PERIOD;
    }

    function isValidReserveAsset(address _reserveAsset) external view override returns (bool) {
        return validReserveAsset[_reserveAsset];
    }

    function isValidKeeper(address _keeper) external view override returns (bool) {
        return keeperList[_keeper];
    }

    /**
     * Returns the percentages of a strategy Profit Sharing
     *
     * @return            Strategist, Stewards, Lps, creator bonus
     */
    function getProfitSharing()
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (strategistProfitPercentage, stewardsProfitPercentage, lpsProfitPercentage);
    }

    /**
     * Returns the percentages of BABL Profit Sharing
     *
     * @return            Strategist, Stewards, Lps, creator bonus
     */
    function getBABLSharing()
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (strategistBABLPercentage, stewardsBABLPercentage, lpsBABLPercentage, gardenCreatorBonus);
    }

    /**
     * Get the integration address associated with passed human readable name
     *
     * @param  _name         Human readable integration name
     *
     * @return               Address of integration
     */
    function getIntegrationByName(string memory _name) external view override returns (address) {
        return enabledIntegrations[_nameHash(_name)];
    }

    /**
     * Get integration integration address associated with passed hashed name
     *
     * @param  _nameHashP     Hash of human readable integration name
     *
     * @return               Address of integration
     */
    function getIntegrationWithHash(bytes32 _nameHashP) external view override returns (address) {
        return enabledIntegrations[_nameHashP];
    }

    /**
     * Check if integration name is valid
     *
     * @param  _name         Human readable string identifying the integration
     *
     * @return               Boolean indicating if valid
     */
    function isValidIntegration(string memory _name, address _integration) external view override returns (bool) {
        return enabledIntegrations[_nameHash(_name)] == _integration;
    }

    /**
     * Check if a contract address is a garden or one of the system contracts
     *
     * @param  _contractAddress           The contract address to check
     */
    function isSystemContract(address _contractAddress) external view override returns (bool) {
        return (isGarden[_contractAddress] ||
            gardenValuer == _contractAddress ||
            priceOracle == _contractAddress ||
            owner() == _contractAddress ||
            _contractAddress == address(this) ||
            _isOperation(_contractAddress) ||
            (isGarden[address(IStrategy(_contractAddress).garden())] &&
                IGarden(IStrategy(_contractAddress).garden()).isStrategy(_contractAddress)));
    }

    /* ============ Internal Only Function ============ */

    /**
     * Hashes the string and returns a bytes32 value
     */
    function _nameHash(string memory _name) private pure returns (bytes32) {
        return keccak256(bytes(_name));
    }

    function _isOperation(address _address) private view returns (bool) {
        for (uint8 i = 0; i < MAX_OPERATIONS; i++) {
            if (_address == enabledOperations[i]) {
                return true;
            }
        }
        return false;
    }
}
