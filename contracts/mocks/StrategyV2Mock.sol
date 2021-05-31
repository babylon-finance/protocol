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

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/Initializable.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';

import {Errors, _require} from '../lib/BabylonErrors.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {Math} from '../lib/Math.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';

import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {ITradeIntegration} from '../interfaces/ITradeIntegration.sol';
import {IOperation} from '../interfaces/IOperation.sol';
import {IIntegration} from '../interfaces/IIntegration.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IStrategyNFT} from '../interfaces/IStrategyNFT.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';

/**
 * @title Strategy
 * @author Babylon Finance
 *
 * Base Strategy contract. Belongs to a garden. Abstract.
 * Will be extended from specific strategy contracts.
 */
contract StrategyV2Mock {
    using SignedSafeMath for int256;
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for int256;
    using SafeDecimalMath for uint256;
    using Math for int256;
    using Math for uint256;
    using AddressArrayUtils for address[];
    using Address for address;
    using SafeERC20 for IERC20;

    /* ============ Constants ============ */

    uint256 internal constant SLIPPAGE_ALLOWED = 5e16; // 1%
    uint256 internal constant HUNDRED_PERCENT = 1e18; // 100%
    uint256 internal constant MAX_CANDIDATE_PERIOD = 7 days;
    uint256 internal constant ABSOLUTE_MIN_REBALANCE = 1e18;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Max Operations
    uint256 internal constant MAX_OPERATIONS = 6;

    // Keeper max fee
    // TODO: Given DAI, USDC, and WBTC can be a reseve asset, MAX_KEEPER_FEE should depend on reserve asset
    uint256 internal constant MAX_KEEPER_FEE = (1e6 * 1e3 gwei);

    // Quadratic penalty for looses
    uint256 internal constant STAKE_QUADRATIC_PENALTY_FOR_LOSSES = 175e16; // 1.75e18

    /* ============ Structs ============ */

    /* ============ State Variables ============ */

    // Babylon Controller Address
    IBabController public controller;

    // Type of operation.
    // 0 = BuyOperation
    // 1 = LiquidityOperation
    // 2 = VaultOperation
    // 3 = LendOperation

    // Asset Status
    // 0 = Liquid
    // 1 = Put as collateral
    // 2 = Borrowed
    // 3 = staked

    // Types and data for the operations of this strategy
    uint8[] public opTypes;
    address[] public opIntegrations;
    address[] public opDatas;

    // Garden that these strategies belong to
    IGarden public garden;

    address public strategist; // Address of the strategist that submitted the bet

    uint256 public enteredAt; // Timestamp when the strategy was submitted
    uint256 public enteredCooldownAt; // Timestamp when the strategy reached quorum
    uint256 public executedAt; // Timestamp when the strategy was executed
    uint256 public updatedAt; // Timestamp of last capital allocation update
    uint256 public exitedAt; // Timestamp when the strategy was submitted

    address[] public voters; // Addresses with the voters
    uint256 public totalPositiveVotes; // Total positive votes endorsing the strategy execution
    uint256 public totalNegativeVotes; // Total negative votes against the strategy execution
    bool public finalized; // Flag that indicates whether we exited the strategy
    bool public active; // Whether the strategy has met the voting quorum
    bool public dataSet;
    bool public hasMiningStarted;

    uint256 public duration; // Duration of the bet
    uint256 public stake; // Amount of stake by the strategist (in reserve asset) needs to be positive
    uint256 public maxCapitalRequested; // Amount of max capital to allocate
    uint256 public capitalAllocated; // Current amount of capital allocated
    uint256 public expectedReturn; // Expect return by this strategy
    uint256 public capitalReturned; // Actual return by this strategy
    uint256 public minRebalanceCapital; // Min amount of capital so that it is worth to rebalance the capital here
    address[] public tokensNeeded; // Positions that need to be taken prior to enter the strategy
    uint256[] public tokenAmountsNeeded; // Amount of these positions

    uint256 public strategyRewards; // Rewards allocated for this strategy updated on finalized
    uint256 public rewardsTotalOverhead; // Potential extra amount we are giving in BABL rewards

    // Voters mapped to their votes.
    mapping(address => int256) public votes;

    uint256 public newVar;

    function initialize(
        address _strategist,
        address _garden,
        address _controller,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _strategyDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital
    ) external {
      newVar = 42;
    }


    function setData(
        uint8[] calldata _opTypes,
        address[] calldata _opIntegrations,
        address[] calldata _opDatas
    ) external {
    }

    function newMethod() public view returns (string memory) {
        return 'foobar';
    }
}
