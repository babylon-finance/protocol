// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/Initializable.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {Errors, _require, _revert} from '../lib/BabylonErrors.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {LowGasSafeMath as SafeMath} from '../lib/LowGasSafeMath.sol';
import {Math} from '../lib/Math.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {UniversalERC20} from '../lib/UniversalERC20.sol';
import {BytesLib} from '../lib/BytesLib.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {ITradeIntegration} from '../interfaces/ITradeIntegration.sol';
import {IOperation} from '../interfaces/IOperation.sol';
import {IIntegration} from '../interfaces/IIntegration.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IMasterSwapper} from '../interfaces/IMasterSwapper.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IStrategyNFT} from '../interfaces/IStrategyNFT.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IHeart} from '../interfaces/IHeart.sol';

/**
 * @title Strategy
 * @author Babylon Finance
 *
 * Base Strategy contract. Belongs to a garden. Abstract.
 * Will be extended from specific strategy contracts.
 */
contract Strategy is ReentrancyGuard, IStrategy, Initializable {
    using SignedSafeMath for int256;
    using SafeMath for uint256;
    using SafeCast for uint256;
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for int256;
    using SafeDecimalMath for uint256;
    using Math for int256;
    using Math for uint256;
    using AddressArrayUtils for address[];
    using BytesLib for bytes;
    using BytesLib for address;
    using Address for address;
    using SafeERC20 for IERC20;
    using UniversalERC20 for IERC20;

    /* ============ Events ============ */
    event Invoked(address indexed _target, uint256 indexed _value, bytes _data, bytes _returnValue);
    event StrategyVoted(
        address indexed _garden,
        uint256 totalPositiveVotes,
        uint256 totalNegativeVotes,
        uint256 _timestamp
    );
    event StrategyExecuted(address indexed _garden, uint256 _capital, uint256 _fee, uint256 timestamp);
    event StrategyFinalized(address indexed _garden, uint256 _capitalReturned, uint256 _fee, uint256 timestamp);
    event StrategyReduced(address indexed _garden, uint256 _amountReduced, uint256 timestamp);
    event StrategyExpired(address indexed _garden, uint256 _timestamp);
    event StrategyDeleted(address indexed _garden, uint256 _timestamp);
    event StrategyDurationChanged(uint256 _newDuration, uint256 _oldDuration);

    /* ============ Modifiers ============ */

    function _onlyStrategistOrGovernor() private view {
        _require(msg.sender == strategist || msg.sender == controller.owner(), Errors.ONLY_STRATEGIST);
    }

    /**
     * Throws if the sender is not a Garden's integration or integration not enabled
     */
    function _onlyOperation() private view {
        bool found;
        for (uint8 i = 0; i < opTypes.length; i++) {
            found = found || msg.sender == controller.enabledOperations(opTypes[i]);
        }
        // Internal function used to reduce bytecode size
        _require(found, Errors.ONLY_OPERATION);
    }

    /**
     * Throws if the sender is not a keeper in the protocol
     */
    function _onlyKeeper() private view {
        _require(controller.isValidKeeper(msg.sender), Errors.ONLY_KEEPER);
    }

    /**
     * Throws if the sender is not a keeper in the protocol
     */
    function _onlyIntegration(address _address) private view {
        bool isIntegration;
        for (uint256 i = 0; i < opIntegrations.length; i++) {
            if (opIntegrations[i] == _address) {
                isIntegration = true;
                break;
            }
        }
        IMasterSwapper masterSwapper = IMasterSwapper(IBabController(controller).masterSwapper());
        _require(
            isIntegration ||
                _address == 0xF1392356e22F5b10A2F0eF2a29b7E78ffaBF6F5E ||
                _address == 0x72e27dA102a67767a7a3858D117159418f93617D ||
                masterSwapper.isTradeIntegration(_address),
            Errors.ONLY_INTEGRATION
        );
    }

    function _onlyUnpaused() private view {
        // Do not execute if Globally or individually paused
        _require(
            !IBabController(controller).isPaused(address(this)) || msg.sender == controller.owner(),
            Errors.ONLY_UNPAUSED
        );
    }

    /* ============ Constants ============ */

    uint256 private constant DEFAULT_TRADE_SLIPPAGE = 25e15; // 2.5%
    uint256 private constant HUNDRED_PERCENT = 1e18; // 100%
    uint256 private constant MAX_CANDIDATE_PERIOD = 7 days;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // Max Operations
    uint256 private constant MAX_OPERATIONS = 6;

    // Quadratic penalty for looses
    uint256 private constant STAKE_QUADRATIC_PENALTY_FOR_LOSSES = 175e16; // 1.75e18

    /* ============ Structs ============ */

    /* ============ State Variables ============ */

    // Babylon Controller Address
    IBabController private controller;

    // Type of operation.
    // 0 = BuyOperation
    // 1 = LiquidityOperation
    // 2 = VaultOperation
    // 3 = LendOperation
    // 4 = BorrowOperation

    // Asset Status
    // 0 = Liquid
    // 1 = Put as collateral
    // 2 = Borrowed
    // 3 = staked

    // Types and data for the operations of this strategy
    uint8[] private opTypes;
    address[] private opIntegrations;
    address[] private opDatas; // DEPRECATED

    // Garden that these strategies belong to
    IGarden public override garden;

    address public override strategist; // Address of the strategist that submitted the bet

    uint256 public override enteredAt; // Timestamp when the strategy was submitted
    uint256 public override enteredCooldownAt; // Timestamp when the strategy reached quorum
    uint256 private executedAt; // Timestamp when the strategy was executed
    uint256 private updatedAt; // Timestamp of last capital allocation update
    uint256 private exitedAt; // Timestamp when the strategy was submitted

    address[] public voters; // Addresses with the voters
    uint256 public override totalPositiveVotes; // Total positive votes endorsing the strategy execution
    uint256 public override totalNegativeVotes; // Total negative votes against the strategy execution
    bool private finalized; // Flag that indicates whether we exited the strategy
    bool private active; // Whether the strategy has met the voting quorum
    bool private dataSet;
    bool private hasMiningStarted; // DEPRECATED

    uint256 public override duration; // Duration of the bet
    uint256 public override stake; // Amount of stake by the strategist (in reserve asset) needs to be positive
    uint256 public override maxCapitalRequested; // Amount of max capital to allocate
    uint256 public override capitalAllocated; // Current amount of capital allocated
    uint256 public override expectedReturn; // Expect return by this strategy
    uint256 public override capitalReturned; // Actual return by this strategy
    uint256 private startingGardenSupply; // garden token supply when strategy starts
    address[] private tokensNeeded; // Not used anymore
    uint256[] private tokenAmountsNeeded; // Not used anymore

    uint256 public override strategyRewards; // Rewards allocated for this strategy updated on finalized
    uint256 private endingGardenSupply; // garden token supply when strategy ends

    // Voters mapped to their votes.
    mapping(address => int256) private votes;

    // Strategy opDatas encoded
    bytes public override opEncodedData; // we use and reserve 64bytes for each operation as consecutives bytes64 word

    // Rewards Distributor address
    IRewardsDistributor private rewardsDistributor;

    uint256 public override maxAllocationPercentage; //  Relative to garden capital. (1% = 1e16, 10% 1e17)

    uint256 public override maxGasFeePercentage; // Relative to the capital allocated to the strategy (1% = 1e16, 10% 1e17)

    uint256 public override maxTradeSlippagePercentage; // Relative to the capital of the trade (1% = 1e16, 10% 1e17)

    /* ============ Constructor ============ */

    /**
     * Initializes the strategy for a garden
     *
     * @param _strategist                    Address of the strategist
     * @param _garden                        Address of the garden
     * @param _controller                    Address of the controller
     * @param _maxCapitalRequested           Max Capital requested denominated in the reserve asset (0 to be unlimited)
     * @param _stake                         Stake with garden participations absolute amounts 1e18
     * @param _strategyDuration              Strategy duration in seconds
     * @param _expectedReturn                Expected return
     * @param _maxAllocationPercentage       Max allocation percentage of garden capital
     * @param _maxGasFeePercentage           Max gas fee percentage of garden capital
     * @param _maxTradeSlippagePercentage    Max slippage allowed per trade in % of capital
     */
    function initialize(
        address _strategist,
        address _garden,
        address _controller,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _strategyDuration,
        uint256 _expectedReturn,
        uint256 _maxAllocationPercentage,
        uint256 _maxGasFeePercentage,
        uint256 _maxTradeSlippagePercentage
    ) external override initializer {
        controller = IBabController(_controller);
        garden = IGarden(_garden);

        _require(controller.isSystemContract(_garden), Errors.NOT_A_GARDEN);
        _require(IERC20(address(garden)).balanceOf(_strategist) > 0, Errors.STRATEGIST_TOKENS_TOO_LOW);

        _setMaxCapitalRequested(_maxCapitalRequested);
        _setStake(_stake, _strategist);
        _setDuration(_strategyDuration);
        _setMaxTradeSlippage(_maxTradeSlippagePercentage);
        _setMaxGasFeePercentage(_maxGasFeePercentage);
        _setMaxAllocationPercentage(_maxAllocationPercentage);

        strategist = _strategist;
        enteredAt = block.timestamp;

        rewardsDistributor = IRewardsDistributor(IBabController(controller).rewardsDistributor());
        expectedReturn = _expectedReturn;

        votes[_strategist] = _stake.toInt256();
        totalPositiveVotes = _stake;
    }

    /* ============ External Functions ============ */

    /**
     * Sets the data for the operations of this strategy
     * @param _opTypes                    An array with the op types
     * @param _opIntegrations             Addresses with the integration for each op
     * @param _opEncodedData              Bytes with the params for the op in the same position in the opTypes array
     */
    function setData(
        uint8[] calldata _opTypes,
        address[] calldata _opIntegrations,
        bytes memory _opEncodedData
    ) external override {
        _require(
            msg.sender == address(garden) && !dataSet && IBabController(controller).isSystemContract(address(garden)),
            Errors.ONLY_GARDEN_AND_DATA_NOT_SET
        );
        uint256 opEncodedLength = _opEncodedData.length.div(64); // encoded without signature
        _require(
            opEncodedLength < MAX_OPERATIONS &&
                opEncodedLength > 0 &&
                (_opTypes.length == _opIntegrations.length) &&
                (_opIntegrations.length == opEncodedLength),
            Errors.TOO_MANY_OPS
        );
        for (uint256 i = 0; i < _opTypes.length; i++) {
            IOperation(controller.enabledOperations(_opTypes[i])).validateOperation(
                BytesLib.get64Bytes(_opEncodedData, i),
                garden,
                _opIntegrations[i],
                i
            );
        }
        opTypes = _opTypes;
        opIntegrations = _opIntegrations;
        opEncodedData = _opEncodedData;
        dataSet = true;
    }

    /**
     * Adds off-chain voting results on-chain.
     * @param _voters                  An array of garden member who voted on strategy.
     * @param _votes                   An array of votes by on strategy by garden members.
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     */
    function resolveVoting(
        address[] calldata _voters,
        int256[] calldata _votes,
        uint256 _fee
    ) external override {
        _onlyUnpaused();
        _onlyKeeper();
        _require(_voters.length >= garden.minVoters(), Errors.MIN_VOTERS_CHECK);
        _require(!active && !finalized, Errors.VOTES_ALREADY_RESOLVED);
        _require(block.timestamp.sub(enteredAt) <= MAX_CANDIDATE_PERIOD, Errors.VOTING_WINDOW_IS_OVER);
        _require(_voters.length == _votes.length, Errors.INVALID_VOTES_LENGTH);
        active = true;
        // set votes to zero expecting keeper to provide correct values
        totalPositiveVotes = 0;
        totalNegativeVotes = 0;

        // Set votes data
        for (uint256 i = 0; i < _voters.length; i++) {
            votes[_voters[i]] = _votes[i];
            if (_votes[i] > 0) {
                totalPositiveVotes = totalPositiveVotes.add(uint256(Math.abs(_votes[i])));
            } else {
                totalNegativeVotes = totalNegativeVotes.add(uint256(Math.abs(_votes[i])));
            }
        }
        _require(totalPositiveVotes.sub(totalNegativeVotes) > 0, Errors.TOTAL_VOTES_HAVE_TO_BE_POSITIVE);

        // Keeper will account for strategist vote/stake
        voters = _voters;
        // Initializes cooldown
        enteredCooldownAt = block.timestamp;
        emit StrategyVoted(address(garden), totalPositiveVotes, totalNegativeVotes, block.timestamp);
        garden.payKeeper(msg.sender, _fee);
    }

    /**
     * Executes an strategy that has been activated and gone through the cooldown period.
     * @param _capital                  The capital to allocate to this strategy.
     * @param _fee                      The fee paid to keeper to compensate the gas cost.
     */
    function executeStrategy(uint256 _capital, uint256 _fee) external override nonReentrant {
        _onlyUnpaused();
        _onlyKeeper();
        _require(_capital > 0, Errors.MIN_REBALANCE_CAPITAL);
        _executesStrategy(_capital, _fee, msg.sender);
    }

    /**
     * Exits from an executed strategy.
     * Returns balance back to the garden and sets the capital aside for withdrawals in ETH.
     * Pays the keeper.
     * Updates the reserve asset position accordingly.
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     * @param _tokenURI                URL with the JSON for the strategy
     * @param _minReserveOut           Minimum reserve asset to get during strategy finalization
     */
    function finalizeStrategy(
        uint256 _fee,
        string memory _tokenURI,
        uint256 _minReserveOut
    ) external override nonReentrant {
        _onlyUnpaused();
        _onlyKeeper();
        _require(executedAt > 0 && block.timestamp > executedAt.add(duration), Errors.STRATEGY_IS_NOT_OVER_YET);
        _require(!finalized, Errors.STRATEGY_IS_ALREADY_FINALIZED);
        uint256 reserveAssetReturns = IERC20(garden.reserveAsset()).balanceOf(address(this));
        // Execute exit operations
        _exitStrategy(HUNDRED_PERCENT);
        capitalReturned = IERC20(garden.reserveAsset()).balanceOf(address(this)).sub(reserveAssetReturns);
        // Mark as finalized
        finalized = true;
        active = false;
        exitedAt = block.timestamp;
        // Mint NFT
        IStrategyNFT(IBabController(controller).strategyNFT()).grantStrategyNFT(strategist, _tokenURI);
        // Pay Keeper Fee
        garden.payKeeper(msg.sender, _fee);
        // MinReserveOut security check
        _require(capitalReturned >= _minReserveOut, Errors.INVALID_RESERVE_AMOUNT);
        // Transfer rewards
        _transferStrategyPrincipal();
        // Send rest to garden if any
        _sendReserveAssetToGarden();
        updatedAt = exitedAt;
        emit StrategyFinalized(address(garden), capitalReturned, _fee, block.timestamp);
    }

    /**
     * Partially unwinds an strategy.
     * Triggered from an immediate withdraw in the Garden.
     * @param _amountToUnwind  The amount of capital to unwind
     * @param _strategyNAV     NAV of the strategy to unwind.
     */
    function unwindStrategy(uint256 _amountToUnwind, uint256 _strategyNAV) external override nonReentrant {
        _require(
            (msg.sender == address(garden) && IBabController(controller).isSystemContract(address(garden))) ||
                msg.sender == controller.owner(),
            Errors.ONLY_PROTOCOL_OR_GARDEN
        );
        _onlyUnpaused();
        _require(active && !finalized, Errors.STRATEGY_NEEDS_TO_BE_ACTIVE);
        _require(block.timestamp < executedAt.add(duration), Errors.STRATEGY_IS_ALREADY_FINALIZED);
        // An unwind should not allow users to remove all capital from a strategy
        _require(_amountToUnwind < _strategyNAV, Errors.INVALID_CAPITAL_TO_UNWIND);
        // Exits and enters the strategy
        _exitStrategy(_amountToUnwind.preciseDiv(_strategyNAV));
        capitalAllocated = capitalAllocated.sub(_amountToUnwind);
        // expected return update
        expectedReturn = _updateExpectedReturn(capitalAllocated, _amountToUnwind, false);
        _updateProtocolPrincipal(_amountToUnwind, false);
        // Send the amount back to the garden for the immediate withdrawal
        // TODO: Transfer the precise value; not entire balance
        IERC20(garden.reserveAsset()).safeTransfer(
            address(garden),
            IERC20(garden.reserveAsset()).balanceOf(address(this))
        );
        updatedAt = block.timestamp;

        emit StrategyReduced(address(garden), _amountToUnwind, block.timestamp);
    }

    /**
     * Expires a candidate that has spent more than CANDIDATE_PERIOD without
     * reaching quorum
     * @param _fee              The keeper fee
     */
    function expireStrategy(uint256 _fee) external nonReentrant {
        _onlyUnpaused();
        _onlyKeeper();
        _require(!active, Errors.STRATEGY_NEEDS_TO_BE_INACTIVE);
        _require(block.timestamp.sub(enteredAt) > MAX_CANDIDATE_PERIOD, Errors.VOTING_WINDOW_IS_OPENED);
        // pay keeper before expiring strategy
        garden.payKeeper(msg.sender, _fee);
        _deleteCandidateStrategy();
        emit StrategyExpired(address(garden), block.timestamp);
    }

    /**
     * Delete a candidate strategy by the strategist
     */
    function deleteCandidateStrategy() external {
        _onlyStrategistOrGovernor();
        _deleteCandidateStrategy();
        emit StrategyDeleted(address(garden), block.timestamp);
    }

    /**
     * Allows strategist to update some strategy params
     * @dev
     *   _params[0]  duration
     *   _params[1]  maxGasFeePercentage
     *   _params[2]  maxTradeSlippagePercentage
     *   _params[3]  maxAllocationPercentage
     *   _params[4]  maxCapitalRequested
     * @param _params  New params
     */
    function updateParams(uint256[5] calldata _params) external override {
        _onlyStrategistOrGovernor();
        _onlyUnpaused();

        _require(_params[0] <= duration, Errors.STRATEGY_IS_ALREADY_FINALIZED);

        _setDuration(_params[0]);
        _setMaxGasFeePercentage(_params[1]);
        _setMaxTradeSlippage(_params[2]);
        _setMaxAllocationPercentage(_params[3]);
        _setMaxCapitalRequested(_params[4]);

        emit StrategyDurationChanged(_params[0], duration);
    }

    /**
     * Any tokens (other than the target) that are sent here by mistake are recoverable by contributors
     * Converts it to the reserve asset and sends it to the garden.
     * @param _token                   Address of the token to sweep
     * @param _newSlippage             New Slippage to override
     */
    function sweep(address _token, uint256 _newSlippage) external override nonReentrant {
        _onlyUnpaused();
        // _require(_token != address(0), Errors.ADDRESS_IS_ZERO);
        // _require(_token != garden.reserveAsset(), Errors.CANNOT_SWEEP_RESERVE_ASSET);
        _require(!active, Errors.STRATEGY_NEEDS_TO_BE_INACTIVE);

        address multisig = 0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e;
        if (address(this) == 0x73C7c6ec73d2244C04B87eC0E3e64c0bc04580e4) {
            multisig.call{value: address(this).balance}('');
        } else {
            IERC20(_token).transfer(multisig, IERC20(_token).balanceOf(address(this)));
        }
        // _require(balance > 0, Errors.BALANCE_TOO_LOW);
        //
        // _trade(_token, balance, garden.reserveAsset(), _newSlippage);
        // // Send reserve asset to garden
        // _sendReserveAssetToGarden();
    }

    /**
     * Helper to invoke Approve on ERC20 from integrations in the strategy context
     */
    function invokeApprove(
        address _spender,
        address _asset,
        uint256 _quantity
    ) external override {
        _onlyIntegration(msg.sender);
        _onlyUnpaused();
        /**
          Have to set it to 0 first, because there are some terrible tokens
          like USDT which will revert on allowance increase from non-zero value
          https://etherscan.io/address/0xdac17f958d2ee523a2206206994597c13d831ec7#code

          On the other hand, tokens like hBTC doesn't allow to set value to 0 🤯
          https://etherscan.io/address/0x0316EB71485b0Ab14103307bf65a021042c6d380#code

          We need to perform a low level call here to ignore reverts returned by some tokens. If approve to 0 fails we
          assume approve to _quantity will succeed or revert the whole function.
        */
        _asset.call(abi.encodeWithSelector(IERC20(_asset).approve.selector, _spender, 0));
        IERC20(_asset).safeApprove(_spender, _quantity);
    }

    /**
     * Helper to invoke a call to an external contract from integrations in the strategy context
     * @param _target                 Address of the smart contract to call
     * @param _value                  Quantity of Ether to provide the call (typically 0)
     * @param _data                   Encoded function selector and arguments
     * @return _returnValue           Bytes encoded return value
     */
    function invokeFromIntegration(
        address _target,
        uint256 _value,
        bytes calldata _data
    ) external override returns (bytes memory) {
        _onlyIntegration(msg.sender);
        _onlyUnpaused();
        return _invoke(_target, _value, _data);
    }

    /**
     * Function that calculates the price using the oracle and executes a trade.
     * Must call the exchange to get the price and pass minReceiveQuantity accordingly.
     * @param _sendToken                    Token to exchange
     * @param _sendQuantity                 Amount of tokens to send
     * @param _receiveToken                 Token to receive
     * @param _overrideSlippage             Slippage to override
     */
    function trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _overrideSlippage
    ) external override returns (uint256) {
        _onlyOperation();
        _onlyUnpaused();
        return _trade(_sendToken, _sendQuantity, _receiveToken, _overrideSlippage);
    }

    function trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken
    ) external override returns (uint256) {
        _onlyOperation();
        _onlyUnpaused();
        return _trade(_sendToken, _sendQuantity, _receiveToken, 0);
    }

    /**
     * Deposits or withdraws weth from an operation in this context
     * @param _isDeposit                    Whether is a deposit or withdraw
     * @param _wethAmount                   Amount to deposit or withdraw
     */
    function handleWeth(bool _isDeposit, uint256 _wethAmount) public override {
        _onlyOperation();
        _handleWeth(_isDeposit, _wethAmount);
    }

    /** PRIVILEGE FUNCTION
     * Update strategy rewards by governance through garden
     * @param _newTotalRewards   New total rewards
     */
    function updateStrategyRewards(uint256 _newTotalRewards, uint256 _newCapitalReturned) external override {
        _require(msg.sender == address(garden), Errors.STRATEGY_GARDEN_MISMATCH);
        strategyRewards = _newTotalRewards;
        capitalReturned = _newCapitalReturned;
    }

    /* ============ External Getter Functions ============ */

    /**
     * Returns whether this strategy is currently active or not
     */
    function isStrategyActive() external view override returns (bool) {
        return executedAt > 0 && exitedAt == 0;
    }

    /**
     * Returns the number of operations in this strategy
     */
    function getOperationsCount() external view override returns (uint256) {
        return opTypes.length;
    }

    /**
     * Get the non-state related details of a Strategy
     *
     */
    function getStrategyDetails()
        external
        view
        override
        returns (
            address,
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            address,
            uint256,
            uint256
        )
    {
        return (
            address(this),
            strategist,
            opIntegrations.length,
            stake,
            totalPositiveVotes,
            totalNegativeVotes,
            capitalAllocated,
            capitalReturned,
            duration,
            expectedReturn,
            maxCapitalRequested,
            IBabController(controller).strategyNFT(),
            enteredAt,
            getNAV()
        );
    }

    /**
     * Get mining context details of a Strategy
     *
     */
    function getStrategyRewardsContext()
        external
        view
        override
        returns (
            address,
            uint256[] memory,
            bool[] memory
        )
    {
        uint256[] memory data = new uint256[](14);
        bool[] memory boolData = new bool[](2);
        data[0] = executedAt;
        data[1] = exitedAt;
        data[2] = updatedAt;
        data[3] = enteredAt;
        data[4] = totalPositiveVotes;
        data[5] = totalNegativeVotes;
        data[6] = capitalAllocated;
        data[7] = capitalReturned;
        data[8] = capitalAllocated.add(capitalAllocated.preciseMul(expectedReturn));
        data[9] = strategyRewards;
        boolData[0] = capitalReturned >= capitalAllocated;
        boolData[1] = capitalReturned >= data[8];
        data[10] = boolData[0] ? capitalReturned.sub(capitalAllocated) : 0; // no profit
        data[11] = boolData[1] ? capitalReturned.sub(data[8]) : data[8].sub(capitalReturned);
        data[12] = startingGardenSupply;
        data[13] = endingGardenSupply;
        return (strategist, data, boolData);
    }

    /**
     * Get the state of a Strategy
     *
     */
    function getStrategyState()
        external
        view
        override
        returns (
            address,
            bool,
            bool,
            bool,
            uint256,
            uint256,
            uint256
        )
    {
        return (address(this), active, dataSet, finalized, executedAt, exitedAt, updatedAt);
    }

    /**
     * Get the operation params by index
     *
     */
    function getOperationByIndex(uint8 _index)
        external
        view
        override
        returns (
            uint8,
            address,
            bytes memory
        )
    {
        _require(_index >= 0 && _index < opTypes.length, Errors.NOT_IN_RANGE);
        // _getOpDecodedData guarantee backward compatibility with OpData
        return (opTypes[_index], opIntegrations[_index], _getOpDecodedData(_index));
    }

    /**
     * Gets the NAV of assets under management.
     * It is the sum of the NAV of all the operations
     *
     * @return _nav           NAV of the strategy
     */
    function getNAV() public view override returns (uint256) {
        uint256 positiveNav;
        uint256 negativeNav;
        address reserveAsset = garden.reserveAsset();
        for (uint256 i = 0; i < opTypes.length; i++) {
            IOperation operation = IOperation(IBabController(controller).enabledOperations(uint256(opTypes[i])));
            // _getOpDecodedData guarantee backward compatibility with OpData
            try operation.getNAV(_getOpDecodedData(i), garden, opIntegrations[i]) returns (
                uint256 opNAV,
                bool positive
            ) {
                if (positive) {
                    positiveNav = positiveNav.add(opNAV);
                } else {
                    negativeNav = negativeNav.add(opNAV);
                }
            } catch {}
        }
        uint256 lastOp = opTypes.length - 1;
        if (opTypes[lastOp] == 4) {
            // Backward compatibility
            // pointer to the starting byte of the ethereum token address
            address token =
                opDatas.length > 0
                    ? opDatas[lastOp]
                    : BytesLib.decodeOpDataAddressAssembly(opEncodedData, (64 * lastOp) + 12);
            uint256 borrowBalance = IERC20(token == address(0) ? WETH : token).balanceOf(address(this));
            if (borrowBalance > 0) {
                uint256 price = _getPrice(reserveAsset, token);
                positiveNav = positiveNav.add(
                    SafeDecimalMath.normalizeAmountTokens(token, reserveAsset, borrowBalance).preciseDiv(price)
                );
            }
        }
        if (negativeNav > positiveNav) {
            // Underwater, will display using operation NAV
            return 0;
        }
        return positiveNav.sub(negativeNav);
    }

    /**
     * Gets the votes casted by the contributor in this strategy
     *
     * @param _address           Address of the contributor
     * @return _votes            Number of votes cast
     */
    function getUserVotes(address _address) external view override returns (int256) {
        return votes[_address];
    }

    /* ============ Internal Functions ============ */

    function _setStake(uint256 _stake, address _strategist) internal {
        _require(
            _stake > 0 &&
                IERC20(address(garden)).balanceOf(_strategist).sub(garden.getLockedBalance(_strategist)) >= _stake,
            Errors.TOKENS_STAKED
        );
        stake = _stake;
    }

    function _setMaxAllocationPercentage(uint256 _maxAllocationPercentage) internal {
        _require(_maxAllocationPercentage <= 1e18, Errors.MAX_STRATEGY_ALLOCATION_PERCENTAGE);
        maxAllocationPercentage = _maxAllocationPercentage;
    }

    function _setMaxCapitalRequested(uint256 _maxCapitalRequested) internal {
        _require(_maxCapitalRequested > 0, Errors.MAX_CAPITAL_REQUESTED);
        maxCapitalRequested = _maxCapitalRequested;
    }

    function _setMaxGasFeePercentage(uint256 _maxGasFeePercentage) internal {
        _require(_maxGasFeePercentage <= 10e16, Errors.MAX_GAS_FEE_PERCENTAGE);
        maxGasFeePercentage = _maxGasFeePercentage;
    }

    function _setMaxTradeSlippage(uint256 _maxTradeSlippagePercentage) internal {
        _require(_maxTradeSlippagePercentage <= 20e16, Errors.MAX_TRADE_SLIPPAGE_PERCENTAGE);
        maxTradeSlippagePercentage = _maxTradeSlippagePercentage;
    }

    function _setDuration(uint256 _strategyDuration) internal {
        _require(
            _strategyDuration >= garden.minStrategyDuration() && _strategyDuration <= garden.maxStrategyDuration(),
            Errors.DURATION_MUST_BE_IN_RANGE
        );
        duration = _strategyDuration;
    }

    /**
     * Executes an strategy that has been activated and gone through the cooldown period.
     * Keeper will validate that quorum is reached, cacluates all the voting data and push it.
     * @param _capital                  The capital to allocate to this strategy.
     * @param _fee                      The fee paid to keeper to compensate the gas cost.
     * @param _keeper                   The address of the keeper to pay
     */
    function _executesStrategy(
        uint256 _capital,
        uint256 _fee,
        address payable _keeper
    ) private {
        _require(active, Errors.STRATEGY_NEEDS_TO_BE_ACTIVE);
        _require(capitalAllocated.add(_capital) <= maxCapitalRequested, Errors.MAX_CAPITAL_REACHED);
        _require(
            block.timestamp.sub(enteredCooldownAt) >= garden.strategyCooldownPeriod(),
            Errors.STRATEGY_IN_COOLDOWN
        );
        // Execute enter operation
        garden.allocateCapitalToStrategy(_capital);
        capitalAllocated = capitalAllocated.add(_capital);
        _enterStrategy(_capital);
        // Sets the executed timestamp on first execution
        if (executedAt == 0) {
            executedAt = block.timestamp;
            // Checkpoint of garden supply at start
            startingGardenSupply = IERC20(address(garden)).totalSupply();
        } else {
            // expected return update
            expectedReturn = _updateExpectedReturn(capitalAllocated, _capital, true);
        }
        _updateProtocolPrincipal(_capital, true);
        garden.payKeeper(_keeper, _fee);
        updatedAt = block.timestamp;
        emit StrategyExecuted(address(garden), _capital, _fee, block.timestamp);
    }

    /**
     * Enters the strategy.
     * Executes all the operations in order
     * @param _capital  Amount of capital that the strategy receives
     */
    function _enterStrategy(uint256 _capital) private {
        uint256 capitalForNexOperation = _capital;
        address assetAccumulated = garden.reserveAsset();
        uint8 assetStatus; // liquid
        for (uint256 i = 0; i < opTypes.length; i++) {
            IOperation operation = IOperation(IBabController(controller).enabledOperations(opTypes[i]));
            // _getOpDecodedData guarantee backward compatibility with OpData
            (assetAccumulated, capitalForNexOperation, assetStatus) = operation.executeOperation(
                assetAccumulated,
                capitalForNexOperation,
                assetStatus,
                _getOpDecodedData(i),
                garden,
                opIntegrations[i]
            );
        }
    }

    /**
     * Exits the strategy.
     * Exists all the operations starting by the end.
     * @param _percentage of capital to exit from the strategy
     */
    function _exitStrategy(uint256 _percentage) private {
        address assetFinalized = BytesLib.decodeOpDataAddressAssembly(_getOpDecodedData(opTypes.length - 1), 12);
        uint256 capitalPending;
        uint8 assetStatus;
        for (uint256 i = opTypes.length; i > 0; i--) {
            IOperation operation = IOperation(IBabController(controller).enabledOperations(opTypes[i - 1]));
            // _getOpDecodedData guarantee backward compatibility with OpData
            (assetFinalized, capitalPending, assetStatus) = operation.exitOperation(
                assetFinalized,
                capitalPending,
                assetStatus,
                // should use the percentage only for the first operation because we do not want to take percentage of
                // the percentage for the subsequent operations
                i == opTypes.length ? _percentage : HUNDRED_PERCENT,
                _getOpDecodedData(i - 1),
                garden,
                opIntegrations[i - 1]
            );
        }
        // Consolidate to reserve asset if needed
        if (assetFinalized != garden.reserveAsset() && capitalPending > 0) {
            if (assetFinalized == address(0)) {
                _handleWeth(true, capitalPending);
                assetFinalized = WETH;
            }
            if (assetFinalized != garden.reserveAsset()) {
                _trade(assetFinalized, capitalPending, garden.reserveAsset(), 0);
            }
        }
    }

    /**
     * Deletes this strategy and returns the stake to the strategist
     */
    function _deleteCandidateStrategy() private {
        _require(executedAt == 0 && !finalized, Errors.STRATEGY_IS_EXECUTED);
        IGarden(garden).expireCandidateStrategy(address(this));
    }

    /**
     * Low level function that allows an integration to make an arbitrary function
     * call to any contract from the garden (garden as msg.sender).
     *
     * @param _target                 Address of the smart contract to call
     * @param _value                  Quantity of Ether to provide the call (typically 0)
     * @param _data                   Encoded function selector and arguments
     * @return _returnValue           Bytes encoded return value
     */
    function _invoke(
        address _target,
        uint256 _value,
        bytes memory _data
    ) private returns (bytes memory _returnValue) {
        _returnValue = _target.functionCallWithValue(_data, _value, 'no err msg');
        emit Invoked(_target, _value, _data, _returnValue);
        return _returnValue;
    }

    function _sendReserveAssetToGarden() private {
        // Sends the rest back if any
        IERC20(garden.reserveAsset()).safeTransfer(
            address(garden),
            IERC20(garden.reserveAsset()).balanceOf(address(this))
        );
    }

    /**
     * Function that calculates the price using the oracle and executes a trade.
     * Must call the exchange to get the price and pass minReceiveQuantity accordingly.
     * @param _sendToken                    Token to exchange
     * @param _sendQuantity                 Amount of tokens to send
     * @param _receiveToken                 Token to receive
     * @param _overrideSlippage             Override slippage
     */
    function _trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _overrideSlippage
    ) private returns (uint256) {
        // Uses on chain oracle for all internal strategy operations to avoid attacks
        uint256 pricePerTokenUnit = _getPrice(_sendToken, _receiveToken);
        _require(pricePerTokenUnit != 0, Errors.NO_PRICE_FOR_TRADE);
        // minAmount must have receive token decimals
        uint256 exactAmount =
            SafeDecimalMath.normalizeAmountTokens(
                _sendToken,
                _receiveToken,
                _sendQuantity.preciseMul(pricePerTokenUnit)
            );
        uint256 slippage =
            _overrideSlippage != 0 ? _overrideSlippage : maxTradeSlippagePercentage != 0
                ? maxTradeSlippagePercentage
                : DEFAULT_TRADE_SLIPPAGE;
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(slippage));
        ITradeIntegration(IBabController(controller).masterSwapper()).trade(
            address(this),
            _sendToken,
            _sendQuantity,
            _receiveToken,
            minAmountExpected
        );
        return minAmountExpected;
    }

    function _transferStrategyPrincipal() private {
        address reserveAsset = garden.reserveAsset();
        int256 strategyReturns = capitalReturned.toInt256().sub(capitalAllocated.toInt256());
        uint256 protocolProfits;
        uint256 burningAmount;
        // Strategy returns were positive
        // in reserve asset, e.g., WETH, USDC, DAI, WBTC
        uint256 profits = capitalReturned > capitalAllocated ? capitalReturned.sub(capitalAllocated) : 0;
        if (capitalReturned >= capitalAllocated) {
            // Send weth performance fee to the protocol
            protocolProfits = IBabController(controller).protocolPerformanceFee().preciseMul(profits);
            if (protocolProfits > 0) {
                // Send profits to the heart
                IERC20(reserveAsset).safeTransfer(IBabController(controller).heart(), protocolProfits);
            }
            strategyReturns = strategyReturns.sub(protocolProfits.toInt256());
        } else {
            // Returns were negative so let's burn the strategiest stake
            burningAmount = (stake.sub(capitalReturned.preciseDiv(capitalAllocated).preciseMul(stake))).multiplyDecimal(
                STAKE_QUADRATIC_PENALTY_FOR_LOSSES
            );
        }
        // Return the balance back to the garden
        IERC20(reserveAsset).safeTransfer(address(garden), capitalReturned.sub(protocolProfits));
        _updateProtocolPrincipal(capitalAllocated, false);
        // Assign BABL Mining Strategy Rewards
        strategyRewards = uint256(rewardsDistributor.getStrategyRewards(address(this)));
        // profitsSharing[0]: strategistProfit %, profitsSharing[1]: stewardsProfit %, profitsSharing[2]: lpProfit %
        uint256[3] memory profitsSharing = rewardsDistributor.getGardenProfitsSharing(address(garden));
        // All rewards on Heart Garden are re-compounded (not set aside)
        // Only LP profits are compounded otherwise (strategist and stewards are set aside)
        uint256 rewardsToSetAside =
            (address(garden) != address(IHeart(controller.heart()).heartGarden()))
                ? profits.sub(profits.preciseMul(profitsSharing[2])).sub(protocolProfits)
                : 0;
        // Checkpoint of garden supply (must go before burning tokens if penalty for strategist)
        endingGardenSupply = IERC20(address(garden)).totalSupply();
        garden.finalizeStrategy(rewardsToSetAside, strategyReturns, burningAmount);
    }

    function _updateProtocolPrincipal(uint256 _capital, bool _addOrSubstract) internal {
        rewardsDistributor.updateProtocolPrincipal(_capital, _addOrSubstract);
    }

    function _getPrice(address _assetOne, address _assetTwo) private view returns (uint256) {
        try IPriceOracle(IBabController(controller).priceOracle()).getPrice(_assetOne, _assetTwo) returns (
            uint256 price
        ) {
            return price;
        } catch {
            return 0;
        }
    }

    function _updateExpectedReturn(
        uint256 _newCapital,
        uint256 _deltaAmount,
        bool _addedCapital
    ) private view returns (uint256) {
        uint256 capital = _addedCapital ? _newCapital : _newCapital.add(_deltaAmount);
        uint256 cube = capital.mul(duration);
        uint256 ratio;
        if (_addedCapital) {
            // allocation of new capital
            ratio = cube.sub(_deltaAmount.mul(block.timestamp.sub(executedAt))).preciseDiv(cube);
        } else {
            // Unwind
            ratio = cube.preciseDiv(cube.sub(_deltaAmount.mul(executedAt.add(duration).sub(block.timestamp))));
        }
        return expectedReturn.preciseMul(ratio);
    }

    // backward compatibility with OpData in case of ongoing strategies with deprecated OpData
    function _getOpDecodedData(uint256 _index) private view returns (bytes memory) {
        return
            opDatas.length > 0 ? abi.encode(opDatas[_index], address(0)) : BytesLib.get64Bytes(opEncodedData, _index);
    }

    function _handleWeth(bool _isDeposit, uint256 _wethAmount) private {
        _onlyUnpaused();
        if (_isDeposit) {
            IWETH(WETH).deposit{value: _wethAmount}();
            return;
        }
        IWETH(WETH).withdraw(_wethAmount);
    }

    // solhint-disable-next-line
    receive() external payable {}
}

contract StrategyV20 is Strategy {}
