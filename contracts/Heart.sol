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
pragma abicoder v2;
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import {IHypervisor} from './interfaces/IHypervisor.sol';
import {IBabController} from './interfaces/IBabController.sol';
import {IGovernor} from './interfaces/external/oz/IGovernor.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IWETH} from './interfaces/external/weth/IWETH.sol';
import {ICToken} from './interfaces/external/compound/ICToken.sol';
import {ICEther} from './interfaces/external/compound/ICEther.sol';
import {IComptroller} from './interfaces/external/compound/IComptroller.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {IMasterSwapper} from './interfaces/IMasterSwapper.sol';
import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from './lib/SafeDecimalMath.sol';
import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';
import {Errors, _require, _revert} from './lib/BabylonErrors.sol';

/**
 * @title Heart
 * @author Babylon Finance
 *
 * Contract that assists The Heart of Babylon garden with BABL staking.
 *
 */
contract Heart is OwnableUpgradeable {
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ Modifiers ============ */

    modifier onlyGovernanceOrEmergency {
        _require(
            msg.sender == owner() || msg.sender == controller.EMERGENCY_OWNER(),
            Errors.ONLY_GOVERNANCE_OR_EMERGENCY
        );
        _;
    }

    /* ============ Events ============ */

    event FeesCollected(uint256 _timestamp, uint256 _amount);
    event LiquidityAdded(uint256 _timestamp, uint256 _wethBalance, uint256 _bablBalance);
    event BablBuyback(uint256 _timestamp, uint256 _wethSpent, uint256 _bablBought);
    event GardenSeedInvest(uint256 _timestamp, address indexed _garden, uint256 _wethInvested);
    event FuseLentAsset(uint256 _timestamp, address indexed _asset, uint256 _assetAmount);
    event BABLRewardSent(uint256 _timestamp, uint256 _bablSent);
    event ProposalVote(uint256 _timestamp, uint256 _proposalId, bool _isApprove);
    event UpdatedGardenWeights(uint256 _timestamp);

    /* ============ Constants ============ */

    // Address of Uniswap factory
    IUniswapV3Factory internal constant factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;
    uint24 private constant FEE_HIGH = 10000;

    // Min Amounts to trade
    mapping(address => uint256) public minAmounts;

    // Babylon addresses
    address private constant TREASURY = 0xD7AAf4676F0F52993cb33aD36784BF970f0E1259;
    address private constant GOVERNOR = 0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24;
    uint256 private constant DEFAULT_TRADE_SLIPPAGE = 25e15; // 2.5%

    // Tokens
    IWETH private constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant BABL = IERC20(0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74);
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IGarden private constant HEART_GARDEN = IGarden(0x0);

    // Visor
    IHypervisor visor = IHypervisor(0x5e6c481dE496554b66657Dd1CA1F70C61cf11660);

    // Fuse
    address private constant BABYLON_FUSE_POOL_ADDRESS = 0xC7125E3A2925877C7371d579D29dAe4729Ac9033;

    /* ============ State Variables ============ */

    // Instance of the Controller contract
    IBabController public controller;

    // Variables to handle garden seed investments
    address[] public votedGardens;
    uint256[] public gardenWeights;

    // Fuse pool Variables
    // Mapping of asset addresses to cToken addresses in the fuse pool
    mapping(address => address) public assetToCToken;
    // Which asset is going to receive the next batch of liquidity in fuse
    address public assetToLend;

    // Timestamp when the heart was last pumped
    uint256 public lastPumpAt;

    // Timestamp when the votes were sent by the keeper last
    uint256 public lastVotesAt;

    // Amount to gift to the Heart of Babylon Garden weekly
    uint256 public weeklyRewardAmount;
    uint256 public bablRewardLeft;

    // Array with the weights to distribute to different heart activities
    // 0: Buybacks
    // 1: Liquidity BABL-ETH
    // 2: Garden Seed Investments
    // 3: Fuse Pool
    uint256[] public feeDistributionWeights;

    // Metric Totals
    // 0: fees accumulated in weth
    // 1: babl bought in babl
    // 2: liquidity added in weth
    // 3: amount invested in gardens in weth
    // 4: amount lent on fuse in weth
    uint256[] public totalStats;

    /* ============ Initializer ============ */

    /**
     * Set state variables and map asset pairs to their oracles
     *
     * @param _controller             Address of controller contract
     */
    function initialize(IBabController _controller, uint256[] calldata _feeWeights) public {
        OwnableUpgradeable.__Ownable_init();
        _require(address(_controller) != address(0), Errors.ADDRESS_IS_ZERO);
        controller = _controller;
        updateFeeWeights(_feeWeights);
        updateMarkets();
        updateAssetToLend(address(DAI));
        minAmounts[address(DAI)] = 500e18;
        minAmounts[address(USDC)] = 500e6;
        minAmounts[address(WETH)] = 5e17;
        minAmounts[address(WBTC)] = 3e6;
    }

    /* ============ External Functions ============ */

    /**
     * Function to pump blood to the heart
     *
     * Note: Anyone can call this. Keeper in Defender will be set up to do it for convenience.
     */
    function pump() external {
        _require(block.timestamp.sub(lastPumpAt) > 1 weeks, Errors.HEART_ALREADY_PUMPED);
        _require(block.timestamp.sub(lastVotesAt) < 1 weeks, Errors.HEART_VOTES_MISSING);
        // Consolidate all fees
        _consolidateFeesToWeth();
        uint256 wethBalance = WETH.balanceOf(address(this));
        _require(wethBalance >= 3e18, Errors.HEART_MINIMUM_FEES);
        // 50% for buybacks
        _buyback(wethBalance.preciseMul(feeDistributionWeights[0]));
        // 20% to BABL-ETH pair
        _addLiquidity(wethBalance.preciseMul(feeDistributionWeights[1]));
        // 20% to Garden Investments
        _investInGardens(wethBalance.preciseMul(feeDistributionWeights[2]));
        // 10% lend in fuse pool
        _lendFusePool(wethBalance.preciseMul(feeDistributionWeights[3]));
        // Add BABL reward to stakers (if any)
        _sendWeeklyReward();
        lastPumpAt = block.timestamp;
    }

    /**
     * Function to vote for a proposal
     *
     * Note: Only keeper can call this. Votes need to have been resolved offchain.
     */
    function voteProposal(uint256 _proposalId, bool _isApprove) external {
        _onlyKeeper();
        _require(
            IGovernor(GOVERNOR).state(_proposalId) == IGovernor.ProposalState.Active,
            Errors.HEART_PROPOSAL_NOT_ACTIVE
        );
        _require(!IGovernor(GOVERNOR).hasVoted(_proposalId, address(this)), Errors.HEART_ALREADY_VOTED);
        IGovernor(GOVERNOR).castVote(_proposalId, _isApprove ? 1 : 0);
        emit ProposalVote(block.timestamp, _proposalId, _isApprove);
    }

    /**
     * Resolves garden votes for this cycle
     *
     * Note: Only keeper can call this
     * @param _gardens             Gardens that are going to receive investment
     * @param _weights             Weight for the investment in each garden
     */
    function resolveGardenVotes(address[] memory _gardens, uint256[] memory _weights) public {
        _onlyKeeper();
        _require(_gardens.length == _weights.length, Errors.HEART_VOTES_LENGTH);
        delete votedGardens;
        delete gardenWeights;
        for (uint256 i = 0; i < _gardens.length; i++) {
            votedGardens.push(_gardens[i]);
            gardenWeights.push(_weights[i]);
        }
        lastVotesAt = block.timestamp;
        emit UpdatedGardenWeights(block.timestamp);
    }

    /**
     * Updates fuse pool market information and enters the markets
     *
     */
    function updateMarkets() public onlyGovernanceOrEmergency {
        // Enter markets of the fuse pool for all these assets
        address[] memory markets = IComptroller(BABYLON_FUSE_POOL_ADDRESS).getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            address underlying = ICToken(markets[i]).underlying();
            assetToCToken[underlying] = markets[i];
        }
        IComptroller(BABYLON_FUSE_POOL_ADDRESS).enterMarkets(markets);
    }

    /**
     * Set the weights to allocate to different heart initiatives
     *
     * @param _feeWeights             Array of % (up to 1e18) with the fee weights
     */
    function updateFeeWeights(uint256[] calldata _feeWeights) public onlyGovernanceOrEmergency {
        delete feeDistributionWeights;
        for (uint256 i = 0; i < _feeWeights.length; i++) {
            feeDistributionWeights.push(_feeWeights[i]);
        }
    }

    /**
     * Set the weights to allocate to different heart initiatives
     *
     * @param _assetToLend             New asset to lend
     */
    function updateAssetToLend(address _assetToLend) public onlyGovernanceOrEmergency {
        _require(assetToLend != _assetToLend, Errors.HEART_ASSET_LEND_SAME);
        assetToLend = _assetToLend;
    }

    /**
     * Adds a BABL reward to be distributed weekly back to the heart garden
     *
     * @param _bablAmount             Total amount to distribute
     * @param _weeklyRate             Weekly amount to distribute
     */
    function addReward(uint256 _bablAmount, uint256 _weeklyRate) public onlyGovernanceOrEmergency {
        // Get the BABL reward
        IERC20(BABL).transferFrom(msg.sender, address(this), _bablAmount);
        bablRewardLeft += _bablAmount;
        weeklyRewardAmount = _weeklyRate;
    }

    /**
     * Updates the min amount to trade a specific asset
     *
     * @param _asset                Asset to edit the min amount
     * @param _minAmount            New min amount
     */
    function setMinTradeAmount(address _asset, uint256 _minAmount) public onlyGovernanceOrEmergency {
        minAmounts[_asset] = _minAmount;
    }

    /* ============ Internal Functions ============ */

    /**
     * Consolidates all reserve asset fees to weth
     *
     */
    function _consolidateFeesToWeth() private {
        address[] memory reserveAssets = controller.getReserveAssets();
        for (uint256 i = 0; i < reserveAssets.length; i++) {
            address reserveAsset = reserveAssets[i];
            uint256 balance = IERC20(reserveAsset).balanceOf(address(this));
            // Trade if it's above a min amount (otherwise wait until next pump)
            if (reserveAsset != address(BABL) && reserveAsset != address(WETH) && balance > minAmounts[reserveAsset]) {
                totalStats[0] += _trade(reserveAsset, address(WETH), balance);
            }
        }
        emit FeesCollected(block.timestamp, IERC20(WETH).balanceOf(address(this)));
    }

    /**
     * Buys back BABL through the uniswap V3 BABL-ETH pool
     *
     */
    function _buyback(uint256 _amount) private {
        // Gift 100% BABL back to garden
        uint256 bablBought = _trade(address(WETH), address(BABL), _amount); // 50%
        IERC20(BABL).transferFrom(address(this), address(HEART_GARDEN), bablBought);
        totalStats[1] += bablBought;
        emit BablBuyback(block.timestamp, _amount, bablBought);
    }

    /**
     * Adds liquidity to the BABL-ETH pair through the hypervisor
     *
     * Note: Address of the heart needs to be whitelisted by Visor.
     */
    function _addLiquidity(uint256 _wethBalance) private {
        // Buy BABL again with half to add 50/50
        uint256 wethToDeposit = _wethBalance.preciseMul(5e17);
        uint256 bablTraded = _trade(address(WETH), address(BABL), wethToDeposit); // 50%
        BABL.approve(address(visor), bablTraded);
        WETH.approve(address(visor), wethToDeposit);
        uint256 shares = visor.deposit(wethToDeposit, bablTraded, TREASURY);
        _require(shares == visor.balanceOf(TREASURY) && visor.balanceOf(TREASURY) > 0, Errors.HEART_LP_TOKENS);
        totalStats[2] += wethToDeposit;
        emit LiquidityAdded(block.timestamp, wethToDeposit, bablTraded);
    }

    /**
     * Invests in gardens using WETH converting it to garden reserve asset first
     *
     * @param _wethAmount             Total amount of weth to invest in all gardens
     */
    function _investInGardens(uint256 _wethAmount) private {
        for (uint256 i = 0; i < votedGardens.length; i++) {
            address reserveAsset = IGarden(votedGardens[i]).reserveAsset();
            uint256 amountTraded = _trade(address(WETH), reserveAsset, _wethAmount.preciseMul(gardenWeights[i]));
            // Gift it to garden
            IERC20(reserveAsset).transferFrom(address(this), votedGardens[i], amountTraded);
            emit GardenSeedInvest(block.timestamp, votedGardens[i], _wethAmount.preciseMul(gardenWeights[i]));
        }
        totalStats[3] += _wethAmount;
    }

    /**
     * Lends an amount of WETH converting it first to the pool asset that is the lowest (except BABL)
     *
     * @param _wethAmount             Total amount of weth to lend
     */
    function _lendFusePool(uint256 _wethAmount) private {
        address cToken = assetToCToken[assetToLend];
        _require(cToken != address(0), Errors.HEART_INVALID_CTOKEN);
        if (assetToLend == address(0)) {
            // Convert WETH to ETH
            IWETH(WETH).withdraw(_wethAmount);
            ICEther(cToken).mint{value: _wethAmount}();
        } else {
            // Trade to asset to lend from WETH
            uint256 assetToLendBalance = _trade(address(WETH), assetToLend, _wethAmount);
            ICToken(cToken).mint(assetToLendBalance);
        }
        totalStats[4] += _wethAmount;
        emit FuseLentAsset(block.timestamp, assetToLend, _wethAmount);
    }

    /**
     * Sends the weekly BABL reward to the garden (if any)
     */
    function _sendWeeklyReward() private {
        if (bablRewardLeft > 0) {
            uint256 bablToSend = bablRewardLeft > weeklyRewardAmount ? bablRewardLeft : weeklyRewardAmount;
            IERC20(BABL).transferFrom(address(this), address(HEART_GARDEN), bablToSend);
            emit BABLRewardSent(block.timestamp, bablToSend);
        }
    }

    /**
     * Trades _tokenIn to _tokenOut using Uniswap V3
     *
     * @param _tokenIn             Token that is sold
     * @param _tokenOut            Token that is purchased
     * @param _amount              Amount of tokenin to sell
     */
    function _trade(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount
    ) private returns (uint256) {
        if (_tokenIn == _tokenOut) {
          return _amount;
        }
        // Uses on chain oracle for all internal strategy operations to avoid attacks
        uint256 pricePerTokenUnit = IPriceOracle(controller.priceOracle()).getPrice(_tokenIn, _tokenOut);
        _require(pricePerTokenUnit != 0, Errors.NO_PRICE_FOR_TRADE);
        // minAmount must have receive token decimals
        uint256 exactAmount =
            SafeDecimalMath.normalizeAmountTokens(_tokenIn, _tokenOut, _amount.preciseMul(pricePerTokenUnit));
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(DEFAULT_TRADE_SLIPPAGE));
        ISwapRouter swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        // Approve the router to spend token in.
        TransferHelper.safeApprove(_tokenIn, address(swapRouter), _amount);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: _getUniswapPoolFeeWithHighestLiquidity(_tokenIn, _tokenOut),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amount,
                amountOutMinimum: minAmountExpected,
                sqrtPriceLimitX96: 0
            });
        return swapRouter.exactInputSingle(params);
    }

    /**
     * Throws if the sender is not a keeper in the protocol
     */
    function _onlyKeeper() private view {
        _require(controller.isValidKeeper(msg.sender), Errors.ONLY_KEEPER);
    }

    /**
     * Returns the FEE of the highest liquidity pool in univ3 for this pair
     * @param sendToken               Token that is sold
     * @param receiveToken            Token that is purchased
     */
    function _getUniswapPoolFeeWithHighestLiquidity(address sendToken, address receiveToken)
        private
        view
        returns (uint24)
    {
        IUniswapV3Pool poolLow = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_LOW));
        IUniswapV3Pool poolMedium = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_MEDIUM));
        IUniswapV3Pool poolHigh = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_HIGH));

        uint128 liquidityLow = address(poolLow) != address(0) ? poolLow.liquidity() : 0;
        uint128 liquidityMedium = address(poolMedium) != address(0) ? poolMedium.liquidity() : 0;
        uint128 liquidityHigh = address(poolHigh) != address(0) ? poolHigh.liquidity() : 0;
        if (liquidityLow >= liquidityMedium && liquidityLow >= liquidityHigh) {
            return FEE_LOW;
        }
        if (liquidityMedium >= liquidityLow && liquidityMedium >= liquidityHigh) {
            return FEE_MEDIUM;
        }
        return FEE_HIGH;
    }
}
