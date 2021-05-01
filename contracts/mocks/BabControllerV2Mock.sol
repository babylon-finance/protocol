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
    address public constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint8 public constant MAX_OPERATIONS = 20;

    // List of enabled Communities
    address[] public gardens;
    address[] public reserveAssets;
    address public gardenValuer;
    address public priceOracle;
    address public gardenFactory;
    address public rewardsDistributor;
    address public ishtarGate;
    address public strategyFactory;

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

    // Assets
    // Absolute Min liquidity of assets for risky gardens 1000 ETH
    uint256 public minRiskyPairLiquidityEth;

    // Enable Transfer of ERC20 gardenTokens
    // Only members can transfer tokens until the protocol is fully decentralized
    bool public gardenTokensTransfersEnabled;

    // Enable Transfer of ERC20 BABL Tokens
    // Only Minting or transfers from/to TimeLockRegistry and Rewards Distributor can transfer tokens until the protocol is fully decentralized
    bool public bablTokensTransfersEnabled;
    // Enable and starts the BABL Mining program within Rewards Distributor contract
    bool public bablMiningProgramEnabled;
    // Enable public gardens
    bool public allowPublicGardens;

    uint256 public protocolPerformanceFee; // 5% (0.01% = 1e14, 1% = 1e16) on profits
    uint256 public protocolManagementFee; // 0.5% (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolDepositGardenTokenFee; // 0 (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolWithdrawalGardenTokenFee; // 0 (0.01% = 1e14, 1% = 1e16)

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
        bablTokensTransfersEnabled = false;
        bablMiningProgramEnabled = false;
        minRiskyPairLiquidityEth = 1000 * 1e18;

        strategistProfitPercentage = 10e16;
        stewardsProfitPercentage = 5e16;
        lpsProfitPercentage = 80e16;

        strategistBABLPercentage = 8e16;
        stewardsBABLPercentage = 17e16;
        lpsBABLPercentage = 75e16;

        gardenCreatorBonus = 15e16;
    }

    /* ============ External Functions ============ */

    function newMethod() public pure returns (string memory) {
        return 'foobar';
    }
}
