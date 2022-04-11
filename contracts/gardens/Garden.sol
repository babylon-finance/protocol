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
import {SignatureChecker} from '../lib/SignatureChecker.sol';

import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IStrategyFactory} from '../interfaces/IStrategyFactory.sol';
import {IGardenValuer} from '../interfaces/IGardenValuer.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IGarden, ICoreGarden} from '../interfaces/IGarden.sol';
import {IGardenNFT} from '../interfaces/IGardenNFT.sol';
import {IMardukGate} from '../interfaces/IMardukGate.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IHeart} from '../interfaces/IHeart.sol';
import {IERC1271} from '../interfaces/IERC1271.sol';

import {VTableBeaconProxy} from '../proxy/VTableBeaconProxy.sol';
import {VTableBeacon} from '../proxy/VTableBeacon.sol';

/**
 * @title BaseGarden
 *
 * User facing features of Garden plus BeaconProxy
 */
contract Garden is ERC20Upgradeable, ReentrancyGuard, VTableBeaconProxy, ICoreGarden, IERC1271 {
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

    using SignatureChecker for address;

    /* ============ Events ============ */

    // DO NOT TOUCH for the love of GOD
    event GardenDeposit(address indexed _to, uint256 reserveToken, uint256 reserveTokenQuantity, uint256 timestamp);
    event GardenWithdrawal(
        address indexed _from,
        address indexed _to,
        uint256 reserveToken,
        uint256 reserveTokenQuantity,
        uint256 timestamp
    );

    event RewardsForContributor(address indexed _contributor, uint256 indexed _amount);
    event BABLRewardsForContributor(address indexed _contributor, uint256 _rewards);
    event StakeBABLRewards(address indexed _contributor, uint256 _babl);

    /* ============ Constants ============ */

    // Wrapped ETH address
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IERC20 private constant BABL = IERC20(0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74);

    // Strategy cooldown period
    uint256 private constant MIN_COOLDOWN_PERIOD = 60 seconds;
    uint256 private constant MAX_COOLDOWN_PERIOD = 7 days;

    uint8 private constant MAX_EXTRA_CREATORS = 4;
    uint256 private constant EARLY_WITHDRAWAL_PENALTY = 25e15;
    uint256 private constant TEN_PERCENT = 1e17;

    bytes32 private constant DEPOSIT_BY_SIG_TYPEHASH =
        keccak256(
            'DepositBySig(uint256 _amountIn,uint256 _minAmountOut,uint256 _nonce,uint256 _maxFee,address _to,address _referrer)'
        );
    bytes32 private constant WITHDRAW_BY_SIG_TYPEHASH =
        keccak256(
            'WithdrawBySig(uint256 _amountIn,uint256 _minAmountOut,uint256,_nonce,uint256 _maxFee,uint256 _withPenalty)'
        );
    bytes32 private constant REWARDS_BY_SIG_TYPEHASH =
        keccak256('RewardsBySig(uint256 _babl,uint256 _profits,uint256 _nonce,uint256 _maxFee)');

    bytes32 private constant STAKE_REWARDS_BY_SIG_TYPEHASH =
        keccak256(
            'StakeRewardsBySig(uint256 _babl,uint256 _profits,uint256 _minAmountOut,uint256 _nonce,uint256 _nonceHeart,uint256 _maxFee,address _to)'
        );

    uint256 private constant CLAIM_BY_SIG_CAP = 5_500e18; // 5.5K BABL cap per user per bySig tx

    /* ============ Structs ============ */

    /* ============ State Variables ============ */

    // Reserve Asset of the garden
    address public override reserveAsset;

    // Address of the controller
    IBabController public override controller;

    // Address of the rewards distributor
    IRewardsDistributor private rewardsDistributor;

    // The person that creates the garden
    address public override creator;

    bool private active; // DEPRECATED;
    bool public override privateGarden;

    uint256 private principal; // DEPRECATED;

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
    mapping(address => IGarden.Contributor) private contributors;
    uint256 public override totalContributors;
    uint256 private maxContributors; // DEPRECATED
    uint256 public override maxDepositLimit; // Limits the amount of deposits

    uint256 public override gardenInitializedAt; // Garden Initialized at timestamp
    // Number of garden checkpoints used to control the garden power and each contributor power with accuracy
    uint256 private pid;

    // Min contribution in the garden
    uint256 public override minContribution; //wei
    uint256 private minGardenTokenSupply; // DEPRECATED

    // Strategies variables
    uint256 public override totalStake;
    uint256 public override minVotesQuorum; // 10%. (0.01% = 1e14, 1% = 1e16)
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
    uint256 public override keeperDebt;
    uint256 public override totalKeeperFees;

    // Allow public strategy creators for certain gardens
    bool public override publicStrategists;

    // Allow public strategy stewards for certain gardens
    bool public override publicStewards;

    // Addresses for extra creators
    address[MAX_EXTRA_CREATORS] public override extraCreators;

    // last recorded price per share of the garden during deposit or withdrawal operation
    uint256 public override lastPricePerShare;

    // last recorded time of the deposit or withdraw in seconds
    uint256 public override lastPricePerShareTS;

    // Decay rate of the slippage for pricePerShare over time
    uint256 public override pricePerShareDecayRate;

    // Base slippage for pricePerShare of the garden
    uint256 public override pricePerShareDelta;

    // Whether or not governance has verified and the category
    uint256 public override verifiedCategory;

    // Variable that overrides the depositLock with a global one
    uint256 public override hardlockStartsAt;

    // EIP-1271 signer
    address private signer;
    // Variable that controls whether the NFT can be minted after x amount of time
    uint256 public override canMintNftAfter;

    /* ============ Modifiers ============ */

    function _onlyUnpaused() private view {
        // Do not execute if Globally or individually paused
        _require(!controller.isPaused(address(this)), Errors.ONLY_UNPAUSED);
    }

    /**
     * Check if msg.sender is keeper
     */
    function _onlyKeeperAndFee(uint256 _fee, uint256 _maxFee) private view {
        _require(controller.isValidKeeper(msg.sender), Errors.ONLY_KEEPER);
        _require(_fee <= _maxFee, Errors.FEE_TOO_HIGH);
    }

    /**
     * Check if is a valid _signer with a valid nonce
     */
    function _onlyValidSigner(
        address _signer,
        address _to,
        uint256 _nonce,
        bytes32 _hash,
        bytes memory _signature
    ) private view {
        _require(contributors[_to].nonce == _nonce, Errors.INVALID_NONCE);
        // to prevent replay attacks
        _require(_signer.isValidSignatureNow(_hash, _signature), Errors.INVALID_SIGNER);
    }

    function _onlyNonZero(address _address) private pure {
        _require(_address != address(0), Errors.ADDRESS_IS_ZERO);
    }

    /* ============ Constructor ============ */

    constructor(VTableBeacon _beacon) VTableBeaconProxy(_beacon) {}

    /* ============ External Functions ============ */

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
     * @param _referrer               The user that referred the deposit
     */
    function deposit(
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _to,
        address _referrer
    ) external payable override nonReentrant {
        // calculate pricePerShare
        // if there are no strategies then NAV === liquidReserve
        _internalDeposit(_amountIn, _minAmountOut, _to, msg.sender, _getPricePerShare(), minContribution, _referrer);
    }

    /**
     * @notice
     *   Deposits the _amountIn in reserve asset into the garden. Gurantee to
     *   recieve at least _minAmountOut.
     * @param _amountIn               Amount of the reserve asset that is received from contributor.
     * @param _minAmountOut           Min amount of Garden shares to receive by contributor.
     * @param _nonce                  Current nonce to prevent replay attacks.
     * @param _maxFee                 Max fee user is willing to pay keeper. Fee is
     *                                substracted from the withdrawn amount. Fee is
     *                                expressed in reserve asset.
     * @param _pricePerShare          Price per share of the garden calculated off-chain by Keeper.
     * @param _to                     Address to mint shares to.
     * @param _fee                    Actual fee keeper demands. Have to be less than _maxFee.
     * @param _signer                 The user to who signed the signature.
     * @param _referrer               The user that referred the deposit
     * @param _signature              Signature by the user to verify deposit parmas.
     */
    function depositBySig(
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint256 _nonce,
        uint256 _maxFee,
        address _to,
        uint256 _pricePerShare,
        uint256 _fee,
        address _signer,
        address _referrer,
        bytes memory _signature
    ) external override nonReentrant {
        _onlyKeeperAndFee(_fee, _maxFee);

        bytes32 hash =
            keccak256(
                abi.encode(
                    DEPOSIT_BY_SIG_TYPEHASH,
                    address(this),
                    _amountIn,
                    _minAmountOut,
                    _nonce,
                    _maxFee,
                    _to,
                    _referrer
                )
            )
                .toEthSignedMessageHash();
        _onlyValidSigner(_signer, _to, _nonce, hash, _signature);

        // If a Keeper fee is greater than zero then reduce user shares to
        // exchange and pay keeper the fee.
        if (_fee > 0) {
            // account for non 18 decimals ERC20 tokens, e.g. USDC
            uint256 feeShares = _reserveToShares(_fee, _pricePerShare);
            _internalDeposit(
                _amountIn.sub(_fee),
                _minAmountOut.sub(feeShares),
                _to,
                _signer,
                _pricePerShare,
                minContribution > _fee ? minContribution.sub(_fee) : 0,
                _referrer
            );
            // pay Keeper the fee
            IERC20(reserveAsset).safeTransferFrom(_signer, msg.sender, _fee);
        } else {
            _internalDeposit(_amountIn, _minAmountOut, _to, _signer, _pricePerShare, minContribution, _referrer);
        }
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
     * @param _amountIn         Quantity of the garden token to withdrawal
     * @param _minAmountOut     Min quantity of reserve asset to receive
     * @param _to               Address to send component assets to
     * @param _withPenalty      Whether or not this is an immediate withdrawal
     * @param _unwindStrategy   Strategy to unwind
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

        _require(msg.sender == _to, Errors.ONLY_CONTRIBUTOR);
        _withdrawInternal(
            _amountIn,
            _minAmountOut,
            _to,
            _withPenalty,
            _unwindStrategy,
            _getPricePerShare(),
            _withPenalty ? IStrategy(_unwindStrategy).getNAV() : 0,
            0
        );
    }

    /**
     * @notice
     *   Exchanges user's gardens shairs for amount in reserve asset. This
     *   method allows users to leave garden and reclaim their inital investment
     *   plus profits or losses.
     * @dev
     *   Should be called instead of the `withdraw` to save gas due to
     *   pricePerShare caculated off-chain. Doesn't allow to unwind strategies
     *   contrary to `withdraw`.
     *   The Keeper fee is paid out of user's shares.
     *   The true _minAmountOut is actually _minAmountOut - _maxFee due to the
     *   Keeper fee.
     * @param _amountIn        Quantity of the garden tokens to withdraw.
     * @param _minAmountOut    Min quantity of reserve asset to receive.
     * @param _nonce           Current nonce to prevent replay attacks.
     * @param _maxFee          Max fee user is willing to pay keeper. Fee is
     *                         substracted from the withdrawn amount. Fee is
     *                         expressed in reserve asset.
     * @param _withPenalty     Whether or not this is an immediate withdrawal
     * @param _unwindStrategy  Strategy to unwind
     * @param _pricePerShare   Price per share of the garden calculated off-chain by Keeper.
     * @param _strategyNAV     NAV of the strategy to unwind.
     * @param _fee             Actual fee keeper demands. Have to be less than _maxFee.
     * @param _signer          The user to who signed the signature
     * @param _signature       Signature by the user to verify withdraw parmas.
     */
    function withdrawBySig(
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint256 _nonce,
        uint256 _maxFee,
        bool _withPenalty,
        address _unwindStrategy,
        uint256 _pricePerShare,
        uint256 _strategyNAV,
        uint256 _fee,
        address _signer,
        bytes memory _signature
    ) external override nonReentrant {
        _onlyKeeperAndFee(_fee, _maxFee);

        bytes32 hash =
            keccak256(
                abi.encode(
                    WITHDRAW_BY_SIG_TYPEHASH,
                    address(this),
                    _amountIn,
                    _minAmountOut,
                    _nonce,
                    _maxFee,
                    _withPenalty
                )
            )
                .toEthSignedMessageHash();

        _onlyValidSigner(_signer, _signer, _nonce, hash, _signature);

        _withdrawInternal(
            _amountIn,
            _minAmountOut.sub(_maxFee),
            payable(_signer),
            _withPenalty,
            _unwindStrategy,
            _pricePerShare,
            _strategyNAV,
            _fee
        );
    }

    /**
     * User can claim the rewards from the strategies that his principal
     * was invested in.
     */
    function claimReturns(address[] calldata _finalizedStrategies) external override nonReentrant {
        uint256[] memory rewards = new uint256[](8);
        rewards = rewardsDistributor.getRewards(address(this), msg.sender, _finalizedStrategies);
        _sendRewardsInternal(msg.sender, rewards[5], rewards[6], false);
    }

    /**
     * User can claim the rewards from the strategies that his principal
     * was invested in and stake BABL into Heart Garden
     */
    function claimAndStakeReturns(uint256 _minAmountOut, address[] calldata _finalizedStrategies)
        external
        override
        nonReentrant
    {
        uint256[] memory rewards = new uint256[](8);
        rewards = rewardsDistributor.getRewards(address(this), msg.sender, _finalizedStrategies);
        IGarden heartGarden = IGarden(address(IHeart(controller.heart()).heartGarden()));
        // User non BABL rewards are sent to user wallet (_profits)
        // User BABL rewards are sent to this garden from RD to stake them into Heart Garden
        // on behalf of user
        _sendRewardsInternal(msg.sender, rewards[5], rewards[6], true); // true = stake babl rewards, false = no stake
        _approveBABL(address(heartGarden), rewards[5]);
        heartGarden.deposit(rewards[5], _minAmountOut, msg.sender, address(0));
        emit StakeBABLRewards(msg.sender, rewards[5]);
    }

    /**
     * @notice
     *   This method allows users
     *   to claim their rewards either profits or BABL.
     * @dev
     *   Should be called instead of the `claimRewards at RD` to save gas due to
     *   getRewards caculated off-chain.
     *   The Keeper fee is paid out of user's reserveAsset and it is calculated off-chain.
     *
     * @param _babl            BABL rewards from mining program.
     * @param _profits         Profit rewards in reserve asset.
     * @param _nonce           Current nonce to prevent replay attacks.
     * @param _maxFee          Max fee user is willing to pay keeper. Fee is
     *                         substracted from user wallet in reserveAsset. Fee is
     *                         expressed in reserve asset.
     * @param _fee             Actual fee keeper demands. Have to be less than _maxFee.
     * @param _signer          The user to who signed the signature
     * @param _signature       Signature by the user to verify claim parmas.
     */
    function claimRewardsBySig(
        uint256 _babl,
        uint256 _profits,
        uint256 _nonce,
        uint256 _maxFee,
        uint256 _fee,
        address _signer,
        bytes memory _signature
    ) external override nonReentrant {
        _onlyKeeperAndFee(_fee, _maxFee);
        bytes32 hash =
            keccak256(abi.encode(REWARDS_BY_SIG_TYPEHASH, address(this), _babl, _profits, _nonce, _maxFee))
                .toEthSignedMessageHash();
        _require(_fee > 0, Errors.FEE_TOO_LOW);

        _onlyValidSigner(_signer, _signer, _nonce, hash, _signature);
        _require(_babl <= CLAIM_BY_SIG_CAP, Errors.MAX_BABL_CAP_REACHED);
        // pay to Keeper the fee to execute the tx on behalf
        IERC20(reserveAsset).safeTransferFrom(_signer, msg.sender, _fee);
        _sendRewardsInternal(_signer, _babl, _profits, false);
    }

    /**
     * @notice
     *   This method allows users
     *   to stake their BABL rewards and claim their profit rewards.
     * @dev
     *   Should be called instead of the `claimAndStakeReturns` to save gas due to
     *   getRewards caculated off-chain.
     *   The Keeper fee is paid out of user's reserveAsset and it is calculated off-chain.
     *
     * @param _babl            BABL rewards from mining program.
     * @param _profits         Profit rewards in reserve asset.
     * @param _minAmountOut    Minimum hBABL as part of the Heart Garden BABL staking
     * @param _nonce           Current nonce of user in the claiming garden at to prevent replay attacks.
     * @param _nonceHeart      Current nonce of user in Heart Garden to prevent replay attacks.
     * @param _maxFee          Max fee user is willing to pay keeper. Fee is
     *                         substracted from user wallet in reserveAsset. Fee is
     *                         expressed in reserve asset.
     * @param _fee             Actual fee keeper demands. Have to be less than _maxFee.
     * @param _pricePerShare   Price per share of Heart Garden
     * @param _signer          Signer of the tx
     * @param _signature       Signature of signer
     */
    function claimAndStakeRewardsBySig(
        uint256 _babl,
        uint256 _profits,
        uint256 _minAmountOut,
        uint256 _nonce,
        uint256 _nonceHeart,
        uint256 _maxFee,
        uint256 _pricePerShare,
        uint256 _fee,
        address _signer,
        bytes memory _signature
    ) external override nonReentrant {
        _onlyKeeperAndFee(_fee, _maxFee);
        IGarden heartGarden = IHeart(controller.heart()).heartGarden();
        bytes32 hash =
            keccak256(
                abi.encode(
                    STAKE_REWARDS_BY_SIG_TYPEHASH,
                    address(heartGarden),
                    _babl,
                    _profits,
                    _minAmountOut,
                    _nonce,
                    _nonceHeart,
                    _maxFee,
                    _signer
                )
            )
                .toEthSignedMessageHash();
        _onlyValidSigner(_signer, _signer, _nonce, hash, _signature);
        _require(_fee > 0, Errors.FEE_TOO_LOW);
        _require(_babl <= CLAIM_BY_SIG_CAP, Errors.MAX_BABL_CAP_REACHED);

        // pay to Keeper the fee to execute the tx on behalf
        IERC20(reserveAsset).safeTransferFrom(_signer, msg.sender, _fee);

        // User non BABL rewards are sent to user wallet (_profits)
        // User BABL rewards are sent to this garden from RD to later stake them into Heart Garden
        // on behalf of the user
        _sendRewardsInternal(_signer, _babl, _profits, true); // true = stake babl rewards, false = no stake
        _approveBABL(address(heartGarden), _babl);
        // grant permission to deposit
        signer = _signer;
        // Now this garden makes a deposit on Heart Garden on behalf of user
        heartGarden.stakeBySig(
            _babl,
            _profits,
            _minAmountOut,
            _nonce,
            _nonceHeart,
            _maxFee,
            _signer,
            _pricePerShare,
            address(this),
            _signature
        );
        // revoke permission to deposit
        signer = address(0);
        emit StakeBABLRewards(_signer, _babl);
    }

    /**
     * @notice
     *   Deposits the _amountIn in reserve asset into the garden. Guarantee to
     *   receive at least _minAmountOut.
     * @param _amountIn               Amount of the reserve asset that is received from contributor.
     * @param _profits                Amount of the reserve asset that is received from contributor.
     * @param _minAmountOut           Min amount of Garden shares to receive by contributor.
     * @param _nonce                  Current nonce to prevent replay attacks.
     * @param _nonceHeart             Current nonce to prevent replay attacks.
     * @param _maxFee                 Max fee user is willing to pay keeper. Fee is
     *                                substracted from the withdrawn amount. Fee is
     *                                expressed in reserve asset.
     * @param _pricePerShare          Price per share of the garden calculated off-chain by Keeper.
     * @param _to                     Address to mint shares to.
     * @param _signer                 The user to who signed the signature.
     * @param _signature              Signature by the user to verify deposit params.
     */
    function stakeBySig(
        uint256 _amountIn,
        uint256 _profits,
        uint256 _minAmountOut,
        uint256 _nonce,
        uint256 _nonceHeart,
        uint256 _maxFee,
        address _to,
        uint256 _pricePerShare,
        address _signer,
        bytes memory _signature
    ) external override nonReentrant {
        _require(controller.isGarden(msg.sender), Errors.ONLY_ACTIVE_GARDEN);
        _require(address(this) == address(IHeart(controller.heart()).heartGarden()), Errors.ONLY_HEART_GARDEN);

        bytes32 hash =
            keccak256(
                abi.encode(
                    STAKE_REWARDS_BY_SIG_TYPEHASH,
                    address(this),
                    _amountIn,
                    _profits,
                    _minAmountOut,
                    _nonce,
                    _nonceHeart,
                    _maxFee,
                    _to
                )
            )
                .toEthSignedMessageHash();
        _onlyValidSigner(_signer, _to, _nonceHeart, hash, _signature);

        // Keeper fee must have been paid in the original garden
        _internalDeposit(_amountIn, _minAmountOut, _to, _signer, _pricePerShare, minContribution, address(0));
    }

    /**
     * @notice
     *   Allows Garden contributors to claim an NFT.
     */
    function claimNFT() external override {
        _require(balanceOf(msg.sender) > minContribution, Errors.ONLY_CONTRIBUTOR);
        IGarden.Contributor storage contributor = contributors[msg.sender];
        _require(
            canMintNftAfter > 0 && block.timestamp.sub(contributor.initialDepositAt) > canMintNftAfter,
            Errors.CLAIM_GARDEN_NFT
        );
        IGardenNFT(controller.gardenNFT()).grantGardenNFT(msg.sender);
    }

    /**
     * Implements EIP-1271
     */
    function isValidSignature(bytes32 _hash, bytes memory _signature) public view override returns (bytes4 magicValue) {
        return
            ECDSA.recover(_hash, _signature) == signer && signer != address(0)
                ? this.isValidSignature.selector
                : bytes4(0);
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
            uint256 lastDepositAt,
            uint256 initialDepositAt,
            uint256 claimedAt,
            uint256 claimedBABL,
            uint256 claimedRewards,
            uint256 withdrawnSince,
            uint256 totalDeposits,
            uint256 nonce,
            uint256 lockedBalance
        )
    {
        IGarden.Contributor memory contributor = contributors[_contributor];
        return (
            contributor.lastDepositAt,
            contributor.initialDepositAt,
            contributor.claimedAt,
            contributor.claimedBABL,
            contributor.claimedRewards,
            contributor.withdrawnSince,
            contributor.totalDeposits,
            contributor.nonce,
            contributor.lockedBalance
        );
    }

    /* ============ Internal Functions ============ */

    function _sharesToReserve(uint256 _shares, uint256 _pricePerShare) internal view returns (uint256) {
        // in case of USDC that would with 6 decimals
        return _shares.preciseMul(_pricePerShare).preciseMul(10**ERC20Upgradeable(reserveAsset).decimals());
    }

    function _reserveToShares(uint256 _reserve, uint256 _pricePerShare) internal view returns (uint256) {
        return _reserve.preciseDiv(10**ERC20Upgradeable(reserveAsset).decimals()).preciseDiv(_pricePerShare);
    }

    function _withdrawInternal(
        uint256 _amountIn,
        uint256 _minAmountOut,
        address payable _to,
        bool _withPenalty,
        address _unwindStrategy,
        uint256 _pricePerShare,
        uint256 _strategyNAV,
        uint256 _fee
    ) internal {
        _onlyUnpaused();
        _checkLastPricePerShare(_pricePerShare);

        uint256 prevBalance = balanceOf(_to);
        _require(prevBalance > 0, Errors.ONLY_CONTRIBUTOR);
        // Flashloan protection
        _require(block.timestamp.sub(_getLastDepositAt(_to)) >= depositHardlock, Errors.DEPOSIT_HARDLOCK);

        // Strategists cannot withdraw locked stake while in active strategies
        // Withdrawal amount has to be equal or less than msg.sender balance minus the locked balance
        // any amountIn higher than user balance is treated as withdrawAll
        uint256 lockedBalance = contributors[_to].lockedBalance;
        _amountIn = _amountIn > prevBalance.sub(lockedBalance) ? prevBalance.sub(lockedBalance) : _amountIn;
        _require(_amountIn <= prevBalance.sub(lockedBalance), Errors.TOKENS_STAKED);

        uint256 amountOut = _sharesToReserve(_amountIn, _pricePerShare);

        // if withPenaltiy then unwind strategy
        if (_withPenalty && !(_liquidReserve() >= amountOut)) {
            amountOut = amountOut.sub(amountOut.preciseMul(EARLY_WITHDRAWAL_PENALTY));
            // When unwinding a strategy, a slippage on integrations will result in receiving less tokens
            // than desired so we have have to account for this with a 5% slippage.
            // TODO: if there is more than 5% slippage that will block
            // withdrawal
            _onlyNonZero(_unwindStrategy);
            IStrategy(_unwindStrategy).unwindStrategy(amountOut.add(amountOut.preciseMul(5e16)), _strategyNAV);
        }

        _require(amountOut >= _minAmountOut && _amountIn > 0, Errors.RECEIVE_MIN_AMOUNT);

        _require(_liquidReserve() >= amountOut, Errors.MIN_LIQUIDITY);

        _burn(_to, _amountIn);
        _safeSendReserveAsset(_to, amountOut.sub(_fee));
        if (_fee > 0) {
            // If fee > 0 pay Accountant
            IERC20(reserveAsset).safeTransfer(msg.sender, _fee);
        }
        _updateContributorWithdrawalInfo(_to, amountOut, prevBalance, balanceOf(_to), _amountIn);
        contributors[_to].nonce++;

        emit GardenWithdrawal(_to, _to, amountOut, _amountIn, block.timestamp);
    }

    function _getPricePerShare() internal view returns (uint256) {
        if (strategies.length == 0) {
            return
                totalSupply() == 0
                    ? PreciseUnitMath.preciseUnit()
                    : _liquidReserve().preciseDiv(uint256(10)**ERC20Upgradeable(reserveAsset).decimals()).preciseDiv(
                        totalSupply()
                    );
        } else {
            // Get valuation of the Garden with the quote asset as the reserve asset.
            return IGardenValuer(controller.gardenValuer()).calculateGardenValuation(address(this), reserveAsset);
        }
    }

    function _internalDeposit(
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _to,
        address _from,
        uint256 _pricePerShare,
        uint256 _minContribution,
        address _referrer
    ) private {
        _onlyUnpaused();
        _onlyNonZero(_to);
        _checkLastPricePerShare(_pricePerShare);

        bool canDeposit = !privateGarden || IMardukGate(controller.mardukGate()).canJoinAGarden(address(this), _to);
        _require(_isCreator(_to) || canDeposit, Errors.USER_CANNOT_JOIN);

        if (maxDepositLimit > 0) {
            // This is wrong; but calculate principal would be gas expensive
            _require(_liquidReserve().add(_amountIn) <= maxDepositLimit, Errors.MAX_DEPOSIT_LIMIT);
        }

        _require(_amountIn >= _minContribution, Errors.MIN_CONTRIBUTION);

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

        // Adds rewards
        controller.addAffiliateReward(_from, _referrer != address(0) ? _referrer : _from, _amountIn);
        // We need to update at Rewards Distributor smartcontract for rewards accurate calculations
        _updateContributorDepositInfo(_to, previousBalance, _amountIn, sharesToMint);
        contributors[_to].nonce++;

        emit GardenDeposit(_to, _minAmountOut, _amountIn, block.timestamp);
    }

    /**
     * @param _contributor     Contributor address to send rewards to
     * @param _babl            BABL rewards from mining program.
     * @param _profits         Profit rewards in reserve asset.
     * @param _stake           Whether user wants to stake in Heart or not its BABL rewards.
     */
    function _sendRewardsInternal(
        address _contributor,
        uint256 _babl,
        uint256 _profits,
        bool _stake
    ) internal {
        _onlyUnpaused();
        IGarden.Contributor storage contributor = contributors[_contributor];
        _require(contributor.nonce > 0, Errors.ONLY_CONTRIBUTOR); // have been user garden
        _require(_babl > 0 || _profits > 0, Errors.NO_REWARDS_TO_CLAIM);
        _require(reserveAssetRewardsSetAside >= _profits, Errors.RECEIVE_MIN_AMOUNT);
        // Avoid replay attack between claimRewardsBySig and claimRewards or even between 2 of each
        contributor.nonce++;
        _require(block.timestamp > contributor.claimedAt, Errors.ALREADY_CLAIMED);
        contributor.claimedAt = block.timestamp; // Checkpoint of this claim
        if (_profits > 0) {
            contributor.claimedRewards = contributor.claimedRewards.add(_profits); // Rewards claimed properly
            reserveAssetRewardsSetAside = reserveAssetRewardsSetAside.sub(_profits);
            _safeSendReserveAsset(payable(_contributor), _profits);
            emit RewardsForContributor(_contributor, _profits);
        }
        if (_babl > 0) {
            // If _stake = true, the BABL is sent first to this garden
            // then it is deposited into Heart Garden on behalf of user
            uint256 bablSent = rewardsDistributor.sendBABLToContributor(_stake ? address(this) : _contributor, _babl);
            contributor.claimedBABL = contributor.claimedBABL.add(bablSent); // BABL Rewards claimed properly
            emit BABLRewardsForContributor(_contributor, bablSent);
        }
    }

    /**
     * Gets liquid reserve available for to Garden.
     */
    function _liquidReserve() private view returns (uint256) {
        uint256 reserve = IERC20(reserveAsset).balanceOf(address(this)).sub(reserveAssetRewardsSetAside);
        return reserve > keeperDebt ? reserve.sub(keeperDebt) : 0;
    }

    // Disable garden token transfers. Allow minting and burning.
    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual override {
        super._beforeTokenTransfer(_from, _to, _amount);
        _require(
            _from == address(0) || _to == address(0) || (controller.gardenTokensTransfersEnabled() && !privateGarden),
            Errors.GARDEN_TRANSFERS_DISABLED
        );

        if (_from != address(0) && _to != address(0)) {
            uint256 fromBalance = balanceOf(_from);

            uint256 lockedBalance = contributors[_from].lockedBalance;
            _require(fromBalance.sub(lockedBalance) >= _amount, Errors.TOKENS_STAKED);

            _updateContributorWithdrawalInfo(_from, 0, fromBalance, fromBalance.sub(_amount), _amount);
            _updateContributorDepositInfo(_to, balanceOf(_to), 0, _amount);
        }
    }

    function _safeSendReserveAsset(address payable _to, uint256 _amount) private {
        if (reserveAsset == WETH) {
            // Check that the withdrawal is possible
            // Unwrap WETH if ETH balance lower than amount
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

    /**
     * Approves BABL staking amount for claim and stake rewards
     * Only used to approve Heart Garden to stake
     */
    function _approveBABL(address _garden, uint256 _amount) internal {
        IERC20 bablToken = IERC20(address(rewardsDistributor.babltoken()));
        _require(bablToken.balanceOf(address(this)) >= _amount, Errors.NOT_ENOUGH_BABL);
        bablToken.safeApprove(address(_garden), _amount);
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorDepositInfo(
        address _contributor,
        uint256 _previousBalance,
        uint256 _amountIn,
        uint256 _sharesIn
    ) private {
        IGarden.Contributor storage contributor = contributors[_contributor];
        // If new contributor, create one, increment count, and set the current TS
        if (_previousBalance == 0 || contributor.initialDepositAt == 0) {
            totalContributors = totalContributors.add(1);
            contributor.initialDepositAt = block.timestamp;
        }
        // We make checkpoints around contributor deposits to give the right rewards afterwards
        contributor.totalDeposits = contributor.totalDeposits.add(_amountIn);
        contributor.lastDepositAt = block.timestamp;
        // RD checkpoint for accurate rewards
        rewardsDistributor.updateGardenPowerAndContributor(
            address(this),
            _contributor,
            _previousBalance,
            _sharesIn,
            true // true = deposit , false = withdraw
        );
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorWithdrawalInfo(
        address _contributor,
        uint256 _amountOut,
        uint256 _previousBalance,
        uint256 _balance,
        uint256 _tokensToBurn
    ) private {
        IGarden.Contributor storage contributor = contributors[_contributor];
        // If withdrawn everything
        if (_balance == 0) {
            contributor.lastDepositAt = 0;
            contributor.initialDepositAt = 0;
            contributor.withdrawnSince = 0;
            contributor.totalDeposits = 0;
            totalContributors = totalContributors.sub(1);
        } else {
            contributor.withdrawnSince = contributor.withdrawnSince.add(_amountOut);
        }
        // RD checkpoint for accurate rewards
        rewardsDistributor.updateGardenPowerAndContributor(
            address(this),
            _contributor,
            _previousBalance,
            _tokensToBurn,
            false // true = deposit , false = withdraw
        );
    }

    // Checks if an address is a creator
    function _isCreator(address _creator) private view returns (bool) {
        return
            _creator != address(0) &&
            (extraCreators[0] == _creator ||
                extraCreators[1] == _creator ||
                extraCreators[2] == _creator ||
                extraCreators[3] == _creator ||
                _creator == creator);
    }

    /**
      @notice
        Validates that pricePerShare is within acceptable range; if not reverts
      @dev
        Allowed slippage between deposits and withdrawals in terms of the garden price per share is:

        slippage = lastPricePerShare % (pricePerShareDelta + timePast * pricePerShareDecayRate);

        For example, if lastPricePerShare is 1e18 and slippage is 10% then deposits with pricePerShare between
        9e17 and 11e17 allowed immediately. After one year (100% change in time) and with a decay rate 1x;
        deposits between 5e17 and 2e18 are possible. Different gardens should have different settings for
        slippage and decay rate due to various volatility of the strategies. For example, stable gardens
        would have low slippage and decay rate while some moonshot gardens may have both of them
        as high as 100% and 10x.
      @param _pricePerShare  Price of the graden share to validate against historical data
    */
    function _checkLastPricePerShare(uint256 _pricePerShare) private {
        uint256 slippage = pricePerShareDelta > 0 ? pricePerShareDelta : 25e16;
        uint256 decay = pricePerShareDecayRate > 0 ? pricePerShareDecayRate : 1e18;
        // if no previous record then just pass the check
        if (lastPricePerShare != 0) {
            slippage = slippage.add(block.timestamp.sub(lastPricePerShareTS).preciseDiv(365 days).preciseMul(decay));
            if (_pricePerShare > lastPricePerShare) {
                _require(
                    _pricePerShare.sub(lastPricePerShare) <= lastPricePerShare.preciseMul(slippage),
                    Errors.PRICE_PER_SHARE_WRONG
                );
            } else {
                _require(
                    lastPricePerShare.sub(_pricePerShare) <=
                        lastPricePerShare.sub(lastPricePerShare.preciseDiv(slippage.add(1e18))),
                    Errors.PRICE_PER_SHARE_WRONG
                );
            }
        }
        lastPricePerShare = _pricePerShare;
        lastPricePerShareTS = block.timestamp;
    }

    // Assign extra creators
    function _assignExtraCreator(uint8 _index, address _newCreator) private {
        _require(!_isCreator(_newCreator), Errors.NEW_CREATOR_MUST_NOT_EXIST);
        _require(extraCreators[_index] == address(0), Errors.NEW_CREATOR_MUST_NOT_EXIST);
        extraCreators[_index] = _newCreator;
    }

    function _getLastDepositAt(address _to) private view returns (uint256) {
        return hardlockStartsAt > contributors[_to].lastDepositAt ? hardlockStartsAt : contributors[_to].lastDepositAt;
    }
}

contract GardenV20 is Garden {
    constructor(VTableBeacon _beacon) Garden(_beacon) {}
}
