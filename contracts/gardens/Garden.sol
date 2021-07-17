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
contract Garden is ERC20Upgradeable, ReentrancyGuard, IGarden {
    using SafeCast for int256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using SafeDecimalMath for int256;

    using SafeCast for uint256;
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    using Address for address;
    using AddressArrayUtils for address[];

    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /* ============ Events ============ */
    event GardenDeposit(
        address indexed _to,
        uint256 minAmountOutShares,
        uint256 reserveTokenQuantity,
        uint256 timestamp
    );
    event GardenWithdrawal(
        address indexed _from,
        address indexed _to,
        uint256 reserveToken,
        uint256 reserveTokenQuantity,
        uint256 timestamp
    );
    event AddStrategy(address indexed _strategy, string _name, uint256 _expectedReturn);

    event RewardsForContributor(address indexed _contributor, uint256 indexed _amount);
    event BABLRewardsForContributor(address indexed _contributor, uint256 _rewards);

    /* ============ Constants ============ */

    // Wrapped ETH address
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    uint256 private constant EARLY_WITHDRAWAL_PENALTY = 5e16;
    uint256 private constant MAX_TOTAL_STRATEGIES = 20; // Max number of strategies
    uint256 private constant TEN_PERCENT = 1e17;

    bytes32 private constant DEPOSIT_BY_SIG_TYPEHASH =
        keccak256('DepositBySig(uint256 _amountIn,uint256 _minAmountOut,bool _mintNft, uint256 _nonce)');
    bytes32 private constant WITHDRAW_BY_SIG_TYPEHASH =
        keccak256('WithdrawBySig(uint256 _amountIn,uint256 _minAmountOut, uint256 _nonce)');

    /* ============ Structs ============ */

    struct Contributor {
        uint256 lastDepositAt;
        uint256 initialDepositAt;
        uint256 claimedAt;
        uint256 claimedBABL;
        uint256 claimedRewards;
        uint256 withdrawnSince;
        uint256 totalDeposits;
        uint256 nonce;
    }

    /* ============ State Variables ============ */

    // Reserve Asset of the garden
    address public override reserveAsset;

    // Address of the controller
    address public override controller;

    // Address of the rewards distributor
    IRewardsDistributor private rewardsDistributor;

    // The person that creates the garden
    address public override creator;
    // Whether the garden is currently active or not
    bool public override active;
    bool public override privateGarden;

    // Keeps track of the garden balance in reserve asset.
    uint256 public override principal;

    // The amount of funds set aside to be paid as rewards. Should NEVER be spent
    // on anything else ever.
    uint256 public override reserveAssetRewardsSetAside;

    uint256 private reserveAssetPrincipalWindow; // DEPRECATED
    int256 public override absoluteReturns; // Total profits or losses of this garden

    // Indicates the minimum liquidity the asset needs to have to be tradable by this garden
    uint256 public override minLiquidityAsset;

    uint256 public override depositHardlock; // Window of time after deposits when withdraws are disabled for that user
    uint256 private withdrawalsOpenUntil; // DEPRECATED

    // Contributors
    mapping(address => Contributor) private contributors;
    uint256 public override totalContributors;
    uint256 public override maxContributors;
    uint256 public override maxDepositLimit; // Limits the amount of deposits

    uint256 public override gardenInitializedAt; // Garden Initialized at timestamp
    // Number of garden checkpoints used to control the garden power and each contributor power with accuracy
    uint256 private pid;

    // Min contribution in the garden
    uint256 public override minContribution; //wei
    uint256 private minGardenTokenSupply; // DEPRECATED

    // Strategies variables
    uint256 public override totalStake;
    uint256 public override minVotesQuorum = TEN_PERCENT; // 10%. (0.01% = 1e14, 1% = 1e16)
    uint256 public override minVoters;
    uint256 public override minStrategyDuration; // Min duration for an strategy
    uint256 public override maxStrategyDuration; // Max duration for an strategy
    // Window for the strategy to cooldown after approval before receiving capital
    uint256 public override strategyCooldownPeriod;

    address[] private strategies; // Strategies that are either in candidate or active state
    address[] private finalizedStrategies; // Strategies that have finalized execution
    mapping(address => bool) public override strategyMapping;
    mapping(address => bool) public override isGardenStrategy; // Security control mapping

    // Keeper debt in reserve asset if any, repaid upon every strategy finalization
    uint256 public keeperDebt;

    // Allow public strategy creators for certain gardens
    bool public override publicStrategists;

    // Allow public strategy stewards for certain gardens
    bool public override publicStewards;

    /* ============ Modifiers ============ */

    function _onlyUnpaused() private view {
        // Do not execute if Globally or individually paused
        _require(!IBabController(controller).isPaused(address(this)), Errors.ONLY_UNPAUSED);
    }

    function _onlyContributor() private view {
        _require(balanceOf(msg.sender) > 0, Errors.ONLY_CONTRIBUTOR);
    }

    /**
     * Throws if the sender is not an strategy of this garden
     */
    function _onlyStrategy() private view {
        _require(strategyMapping[msg.sender], Errors.ONLY_STRATEGY);
    }

    /**
     * Throws if the garden is not active
     */
    function _onlyActive() private view {
        _require(active, Errors.ONLY_ACTIVE);
    }

    /* ============ Constructor ============ */

    /**
     * When a new Garden is created.
     * All parameter validations are on the BabController contract. Validations are performed already on the
     * BabController.
     * WARN: If the reserve Asset is different than WETH the gardener needs to have approved the controller.
     *
     * @param _reserveAsset                     Address of the reserve asset ERC20
     * @param _controller                       Address of the controller
     * @param _creator                          Address of the creator
     * @param _name                             Name of the Garden
     * @param _symbol                           Symbol of the Garden
     * @param _gardenParams                     Array of numeric garden params
     * @param _initialContribution              Initial Contribution by the Gardener
     * @param _publicGardenStrategistsStewards  Public garden, public strategists rights and public stewards rights
     */
    function initialize(
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol,
        uint256[] calldata _gardenParams,
        uint256 _initialContribution,
        bool[] memory _publicGardenStrategistsStewards
    ) public payable override initializer {
        _require(bytes(_name).length < 50, Errors.NAME_TOO_LONG);
        _require(
            _creator != address(0) && _controller != address(0) && ERC20Upgradeable(_reserveAsset).decimals() > 0,
            Errors.ADDRESS_IS_ZERO
        );
        _require(_gardenParams.length == 9, Errors.GARDEN_PARAMS_LENGTH);
        _require(IBabController(_controller).isValidReserveAsset(_reserveAsset), Errors.MUST_BE_RESERVE_ASSET);
        __ERC20_init(_name, _symbol);

        controller = _controller;
        reserveAsset = _reserveAsset;
        creator = _creator;
        maxContributors = IBabController(_controller).maxContributorsPerGarden();
        rewardsDistributor = IRewardsDistributor(IBabController(controller).rewardsDistributor());
        _require(address(rewardsDistributor) != address(0), Errors.ADDRESS_IS_ZERO);
        privateGarden = (IBabController(controller).allowPublicGardens() && _publicGardenStrategistsStewards[0])
            ? !_publicGardenStrategistsStewards[0]
            : true;
        publicStrategists = !privateGarden && _publicGardenStrategistsStewards[1] ? true : false;
        publicStewards = !privateGarden && _publicGardenStrategistsStewards[2] ? true : false;
        _start(
            _initialContribution,
            _gardenParams[0],
            _gardenParams[1],
            _gardenParams[2],
            _gardenParams[3],
            _gardenParams[4],
            _gardenParams[5],
            _gardenParams[6],
            _gardenParams[7],
            _gardenParams[8]
        );
        active = true;
    }

    /* ============ External Functions ============ */

    /**
     * FUND LEAD ONLY.  Starts the Garden with allowed reserve assets,
     * fees and issuance premium. Only callable by the Garden's creator
     *
     * @param _creatorDeposit                       Deposit by the creator
     * @param _maxDepositLimit                      Max deposit limit
     * @param _minLiquidityAsset                    Number that represents min amount of liquidity denominated in ETH
     * @param _depositHardlock                      Number that represents the time deposits are locked for an user after he deposits
     * @param _minContribution                      Min contribution to the garden
     * @param _strategyCooldownPeriod               How long after the strategy has been activated, will it be ready to be executed
     * @param _minVotesQuorum                       Percentage of votes needed to activate an strategy (0.01% = 1e14, 1% = 1e16)
     * @param _minStrategyDuration                  Min duration of an strategy
     * @param _maxStrategyDuration                  Max duration of an strategy
     * @param _minVoters                            The minimum amount of voters needed for quorum
     */
    function _start(
        uint256 _creatorDeposit,
        uint256 _maxDepositLimit,
        uint256 _minLiquidityAsset,
        uint256 _depositHardlock,
        uint256 _minContribution,
        uint256 _strategyCooldownPeriod,
        uint256 _minVotesQuorum,
        uint256 _minStrategyDuration,
        uint256 _maxStrategyDuration,
        uint256 _minVoters
    ) private {
        _require(_minContribution > 0 && _creatorDeposit >= _minContribution, Errors.MIN_CONTRIBUTION);
        _require(
            _minLiquidityAsset >= IBabController(controller).minLiquidityPerReserve(reserveAsset),
            Errors.MIN_LIQUIDITY
        );
        _require(
            _creatorDeposit <= _maxDepositLimit && _maxDepositLimit <= (reserveAsset == WETH ? 1e22 : 1e25),
            Errors.MAX_DEPOSIT_LIMIT
        );
        _require(_depositHardlock > 0, Errors.DEPOSIT_HARDLOCK);
        _require(
            _strategyCooldownPeriod <= IBabController(controller).getMaxCooldownPeriod() &&
                _strategyCooldownPeriod >= IBabController(controller).getMinCooldownPeriod(),
            Errors.NOT_IN_RANGE
        );
        _require(_minVotesQuorum >= TEN_PERCENT && _minVotesQuorum <= TEN_PERCENT.mul(5), Errors.VALUE_TOO_LOW);
        _require(
            _maxStrategyDuration >= _minStrategyDuration &&
                _minStrategyDuration >= 1 days &&
                _maxStrategyDuration <= 500 days,
            Errors.DURATION_RANGE
        );
        _require(_minVoters >= 1 && _minVoters < 10, Errors.MIN_VOTERS_CHECK);

        minContribution = _minContribution;
        strategyCooldownPeriod = _strategyCooldownPeriod;
        minVotesQuorum = _minVotesQuorum;
        minVoters = _minVoters;
        minStrategyDuration = _minStrategyDuration;
        maxStrategyDuration = _maxStrategyDuration;
        maxDepositLimit = _maxDepositLimit;
        gardenInitializedAt = block.timestamp;
        minLiquidityAsset = _minLiquidityAsset;
        depositHardlock = _depositHardlock;
    }

    /**
     * @notice
     *   Deposits the _amountIn in reserve asset into the garden. Gurantee to
     *   recieve at least _minAmountOut.
     * @dev
     *   WARN: If the reserve asset is different than ETH the sender needs to
     *   have approved the garden.
     *   Efficient to use of strategies.length == 0, otherwise can consume a lot
     *   of gas ~2kk. Use `depositBySig` for gas efficiency.
     * @param _amountIn               Amount of the reserve asset that is received from contributor
     * @param _minAmountOut           Min amount of Garden shares to receive by contributor
     * @param _to                     Address to mint Garden shares to
     * @param _mintNft                Whether to mint NFT or not
     */
    function deposit(
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _to,
        bool _mintNft
    ) external payable override nonReentrant {
        // calculate pricePerShare
        uint256 pricePerShare;
        // if there are no strategies then NAV === liquidReserve
        if (strategies.length == 0) {
            pricePerShare = totalSupply() == 0
                ? PreciseUnitMath.preciseUnit()
                : liquidReserve().preciseDiv(uint256(10)**ERC20Upgradeable(reserveAsset).decimals()).preciseDiv(
                    totalSupply()
                );
        } else {
            // Get valuation of the Garden with the quote asset as the reserve asset.
            pricePerShare = IGardenValuer(IBabController(controller).gardenValuer()).calculateGardenValuation(
                address(this),
                reserveAsset
            );
        }

        _internalDeposit(_amountIn, _minAmountOut, _to, msg.sender, _mintNft, pricePerShare);
    }

    function depositBySig(
        uint256 _amountIn,
        uint256 _minAmountOut,
        bool _mintNft,
        uint256 _nonce,
        uint256 _pricePerShare,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override nonReentrant {
        bytes32 hash =
            keccak256(abi.encode(DEPOSIT_BY_SIG_TYPEHASH, _amountIn, _minAmountOut, _mintNft, _nonce))
                .toEthSignedMessageHash();
        address signer = ECDSA.recover(hash, v, r, s);

        _require(signer != address(0), Errors.INVALID_SIGNER);

        // to prevent replay attacks
        _require(contributors[signer].nonce == _nonce, Errors.INVALID_NONCE);

        _internalDeposit(_amountIn, _minAmountOut, signer, signer, _mintNft, _pricePerShare);
    }

    function _internalDeposit(
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _to,
        address _from,
        bool _mintNft,
        uint256 _pricePerShare
    ) private {
        _onlyUnpaused();
        _onlyActive();
        _require(
            IIshtarGate(IBabController(controller).ishtarGate()).canJoinAGarden(address(this), _to) || creator == _to,
            Errors.USER_CANNOT_JOIN
        );

        // if deposit limit is 0, then there is no deposit limit
        if (maxDepositLimit > 0) {
            _require(principal.add(_amountIn) <= maxDepositLimit, Errors.MAX_DEPOSIT_LIMIT);
        }

        _require(totalContributors <= maxContributors, Errors.MAX_CONTRIBUTORS);
        _require(_amountIn >= minContribution, Errors.MIN_CONTRIBUTION);

        uint256 reserveAssetBalanceBefore = IERC20(reserveAsset).balanceOf(address(this));

        // If reserve asset is WETH and user sent ETH then wrap it
        if (reserveAsset == WETH && msg.value > 0) {
            IWETH(WETH).deposit{value: msg.value}();
        } else {
            // Transfer ERC20 to the garden
            IERC20(reserveAsset).safeTransferFrom(_from, address(this), _amountIn);
        }

        // Make sure we received the correct amount of reserve asset
        _require(
            IERC20(reserveAsset).balanceOf(address(this)).sub(reserveAssetBalanceBefore) == _amountIn,
            Errors.MSG_VALUE_DO_NOT_MATCH
        );

        uint256 previousBalance = balanceOf(_to);

        uint256 normalizedAmountIn = _amountIn.preciseDiv(uint256(10)**ERC20Upgradeable(reserveAsset).decimals());
        uint256 sharesToMint = normalizedAmountIn.preciseDiv(_pricePerShare);

        // make sure contributor gets desired amount of shares
        _require(sharesToMint >= _minAmountOut, Errors.RECEIVE_MIN_AMOUNT);

        // mint shares
        _mint(_to, sharesToMint);

        _updateContributorDepositInfo(_to, previousBalance, _amountIn);

        // account deposit in the principal
        principal = principal.add(_amountIn);

        // Mint the garden NFT
        if (_mintNft) {
            IGardenNFT(IBabController(controller).gardenNFT()).grantGardenNFT(_to);
        }

        emit GardenDeposit(_to, _minAmountOut, _amountIn, block.timestamp);
    }

    /**
     * @notice
     *   Withdraws the reserve asset relative to the token participation in the garden
     *   and sends it back to the sender.
     * @dev
     *   ATTENTION. Do not call withPenalty unless certain. If penalty is set,
     *   it will be applied regardless of the garden state.
     *   It is advised to first try to withdraw with no penalty and it this
     *   reverts then try to with penalty.
     * @param _amountIn           Quantity of the garden token to withdrawal
     * @param _minAmountOut     Min quantity of reserve asset to receive
     * @param _to                            Address to send component assets to
     * @param _withPenalty                   Whether or not this is an immediate withdrawal
     * @param _unwindStrategy                Strategy to unwind
     */
    function withdraw(
        uint256 _amountIn,
        uint256 _minAmountOut,
        address payable _to,
        bool _withPenalty,
        address _unwindStrategy
    ) external override nonReentrant {
        // Get valuation of the Garden with the quote asset as the reserve asset. Returns value in precise units (10e18)
        // Reverts if price is not found
        uint256 pricePerShare =
            IGardenValuer(IBabController(controller).gardenValuer()).calculateGardenValuation(
                address(this),
                reserveAsset
            );

        _require(msg.sender == _to, Errors.ONLY_CONTRIBUTOR);
        _withdrawInternal(_amountIn, _minAmountOut, _to, _withPenalty, _unwindStrategy, pricePerShare);
    }

    function withdrawBySig(
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint256 _nonce,
        uint256 _pricePerShare,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override nonReentrant {
        bytes32 hash =
            keccak256(abi.encode(WITHDRAW_BY_SIG_TYPEHASH, _amountIn, _minAmountOut, _nonce)).toEthSignedMessageHash();
        address signer = ECDSA.recover(hash, v, r, s);

        _require(signer != address(0), Errors.INVALID_SIGNER);

        // to prevent replay attacks
        _require(contributors[signer].nonce == _nonce, Errors.INVALID_NONCE);

        _withdrawInternal(_amountIn, _minAmountOut, payable(signer), false, address(0), _pricePerShare);
    }

    function _withdrawInternal(
        uint256 _amountIn,
        uint256 _minAmountOut,
        address payable _to,
        bool _withPenalty,
        address _unwindStrategy,
        uint256 _pricePerShare
    ) internal {
        _onlyUnpaused();
        _require(balanceOf(_to) > 0, Errors.ONLY_CONTRIBUTOR);
        // Flashloan protection
        _require(block.timestamp.sub(contributors[_to].lastDepositAt) >= depositHardlock, Errors.DEPOSIT_HARDLOCK);
        // Withdrawal amount has to be equal or less than msg.sender balance minus the locked balance
        uint256 lockedAmount = getLockedBalance(_to);
        _require(_amountIn <= balanceOf(_to).sub(lockedAmount), Errors.TOKENS_STAKED); // Strategists cannot withdraw locked stake while in active strategies

        // this value would have 18 decimals even for USDC
        uint256 amountOutNormalized = _amountIn.preciseMul(_pricePerShare);
        // in case of USDC that would with 6 decimals
        uint256 amountOut = amountOutNormalized.preciseMul(10**ERC20Upgradeable(reserveAsset).decimals());

        // if withPenaltiy then unwind strategy
        if (_withPenalty) {
            amountOut = amountOut.sub(amountOut.preciseMul(EARLY_WITHDRAWAL_PENALTY));
            // When unwinding a strategy, a slippage on integrations will result in receiving less tokens
            // than desired so we have have to account for this with a 5% slippage.
            IStrategy(_unwindStrategy).unwindStrategy(amountOut.add(amountOut.preciseMul(5e16)));
        }

        _require(amountOut >= _minAmountOut, Errors.RECEIVE_MIN_AMOUNT);

        _require(liquidReserve() >= amountOut, Errors.MIN_LIQUIDITY);

        _burn(_to, _amountIn);
        _safeSendReserveAsset(_to, amountOut);
        _updateContributorWithdrawalInfo(amountOut);

        _require(amountOut >= _minAmountOut, Errors.BALANCE_TOO_LOW);
        principal = principal.sub(amountOut);

        emit GardenWithdrawal(_to, _to, amountOut, _amountIn, block.timestamp);
    }

    /**
     * User can claim the rewards from the strategies that his principal
     * was invested in.
     */
    function claimReturns(address[] calldata _finalizedStrategies) external override nonReentrant {
        _onlyUnpaused();
        _onlyContributor();
        Contributor storage contributor = contributors[msg.sender];
        _require(block.timestamp > contributor.claimedAt, Errors.ALREADY_CLAIMED); // race condition check
        uint256[] memory rewards = new uint256[](7);

        rewards = rewardsDistributor.getRewards(address(this), msg.sender, _finalizedStrategies);
        _require(rewards[5] > 0 || rewards[6] > 0, Errors.NO_REWARDS_TO_CLAIM);

        if (rewards[6] > 0) {
            contributor.claimedRewards = contributor.claimedRewards.add(rewards[6]); // Rewards claimed properly
            reserveAssetRewardsSetAside = reserveAssetRewardsSetAside.sub(rewards[6]);
            contributor.claimedAt = block.timestamp; // Checkpoint of this claim
            _safeSendReserveAsset(msg.sender, rewards[6]);
            emit RewardsForContributor(msg.sender, rewards[6]);
        }
        if (rewards[5] > 0) {
            contributor.claimedBABL = contributor.claimedBABL.add(rewards[5]); // BABL Rewards claimed properly
            contributor.claimedAt = block.timestamp; // Checkpoint of this claim
            // Send BABL rewards
            rewardsDistributor.sendTokensToContributor(msg.sender, rewards[5]);
            emit BABLRewardsForContributor(msg.sender, rewards[5]);
        }
    }

    /**
     * @notice
     *  When strategy ends puts saves returns, rewards and marks strategy as
     *  finalized.
     *
     * @param _rewards                       Amount of Reserve Asset to set aside forever
     * @param _returns                       Profits or losses that the strategy received
     */
    function finalizeStrategy(uint256 _rewards, int256 _returns) external override {
        _onlyUnpaused();
        _require(
            (strategyMapping[msg.sender] && address(IStrategy(msg.sender).garden()) == address(this)),
            Errors.ONLY_STRATEGY
        );

        reserveAssetRewardsSetAside = reserveAssetRewardsSetAside.add(_rewards);

        // Mark strategy as finalized
        absoluteReturns = absoluteReturns.add(_returns);
        strategies = strategies.remove(msg.sender);
        finalizedStrategies.push(msg.sender);
        strategyMapping[msg.sender] = false;
    }

    /**
     * @notice
     *   Pays gas costs back to the keeper from executing transactions
     *   including the past debt
     * @dev
     *   We assume that calling keeper functions should be less expensive than
     *   1 million gas and the gas price should be lower than 1000 gwei.
     * @param _keeper  Keeper that executed the transaction
     * @param _fee     The fee paid to keeper to compensate the gas cost
     */
    function payKeeper(address payable _keeper, uint256 _fee) external override {
        _onlyUnpaused();
        _onlyStrategy();
        _require(IBabController(controller).isValidKeeper(_keeper), Errors.ONLY_KEEPER);

        if (reserveAsset == WETH) {
            // 1 ETH
            _require(_fee <= (1e6 * 1e3 gwei), Errors.FEE_TOO_HIGH);
        } else if (reserveAsset == DAI) {
            // 2000 DAI
            _require(_fee <= 2000 * 1e18, Errors.FEE_TOO_HIGH);
        } else if (reserveAsset == USDC) {
            // 2000 USDC
            _require(_fee <= 2000 * 1e6, Errors.FEE_TOO_HIGH);
        } else if (reserveAsset == WBTC) {
            // 0.05 WBTC
            _require(_fee <= 0.05 * 1e8, Errors.FEE_TOO_HIGH);
        } else {
            _revert(Errors.RESERVE_ASSET_NOT_SUPPORTED);
        }

        keeperDebt = keeperDebt.add(_fee);
        // Pay Keeper in Reserve Asset
        if (keeperDebt > 0 && liquidReserve() >= 0) {
            uint256 toPay = liquidReserve() > keeperDebt ? keeperDebt : liquidReserve();
            IERC20(reserveAsset).safeTransfer(_keeper, toPay);
            keeperDebt = keeperDebt.sub(toPay);
        }
    }

    /**
     * Makes a previously private garden public
     */
    function makeGardenPublic() external override {
        _require(msg.sender == creator, Errors.ONLY_CREATOR);
        _require(privateGarden && IBabController(controller).allowPublicGardens(), Errors.GARDEN_ALREADY_PUBLIC);
        privateGarden = false;
    }

    /**
     * Gives the right to create strategies and/or voting power to garden users
     */
    function setPublicRights(bool _publicStrategists, bool _publicStewards) external override {
        _require(msg.sender == creator, Errors.ONLY_CREATOR);
        _require(!privateGarden, Errors.GARDEN_IS_NOT_PUBLIC);
        publicStrategists = _publicStrategists;
        publicStewards = _publicStewards;
    }

    /**
     * PRIVILEGED Manager, protocol FUNCTION. When a Garden is active, deposits are enabled.
     */
    function setActive(bool _newValue) external override {
        _require(msg.sender == controller, Errors.ONLY_CONTROLLER);
        _require(active != _newValue, Errors.ONLY_INACTIVE);
        active = _newValue;
    }

    /* ============ Strategy Functions ============ */
    /**
     * Creates a new strategy calling the factory and adds it to the array
     * @param _name                          Name of the strategy
     * @param _symbol                        Symbol of the strategy
     * @param _stratParams                   Num params for the strategy
     * @param _opTypes                      Type for every operation in the strategy
     * @param _opIntegrations               Integration to use for every operation
     * @param _opEncodedDatas               Param for every operation in the strategy
     */
    function addStrategy(
        string memory _name,
        string memory _symbol,
        uint256[] calldata _stratParams,
        uint8[] calldata _opTypes,
        address[] calldata _opIntegrations,
        bytes calldata _opEncodedDatas
    ) external override {
        _onlyUnpaused();
        _onlyActive();
        _onlyContributor();

        _require(
            IIshtarGate(IBabController(controller).ishtarGate()).canAddStrategiesInAGarden(address(this), msg.sender),
            Errors.USER_CANNOT_ADD_STRATEGIES
        );
        _require(strategies.length < MAX_TOTAL_STRATEGIES, Errors.VALUE_TOO_HIGH);
        _require(_stratParams.length == 4, Errors.STRAT_PARAMS_LENGTH);
        address strategy =
            IStrategyFactory(IBabController(controller).strategyFactory()).createStrategy(
                _name,
                _symbol,
                msg.sender,
                address(this),
                _stratParams
            );
        strategyMapping[strategy] = true;
        totalStake = totalStake.add(_stratParams[1]);
        strategies.push(strategy);
        IStrategy(strategy).setData(_opTypes, _opIntegrations, _opEncodedDatas);
        isGardenStrategy[strategy] = true;
        emit AddStrategy(strategy, _name, _stratParams[3]);
    }

    /**
     * Allocates garden capital to an strategy
     *
     * @param _capital        Amount of capital to allocate to the strategy
     */
    function allocateCapitalToStrategy(uint256 _capital) external override {
        _onlyStrategy();
        _onlyActive();

        uint256 protocolMgmtFee = IBabController(controller).protocolManagementFee().preciseMul(_capital);
        _require(_capital.add(protocolMgmtFee) <= liquidReserve(), Errors.MIN_LIQUIDITY);

        // Take protocol mgmt fee
        _payProtocolFeeFromGarden(reserveAsset, protocolMgmtFee);

        // Send Capital to strategy
        IERC20(reserveAsset).safeTransfer(msg.sender, _capital);
    }

    /*
     * Remove an expire candidate from the strategy Array
     * @param _strategy      Strategy to remove
     */
    function expireCandidateStrategy(address _strategy) external override {
        _onlyStrategy();
        strategies = strategies.remove(_strategy);
        strategyMapping[_strategy] = false;
    }

    /*
     * Burns the stake of the strategist of a given strategy
     * @param _strategy      Strategy
     */
    function burnStrategistStake(address _strategist, uint256 _amount) external override {
        _onlyStrategy();
        if (_amount >= balanceOf(_strategist)) {
            // Avoid underflow condition
            _amount = balanceOf(_strategist);
        }
        _burn(_strategist, _amount);
    }

    /* ============ External Getter Functions ============ */

    /**
     * Gets current strategies
     *
     * @return  address[]        Returns list of addresses
     */

    function getStrategies() external view override returns (address[] memory) {
        return strategies;
    }

    /**
     * Gets finalized strategies
     *
     * @return  address[]        Returns list of addresses
     */

    function getFinalizedStrategies() external view override returns (address[] memory) {
        return finalizedStrategies;
    }

    function getContributor(address _contributor)
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        Contributor storage contributor = contributors[_contributor];
        uint256 contributorPower =
            rewardsDistributor.getContributorPower(
                address(this),
                _contributor,
                contributor.initialDepositAt,
                block.timestamp
            );
        uint256 balance = balanceOf(_contributor);
        uint256 lockedBalance = getLockedBalance(_contributor);
        return (
            contributor.lastDepositAt,
            contributor.initialDepositAt,
            contributor.claimedAt,
            contributor.claimedBABL,
            contributor.claimedRewards,
            contributor.totalDeposits > contributor.withdrawnSince
                ? contributor.totalDeposits.sub(contributor.withdrawnSince)
                : 0,
            balance,
            lockedBalance,
            contributorPower,
            contributor.nonce
        );
    }

    /**
     * Checks balance locked for strategists in active strategies
     *
     * @param _contributor                 Address of the account
     *
     * @return  uint256                    Returns the amount of locked garden tokens for the account
     */
    function getLockedBalance(address _contributor) public view override returns (uint256) {
        uint256 lockedAmount;
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            if (_contributor == strategy.strategist()) {
                lockedAmount = lockedAmount.add(strategy.stake());
            }
        }
        // Avoid overflows if off-chain voting system fails
        if (balanceOf(_contributor) < lockedAmount) lockedAmount = balanceOf(_contributor);
        return lockedAmount;
    }

    /* ============ Internal Functions ============ */
    /**
     * Gets liquid reserve available for to Garden.
     */
    function liquidReserve() private view returns (uint256) {
        uint256 reserve = IERC20(reserveAsset).balanceOf(address(this)).sub(reserveAssetRewardsSetAside);
        return reserve > keeperDebt ? reserve.sub(keeperDebt) : 0;
    }

    /**
     * Gets the total active capital currently invested in strategies
     *
     * @return uint256       Total amount active
     * @return uint256       Total amount active in the largest strategy
     * @return address       Address of the largest strategy
     */
    function _getActiveCapital()
        private
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        uint256 totalActiveCapital;
        uint256 maxAllocation;
        address maxStrategy = address(0);
        for (uint8 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            if (strategy.isStrategyActive()) {
                uint256 allocation = strategy.capitalAllocated();
                totalActiveCapital = totalActiveCapital.add(allocation);
                if (allocation > maxAllocation) {
                    maxAllocation = allocation;
                    maxStrategy = strategies[i];
                }
            }
        }
        return (totalActiveCapital, maxAllocation, maxStrategy);
    }

    /**
     * Pays the _feeQuantity from the _garden denominated in _token to the protocol fee recipient
     * @param _token                   Address of the token to pay with
     * @param _feeQuantity             Fee to transfer
     */
    function _payProtocolFeeFromGarden(address _token, uint256 _feeQuantity) private {
        IERC20(_token).safeTransfer(IBabController(controller).treasury(), _feeQuantity);
    }

    // Disable garden token transfers. Allow minting and burning.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 _amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, _amount);
        _require(
            from == address(0) ||
                to == address(0) ||
                (IBabController(controller).gardenTokensTransfersEnabled() && !privateGarden),
            Errors.GARDEN_TRANSFERS_DISABLED
        );
    }

    function _safeSendReserveAsset(address payable _to, uint256 _amount) private {
        if (reserveAsset == WETH) {
            // Check that the withdrawal is possible
            // Unwrap WETH if ETH balance lower than netFlowQuantity
            if (address(this).balance < _amount) {
                IWETH(WETH).withdraw(_amount.sub(address(this).balance));
            }
            // Send ETH
            Address.sendValue(_to, _amount);
        } else {
            // Send reserve asset
            IERC20(reserveAsset).safeTransfer(_to, _amount);
        }
    }

    function _getWithdrawalReserveQuantity(address _reserveAsset, uint256 _gardenTokenQuantity)
        private
        view
        returns (uint256)
    {}

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorDepositInfo(
        address _contributor,
        uint256 previousBalance,
        uint256 _reserveAssetQuantity
    ) private {
        Contributor storage contributor = contributors[_contributor];
        // If new contributor, create one, increment count, and set the current TS
        if (previousBalance == 0 || contributor.initialDepositAt == 0) {
            _require(totalContributors < maxContributors, Errors.MAX_CONTRIBUTORS);
            totalContributors = totalContributors.add(1);
            contributor.initialDepositAt = block.timestamp;
        }
        // We make checkpoints around contributor deposits to give the right rewards afterwards
        contributor.totalDeposits = contributor.totalDeposits.add(_reserveAssetQuantity);
        contributor.lastDepositAt = block.timestamp;
        contributor.nonce = contributor.nonce + 1;
        rewardsDistributor.updateGardenPowerAndContributor(address(this), _contributor, previousBalance, true, pid);
        pid++;
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorWithdrawalInfo(uint256 _netflowQuantity) private {
        Contributor storage contributor = contributors[msg.sender];
        // If sold everything
        if (balanceOf(msg.sender) == 0) {
            contributor.lastDepositAt = 0;
            contributor.initialDepositAt = 0;
            contributor.withdrawnSince = 0;
            contributor.totalDeposits = 0;
            totalContributors = totalContributors.sub(1);
        } else {
            contributor.withdrawnSince = contributor.withdrawnSince.add(_netflowQuantity);
        }
        rewardsDistributor.updateGardenPowerAndContributor(address(this), msg.sender, 0, false, pid);
        contributor.nonce = contributor.nonce + 1;
        pid++;
    }

    // solhint-disable-next-line
    receive() external payable {}
}

contract GardenV3 is Garden {}
