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
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import {IRewardsDistributor} from './interfaces/IRewardsDistributor.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IGardenFactory} from './interfaces/IGardenFactory.sol';
import {IStrategy} from './interfaces/IStrategy.sol';
import {IIshtarGate} from './interfaces/IIshtarGate.sol';
import {IIntegration} from './interfaces/IIntegration.sol';
import {IBabController} from './interfaces/IBabController.sol';

import {AddressArrayUtils} from './lib/AddressArrayUtils.sol';
import {LowGasSafeMath} from './lib/LowGasSafeMath.sol';

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
    using LowGasSafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ============ Events ============ */
    event GardenAdded(address indexed _garden, address indexed _factory);
    event GardenRemoved(address indexed _garden);

    event ControllerIntegrationAdded(address _integration, string indexed _integrationName);
    event ControllerIntegrationRemoved(address _integration, string indexed _integrationName);
    event ControllerIntegrationEdited(address _newIntegration, string indexed _integrationName);
    event ControllerOperationSet(uint8 indexed _kind, address _address);
    event MasterSwapperChanged(address indexed _newTradeIntegration, address _oldTradeIntegration);

    event ReserveAssetAdded(address indexed _reserveAsset);
    event ReserveAssetRemoved(address indexed _reserveAsset);
    event LiquidityMinimumEdited(address indexed _resesrveAsset, uint256 _newMinLiquidityReserve);

    event PriceOracleChanged(address indexed _priceOracle, address _oldPriceOracle);
    event RewardsDistributorChanged(address indexed _rewardsDistributor, address _oldRewardsDistributor);
    event TreasuryChanged(address _newTreasury, address _oldTreasury);
    event IshtarGateChanged(address _newIshtarGate, address _oldIshtarGate);
    event MardukGateChanged(address _newMardukGate, address _oldMardukGate);
    event GardenValuerChanged(address indexed _gardenValuer, address _oldGardenValuer);
    event GardenFactoryChanged(address indexed _gardenFactory, address _oldGardenFactory);
    event UniswapFactoryChanged(address indexed _newUniswapFactory, address _oldUniswapFactory);
    event GardenNFTChanged(address indexed _newGardenNFT, address _oldStrategyNFT);
    event StrategyNFTChanged(address indexed _newStrategyNFT, address _oldStrategyNFT);

    event StrategyFactoryEdited(address indexed _strategyFactory, address _oldStrategyFactory);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address _oldPauseGuardian, address _newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string _action, bool _pauseState);

    /// @notice Emitted when an action is paused individually
    event ActionPausedIndividually(string _action, address _address, bool _pauseState);

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint8 public constant MAX_OPERATIONS = 20;

    // List of enabled Communities
    address[] public gardens;
    address[] public reserveAssets;
    address private uniswapFactory; // do not use
    address public override gardenValuer;
    address public override priceOracle;
    address public override gardenFactory;
    address public override rewardsDistributor;
    address public override ishtarGate;
    address public override strategyFactory;
    address public override gardenNFT;
    address public override strategyNFT;

    // Mapping of integration name => integration address
    mapping(bytes32 => address) private enabledIntegrations; // DEPRECATED
    // Address of the master swapper used by the protocol
    address public override masterSwapper;
    // Mapping of valid operations
    address[MAX_OPERATIONS] public override enabledOperations;

    // Mappings to check whether address is valid Garden or Reserve Asset
    mapping(address => bool) public override isGarden;
    mapping(address => bool) public validReserveAsset;

    // Mapping to check whitelisted assets
    mapping(address => bool) public assetWhitelist;

    // Mapping to check keepers
    mapping(address => bool) public keeperList;

    // Mapping of minimum liquidity per reserve asset
    mapping(address => uint256) public override minLiquidityPerReserve;

    // Recipient of protocol fees
    address public override treasury;

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

    // Enable Transfer of ERC20 gardenTokens
    // Only members can transfer tokens until the protocol is fully decentralized
    bool public override gardenTokensTransfersEnabled;

    // Enable and starts the BABL Mining program within Rewards Distributor contract
    bool public override bablMiningProgramEnabled;
    // Enable public gardens
    bool public override allowPublicGardens;

    uint256 public override protocolPerformanceFee; // 5% (0.01% = 1e14, 1% = 1e16) on profits
    uint256 public override protocolManagementFee; // 0.5% (0.01% = 1e14, 1% = 1e16)
    uint256 private protocolDepositGardenTokenFee; // 0 (0.01% = 1e14, 1% = 1e16)
    uint256 private protocolWithdrawalGardenTokenFee; // 0 (0.01% = 1e14, 1% = 1e16)

    // Maximum number of contributors per garden
    uint256 public override maxContributorsPerGarden;

    // Enable garden creations to be fully open to the public (no need of Ishtar gate anymore)
    bool public override gardenCreationIsOpen;

    // Pause Guardian
    address public guardian;
    mapping(address => bool) public override guardianPaused;
    bool public override guardianGlobalPaused;
    address public override mardukGate;

    uint256 private profitWeight;
    uint256 private principalWeight;

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
        strategistProfitPercentage = 10e16;
        stewardsProfitPercentage = 5e16;
        lpsProfitPercentage = 80e16;

        strategistBABLPercentage = 10e16;
        stewardsBABLPercentage = 10e16;
        lpsBABLPercentage = 80e16;
        profitWeight = 60e16;
        principalWeight = 40e16;

        gardenCreatorBonus = 15e16;
        maxContributorsPerGarden = 100;
        gardenCreationIsOpen = false;
    }

    /* ============ External Functions ============ */

    // ===========  Garden related Gov Functions ======
    /**
     * Creates a Garden smart contract and registers the Garden with the controller.
     *
     * If asset is not WETH, the creator needs to approve the controller
     * @param _reserveAsset                     Reserve asset of the Garden. Initially just weth
     * @param _name                             Name of the Garden
     * @param _symbol                           Symbol of the Garden
     * @param _gardenParams                     Array of numeric garden params
     * @param _tokenURI                         Garden NFT token URI
     * @param _seed                             Seed to regenerate the garden NFT
     * @param _initialContribution              Initial contribution by the gardener
     * @param _publicGardenStrategistsStewards  Public garden, public strategist rights and public stewards rights
     * @param _profitSharing                    Custom profit sharing (if any)
     */
    function createGarden(
        address _reserveAsset,
        string memory _name,
        string memory _symbol,
        string memory _tokenURI,
        uint256 _seed,
        uint256[] calldata _gardenParams,
        uint256 _initialContribution,
        bool[] memory _publicGardenStrategistsStewards,
        uint256[] memory _profitSharing
    ) external payable override returns (address) {
        require(masterSwapper != address(0), 'Need a default trade integration');
        require(enabledOperations.length > 0, 'Need operations enabled');
        require(
            IIshtarGate(mardukGate).canCreate(msg.sender) || gardenCreationIsOpen,
            'User does not have creation permissions'
        );
        address newGarden =
            IGardenFactory(gardenFactory).createGarden(
                _reserveAsset,
                msg.sender,
                _name,
                _symbol,
                _tokenURI,
                _seed,
                _gardenParams,
                _initialContribution,
                _publicGardenStrategistsStewards
            );
        if (_reserveAsset != WETH || msg.value == 0) {
            IERC20(_reserveAsset).safeTransferFrom(msg.sender, address(this), _initialContribution);
            IERC20(_reserveAsset).safeApprove(newGarden, _initialContribution);
        }
        require(!isGarden[newGarden], 'Garden already exists');
        isGarden[newGarden] = true;
        gardens.push(newGarden);
        IGarden(newGarden).deposit{value: msg.value}(_initialContribution, _initialContribution, msg.sender, true);
        // Avoid gas cost if default sharing values are provided (0,0,0)
        if (_profitSharing[0] != 0 || _profitSharing[1] != 0 || _profitSharing[2] != 0) {
            IRewardsDistributor(rewardsDistributor).setProfitRewards(
                newGarden,
                _profitSharing[0],
                _profitSharing[1],
                _profitSharing[2]
            );
        }
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
        require(IGarden(_garden).getStrategies().length == 0, 'Garden has active strategies!');
        gardens = gardens.remove(_garden);
        delete isGarden[_garden];

        emit GardenRemoved(_garden);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to enable public creation of gardens
     *
     */
    function openPublicGardenCreation() external override onlyOwner {
        require(!gardenCreationIsOpen, 'Garden creation is already open to the public');
        gardenCreationIsOpen = true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows transfers of ERC20 gardenTokens
     * Can only happen after 2021 is finished.
     */
    function enableGardenTokensTransfers() external override onlyOwner {
        require(block.timestamp > 1641024000, 'Transfers cannot be enabled yet');
        gardenTokensTransfersEnabled = true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows public gardens
     */
    function setAllowPublicGardens() external override onlyOwner {
        allowPublicGardens = true;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Change the max number of contributors for new Gardens since the change
     */
    function setMaxContributorsPerGarden(uint256 _newMax) external override onlyOwner {
        require(_newMax >= 1, 'Contributors cannot be less than 1 per garden');
        maxContributorsPerGarden = _newMax;
    }

    // ===========  Protocol related Gov Functions ======

    /**  PRIVILEGED GOVERNANCE FUNCTION. Enable and starts the BABL Mining program by the Rewards Distributor
     * Can only happen after public launch of the protocol.
     */
    function enableBABLMiningProgram() external override onlyOwner {
        if (bablMiningProgramEnabled == false) {
            // Can only be activated once
            bablMiningProgramEnabled = true;
            IRewardsDistributor(rewardsDistributor).startBABLRewards(); // Sets the timestamp
        }
    }

    /**  PRIVILEGED GOVERNANCE FUNCTION. Set new % share between participants for BABL mining program
     */
    function setBABLMiningParameters(
        uint256 _newStrategistBABLPercentage,
        uint256 _newStewardsBABLPercentage,
        uint256 _newLpsBABLPercentage,
        uint256 _newGardenCreatorBonus,
        uint256 _profitWeight,
        uint256 _principalWeight
    ) external override onlyOwner {
        require(
            _newStrategistBABLPercentage.add(_newStewardsBABLPercentage).add(_newLpsBABLPercentage) == 1e18 &&
                _newGardenCreatorBonus <= 1e18,
            'new sharing % does not match'
        );
        require(_profitWeight.add(_principalWeight) == 1e18, 'principal and profit weigth do not match');
        strategistBABLPercentage = _newStrategistBABLPercentage;
        stewardsBABLPercentage = _newStewardsBABLPercentage;
        lpsBABLPercentage = _newLpsBABLPercentage;
        gardenCreatorBonus = _newGardenCreatorBonus;
        profitWeight = _profitWeight;
        principalWeight = _principalWeight;
        IRewardsDistributor(rewardsDistributor).setBABLRewards(
            _newStrategistBABLPercentage,
            _newStewardsBABLPercentage,
            _newLpsBABLPercentage,
            _newGardenCreatorBonus,
            _profitWeight,
            _principalWeight
        ); // Sets the new % share at Rewards Distributor
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
        // TODO: check decimals reserve asset
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
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the Marduk Gate Address
     *
     * @param _mardukGate               Address of the new Marduk Gate
     */
    function editMardukGate(address _mardukGate) external override onlyOwner {
        require(_mardukGate != mardukGate, 'Marduk Gate already exists');

        require(_mardukGate != address(0), 'Marduk Gate oracle must exist');

        address oldMardukGate = mardukGate;
        mardukGate = _mardukGate;

        emit MardukGateChanged(_mardukGate, oldMardukGate);
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
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit the protocol garden NFT
     *
     * @param _newGardenNFT      Address of the new garden NFT
     */
    function editGardenNFT(address _newGardenNFT) external override onlyOwner {
        require(_newGardenNFT != address(0), 'Address must not be 0');

        address oldGardenNFT = gardenNFT;
        gardenNFT = _newGardenNFT;

        emit GardenNFTChanged(_newGardenNFT, oldGardenNFT);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit the protocol strategy NFT
     *
     * @param _newStrategyNFT      Address of the new strategy NFT
     */
    function editStrategyNFT(address _newStrategyNFT) external override onlyOwner {
        require(_newStrategyNFT != address(0), 'Address must not be 0');

        address oldStrategyNFT = strategyNFT;
        strategyNFT = _newStrategyNFT;

        emit StrategyNFTChanged(_newStrategyNFT, oldStrategyNFT);
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
     * @param _newDefaultMasterSwapper     Address of the new default trade integration
     */
    function setMasterSwapper(address _newDefaultMasterSwapper) external override onlyOwner {
        require(_newDefaultMasterSwapper != address(0), 'Address must not be 0');
        require(_newDefaultMasterSwapper != masterSwapper, 'Address must be different');
        address oldMasterSwapper = masterSwapper;
        masterSwapper = _newDefaultMasterSwapper;

        emit MasterSwapperChanged(_newDefaultMasterSwapper, oldMasterSwapper);
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
     * @param  _reserve                         Address of the reserve to edit
     * @param  _newMinLiquidityReserve          Absolute min liquidity of an asset to grab price
     */
    function editLiquidityReserve(address _reserve, uint256 _newMinLiquidityReserve) public override onlyOwner {
        require(_newMinLiquidityReserve > 0, '_minRiskyPairLiquidityEth > 0');
        require(validReserveAsset[_reserve], 'Needs to be a valid reserve');
        minLiquidityPerReserve[_reserve] = _newMinLiquidityReserve;

        emit LiquidityMinimumEdited(_reserve, _newMinLiquidityReserve);
    }

    // ===========  Protocol security related Gov Functions ======

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Set-up a pause guardian
     * @param _guardian               Address of the guardian
     */
    function setPauseGuardian(address _guardian) external override {
        require(
            msg.sender == guardian || msg.sender == owner(),
            'only pause guardian and owner can update pause guardian'
        );
        require(msg.sender == owner() || _guardian != address(0), 'Guardian cannot remove himself');
        // Save current value for inclusion in log
        address oldPauseGuardian = guardian;
        // Store pauseGuardian with value newPauseGuardian
        guardian = _guardian;
        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, _guardian);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Pause the protocol globally in case of unexpected issue
     * Only the governance can unpause it
     * @param _state               True to pause, false to unpause.
     */
    function setGlobalPause(bool _state) external override returns (bool) {
        require(msg.sender == guardian || msg.sender == owner(), 'only pause guardian and owner can pause globally');
        require(msg.sender == owner() || _state == true, 'only admin can unpause');

        guardianGlobalPaused = _state;
        emit ActionPaused('Guardian global pause', _state);
        return _state;
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Pause some smartcontracts in a batch process in case of unexpected issue
     * Only the governance can unpause it
     * @param _address             Addresses of protocol smartcontract to be paused
     * @param _state               Boolean pause state
     */
    function setSomePause(address[] memory _address, bool _state) external override returns (bool) {
        require(
            msg.sender == guardian || msg.sender == owner(),
            'only pause guardian and owner can pause individually'
        );
        require(msg.sender == owner() || _state == true, 'only admin can unpause');
        for (uint256 i = 0; i < _address.length; i++) {
            guardianPaused[_address[i]] = _state;
            emit ActionPausedIndividually('Guardian individual pause', _address[i], _state);
        }
        return _state;
    }

    /* ============ External Getter Functions ============ */

    function owner() public view override(IBabController, OwnableUpgradeable) returns (address) {
        return OwnableUpgradeable.owner();
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

    function isValidReserveAsset(address _reserveAsset) external view override returns (bool) {
        return validReserveAsset[_reserveAsset];
    }

    function isValidKeeper(address _keeper) external view override returns (bool) {
        return keeperList[_keeper];
    }

    /**
     * Check whether or not there is a global pause or a specific pause of the provided contract address
     * @param _contract               Smartcontract address to check for a global or specific pause
     */
    function isPaused(address _contract) external view override returns (bool) {
        return guardianGlobalPaused || guardianPaused[_contract];
    }

    /**
     * Check whether or not the strategies are beta protocol strategies deserving rewards
     * @param _strategies              Smartcontract address to check for a global or specific pause
     */
    function isBetaStrategy(address[] memory _strategies)
        external
        view
        override
        returns (bool[] memory, uint256[] memory)
    {
        uint256[] memory capitalAllocated = new uint256[](_strategies.length);
        bool[] memory isABetaStrategy = new bool[](_strategies.length);
        uint256 startTime = IRewardsDistributor(rewardsDistributor).START_TIME();
        for (uint256 i = 0; i < _strategies.length; i++) {
            require(_strategies[i] != address(0), 'not a valid address');
            address garden = address(IStrategy(_strategies[i]).garden());
            // Only protocol strategies security cross-check
            require(isGarden[garden] && IGarden(garden).isGardenStrategy(_strategies[i]), 'not a protocol strategy');
            // ts[0]: executedAt, ts[1]: updatedAt
            // isStrategyActive implies exitedAt == 0 (not finished yet)
            uint256[] memory ts = new uint256[](2);
            (, , , , ts[0], , ts[1]) = IStrategy(_strategies[i]).getStrategyState();
            isABetaStrategy[i] =
                ts[0] < startTime &&
                ts[1] < startTime &&
                IStrategy(_strategies[i]).isStrategyActive() &&
                startTime != 0;
            capitalAllocated[i] = IStrategy(_strategies[i]).capitalAllocated();
        }
        return (isABetaStrategy, capitalAllocated);
    }

    function getLiveStrategies(uint256 _size) external view override returns (address[] memory) {
        uint256 pid;
        address[] memory liveStrategies = new address[](_size);
        // Get all protocol gardens at initialization of mining program
        for (uint256 i = 0; i < gardens.length; i++) {
            // get all strategies at each garden and check whether or not are active strategies
            address[] memory strategies = IGarden(gardens[i]).getStrategies();
            if (strategies.length == 0) {
                continue;
            }
            for (uint256 j = 0; j < strategies.length; j++) {
                if (IStrategy(strategies[j]).isStrategyActive()) {
                    // We pre-select eligible strategies to call rewards distributor
                    liveStrategies[pid] = address(strategies[j]);
                    pid++;
                }
                if (pid == _size) break;
            }
            if (pid == _size) break;
        }
        return liveStrategies;
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
    function getBABLMiningParameters()
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            strategistBABLPercentage,
            stewardsBABLPercentage,
            lpsBABLPercentage,
            gardenCreatorBonus,
            profitWeight,
            principalWeight
        );
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
            gardenFactory == _contractAddress ||
            masterSwapper == _contractAddress ||
            strategyFactory == _contractAddress ||
            rewardsDistributor == _contractAddress ||
            owner() == _contractAddress ||
            _contractAddress == address(this) ||
            _isOperation(_contractAddress) ||
            (isGarden[address(IStrategy(_contractAddress).garden())] &&
                IGarden(IStrategy(_contractAddress).garden()).strategyMapping(_contractAddress)) ||
            (isGarden[address(IStrategy(_contractAddress).garden())] &&
                IGarden(IStrategy(_contractAddress).garden()).isGardenStrategy(_contractAddress)));
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

contract BabControllerV6 is BabController {}
