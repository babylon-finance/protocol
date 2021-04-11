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
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IRollingGarden} from '../interfaces/IRollingGarden.sol';
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
    uint256 public constant MIN_COOLDOWN_PERIOD = 6 hours;
    uint256 public constant MAX_COOLDOWN_PERIOD = 7 days;

    // Assets
    // Absolute Min liquidity of assets for risky gardens 1000 ETH
    uint256 public minRiskyPairLiquidityEth;

    // Enable Transfer of ERC20 gardenTokens
    // Only members can transfer tokens until the protocol is fully decentralized
    bool public gardenTokensTransfersEnabled;

    uint256 public protocolPerformanceFee; // 5% (0.01% = 1e14, 1% = 1e16) on profits
    uint256 public protocolManagementFee; // 0.5% (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolGardenCreationFee; // (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolDepositGardenTokenFee; // (0.01% = 1e14, 1% = 1e16)
    uint256 public protocolWithdrawalGardenTokenFee; // (0.01% = 1e14, 1% = 1e16)

    bool public newVar;

    /* ============ Constructor ============ */

    /**
     * Initializes the initial fee recipient on deployment.
     *
     * @param _treasury                     Address of the initial protocol fee recipient
     * @param _gardenValuer                 Address of the initial gardenValuer
     * @param _priceOracle                  Address of the initial priceOracle
     * @param _reservePool                  Address of the initial reservePool
     * @param _gardenFactory                Address of the initial garden factory
     * @param _rewardsDistributor           Address of the initial garden distributor
     */
    function initialize(
        address _treasury,
        address _gardenValuer,
        address _priceOracle,
        address _reservePool,
        address _gardenFactory,
        address _rewardsDistributor
    ) public {
        OwnableUpgradeable.__Ownable_init();

        // vars init values has to be set in initialize due to how upgrade proxy pattern works
        protocolManagementFee = 5e15; // 0.5% (0.01% = 1e14, 1% = 1e16)
        protocolPerformanceFee = 5e16; // 5% (0.01% = 1e14, 1% = 1e16) on profits
        gardenTokensTransfersEnabled = false;
        minRiskyPairLiquidityEth = 1000 * 1e18;

        treasury = _treasury;
        gardenValuer = _gardenValuer;
        priceOracle = _priceOracle;
        reservePool = _reservePool;
        gardenFactory = _gardenFactory;
        rewardsDistributor = _rewardsDistributor;
    }

    /* ============ External Functions ============ */

    function newMethod() public pure returns (string memory) {
        return 'foobar';
    }
}
