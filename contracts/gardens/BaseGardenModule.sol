// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {ECDSA} from '@openzeppelin/contracts/cryptography/ECDSA.sol';
import {ERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';

import {Errors, _require, _revert} from '../lib/BabylonErrors.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';

import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IStrategyFactory} from '../interfaces/IStrategyFactory.sol';
import {IGardenValuer} from '../interfaces/IGardenValuer.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IGardenNFT} from '../interfaces/IGardenNFT.sol';
import {IMardukGate} from '../interfaces/IMardukGate.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';

import {VTableBeaconProxy} from '../proxy/VTableBeaconProxy.sol';
import {VTableBeacon} from '../proxy/VTableBeacon.sol';
import {TimeLockedToken} from '../token/TimeLockedToken.sol';

/**
 * @title BaseGardenModule
 *
 * Class that every GardenModule should inherit
 */
contract BaseGardenModule is ERC20Upgradeable, ReentrancyGuard {
    /* ============ Events ============ */

    /* ============ Constants ============ */

    uint8 internal constant MAX_EXTRA_CREATORS = 4;

    /* ============ Structs ============ */

    /* ============ State Variables ============ */

    // Reserve Asset of the garden
    address internal reserveAsset;

    // Address of the controller
    IBabController internal controller;

    // Address of the rewards distributor
    IRewardsDistributor internal rewardsDistributor;

    // The person that creates the garden
    address internal creator;

    bool internal active; // DEPRECATED;
    bool internal privateGarden;

    uint256 internal principal; // DEPRECATED;

    // The amount of funds set aside to be paid as rewards. Should NEVER be spent
    // on anything else ever.
    uint256 internal reserveAssetRewardsSetAside;

    uint256 internal reserveAssetPrincipalWindow; // DEPRECATED
    int256 internal absoluteReturns; // Total profits or losses of this garden

    // Indicates the minimum liquidity the asset needs to have to be tradable by this garden
    uint256 internal minLiquidityAsset;

    uint256 internal depositHardlock; // Window of time after deposits when withdraws are disabled for that user
    uint256 internal withdrawalsOpenUntil; // DEPRECATED

    // Contributors
    mapping(address => IGarden.Contributor) internal contributors;
    uint256 internal totalContributors;
    uint256 internal maxContributors; // DEPRECATED
    uint256 internal maxDepositLimit; // Limits the amount of deposits

    uint256 internal gardenInitializedAt; // Garden Initialized at timestamp
    // Number of garden checkpoints used to control the garden power and each contributor power with accuracy
    uint256 internal pid;

    // Min contribution in the garden
    uint256 internal minContribution; //wei
    uint256 internal minGardenTokenSupply; // DEPRECATED

    // Strategies variables
    uint256 internal totalStake;
    uint256 internal minVotesQuorum; // 10%. (0.01% = 1e14, 1% = 1e16)
    uint256 internal minVoters;
    uint256 internal minStrategyDuration; // Min duration for an strategy
    uint256 internal maxStrategyDuration; // Max duration for an strategy
    // Window for the strategy to cooldown after approval before receiving capital
    uint256 internal strategyCooldownPeriod;

    address[] internal strategies; // Strategies that are either in candidate or active state
    address[] internal finalizedStrategies; // Strategies that have finalized execution
    mapping(address => bool) internal strategyMapping;
    mapping(address => bool) internal isGardenStrategy; // Security control mapping

    // Keeper debt in reserve asset if any, repaid upon every strategy finalization
    uint256 internal keeperDebt;
    uint256 internal totalKeeperFees;

    // Allow internal strategy creators for certain gardens
    bool internal publicStrategists;

    // Allow public strategy stewards for certain gardens
    bool internal publicStewards;

    // Addresses for extra creators
    address[MAX_EXTRA_CREATORS] internal extraCreators;

    // last recorded price per share of the garden during deposit or withdrawal operation
    uint256 internal lastPricePerShare;

    // last recorded time of the deposit or withdraw in seconds
    uint256 internal lastPricePerShareTS;

    // Decay rate of the slippage for pricePerShare over time
    uint256 internal pricePerShareDecayRate;

    // Base slippage for pricePerShare of the garden
    uint256 internal pricePerShareDelta;

    // Whether or not governance has verified and the category
    uint256 internal verifiedCategory;

    // Variable that overrides the depositLock with a global one
    uint256 internal hardlockStartsAt;

    // EIP-1271 signer
    address internal signer;
    // Variable that controls whether the NFT can be minted after x amount of time
    uint256 internal canMintNftAfter;

    /* ============ Modifiers ============ */

    /* ============ Constructor ============ */

    /* ============ External Functions ============ */

    /* ============ External Getter Functions ============ */

    /* ============ Internal Functions ============ */
}
