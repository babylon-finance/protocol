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

pragma solidity 0.7.4;

import 'hardhat/console.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IRollingGarden} from './interfaces/IRollingGarden.sol';
import {IGardenFactory} from './interfaces/IGardenFactory.sol';
import {IIntegration} from './interfaces/IIntegration.sol';
import {AddressArrayUtils} from './lib/AddressArrayUtils.sol';

/**
 * @title BabController
 * @author Babylon Finance Protocol
 *
 * BabController is a smart contract used to deploy new gardens contracts and house the
 * integrations and resources of the system.
 */
contract BabController is Ownable {
    using AddressArrayUtils for address[];
    using SafeMath for uint256;
    using Address for address;

    /* ============ Events ============ */
    event GardenAdded(address indexed _garden, address indexed _factory);
    event GardenRemoved(address indexed _garden);

    event ControllerIntegrationAdded(address _integration, string indexed _integrationName);
    event ControllerIntegrationRemoved(address _integration, string indexed _integrationName);
    event ControllerIntegrationEdited(address _newIntegration, string indexed _integrationName);

    event ReserveAssetAdded(address indexed _reserveAsset);
    event ReserveAssetRemoved(address indexed _reserveAsset);

    event LiquidityMinimumEdited(uint256 _minRiskyPairLiquidityEth);

    event ModuleAdded(address indexed _module);
    event ModuleRemoved(address indexed _module);

    event PriceOracleChanged(address indexed _priceOracle, address _oldPriceOracle);
    event RewardsDistributorChanged(address indexed _rewardsDistributor, address _oldRewardsDistributor);
    event ReservePoolChanged(address indexed _reservePool, address _oldReservePool);
    event TreasuryChanged(address _newTreasury, address _oldTreasury);
    event GardenValuerChanged(address indexed _gardenValuer, address _oldGardenValuer);
    event GardenFactoryChanged(address indexed _gardenFactory, address _oldGardenFactory);
    event StrategyFactoryEdited(
        uint8 indexed _strategyKind,
        address indexed _strategyFactory,
        address _oldStrategyFactory
    );

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    address public constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    // List of enabled Communities
    address[] public gardens;
    address[] public reserveAssets;
    address public gardenValuer;
    address public priceOracle;
    address public reservePool;
    address public gardenFactory;
    address public rewardsDistributor;
    mapping(uint8 => address) public strategyFactory;
    // Mapping of garden => integration identifier => integration address
    mapping(bytes32 => address) private integrations;

    // Mappings to check whether address is valid Garden or Reserve Asset
    mapping(address => bool) public isGarden;
    mapping(address => bool) public validReserveAsset;

    // Mapping to check whitelisted assets
    mapping(address => bool) public assetWhitelist;

    // Mapping to check keepers
    mapping(address => bool) public keeperList;

    // Recipient of protocol fees
    address public treasury;

    // Idea cooldown period
    uint256 public minCooldownPeriod = 6 hours;
    uint256 public maxCooldownPeriod = 7 days;

    // Assets
    uint256 public minRiskyPairLiquidityEth = 1000 * 1e18; // Absolute Min liquidity of assets for risky gardens 1000 ETH

    // Enable Transfer of ERC20 gardenTokens
    bool public gardenTokensTransfersEnabled = false; // Only members can transfer tokens until the protocol is fully decentralized

    uint256 public protocolPerformanceFee = 5e16; // 5% (0.01% = 1e14, 1% = 1e16) on profits
    uint256 public protocolManagementFee = 5e15; // 0.5% (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolGardenCreationFee = 0; // (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolDepositGardenTokenFee = 0; // (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolWithdrawalGardenTokenFee = 0; // (0.01% = 1e14, 1% = 1e16)

    /* ============ Functions ============ */

    /**
     * Initializes the initial fee recipient on deployment.
     *
     * @param _treasury                     Address of the initial protocol fee recipient
     * @param _gardenValuer                 Address of the initial gardenValuer
     * @param _priceOracle                  Address of the initial priceOracle
     * @param _reservePool                  Address of the initial reservePool
     * @param _gardenFactory                Address of the initial garden factory
     * @param _rewardsDistributor           Address of the initial garden factory
     */
    constructor(
        address _treasury,
        address _gardenValuer,
        address _priceOracle,
        address _reservePool,
        address _gardenFactory,
        address _rewardsDistributor
    ) {
        treasury = _treasury;
        gardenValuer = _gardenValuer;
        priceOracle = _priceOracle;
        reservePool = _reservePool;
        gardenFactory = _gardenFactory;
        rewardsDistributor = _rewardsDistributor;
    }

    /* ============ External Functions ============ */

    // ===========  Garden related Gov Functions ======
    /**
     * Creates a Garden smart contract and registers the Garden with the controller.
     *
     * @param _integrations           List of integrations to enable. All integrations must be approved by the Controller
     * @param _weth                   Address of the WETH ERC20
     * @param _name                   Name of the Garden
     * @param _symbol                 Symbol of the Garden
     */
    function createRollingGarden(
        address[] memory _integrations,
        address _weth,
        string memory _name,
        string memory _symbol
    ) external returns (address) {
        require(_integrations.length > 0, 'Garden requires at least one integration');
        for (uint256 i = 0; i < _integrations.length; i++) {
            require(_integrations[i] != address(0), 'Integration must not be null address');
        }
        address newGarden =
            IGardenFactory(gardenFactory).createRollingGarden(
                _integrations,
                _weth,
                address(this),
                msg.sender,
                _name,
                _symbol
            );
        _addGarden(newGarden);
        return newGarden;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to remove a Garden
     *
     * @param _garden               Address of the Garden contract to remove
     */
    function removeGarden(address _garden) external onlyOwner {
        require(isGarden[_garden], 'Garden does not exist');
        require(!IGarden(_garden).active(), 'The garden needs to be disabled.');
        gardens = gardens.remove(_garden);

        isGarden[_garden] = false;

        emit GardenRemoved(_garden);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to disable a garden
     *
     * @param _garden               Address of the garden
     */
    function disableGarden(address _garden) external onlyOwner {
        require(isGarden[_garden], 'Garden does not exist');
        IGarden garden = IGarden(_garden);
        require(!!garden.active(), 'The garden needs to be active.');
        garden.setDisabled();
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
        garden.setActive();
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows transfers of ERC20 gardenTokens
     * Can only happen after 2021 is finished.
     */
    function enableGardenTokensTransfers() external onlyOwner {
        require(block.timestamp > 1641024000000, 'Transfers cannot be enabled yet'); // TODO: Check timestamp. January 1 2022
        gardenTokensTransfersEnabled = true;
    }

    // ===========  Protocol related Gov Functions ======

    /**
     * PRIVILEGED FACTORY FUNCTION. Adds a new valid keeper to the list
     *
     * @param _keeper Address of the keeper
     */
    function addKeeper(address _keeper) external onlyOwner {
        keeperList[_keeper] = true;
    }

    /**
     * PRIVILEGED FACTORY FUNCTION. Removes a keeper
     *
     * @param _keeper Address of the keeper
     */
    function removeKeeper(address _keeper) external onlyOwner {
        require(keeperList[_keeper], 'Keeper is whitelisted');
        keeperList[_keeper] = false;
    }

    /**
     * PRIVILEGED FACTORY FUNCTION. Adds a list of assets to the whitelist
     *
     * @param _keepers List with keeprs of the assets to whitelist
     */
    function addKeepers(address[] memory _keepers) external onlyOwner {
        for (uint256 i = 0; i < _keepers.length; i++) {
            keeperList[_keepers[i]] = true;
        }
    }

    /**
     * PRIVILEGED FACTORY FUNCTION. Adds a new valid reserve asset for gardens
     *
     * @param _reserveAsset Address of the reserve assset
     */
    function addReserveAsset(address _reserveAsset) external onlyOwner {
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
    function removeReserveAsset(address _reserveAsset) external onlyOwner {
        require(validReserveAsset[_reserveAsset], 'Reserve asset does not exist');

        reserveAssets = reserveAssets.remove(_reserveAsset);

        validReserveAsset[_reserveAsset] = false;

        emit ReserveAssetRemoved(_reserveAsset);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the price oracle
     *
     * @param _priceOracle               Address of the new price oracle
     */
    function editPriceOracle(address _priceOracle) external onlyOwner {
        require(_priceOracle != priceOracle, 'Price oracle already exists');

        require(_priceOracle != address(0), 'Price oracle must exist');

        address oldPriceOracle = priceOracle;
        priceOracle = _priceOracle;

        emit PriceOracleChanged(_priceOracle, oldPriceOracle);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the reserve pool
     *
     * @param _reservePool               Address of the new reserve pool
     */
    function editReservePool(address _reservePool) external onlyOwner {
        require(_reservePool != reservePool, 'Reserve Pool already exists');

        require(_reservePool != address(0), 'Reserve pool must exist');

        address oldReservePool = reservePool;
        reservePool = _reservePool;

        emit ReservePoolChanged(_reservePool, oldReservePool);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the integration registry
     *
     * @param _gardenValuer Address of the new price oracle
     */
    function editGardenValuer(address _gardenValuer) external onlyOwner {
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
    function editTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), 'Address must not be 0');

        address oldTreasury = treasury;
        treasury = _newTreasury;

        emit TreasuryChanged(_newTreasury, oldTreasury);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit the protocol fee recipient
     *
     * @param _newRewardsDistributor      Address of the new protocol fee recipient
     */
    function editRewardsDistributor(address _newRewardsDistributor) external onlyOwner {
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
    function editGardenFactory(address _newGardenFactory) external onlyOwner {
        require(_newGardenFactory != address(0), 'Address must not be 0');

        address oldGardenFactory = gardenFactory;
        gardenFactory = _newGardenFactory;

        emit GardenFactoryChanged(_newGardenFactory, oldGardenFactory);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit the protocol strategy factory
     *
     * @param _strategyKind            Type of the strategy
     * @param _newStrategyFactory      Address of the new strategy factory
     */
    function editStrategyFactory(uint8 _strategyKind, address _newStrategyFactory) external onlyOwner {
        require(_newStrategyFactory != address(0), 'Address must not be 0');

        address oldStrategyFactory = strategyFactory[_strategyKind];
        strategyFactory[_strategyKind] = _newStrategyFactory;

        emit StrategyFactoryEdited(_strategyKind, _newStrategyFactory, oldStrategyFactory);
    }

    /**
     * GOVERNANCE FUNCTION: Add a new integration to the registry
     *
     * @param  _name             Human readable string identifying the integration
     * @param  _integration      Address of the integration contract to add
     */
    function addIntegration(string memory _name, address _integration) public onlyOwner {
        bytes32 hashedName = _nameHash(_name);
        require(integrations[hashedName] == address(0), 'Integration exists already.');
        require(_integration != address(0), 'Integration address must exist.');

        integrations[hashedName] = _integration;

        emit ControllerIntegrationAdded(_integration, _name);
    }

    /**
     * GOVERNANCE FUNCTION: Edit an existing integration on the registry
     *
     * @param  _name         Human readable string identifying the integration
     * @param  _integration      Address of the integration contract to edit
     */
    function editIntegration(string memory _name, address _integration) public onlyOwner {
        bytes32 hashedName = _nameHash(_name);

        require(integrations[hashedName] != address(0), 'Integration does not exist.');
        require(_integration != address(0), 'Integration address must exist.');

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
        require(integrations[hashedName] != address(0), 'Integration does not exist.');

        address oldIntegration = integrations[hashedName];
        delete integrations[hashedName];

        emit ControllerIntegrationRemoved(oldIntegration, _name);
    }

    /**
     * GOVERNANCE FUNCTION: Edit
     *
     * @param  _minRiskyPairLiquidityEth       Absolute min liquidity of an asset to grab price
     */
    function editLiquidityMinimum(uint256 _minRiskyPairLiquidityEth) public onlyOwner {
        require(_minRiskyPairLiquidityEth > 0);
        minRiskyPairLiquidityEth = _minRiskyPairLiquidityEth;

        emit LiquidityMinimumEdited(_minRiskyPairLiquidityEth);
    }

    /* ============ External Getter Functions ============ */

    function getUniswapFactory() external pure returns (address) {
        return UNISWAP_FACTORY;
    }

    function getPriceOracle() external view returns (address) {
        return priceOracle;
    }

    function getReservePool() external view returns (address) {
        return reservePool;
    }

    function getGardenValuer() external view returns (address) {
        return gardenValuer;
    }

    function getGardenFactory() external view returns (address) {
        return gardenFactory;
    }

    function getStrategyFactory(uint8 _strategyKind) external view returns (address) {
        return strategyFactory[_strategyKind];
    }

    function getGardens() external view returns (address[] memory) {
        return gardens;
    }

    function getReserveAssets() external view returns (address[] memory) {
        return reserveAssets;
    }

    function getMinCooldownPeriod() external view returns (uint256) {
        return minCooldownPeriod;
    }

    function getMaxCooldownPeriod() external view returns (uint256) {
        return maxCooldownPeriod;
    }

    function getProtocolDepositGardenTokenFee() external view returns (uint256) {
        return protocolDepositGardenTokenFee;
    }

    function getProtocolPerformanceFee() external view returns (uint256) {
        return protocolPerformanceFee;
    }

    function getProtocolManagementFee() external view returns (uint256) {
        return protocolManagementFee;
    }

    function getProtocolWithdrawalGardenTokenFee() external view returns (uint256) {
        return protocolWithdrawalGardenTokenFee;
    }

    function getRewardsDistributor() external view returns (address) {
        return rewardsDistributor;
    }
    
    function getTreasury() external view returns (address) {
        return treasury;
    }

    function isValidReserveAsset(address _reserveAsset) external view returns (bool) {
        return validReserveAsset[_reserveAsset];
    }

    function isValidKeeper(address _keeper) external view returns (bool) {
        return keeperList[_keeper];
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
     * Get integration integration address associated with passed human readable name
     *
     * hparam  _integration         Address of the integration
     *
     * @return                  Integration fee
     */
    function getIntegrationFee(
        address /* _integration */
    ) external pure returns (uint256) {
        return 0;
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
    function isValidIntegration(string memory _name, address _integration) external view returns (bool) {
        return integrations[_nameHash(_name)] == _integration;
    }

    /**
     * Check if a contract address is a garden or one of the system contracts
     *
     * @param  _contractAddress           The contract address to check
     */
    function isSystemContract(address _contractAddress) external view returns (bool) {
        return (isGarden[_contractAddress] ||
            gardenValuer == _contractAddress ||
            priceOracle == _contractAddress ||
            reservePool == _contractAddress ||
            _contractAddress == address(this));
    }

    /* ============ Internal Only Function ============ */

    /**
     * Hashes the string and returns a bytes32 value
     */
    function _nameHash(string memory _name) internal pure returns (bytes32) {
        return keccak256(bytes(_name));
    }

    /**
     * PRIVILEGED FACTORY FUNCTION. Adds a newly deployed Garden as an enabled Garden.
     *
     * @param _garden Address of the Garden contract to add
     */
    function _addGarden(address _garden) internal {
        require(!isGarden[_garden], 'Garden already exists');
        isGarden[_garden] = true;
        gardens.push(_garden);
        emit GardenAdded(_garden, msg.sender);
    }
}
