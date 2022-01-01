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

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import {IRewardsDistributor} from './interfaces/IRewardsDistributor.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IGardenFactory} from './interfaces/IGardenFactory.sol';
import {IStrategy} from './interfaces/IStrategy.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {IIshtarGate} from './interfaces/IIshtarGate.sol';
import {IIntegration} from './interfaces/IIntegration.sol';
import {IBabController} from './interfaces/IBabController.sol';
import {IHypervisor} from './interfaces/IHypervisor.sol';
import {IWETH} from './interfaces/external/weth/IWETH.sol';

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
    using Address for address;
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

    modifier onlyGovernanceOrEmergency {
        require(msg.sender == owner() || msg.sender == EMERGENCY_OWNER, 'Not enough privileges');
        _;
    }

    /* ============ State Variables ============ */

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
    uint256 private strategistProfitPercentage; // DEPRECATED
    uint256 private stewardsProfitPercentage; // DEPRECATED
    uint256 private lpsProfitPercentage; // DEPRECATED

    // Strategy BABL Rewards Sharing
    uint256 private strategistBABLPercentage; // DEPRECATED
    uint256 private stewardsBABLPercentage; // DEPRECATED
    uint256 private lpsBABLPercentage; // DEPRECATED

    uint256 private gardenCreatorBonus; // DEPRECATED

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
    uint256 private maxContributorsPerGarden; // DEPRECATED

    // Enable garden creations to be fully open to the public (no need of Ishtar gate anymore)
    bool public override gardenCreationIsOpen;

    // Pause Guardian
    address public guardian;
    mapping(address => bool) public override guardianPaused;
    bool public override guardianGlobalPaused;
    address public override mardukGate;

    /* ============ Constants ============ */

    address public constant override EMERGENCY_OWNER = 0x0B892EbC6a4bF484CDDb7253c6BD5261490163b9;
    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 public constant BABL = IERC20(0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74);
    uint8 public constant MAX_OPERATIONS = 20;

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

        maxContributorsPerGarden = 100;
        gardenCreationIsOpen = false;
        allowPublicGardens = true;
        bablMiningProgramEnabled = true;
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
            mardukGate != address(0) &&
                gardenNFT != address(0) &&
                strategyFactory != address(0) &&
                gardenValuer != address(0) &&
                treasury != address(0),
            'Parameters not initialized'
        );
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
        if (_reserveAsset != address(WETH) || msg.value == 0) {
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
     * PRIVILEGED GOVERNANCE FUNCTION. Allows transfers of ERC20 gardenTokens
     * Can only happen after 2021 is finished.
     */
    function enableGardenTokensTransfers() external override onlyOwner {
        require(block.timestamp > 1641024000, 'Transfers cannot be enabled yet');
        gardenTokensTransfersEnabled = true;
    }

    // ===========  Protocol related Gov Functions ======

    /**
     * PRIVILEGED FACTORY FUNCTION. Adds a new valid keeper to the list
     *
     * @param _keeper Address of the keeper
     */
    function addKeeper(address _keeper) external override onlyOwner {
        require(!keeperList[_keeper] && _keeper != address(0), 'Incorrect address');
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
        require(_reserveAsset != address(0) && ERC20(_reserveAsset).decimals() <= 18, 'Incorrect address');
        require(!validReserveAsset[_reserveAsset], 'Reserve asset already added');
        validReserveAsset[_reserveAsset] = true;
        reserveAssets.push(_reserveAsset);
        if (priceOracle != address(0)) {
          IPriceOracle(priceOracle).updateReserves();
        }
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
        if (priceOracle != address(0)) {
          IPriceOracle(priceOracle).updateReserves();
        }
        emit ReserveAssetRemoved(_reserveAsset);
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

    function editRewardsDistributor(address _newRewardsDistributor) external override onlyOwner {
        require(_newRewardsDistributor != address(0), 'Address must not be 0');

        address oldRewardsDistributor = rewardsDistributor;
        rewardsDistributor = _newRewardsDistributor;

        emit RewardsDistributorChanged(_newRewardsDistributor, oldRewardsDistributor);
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

    // Setter that can be changed by the team in case of an emergency

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the price oracle
     *
     * @param _priceOracle               Address of the new price oracle
     */
    function editPriceOracle(address _priceOracle) external override onlyGovernanceOrEmergency {
        require(_priceOracle != priceOracle, 'Price oracle already exists');

        require(_priceOracle != address(0), 'Price oracle must exist');

        address oldPriceOracle = priceOracle;
        priceOracle = _priceOracle;

        emit PriceOracleChanged(_priceOracle, oldPriceOracle);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to change the garden valuer
     *
     * @param _gardenValuer Address of the new garden valuer
     */
    function editGardenValuer(address _gardenValuer) external override onlyGovernanceOrEmergency {
        require(_gardenValuer != gardenValuer, 'Garden Valuer already exists');

        require(_gardenValuer != address(0), 'Garden Valuer must exist');

        address oldGardenValuer = gardenValuer;
        gardenValuer = _gardenValuer;

        emit GardenValuerChanged(_gardenValuer, oldGardenValuer);
    }

    /**
     * PRIVILEGED GOVERNANCE FUNCTION. Allows governance to edit the protocol garden factory
     *
     * @param _newGardenFactory      Address of the new garden factory
     */
    function editGardenFactory(address _newGardenFactory) external override onlyGovernanceOrEmergency {
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
    function editGardenNFT(address _newGardenNFT) external override onlyGovernanceOrEmergency {
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
    function editStrategyNFT(address _newStrategyNFT) external override onlyGovernanceOrEmergency {
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
    function editStrategyFactory(address _newStrategyFactory) external override onlyGovernanceOrEmergency {
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
    function setMasterSwapper(address _newDefaultMasterSwapper) external override onlyGovernanceOrEmergency {
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
    function setOperation(uint8 _kind, address _operation) public override onlyGovernanceOrEmergency {
        require(_kind < MAX_OPERATIONS, 'Max operations reached');
        require(enabledOperations[_kind] != _operation, 'Operation already set');
        require(_operation != address(0), 'Operation address must exist.');
        enabledOperations[_kind] = _operation;

        emit ControllerOperationSet(_kind, _operation);
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

    function getReserveAssets() external view override returns (address[] memory) {
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
     * Check if a contract address is a garden or one of the system contracts
     *
     * @param  _contractAddress           The contract address to check
     */
    function isSystemContract(address _contractAddress) external view override returns (bool) {
        if (_contractAddress == address(0)) {
            return false;
        }
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

    // Can receive ETH
    // solhint-disable-next-line
    receive() external payable {}
}

contract BabControllerV11 is BabController {}
