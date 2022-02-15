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

    // DO NOT TOUCH for the love of GOD
    event GardenDeposit(address indexed _to, uint256 reserveToken, uint256 reserveTokenQuantity, uint256 timestamp);
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

    // Strategy cooldown period
    uint256 private constant MIN_COOLDOWN_PERIOD = 60 seconds;
    uint256 private constant MAX_COOLDOWN_PERIOD = 7 days;

    uint8 private constant MAX_EXTRA_CREATORS = 4;
    uint256 private constant EARLY_WITHDRAWAL_PENALTY = 25e15;
    uint256 private constant MAX_TOTAL_STRATEGIES = 20; // Max number of strategies
    uint256 private constant TEN_PERCENT = 1e17;

    bytes32 private constant DEPOSIT_BY_SIG_TYPEHASH =
        keccak256('DepositBySig(uint256 _amountIn,uint256 _minAmountOut,bool _mintNft,uint256 _nonce,uint256 _maxFee)');
    bytes32 private constant WITHDRAW_BY_SIG_TYPEHASH =
        keccak256(
            'WithdrawBySig(uint256 _amountIn,uint256 _minAmountOut,uint256,_nonce,uint256 _maxFee,uint256 _withPenalty)'
        );
    bytes32 private constant REWARDS_BY_SIG_TYPEHASH =
        keccak256('RewardsBySig(uint256 _babl,uint256 _profits,uint256 _nonce,uint256 _maxFee)');

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
    mapping(address => Contributor) private contributors;
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
    uint256 public override keeperDebt;
    uint256 public override totalKeeperFees;

    // Allow public strategy creators for certain gardens
    bool public override publicStrategists;

    // Allow public strategy stewards for certain gardens
    bool public override publicStewards;

    // Addresses for extra creators
    address[MAX_EXTRA_CREATORS] public override extraCreators;

    // last recorded price per share of the garden during deposit or withdrawal operation
    uint256 public lastPricePerShare;

    // last recorded time of the deposit or withdraw in seconds
    uint256 public lastPricePerShareTS;

    // Decay rate of the slippage for pricePerShare over time
    uint256 public pricePerShareDecayRate;

    // Base slippage for pricePerShare of the garden
    uint256 public pricePerShareSlippage;

    /* ============ Modifiers ============ */

    function _onlyUnpaused() private view {
        // Do not execute if Globally or individually paused
        _require(!controller.isPaused(address(this)), Errors.ONLY_UNPAUSED);
    }

    /**
     * Throws if the sender is not an strategy of this garden
     */
    function _onlyStrategy() private view {
        _require(strategyMapping[msg.sender], Errors.ONLY_STRATEGY);
    }

    /**
     * Checks if the address passed is a creator in the garden
     */
    function _onlyCreator(address _creator) private view {
        _require(_isCreator(_creator), Errors.ONLY_CREATOR);
    }

    /**
     * Check if msg.sender is keeper
     */
    function _onlyKeeperAndFee(uint256 _fee, uint256 _maxFee) private view {
        _require(controller.isValidKeeper(msg.sender), Errors.ONLY_KEEPER);
        _require(_fee <= _maxFee, Errors.FEE_TOO_HIGH);
    }

    /**
     * Check if is a valid signer with a valid nonce
     */
    function _onlyValidSigner(address _signer, uint256 _nonce) private view {
        // Used in by sig
        _require(_signer != address(0), Errors.INVALID_SIGNER);
        // to prevent replay attacks
        _require(contributors[_signer].nonce == _nonce, Errors.INVALID_NONCE);
    }

    function _onlyNonZero(address _address) private pure {
        _require(_address != address(0), Errors.ADDRESS_IS_ZERO);
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
        IBabController _controller,
        address _creator,
        string memory _name,
        string memory _symbol,
        uint256[] calldata _gardenParams,
        uint256 _initialContribution,
        bool[] memory _publicGardenStrategistsStewards
    ) public payable override initializer {
        __ERC20_init(_name, _symbol);

        controller = _controller;
        reserveAsset = _reserveAsset;
        creator = _creator;
        rewardsDistributor = IRewardsDistributor(controller.rewardsDistributor());
        _onlyNonZero(address(rewardsDistributor));
        privateGarden = !(controller.allowPublicGardens() && _publicGardenStrategistsStewards[0]);
        publicStrategists = !privateGarden && _publicGardenStrategistsStewards[1];

        publicStewards = !privateGarden && _publicGardenStrategistsStewards[2];
        _require(
            _gardenParams[3] > 0 &&
                _initialContribution >= _gardenParams[3] &&
                _initialContribution <= _gardenParams[0],
            Errors.MIN_CONTRIBUTION
        );
        gardenInitializedAt = block.timestamp;
        _start(
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
    }

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
     * @param _mintNft                Whether to mint NFT or not
     */
    function deposit(
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _to,
        bool _mintNft
    ) external payable override nonReentrant {
        // calculate pricePerShare
        // if there are no strategies then NAV === liquidReserve

        _internalDeposit(_amountIn, _minAmountOut, _to, msg.sender, _mintNft, _getPricePerShare(), minContribution);
    }

    function depositBySig(
        uint256 _amountIn,
        uint256 _minAmountOut,
        bool _mintNft,
        uint256 _nonce,
        uint256 _maxFee,
        uint256 _pricePerShare,
        uint256 _fee,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override nonReentrant {
        _onlyKeeperAndFee(_fee, _maxFee);

        bytes32 hash =
            keccak256(
                abi.encode(DEPOSIT_BY_SIG_TYPEHASH, address(this), _amountIn, _minAmountOut, _mintNft, _nonce, _maxFee)
            )
                .toEthSignedMessageHash();
        address signer = ECDSA.recover(hash, v, r, s);
        _onlyValidSigner(signer, _nonce);
        // If a Keeper fee is greater than zero then reduce user shares to
        // exchange and pay keeper the fee.
        if (_fee > 0) {
            // account for non 18 decimals ERC20 tokens, e.g. USDC
            uint256 feeShares = _reserveToShares(_fee, _pricePerShare);
            _internalDeposit(
                _amountIn.sub(_fee),
                _minAmountOut.sub(feeShares),
                signer,
                signer,
                _mintNft,
                _pricePerShare,
                minContribution > _fee ? minContribution.sub(_fee) : 0
            );
            // pay Keeper the fee
            IERC20(reserveAsset).safeTransferFrom(signer, msg.sender, _fee);
        } else {
            _internalDeposit(_amountIn, _minAmountOut, signer, signer, _mintNft, _pricePerShare, minContribution);
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
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override nonReentrant {
        _onlyKeeperAndFee(_fee, _maxFee);

        address signer = _getWithdrawSigner(_amountIn, _minAmountOut, _nonce, _maxFee, _withPenalty, v, r, s);

        _withdrawInternal(
            _amountIn,
            _minAmountOut.sub(_maxFee),
            payable(signer),
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
        // Flashloan protection
        _require(
            block.timestamp.sub(contributors[msg.sender].lastDepositAt) >= depositHardlock,
            Errors.DEPOSIT_HARDLOCK
        );
        uint256[] memory rewards = new uint256[](8);
        rewards = rewardsDistributor.getRewards(address(this), msg.sender, _finalizedStrategies);
        _sendRewardsInternal(msg.sender, rewards[5], rewards[6]);
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
     */
    function claimRewardsBySig(
        uint256 _babl,
        uint256 _profits,
        uint256 _nonce,
        uint256 _maxFee,
        uint256 _fee,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override nonReentrant {
        _onlyKeeperAndFee(_fee, _maxFee);
        bytes32 hash =
            keccak256(abi.encode(REWARDS_BY_SIG_TYPEHASH, address(this), _babl, _profits, _nonce, _maxFee))
                .toEthSignedMessageHash();
        address signer = ECDSA.recover(hash, v, r, s);
        _onlyValidSigner(signer, _nonce);
        _require(_fee > 0, Errors.FEE_TOO_LOW);
        // pay to Keeper the fee to execute the tx on behalf
        IERC20(reserveAsset).safeTransferFrom(signer, msg.sender, _fee);
        _sendRewardsInternal(signer, _babl, _profits);
    }

    /**
     * @notice
     *  When strategy ends puts saves returns, rewards and marks strategy as
     *  finalized.
     *
     * @param _rewards        Amount of Reserve Asset to set aside forever
     * @param _returns        Profits or losses that the strategy received
     * @param _burningAmount  The amount of strategist stake to burn in case of
     *                        strategy losses.
     */
    function finalizeStrategy(
        uint256 _rewards,
        int256 _returns,
        uint256 _burningAmount
    ) external override nonReentrant {
        _onlyUnpaused();
        _onlyStrategy();

        // burn stategist stake
        if (_burningAmount > 0) {
            address strategist = IStrategy(msg.sender).strategist();
            if (_burningAmount >= balanceOf(strategist)) {
                // Avoid underflow condition
                _burningAmount = balanceOf(strategist);
            }
            _burn(strategist, _burningAmount);
        }

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
     *   We assume that calling keeper functions should be less expensive than 2000 DAI.
     * @param _keeper  Keeper that executed the transaction
     * @param _fee     The fee paid to keeper to compensate the gas cost
     */
    function payKeeper(address payable _keeper, uint256 _fee) public override nonReentrant {
        _onlyUnpaused();
        _require(msg.sender == address(this) || strategyMapping[msg.sender], Errors.ONLY_STRATEGY);
        _require(controller.isValidKeeper(_keeper), Errors.ONLY_KEEPER);
        uint256 pricePerTokenUnitInDAI = IPriceOracle(controller.priceOracle()).getPrice(reserveAsset, DAI);
        uint256 feeInDAI =
            pricePerTokenUnitInDAI.preciseMul(_fee).mul(
                10**(uint256(18).sub(ERC20Upgradeable(reserveAsset).decimals()))
            );

        _require(feeInDAI <= 2000 * 1e18, Errors.FEE_TOO_HIGH);

        keeperDebt = keeperDebt.add(_fee);
        uint256 liquidReserveAmount = liquidReserve();
        // Pay Keeper in Reserve Asset
        if (keeperDebt > 0 && liquidReserveAmount > 0) {
            uint256 toPay = liquidReserveAmount > keeperDebt ? keeperDebt : liquidReserveAmount;
            IERC20(reserveAsset).safeTransfer(_keeper, toPay);
            totalKeeperFees = totalKeeperFees.add(toPay);
            keeperDebt = keeperDebt.sub(toPay);
        }
    }

    /**
     * Makes a previously private garden public
     */
    function makeGardenPublic() external override {
        _onlyCreator(msg.sender);
        _require(privateGarden && controller.allowPublicGardens(), Errors.GARDEN_ALREADY_PUBLIC);
        privateGarden = false;
    }

    /**
     * Gives the right to create strategies and/or voting power to garden users
     */
    function setPublicRights(bool _publicStrategists, bool _publicStewards) external override {
        _onlyCreator(msg.sender);
        _require(!privateGarden, Errors.GARDEN_IS_NOT_PUBLIC);
        publicStrategists = _publicStrategists;
        publicStewards = _publicStewards;
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
        _require(balanceOf(msg.sender) > 0, Errors.ONLY_CONTRIBUTOR);
        (, , bool canCreateStrategies) = _getUserPermission(msg.sender);
        _require(canCreateStrategies, Errors.USER_CANNOT_ADD_STRATEGIES);
        _require(strategies.length < MAX_TOTAL_STRATEGIES, Errors.VALUE_TOO_HIGH);
        address strategy =
            IStrategyFactory(controller.strategyFactory()).createStrategy(
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

        uint256 protocolMgmtFee = controller.protocolManagementFee().preciseMul(_capital);
        _require(_capital.add(protocolMgmtFee) <= liquidReserve(), Errors.MIN_LIQUIDITY);

        // Take protocol mgmt fee to the heart
        IERC20(reserveAsset).safeTransfer(controller.heart(), protocolMgmtFee);

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
     * Creator transfer his creator rights to another account.
     * Must be a creator or an aux creator
     * @param _newCreator  New creator address
     * @param _index       Index of the creator if it is in the extra
     */
    function transferCreatorRights(address _newCreator, uint8 _index) external override {
        _onlyCreator(msg.sender);
        _require(!_isCreator(_newCreator), Errors.NEW_CREATOR_MUST_NOT_EXIST);
        // Make sure creator can still have normal permissions after renouncing
        // Creator can only renounce to 0x in public gardens
        _require(_newCreator != address(0) || !privateGarden, Errors.CREATOR_CANNOT_RENOUNCE);
        if (msg.sender == creator) {
            creator = _newCreator;
            return;
        }
        _require(extraCreators[_index] == msg.sender, Errors.ONLY_CREATOR);
        extraCreators[_index] = _newCreator;
    }

    /*
     * Adds extra creators. Only the original creator can call this.
     * Can only be called if all the addresses are zero
     * @param _newCreators  Addresses of the new creators
     */
    function addExtraCreators(address[MAX_EXTRA_CREATORS] memory _newCreators) external override {
        _require(msg.sender == creator, Errors.ONLY_FIRST_CREATOR_CAN_ADD);
        _assignExtraCreator(0, _newCreators[0]);
        _assignExtraCreator(1, _newCreators[1]);
        _assignExtraCreator(2, _newCreators[2]);
        _assignExtraCreator(3, _newCreators[3]);
    }

    /**
     * Updates Garden Params
     * Can only be called by the creator
     * @param _newParams  New params
     */
    function updateGardenParams(uint256[9] memory _newParams) external override {
        _onlyCreator(msg.sender);
        _start(
            _newParams[0], // uint256 _maxDepositLimit
            _newParams[1], // uint256 _minLiquidityAsset,
            _newParams[2], // uint256 _depositHardlock,
            _newParams[3], // uint256 _minContribution,
            _newParams[4], // uint256 _strategyCooldownPeriod,
            _newParams[5], // uint256 _minVotesQuorum,
            _newParams[6], // uint256 _minStrategyDuration,
            _newParams[7], // uint256 _maxStrategyDuration,
            _newParams[8] // uint256 _minVoters
        );
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
            0, // Deprecated
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
        if (balanceOf(_contributor) < lockedAmount) {
            lockedAmount = balanceOf(_contributor);
        }
        return lockedAmount;
    }

    /* ============ Internal Functions ============ */

    /**
     * FUND LEAD ONLY.  Starts the Garden with allowed reserve assets,
     * fees and issuance premium. Only callable by the Garden's creator
     *
     * @param _maxDepositLimit             Max deposit limit
     * @param _minLiquidityAsset           Number that represents min amount of liquidity denominated in ETH
     * @param _depositHardlock             Number that represents the time deposits are locked for
     *                                     an user after he deposits
     * @param _minContribution             Min contribution to the garden
     * @param _strategyCooldownPeriod      How long after the strategy has been activated, will it be ready
     *                                     to be executed
     * @param _minVotesQuorum              Percentage of votes needed to activate an strategy (0.01% = 1e14, 1% = 1e16)
     * @param _minStrategyDuration         Min duration of an strategy
     * @param _maxStrategyDuration         Max duration of an strategy
     * @param _minVoters                   The minimum amount of voters needed for quorum
     */
    function _start(
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
        _require(
            _minLiquidityAsset >= controller.minLiquidityPerReserve(reserveAsset) && _minLiquidityAsset > 0,
            Errors.MIN_LIQUIDITY
        );
        _require(_depositHardlock > 0, Errors.DEPOSIT_HARDLOCK);
        _require(
            _strategyCooldownPeriod <= MAX_COOLDOWN_PERIOD && _strategyCooldownPeriod >= MIN_COOLDOWN_PERIOD,
            Errors.NOT_IN_RANGE
        );
        _require(_minVotesQuorum >= TEN_PERCENT.div(2) && _minVotesQuorum <= TEN_PERCENT.mul(5), Errors.VALUE_TOO_LOW);
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
        minLiquidityAsset = _minLiquidityAsset;
        depositHardlock = _depositHardlock;
    }

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
        _require(block.timestamp.sub(contributors[_to].lastDepositAt) >= depositHardlock, Errors.DEPOSIT_HARDLOCK);

        // Strategists cannot withdraw locked stake while in active strategies
        // Withdrawal amount has to be equal or less than msg.sender balance minus the locked balance
        // any amountIn higher than user balance is treated as withdrawAll
        _amountIn = _amountIn > prevBalance.sub(getLockedBalance(_to))
            ? prevBalance.sub(getLockedBalance(_to))
            : _amountIn;
        _require(_amountIn <= prevBalance.sub(getLockedBalance(_to)), Errors.TOKENS_STAKED);

        uint256 amountOut = _sharesToReserve(_amountIn, _pricePerShare);

        // if withPenaltiy then unwind strategy
        if (_withPenalty && !(liquidReserve() >= amountOut)) {
            amountOut = amountOut.sub(amountOut.preciseMul(EARLY_WITHDRAWAL_PENALTY));
            // When unwinding a strategy, a slippage on integrations will result in receiving less tokens
            // than desired so we have have to account for this with a 5% slippage.
            // TODO: if there is more than 5% slippage that will block
            // withdrawal
            _onlyNonZero(_unwindStrategy);
            IStrategy(_unwindStrategy).unwindStrategy(amountOut.add(amountOut.preciseMul(5e16)), _strategyNAV);
        }

        _require(amountOut >= _minAmountOut && _amountIn > 0, Errors.RECEIVE_MIN_AMOUNT);

        _require(liquidReserve() >= amountOut, Errors.MIN_LIQUIDITY);

        _burn(_to, _amountIn);
        _safeSendReserveAsset(_to, amountOut.sub(_fee));
        if (_fee > 0) {
            // If fee > 0 pay Accountant
            IERC20(reserveAsset).safeTransfer(msg.sender, _fee);
        }
        _updateContributorWithdrawalInfo(_to, amountOut, prevBalance, _amountIn);

        emit GardenWithdrawal(_to, _to, amountOut, _amountIn, block.timestamp);
    }

    function _getPricePerShare() internal view returns (uint256) {
        if (strategies.length == 0) {
            return
                totalSupply() == 0
                    ? PreciseUnitMath.preciseUnit()
                    : liquidReserve().preciseDiv(uint256(10)**ERC20Upgradeable(reserveAsset).decimals()).preciseDiv(
                        totalSupply()
                    );
        } else {
            // Get valuation of the Garden with the quote asset as the reserve asset.
            return IGardenValuer(controller.gardenValuer()).calculateGardenValuation(address(this), reserveAsset);
        }
    }

    function _getWithdrawSigner(
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint256 _nonce,
        uint256 _maxFee,
        bool _withPenalty,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (address) {
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
        address signer = ECDSA.recover(hash, v, r, s);
        _onlyValidSigner(signer, _nonce);
        return signer;
    }

    function _internalDeposit(
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _to,
        address _from,
        bool _mintNft,
        uint256 _pricePerShare,
        uint256 _minContribution
    ) private {
        _onlyUnpaused();
        _onlyNonZero(_to);
        _checkLastPricePerShare(_pricePerShare);

        (bool canDeposit, , ) = _getUserPermission(_from);
        _require(_isCreator(_to) || (canDeposit && _from == _to), Errors.USER_CANNOT_JOIN);

        if (maxDepositLimit > 0) {
            // This is wrong; but calculating the principal would be too gas expensive
            _require(liquidReserve().add(_amountIn) <= maxDepositLimit, Errors.MAX_DEPOSIT_LIMIT);
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
        // We need to update at Rewards Distributor smartcontract for rewards accurate calculations
        _updateContributorDepositInfo(_to, previousBalance, _amountIn, sharesToMint);

        // Mint the garden NFT
        if (_mintNft) {
            IGardenNFT(controller.gardenNFT()).grantGardenNFT(_to);
        }

        emit GardenDeposit(_to, _minAmountOut, _amountIn, block.timestamp);
    }

    /**
     * @param _contributor     Contributor address to send rewards to
     * @param _babl            BABL rewards from mining program.
     * @param _profits         Profit rewards in reserve asset.
     */
    function _sendRewardsInternal(
        address _contributor,
        uint256 _babl,
        uint256 _profits
    ) internal {
        _onlyUnpaused();
        Contributor storage contributor = contributors[_contributor];
        _require(contributor.nonce > 0, Errors.ONLY_CONTRIBUTOR); // have been user garden
        _require(_babl > 0 || _profits > 0, Errors.NO_REWARDS_TO_CLAIM);
        _require(reserveAssetRewardsSetAside >= _profits, Errors.RECEIVE_MIN_AMOUNT);
        // Avoid replay attack between rewardsBySig and claimRewards or even between 2 of each
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
            uint256 bablSent = rewardsDistributor.sendBABLToContributor(_contributor, _babl);
            contributor.claimedBABL = contributor.claimedBABL.add(bablSent); // BABL Rewards claimed properly
            emit BABLRewardsForContributor(_contributor, bablSent);
        }
    }

    /**
     * Gets liquid reserve available for to Garden.
     */
    function liquidReserve() private view returns (uint256) {
        uint256 reserve = IERC20(reserveAsset).balanceOf(address(this)).sub(reserveAssetRewardsSetAside);
        return reserve > keeperDebt ? reserve.sub(keeperDebt) : 0;
    }

    // Disable garden token transfers. Allow minting and burning.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 _amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, _amount);
        _require(
            from == address(0) || to == address(0) || (controller.gardenTokensTransfersEnabled() && !privateGarden),
            Errors.GARDEN_TRANSFERS_DISABLED
        );
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
     * Updates the contributor info in the array
     */
    function _updateContributorDepositInfo(
        address _contributor,
        uint256 _previousBalance,
        uint256 _reserveAssetQuantity,
        uint256 _newTokens
    ) private {
        Contributor storage contributor = contributors[_contributor];
        // If new contributor, create one, increment count, and set the current TS
        if (_previousBalance == 0 || contributor.initialDepositAt == 0) {
            totalContributors = totalContributors.add(1);
            contributor.initialDepositAt = block.timestamp;
        }
        // We make checkpoints around contributor deposits to give the right rewards afterwards
        contributor.totalDeposits = contributor.totalDeposits.add(_reserveAssetQuantity);
        contributor.lastDepositAt = block.timestamp;
        // RD checkpoint for accurate rewards
        _updateGardenPowerAndContributor(_contributor, _previousBalance, _newTokens, true);
        // nonce update is done at _updateGardenPowerAndContributor
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorWithdrawalInfo(
        address _contributor,
        uint256 _amountOut,
        uint256 _previousBalance,
        uint256 _tokensToBurn
    ) private {
        Contributor storage contributor = contributors[_contributor];
        // If withdrawn everything
        if (balanceOf(_contributor) == 0) {
            contributor.lastDepositAt = 0;
            contributor.initialDepositAt = 0;
            contributor.withdrawnSince = 0;
            contributor.totalDeposits = 0;
            totalContributors = totalContributors.sub(1);
        } else {
            contributor.withdrawnSince = contributor.withdrawnSince.add(_amountOut);
        }
        // RD checkpoint for accurate rewards
        _updateGardenPowerAndContributor(_contributor, _previousBalance, _tokensToBurn, false);
        // nonce update is done at _updateGardenPowerAndContributor
    }

    /**
     * Rewards Distributor checkpoint updater at deposits / withdrawals
     */
    function _updateGardenPowerAndContributor(
        address _contributor,
        uint256 _prevBalance,
        uint256 _tokens,
        bool _depositOrWithdraw
    ) internal {
        rewardsDistributor.updateGardenPowerAndContributor(
            address(this),
            _contributor,
            _prevBalance,
            _tokens,
            _depositOrWithdraw // true = deposit , false = withdraw
        );
        contributors[_contributor].nonce++;
    }

    /**
     * Check contributor permissions for deposit [0], vote [1] and create strategies [2]
     */
    function _getUserPermission(address _user)
        internal
        view
        returns (
            bool canDeposit,
            bool canVote,
            bool canCreateStrategy
        )
    {
        IMardukGate mgate = IMardukGate(controller.mardukGate());
        bool betaAccess = true;
        canDeposit = (betaAccess && !privateGarden) || mgate.canJoinAGarden(address(this), _user);
        canVote = (betaAccess && publicStewards) || mgate.canVoteInAGarden(address(this), _user);
        canCreateStrategy = (betaAccess && publicStrategists) || mgate.canAddStrategiesInAGarden(address(this), _user);
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

        slippage = lastPricePerShare % (pricePerShareSlippage + timePast * pricePerShareDecayRate);

        For example, if lastPricePerShare is 1e18 and slippage is 10% then deposits with pricePerShare between
        9e17 and 11e17 allowed immediately. After one year (100% change in time) and with a decay rate 1x;
        deposits between 5e17 and 2e18 are possible. Different gardens should have different settings for
        slippage and decay rate due to various volatility of the strategies. For example, stable gardens
        would have low slippage and decay rate while some moonshot garden may have both of them
        as high as 100% and 10x.
      @param _pricePerShare  Price of the graden share to validate against historical data
    */
    function _checkLastPricePerShare(uint256 _pricePerShare) private {
        uint256 slippage = pricePerShareSlippage > 0 ? pricePerShareSlippage : 1e18;
        uint256 decay = pricePerShareDecayRate > 0 ? pricePerShareDecayRate : 1e18;
        // if no previous record then just pass the check
        if (lastPricePerShare != 0) {
            slippage = slippage.add(
                block.timestamp.sub(lastPricePerShareTS).preciseDiv(365 days).preciseMul(decay));
            _require(
                _pricePerShare > lastPricePerShare
                    ? _pricePerShare.sub(lastPricePerShare) <= lastPricePerShare.preciseMul(slippage)
                    : lastPricePerShare.sub(_pricePerShare) <=
                        lastPricePerShare.sub(lastPricePerShare.preciseDiv(slippage.add(1e18))),
                Errors.PRICE_PER_SHARE_WRONG
            );
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

    // solhint-disable-next-line
    receive() external payable {}
}

contract GardenV17 is Garden {}
