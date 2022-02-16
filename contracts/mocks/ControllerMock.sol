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

import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IGardenFactory} from '../interfaces/IGardenFactory.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IIshtarGate} from '../interfaces/IIshtarGate.sol';
import {IIntegration} from '../interfaces/IIntegration.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IHypervisor} from '../interfaces/IHypervisor.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';

import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';

/**
 * @title BabController
 * @author Babylon Finance Protocol
 *
 * BabController is a smart contract used to deploy new gardens contracts and house the
 * integrations and resources of the system.
 */
contract ControllerMock {
    using AddressArrayUtils for address[];
    using Address for address;
    using AddressUpgradeable for address;
    using LowGasSafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ============ Events ============ */

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    // List of enabled Communities
    address[] public gardens;
    address[] public reserveAssets;
    address public override gardenValuer;
    address public override priceOracle;
    address public override gardenFactory;
    address public override rewardsDistributor;
    address public override ishtarGate;
    address public override strategyFactory;
    address public override gardenNFT;
    address public override strategyNFT;

    // Mapping of integration name => integration address
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

    // Enable garden creations to be fully open to the public (no need of Ishtar gate anymore)
    bool public override gardenCreationIsOpen;

    // Pause Guardian
    address public guardian;
    mapping(address => bool) public override guardianPaused;
    bool public override guardianGlobalPaused;
    address public override mardukGate;
    address public override heart;

    /* ============ Constants ============ */

    address public constant override EMERGENCY_OWNER = 0x0B892EbC6a4bF484CDDb7253c6BD5261490163b9;
    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 public constant BABL = IERC20(0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74);
    uint8 public constant MAX_OPERATIONS = 20;

    /* ============ Constructor ============ */

    /* ============ External Functions ============ */

    // ===========  Garden related Gov Functions ======

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
    ) external payable override returns (address) {}

    function removeGarden(address _garden) external override {}

    function enableGardenTokensTransfers() external override {}

    // ===========  Protocol related Gov Functions ======

    function addKeeper(address _keeper) external override {}

    function removeKeeper(address _keeper) external override {}

    function addKeepers(address[] memory _keepers) external override {}

    function addReserveAsset(address _reserveAsset) external override {}

    function removeReserveAsset(address _reserveAsset) external override {}

    function editMardukGate(address _mardukGate) external override {}

    function editRewardsDistributor(address _newRewardsDistributor) external override {}

    function editTreasury(address _newTreasury) external override {}

    function editHeart(address _newHeart) external override {}

    function editLiquidityReserve(address _reserve, uint256 _newMinLiquidityReserve) public override {}

    function editPriceOracle(address _priceOracle) external override {}

    function editGardenValuer(address _gardenValuer) external override {}

    function editGardenFactory(address _newGardenFactory) external override {}

    function editGardenNFT(address _newGardenNFT) external override {}

    function editStrategyNFT(address _newStrategyNFT) external override {}

    function editStrategyFactory(address _newStrategyFactory) external override {}

    function setMasterSwapper(address _newDefaultMasterSwapper) external override {}

    function setOperation(uint8 _kind, address _operation) public override {}

    function setPauseGuardian(address _guardian) external override {}

    function setGlobalPause(bool _state) external override returns (bool) {
        return true;
    }

    function setSomePause(address[] memory _address, bool _state) external override returns (bool) {
        return true;
    }

    /* ============ External Getter Functions ============ */

    function owner() public view override returns (address) {
        return address(0);
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

    function isPaused(address _contract) external view override returns (bool) {
        return guardianGlobalPaused || guardianPaused[_contract];
    }

    function isSystemContract(address _contractAddress) external view override returns (bool) {
        return true;
    }

    /* ============ Internal Only Function ============ */

    // Can receive ETH
    // solhint-disable-next-line
    receive() external payable {}
}
