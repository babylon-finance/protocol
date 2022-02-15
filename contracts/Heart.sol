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
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import {IHypervisor} from './interfaces/IHypervisor.sol';
import {IBabController} from './interfaces/IBabController.sol';
import {IGovernor} from './interfaces/external/oz/IGovernor.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IHeart} from './interfaces/IHeart.sol';
import {IWETH} from './interfaces/external/weth/IWETH.sol';
import {ICToken} from './interfaces/external/compound/ICToken.sol';
import {ICEther} from './interfaces/external/compound/ICEther.sol';
import {IComptroller} from './interfaces/external/compound/IComptroller.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {IMasterSwapper} from './interfaces/IMasterSwapper.sol';
import {IVoteToken} from './interfaces/IVoteToken.sol';

import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from './lib/SafeDecimalMath.sol';
import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';
import {Errors, _require, _revert} from './lib/BabylonErrors.sol';
import {ControllerLib} from './lib/ControllerLib.sol';

/**
 * @title Heart
 * @author Babylon Finance
 *
 * Contract that assists The Heart of Babylon garden with BABL staking.
 *
 */
contract Heart is OwnableUpgradeable, IHeart {
    using SafeERC20 for IERC20;
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;
    using ControllerLib for IBabController;

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not a keeper in the protocol
     */
    function _onlyKeeper() private view {
        _require(controller.isValidKeeper(msg.sender), Errors.ONLY_KEEPER);
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

    // Only for offline use by keeper/fauna
    bytes32 private constant VOTE_PROPOSAL_TYPEHASH =
        keccak256('ProposalVote(uint256 _proposalId,uint256 _amount,bool _isApprove)');
    bytes32 private constant VOTE_GARDEN_TYPEHASH = keccak256('GardenVote(address _garden,uint256 _amount)');

    // Visor
    IHypervisor private constant visor = IHypervisor(0xF19F91d7889668A533F14d076aDc187be781a458);

    // Address of Uniswap factory
    IUniswapV3Factory internal constant factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;
    uint24 private constant FEE_HIGH = 10000;
    uint256 private constant DEFAULT_TRADE_SLIPPAGE = 25e15; // 2.5%

    // Tokens
    IWETH private constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant BABL = IERC20(0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74);
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    // Fuse
    address private constant BABYLON_FUSE_POOL_ADDRESS = 0xC7125E3A2925877C7371d579D29dAe4729Ac9033;

    /* ============ Immutables ============ */

    IBabController private immutable controller;
    IGovernor private immutable governor;
    address private immutable treasury;

    /* ============ State Variables ============ */

    // Instance of the Controller contract

    // Heart garden address
    IGarden public heartGarden;

    // Variables to handle garden seed investments
    address[] public override votedGardens;
    uint256[] public override gardenWeights;

    // Min Amounts to trade
    mapping(address => uint256) public override minAmounts;

    // Fuse pool Variables
    // Mapping of asset addresses to cToken addresses in the fuse pool
    mapping(address => address) public override assetToCToken;
    // Which asset is going to receive the next batch of liquidity in fuse
    address public override assetToLend;

    // Timestamp when the heart was last pumped
    uint256 public override lastPumpAt;

    // Timestamp when the votes were sent by the keeper last
    uint256 public override lastVotesAt;

    // Amount to gift to the Heart of Babylon Garden weekly
    uint256 public override weeklyRewardAmount;
    uint256 public override bablRewardLeft;

    // Array with the weights to distribute to different heart activities
    // 0: Treasury
    // 1: Buybacks
    // 2: Liquidity BABL-ETH
    // 3: Garden Seed Investments
    // 4: Fuse Pool
    uint256[] public override feeDistributionWeights;

    // Metric Totals
    // 0: fees accumulated in weth
    // 1: Money sent to treasury
    // 2: babl bought in babl
    // 3: liquidity added in weth
    // 4: amount invested in gardens in weth
    // 5: amount lent on fuse in weth
    // 6: weekly rewards paid in babl
    uint256[7] public override totalStats;

    // Trade slippage to apply in trades
    uint256 public override tradeSlippage;

    /* ============ Initializer ============ */

    /**
     * Set controller and governor addresses
     *
     * @param _controller             Address of controller contract
     * @param _governor               Address of governor contract
     */
    constructor(IBabController _controller, IGovernor _governor) initializer {
        _require(address(_controller) != address(0), Errors.ADDRESS_IS_ZERO);
        _require(address(_governor) != address(0), Errors.ADDRESS_IS_ZERO);

        controller = _controller;
        treasury = _controller.treasury();
        governor = _governor;
    }

    /**
     * Set state variables and map asset pairs to their oracles
     *
     * @param _feeWeights             Weights of the fee distribution
     */
    function initialize(uint256[] calldata _feeWeights) external initializer {
        OwnableUpgradeable.__Ownable_init();
        updateFeeWeights(_feeWeights);
        updateMarkets();
        updateAssetToLend(address(DAI));
        minAmounts[address(DAI)] = 500e18;
        minAmounts[address(USDC)] = 500e6;
        minAmounts[address(WETH)] = 5e17;
        minAmounts[address(WBTC)] = 3e6;
        // Self-delegation to be able to use BABL balance as voting power
        IVoteToken(address(BABL)).delegate(address(this));
        tradeSlippage = DEFAULT_TRADE_SLIPPAGE;
    }

    /* ============ External Functions ============ */

    /**
     * Function to pump blood to the heart
     *
     * Note: Anyone can call this. Keeper in Defender will be set up to do it for convenience.
     */
    function pump() public override {
        _require(address(heartGarden) != address(0), Errors.HEART_GARDEN_NOT_SET);
        _require(block.timestamp.sub(lastPumpAt) >= 1 weeks, Errors.HEART_ALREADY_PUMPED);
        _require(block.timestamp.sub(lastVotesAt) < 1 weeks, Errors.HEART_VOTES_MISSING);
        // Consolidate all fees
        _consolidateFeesToWeth();
        uint256 wethBalance = WETH.balanceOf(address(this));
        _require(wethBalance >= 3e18, Errors.HEART_MINIMUM_FEES);
        // Send 10% to the treasury
        IERC20(WETH).safeTransferFrom(address(this), treasury, wethBalance.preciseMul(feeDistributionWeights[0]));
        totalStats[1] = totalStats[1].add(wethBalance.preciseMul(feeDistributionWeights[0]));
        // 30% for buybacks
        _buyback(wethBalance.preciseMul(feeDistributionWeights[1]));
        // 25% to BABL-ETH pair
        _addLiquidity(wethBalance.preciseMul(feeDistributionWeights[2]));
        // 15% to Garden Investments
        _investInGardens(wethBalance.preciseMul(feeDistributionWeights[3]));
        // 20% lend in fuse pool
        _lendFusePool(wethBalance.preciseMul(feeDistributionWeights[4]));
        // Add BABL reward to stakers (if any)
        _sendWeeklyReward();
        lastPumpAt = block.timestamp;
    }

    /**
     * Function to vote for a proposal
     *
     * Note: Only keeper can call this. Votes need to have been resolved offchain.
     * Warning: Gardens need to delegate to heart first.
     */
    function voteProposal(uint256 _proposalId, bool _isApprove) external override {
        _onlyKeeper();
        // Governor does revert if trying to cast a vote twice or if proposal is not active
        IGovernor(governor).castVote(_proposalId, _isApprove ? 1 : 0);
        emit ProposalVote(block.timestamp, _proposalId, _isApprove);
    }

    /**
     * Resolves garden votes for this cycle
     *
     * Note: Only keeper can call this
     * @param _gardens             Gardens that are going to receive investment
     * @param _weights             Weight for the investment in each garden normalied to 1e18 precision
     */
    function resolveGardenVotes(address[] memory _gardens, uint256[] memory _weights) public override {
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

    function resolveGardenVotesAndPump(address[] memory _gardens, uint256[] memory _weights) external override {
        resolveGardenVotes(_gardens, _weights);
        pump();
    }

    /**
     * Updates fuse pool market information and enters the markets
     *
     */
    function updateMarkets() public override {
        controller.onlyGovernanceOrEmergency();
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
    function updateFeeWeights(uint256[] calldata _feeWeights) public override {
        controller.onlyGovernanceOrEmergency();
        delete feeDistributionWeights;
        for (uint256 i = 0; i < _feeWeights.length; i++) {
            feeDistributionWeights.push(_feeWeights[i]);
        }
    }

    /**
     * Updates the next asset to lend on fuse pool
     *
     * @param _assetToLend             New asset to lend
     */
    function updateAssetToLend(address _assetToLend) public override {
        controller.onlyGovernanceOrEmergency();
        _require(assetToLend != _assetToLend, Errors.HEART_ASSET_LEND_SAME);
        _require(assetToCToken[_assetToLend] != address(0), Errors.HEART_ASSET_LEND_INVALID);
        assetToLend = _assetToLend;
    }

    /**
     * Adds a BABL reward to be distributed weekly back to the heart garden
     *
     * @param _bablAmount             Total amount to distribute
     * @param _weeklyRate             Weekly amount to distribute
     */
    function addReward(uint256 _bablAmount, uint256 _weeklyRate) external override {
        controller.onlyGovernanceOrEmergency();
        // Get the BABL reward
        IERC20(BABL).safeTransferFrom(msg.sender, address(this), _bablAmount);
        bablRewardLeft = bablRewardLeft.add(_bablAmount);
        weeklyRewardAmount = _weeklyRate;
    }

    /**
     * Updates the min amount to trade a specific asset
     *
     * @param _asset                Asset to edit the min amount
     * @param _minAmount            New min amount
     */
    function setMinTradeAmount(address _asset, uint256 _minAmount) external override {
        controller.onlyGovernanceOrEmergency();
        minAmounts[_asset] = _minAmount;
    }

    /**
     * Updates the heart garden address
     *
     * @param _heartGarden                New heart garden address
     */
    function setHeartGardenAddress(address _heartGarden) external override {
        controller.onlyGovernanceOrEmergency();
        heartGarden = IGarden(_heartGarden);
    }

    /**
     * Updates the tradeSlippage
     *
     * @param _tradeSlippage                Trade slippage
     */
    function setTradeSlippage(uint256 _tradeSlippage) external override {
        controller.onlyGovernanceOrEmergency();
        tradeSlippage = _tradeSlippage;
    }

    // solhint-disable-next-line
    receive() external payable {}

    /* ============ External View Functions ============ */

    /**
     * Getter to get the whole array of voted gardens
     *
     * @return            The array of voted gardens
     */
    function getVotedGardens() external view override returns (address[] memory) {
        return votedGardens;
    }

    /**
     * Getter to get the whole array of garden weights
     *
     * @return            The array of weights for voted gardens
     */
    function getGardenWeights() external view override returns (uint256[] memory) {
        return gardenWeights;
    }

    /**
     * Getter to get the whole array of fee weights
     *
     * @return            The array of weights for the fees
     */
    function getFeeDistributionWeights() external view override returns (uint256[] memory) {
        return feeDistributionWeights;
    }

    /**
     * Getter to get the whole array of total stats
     *
     * @return            The array of stats for the fees
     */
    function getTotalStats() external view override returns (uint256[7] memory) {
        return totalStats;
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
                totalStats[0] = totalStats[0].add(_trade(reserveAsset, address(WETH), balance));
            }
            if (reserveAsset == address(WETH)) {
                totalStats[0] = totalStats[0].add(balance);
            }
        }
        emit FeesCollected(block.timestamp, IERC20(WETH).balanceOf(address(this)));
    }

    /**
     * Buys back BABL through the uniswap V3 BABL-ETH pool
     *
     */
    function _buyback(uint256 _amount) private {
        // Gift 50% BABL back to garden and send 50% to the treasury
        uint256 bablBought = _trade(address(WETH), address(BABL), _amount); // 50%
        IERC20(BABL).safeTransfer(address(heartGarden), bablBought.div(2));
        IERC20(BABL).safeTransfer(treasury, bablBought.div(2));
        totalStats[2] = totalStats[2].add(bablBought);
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
        uint256 oldTreasuryBalance = visor.balanceOf(treasury);
        uint256 shares = visor.deposit(wethToDeposit, bablTraded, treasury);
        _require(
            shares == visor.balanceOf(treasury).sub(oldTreasuryBalance) && visor.balanceOf(treasury) > 0,
            Errors.HEART_LP_TOKENS
        );
        totalStats[3] += _wethBalance;
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
            uint256 amountTraded;
            if (reserveAsset != address(WETH)) {
                amountTraded = _trade(address(WETH), reserveAsset, _wethAmount.preciseMul(gardenWeights[i]));
            } else {
                amountTraded = _wethAmount.preciseMul(gardenWeights[i]);
            }
            // Gift it to garden
            IERC20(reserveAsset).safeTransfer(votedGardens[i], amountTraded);
            emit GardenSeedInvest(block.timestamp, votedGardens[i], _wethAmount.preciseMul(gardenWeights[i]));
        }
        totalStats[4] += _wethAmount;
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
            IERC20(assetToLend).approve(cToken, assetToLendBalance);
            ICToken(cToken).mint(assetToLendBalance);
        }
        totalStats[5] = totalStats[5].add(_wethAmount);
        emit FuseLentAsset(block.timestamp, assetToLend, _wethAmount);
    }

    /**
     * Sends the weekly BABL reward to the garden (if any)
     */
    function _sendWeeklyReward() private {
        if (bablRewardLeft > 0) {
            uint256 bablToSend = bablRewardLeft < weeklyRewardAmount ? bablRewardLeft : weeklyRewardAmount;
            uint256 currentBalance = IERC20(BABL).balanceOf(address(this));
            bablToSend = currentBalance < bablToSend ? currentBalance : bablToSend;
            IERC20(BABL).safeTransfer(address(heartGarden), bablToSend);
            bablRewardLeft = bablRewardLeft.sub(bablToSend);
            emit BABLRewardSent(block.timestamp, bablToSend);
            totalStats[6] = totalStats[6].add(bablToSend);
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
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(tradeSlippage));
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

contract HeartV1 is Heart {
    constructor(IBabController _controller, IGovernor _governor) Heart(_controller, _governor) {}
}
