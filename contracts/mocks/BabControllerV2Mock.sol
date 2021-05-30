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
import {IGarden} from '../interfaces/IGarden.sol';
import {IGardenFactory} from '../interfaces/IGardenFactory.sol';
import {IIntegration} from '../interfaces/IIntegration.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';

/**
 * @title BabController
 * @author Babylon Finance Protocol
 *
 * BabController is a smart contract used to deploy new gardens contracts and house the
 * integrations and resources of the system.
 */
contract BabControllerV2Mock is OwnableUpgradeable {
    using AddressArrayUtils for address[];
    using AddressUpgradeable for address;
    using SafeMath for uint256;

    /* ============ Events ============ */
    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint8 public constant MAX_OPERATIONS = 20;

    // List of enabled Communities
    address[] public gardens;
    address[] public reserveAssets;
    address public uniswapFactory;
    address public gardenValuer;
    address public priceOracle;
    address public gardenFactory;
    address public rewardsDistributor;
    address public ishtarGate;
    address public strategyFactory;
    address public gardenNFT;
    address public strategyNFT;

    // Mapping of integration name => integration address
    mapping(bytes32 => address) private enabledIntegrations;
    // Address of the default trade integration used by the protocol
    address public defaultTradeIntegration;
    // Mapping of valid operations
    address[MAX_OPERATIONS] public enabledOperations;

    // Mappings to check whether address is valid Garden or Reserve Asset
    mapping(address => bool) public isGarden;
    mapping(address => bool) public validReserveAsset;

    // Mapping to check whitelisted assets
    mapping(address => bool) public assetWhitelist;

    // Mapping to check keepers
    mapping(address => bool) public keeperList;

    // Mapping of minimum liquidity per reserve asset
    mapping(address => uint256) public minLiquidityPerReserve;

    // Recipient of protocol fees
    address public treasury;

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

    // Enable Transfer of ERC20 gardenTokens
    // Only members can transfer tokens until the protocol is fully decentralized
    bool public gardenTokensTransfersEnabled;

    // Enable and starts the BABL Mining program within Rewards Distributor contract
    bool public bablMiningProgramEnabled;
    // Enable public gardens
    bool public allowPublicGardens;

    uint256 public protocolPerformanceFee; // 5% (0.01% = 1e14, 1% = 1e16) on profits
    uint256 public protocolManagementFee; // 0.5% (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolDepositGardenTokenFee; // 0 (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolWithdrawalGardenTokenFee; // 0 (0.01% = 1e14, 1% = 1e16)

    // Maximum number of contributors per garden
    uint256 public maxContributorsPerGarden;

    // Enable garden creations to be fully open to the public (no need of Ishtar gate anymore)
    bool public gardenCreationIsOpen;

    // Pause Guardian
    address public guardian;
    mapping(address => bool) public guardianPaused;
    bool public guardianGlobalPaused;

    bool public newVar;

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
        guardianGlobalPaused = false;

        uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

        strategistProfitPercentage = 10e16;
        stewardsProfitPercentage = 5e16;
        lpsProfitPercentage = 80e16;

        strategistBABLPercentage = 8e16;
        stewardsBABLPercentage = 17e16;
        lpsBABLPercentage = 75e16;

        gardenCreatorBonus = 15e16;
        maxContributorsPerGarden = 100;
        gardenCreationIsOpen = false;
    }

    /* ============ External Functions ============ */

    function newMethod() public view returns (string memory) {
        return 'foobar';
    }
}
