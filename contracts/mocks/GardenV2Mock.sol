/*
    Copyright 2021 Babylon Finance.

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
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';

import {Errors, _require} from '../lib/BabylonErrors.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';

import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IStrategyFactory} from '../interfaces/IStrategyFactory.sol';
import {IGardenValuer} from '../interfaces/IGardenValuer.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IGardenNFT} from '../interfaces/IGardenNFT.sol';
import {IIshtarGate} from '../interfaces/IIshtarGate.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';

/**
 * @title BaseGarden
 * @author Babylon Finance
 *
 * Class that holds common garden-related state and functions
 */
contract GardenV2Mock is ERC20Upgradeable, ReentrancyGuard {
    using SafeCast for int256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using SafeDecimalMath for int256;

    using SafeCast for uint256;
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    using Address for address;
    using AddressArrayUtils for address[];

    using SafeERC20 for IERC20;

    /* ============ State Constants ============ */

    // Wrapped ETH address
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 private constant EARLY_WITHDRAWAL_PENALTY = 15e16;
    uint256 private constant MAX_TOTAL_STRATEGIES = 20; // Max number of strategies
    uint256 private constant TEN_PERCENT = 1e17;
    // Window of time after an investment strategy finishes when the capital is available for withdrawals
    uint256 private constant withdrawalWindowAfterStrategyCompletes = 7 days;

    /* ============ Structs ============ */

    struct Contributor {
        uint256 lastDepositAt;
        uint256 initialDepositAt;
        uint256 claimedAt;
        uint256 claimedBABL;
        uint256 claimedRewards;
        uint256 withdrawnSince;
    }

    /* ============ State Variables ============ */

    // Reserve Asset of the garden
    address public reserveAsset;

    // Address of the controller
    address public controller;

    // Address of the rewards distributor
    IRewardsDistributor private rewardsDistributor;

    // The person that creates the garden
    address public creator;
    // Whether the garden is currently active or not
    bool public active;
    bool public guestListEnabled;

    // Keeps track of the reserve balance. In case we receive some through other means
    uint256 public principal;
    uint256 public reserveAssetRewardsSetAside;
    uint256 public reserveAssetPrincipalWindow;
    int256 public absoluteReturns; // Total profits or losses of this garden

    // Indicates the minimum liquidity the asset needs to have to be tradable by this garden
    uint256 public minLiquidityAsset;

    uint256 public depositHardlock; // Window of time after deposits when withdraws are disabled for that user
    uint256 public withdrawalsOpenUntil; // Indicates until when the withdrawals are open and the ETH is set aside

    // Contributors
    mapping(address => Contributor) private contributors;
    uint256 public totalContributors;
    uint256 public maxContributors;
    uint256 public maxDepositLimit; // Limits the amount of deposits

    uint256 public gardenInitializedAt; // Garden Initialized at timestamp
    // Number of garden checkpoints used to control de garden power and each contributor power with accuracy avoiding flash loans and related attack vectors
    uint256 private pid;

    // Min contribution in the garden
    uint256 public minContribution; //wei
    uint256 private minGardenTokenSupply;

    // Strategies variables
    uint256 public totalStake;
    uint256 public minVotesQuorum = TEN_PERCENT; // 10%. (0.01% = 1e14, 1% = 1e16)
    uint256 public minVoters;
    uint256 public minStrategyDuration; // Min duration for an strategy
    uint256 public maxStrategyDuration; // Max duration for an strategy
    // Window for the strategy to cooldown after approval before receiving capital
    uint256 public strategyCooldownPeriod;

    address[] private strategies; // Strategies that are either in candidate or active state
    address[] private finalizedStrategies; // Strategies that have finalized execution
    mapping(address => bool) public strategyMapping;
    mapping(address => bool) public isGardenStrategy; // Security control mapping

    // Keeper debt in reserve asset if any, repaid upon every strategy finalization
    uint256 public keeperDebt;

    uint256 public newVar;

    /* ============ External Functions ============ */
    function initialize(
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol,
        uint256[] calldata _gardenParams,
        uint256 _initialContribution
    ) public payable initializer {
        newVar = 42;
    }

    function deposit(
        uint256 _reserveAssetQuantity,
        uint256 _minGardenTokenReceiveQuantity,
        address _to,
        bool mintNFT
    ) external payable {}

    function newMethod() public view returns (string memory) {
        return 'foobar';
    }
}
