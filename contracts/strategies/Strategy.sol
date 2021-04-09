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

pragma solidity 0.7.4;

import 'hardhat/console.sol';

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/Initializable.sol';

import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';

import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {ITradeIntegration} from '../interfaces/ITradeIntegration.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';

/**
 * @title Strategy
 * @author Babylon Finance
 *
 * Holds the data for an investment strategy
 */
contract Strategy is ReentrancyGuard, Initializable {
    using SignedSafeMath for int256;
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using AddressArrayUtils for address[];
    using Address for address;

    /* ============ Events ============ */
    event Invoked(address indexed _target, uint256 indexed _value, bytes _data, bytes _returnValue);
    event PositionAdded(address indexed _component);
    event PositionRemoved(address indexed _component);
    event PositionBalanceEdited(address indexed _component, int256 _realBalance);

    /* ============ Modifiers ============ */
    /**
     * Throws if the sender is not the creator of the strategy
     */
    modifier onlyController {
        require(msg.sender == address(controller), 'Only Controller can access this');
        _;
    }

    modifier onlyIdeator {
        require(msg.sender == strategist, 'Only Ideator can access this');
        _;
    }

    modifier onlyContributor {
        require(ERC20(address(garden)).balanceOf(msg.sender) > 0, 'Only someone with the garden token can withdraw');
        _;
    }

    /**
     * Throws if the sender is not a Garden's integration or integration not enabled
     */
    modifier onlyIntegration() {
        // Internal function used to reduce bytecode size
        require(
            controller.isValidIntegration(ITradeIntegration(msg.sender).getName(), msg.sender),
            'Integration must be valid'
        );
        _;
    }

    /**
     * Throws if the garden is not active
     */
    modifier onlyActiveGarden() {
        require(garden.active() == true, 'Garden must be active');
        _;
    }

    /**
     * Throws if the sender is not a keeper in the protocol
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     */
    modifier onlyKeeper(uint256 _fee) {
        require(controller.isValidKeeper(msg.sender), 'Only a keeper can call this');
        // We assume that calling keeper functions should be less expensive than 1 million gas and the gas price should be lower than 1000 gwei.
        require(_fee < MAX_KEEPER_FEE, 'Fee is too high');
        _;
    }

    /* ============ Constants ============ */

    uint256 constant SLIPPAGE_ALLOWED = 1e16; // 1%
    uint256 constant MAX_CANDIDATE_PERIOD = 7 days;
    uint256 constant MIN_VOTERS_TO_BECOME_ACTIVE = 2;

    // Keeper max fee
    uint256 internal constant MAX_KEEPER_FEE = (1e6 * 1e3 gwei);
    uint256 internal constant MAX_STRATEGY_KEEPER_FEES = 2 * MAX_KEEPER_FEE;

    /* ============ State Variables ============ */

    // Babylon Controller Address
    IBabController public controller;

    //Type of strategy.
    // 0 = LongStrategy
    // 1 = LiquidityPoolStrategy
    // 2 = YieldFarmingStrategy
    // 3 = LendStrategy
    uint8 public kind;

    // Garden that these strategies belong to
    IGarden public garden;
    address public integration; // Address of the integration
    address public strategist; // Address of the strategist that submitted the bet
    uint256 public enteredAt; // Timestamp when the strategy was submitted
    uint256 public enteredCooldownAt; // Timestamp when the strategy reached quorum
    uint256 public executedAt; // Timestamp when the strategy was executed
    uint256 public updatedAt; // Timestamp of last capital allocation update
    uint256 public exitedAt; // Timestamp when the strategy was submitted
    address[] public voters; // Addresses with the voters
    int256 public totalVotes; // Total votes staked
    uint256 public absoluteTotalVotes; // Absolute number of votes staked
    bool public finalized; // Flag that indicates whether we exited the strategy
    bool public active; // Whether the strategy has met the voting quorum
    bool public dataSet;

    uint256 public duration; // Duration of the bet
    uint256 public stake; // Amount of stake by the strategist (in reserve asset) needs to be positive
    uint256 public maxCapitalRequested; // Amount of max capital to allocate
    uint256 public capitalAllocated; // Current amount of capital allocated
    uint256 public expectedReturn; // Expect return by this investment strategy
    uint256 public capitalReturned; // Actual return by this investment strategy
    uint256 public minRebalanceCapital; // Min amount of capital so that it is worth to rebalance the capital here
    address[] public tokensNeeded; // Positions that need to be taken prior to enter trade
    uint256[] public tokenAmountsNeeded; // Amount of these positions

    uint256 public strategyRewards = 0; // Initialization. Rewards allocated for this strategy updated on finalized
    uint256 public rewardsTotalOverhead = 0;

    // Voters mapped to their votes.
    mapping(address => int256) public votes;

    /* ============ Constructor ============ */

    /**
     * Before a garden is initialized, the garden strategies need to be created and passed to garden initialization.
     *
     * @param _strategist                    Address of the strategist
     * @param _garden                        Address of the garden
     * @param _controller                    Address of the controller
     * @param _maxCapitalRequested           Max Capital requested denominated in the reserve asset (0 to be unlimited)
     * @param _stake                         Stake with garden participations absolute amounts 1e18
     * @param _investmentDuration            Investment duration in seconds
     * @param _expectedReturn                Expected return
     * @param _minRebalanceCapital           Min capital that is worth it to deposit into this strategy
     */
    function initialize(
        address _strategist,
        address _garden,
        address _controller,
        address _integration,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _investmentDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital
    ) public initializer {
        controller = IBabController(_controller);
        garden = IGarden(_garden);
        require(
            controller.isValidIntegration(ITradeIntegration(_integration).getName(), _integration),
            'Integration must be valid'
        );
        require(controller.isSystemContract(_garden), 'Must be a valid garden');
        require(ERC20(address(garden)).balanceOf(_strategist) > 0, 'Only someone with the garden token can withdraw');
        require(_stake > garden.totalSupply().div(100), 'Stake amount must be at least 1% of the garden');
        require(
            _investmentDuration >= garden.minIdeaDuration() && _investmentDuration <= garden.maxIdeaDuration(),
            'Investment duration must be in range'
        );
        require(_stake > 0, 'Stake amount must be greater than 0');
        require(_minRebalanceCapital > 0, 'Min Capital requested amount must be greater than 0');
        require(
            _maxCapitalRequested >= _minRebalanceCapital,
            'The max amount of capital must be greater than one chunk'
        );
        // Check than enter and exit data call integrations
        strategist = _strategist;
        enteredAt = block.timestamp;
        stake = _stake;
        duration = _investmentDuration;
        expectedReturn = _expectedReturn;
        capitalAllocated = 0;
        minRebalanceCapital = _minRebalanceCapital;
        maxCapitalRequested = _maxCapitalRequested;
        totalVotes = _stake.toInt256();
        absoluteTotalVotes = _stake;
        integration = _integration;
        dataSet = false;
    }

    /* ============ External Functions ============ */

    /**
     * Adds results of off-chain voting on-chain.
     * @param _voters                  An array of garden memeber who voted on strategy.
     * @param _votes                   An array of votes by on strategy by garden members. Votes can be positive or negative.
     * @param _absoluteTotalVotes      Abosulte number of votes. _absoluteTotalVotes = abs(upvotes) + abs(downvotes).
     * @param _totalVotes              Total number of votes. _totalVotes = upvotes + downvotes.
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     */
    function resolveVoting(
        address[] calldata _voters,
        int256[] calldata _votes,
        uint256 _absoluteTotalVotes,
        int256 _totalVotes,
        uint256 _fee
    ) external onlyKeeper(_fee) onlyActiveGarden {
        require(!active, 'Voting is already resolved');
        // Set votes data
        for (uint256 i = 0; i < _voters.length; i++) {
            votes[_voters[i]] = _votes[i];
        }
        voters = _voters;
        absoluteTotalVotes = absoluteTotalVotes + _absoluteTotalVotes;
        totalVotes = totalVotes + _totalVotes;
        active = true;

        // Get Keeper Fees allocated
        garden.allocateCapitalToInvestment(MAX_STRATEGY_KEEPER_FEES);

        _payKeeper(msg.sender, _fee);
    }

    /**
     * Executes an strategy that has been activated and gone through the cooldown period.
     * Keeper will validate that quorum is reached, cacluates all the voting data and push it.
     * @param _capital                  The capital to allocate to this strategy.
     * @param _fee                      The fee paid to keeper to compensate the gas cost.
     */
    function executeInvestment(uint256 _capital, uint256 _fee) public onlyKeeper(_fee) nonReentrant onlyActiveGarden {
        require(active, 'Idea needs to be active');
        require(capitalAllocated.add(_capital) <= maxCapitalRequested, 'Max capital reached');
        require(_capital >= minRebalanceCapital, 'Amount needs to be more than min');
        require(
            block.timestamp.sub(enteredCooldownAt) >= garden.strategyCooldownPeriod(),
            'Idea has not completed the cooldown period'
        );

        // Execute enter trade
        garden.allocateCapitalToInvestment(_capital);
        capitalAllocated = capitalAllocated.add(_capital);
        _enterStrategy(_capital);

        // Sets the executed timestamp on first execution
        if (executedAt == 0) {
            executedAt = block.timestamp;
            updatedAt = executedAt;
        } else {
            // Updating allocation - we need to consider the difference for the calculation
            // We control the potential overhead in BABL Rewards calculations to keep control and avoid distributing a wrong number (e.g. flash loans)
            rewardsTotalOverhead = rewardsTotalOverhead.add(_capital.mul(block.timestamp.sub(updatedAt)));
        }

        // Add to Rewards Distributor an update of the Protocol Principal for BABL Mining Rewards calculations
        IRewardsDistributor rewardsDistributor =
            IRewardsDistributor(IBabController(controller).getRewardsDistributor());
        rewardsDistributor.addProtocolPrincipal(_capital);
        _payKeeper(msg.sender, _fee);
        updatedAt = block.timestamp;
    }

    /**
     * Exits from an executed investment.
     * Sends rewards to the person that created the strategy, the voters, and the rest to the garden.
     * If there are profits
     * Updates the reserve asset position accordingly.
     * @param _fee                     The fee paid to keeper to compensate the gas cost
     */
    function finalizeInvestment(uint256 _fee) external onlyKeeper(_fee) nonReentrant onlyActiveGarden {
        require(executedAt > 0, 'This strategy has not been executed');
        require(
            block.timestamp > executedAt.add(duration),
            'Idea can only be finalized after the minimum period has elapsed'
        );
        require(!finalized, 'This investment was already exited');
        // Execute exit trade
        _exitStrategy();
        // Mark as finalized
        finalized = true;
        active = false;
        exitedAt = block.timestamp;
        updatedAt = exitedAt;
        // Transfer rewards
        _transferStrategyRewards(_fee);
        // Pay Keeper Fee
        _payKeeper(msg.sender, _fee);
        uint256 remainingReserve = ERC20(garden.reserveAsset()).balanceOf(address(this));
        // Sends the rest back if any
        require(
            ERC20(garden.reserveAsset()).transfer(address(garden), remainingReserve),
            'Ensure capital does not get stuck'
        );
    }

    /**
     * Expires a candidate that has spent more than CANDIDATE_PERIOD without
     * reaching quorum
     */
    function expireStrategy(uint256 _fee) external onlyKeeper(_fee) nonReentrant onlyActiveGarden {
        _deleteCandidateStrategy();
        _payKeeper(msg.sender, _fee);
    }

    /**
     * Delete a candidate strategy by the ideator
     */
    function deleteCandidateStrategy() external onlyIdeator {
        _deleteCandidateStrategy();
    }

    /**
     * Lets the strategist change the duration of the investment
     * @param _newDuration            New duration of the strategy
     */
    function changeInvestmentDuration(uint256 _newDuration) external onlyIdeator {
        require(!finalized, 'This investment was already exited');
        require(_newDuration < duration, 'Duration needs to be less than the old duration');
        duration = _newDuration;
    }

    // Any tokens (other than the target) that are sent here by mistake are recoverable by contributors
    // Exchange for WETH
    function sweep(address _token) external onlyContributor {
        // TODO: check that is not any of the strategy tokens
        require(_token != garden.reserveAsset(), 'Cannot sweep reserve asset');
        uint256 balance = ERC20(_token).balanceOf(address(this));
        require(balance > 0, 'Token balance > 0');
        _trade(_token, balance, garden.reserveAsset());
    }

    function invokeApprove(
        address _spender,
        address _asset,
        uint256 _quantity
    ) external onlyIntegration {
        ERC20(_asset).approve(_spender, 0);
        ERC20(_asset).approve(_spender, _quantity);
    }

    function invokeFromIntegration(
        address _target,
        uint256 _value,
        bytes calldata _data
    ) external onlyIntegration returns (bytes memory) {
        return _invoke(_target, _value, _data);
    }

    /* ============ External Getter Functions ============ */

    /**
     * Returns whether this strategy is currently active or not
     */
    function isIdeaActive() external view returns (bool) {
        return executedAt > 0 && exitedAt == 0;
    }

    /**
     * Get the non-state related details of a Strategy
     *
     */
    function getStrategyDetails()
        external
        view
        returns (
            address,
            address,
            address,
            uint256,
            uint256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            address(this),
            strategist,
            integration,
            stake,
            absoluteTotalVotes,
            totalVotes,
            capitalAllocated,
            duration,
            expectedReturn,
            maxCapitalRequested,
            minRebalanceCapital,
            enteredAt
        );
    }

    /**
     * Get the state of a Strategy
     *
     */
    function getStrategyState()
        external
        view
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

    function getUserVotes(address _address) external view returns (int256) {
        return votes[_address];
    }

    /* ============ Internal Functions ============ */

    /**
     * Pays gas cost back to the keeper from executing a transaction
     * @param _keeper             Keeper that executed the transaction
     * @param _fee                The fee paid to keeper to compensate the gas cost
     */
    function _payKeeper(address payable _keeper, uint256 _fee) internal {
        require(IBabController(controller).isValidKeeper(_keeper), 'Only Keeper'); // Only keeper
        // Pay Keeper in WETH
        if (_fee > 0) {
            require(ERC20(garden.reserveAsset()).balanceOf(address(this)) >= _fee, 'Not enough weth to pay keeper'); // not enough weth for gas subsidy
            require(ERC20(garden.reserveAsset()).transfer(_keeper, _fee), 'Not enough weth to pay keeper'); // not enough weth for gas subsidy
        }
    }

    /**
     * Enters the strategy. Virtual method.
     * Needs to be overriden in base class.
     *
     */
    function _enterStrategy(
        uint256 /*_capital*/
    ) internal virtual {
        require(false, 'This needs to be overriden');
    }

    /**
     * Exits the strategy. Virtual method.
     * Needs to be overriden in base class.
     *
     */
    function _exitStrategy() internal virtual {
        require(false, 'This needs to be overriden');
    }

    /**
     * Deletes this strategy and returns the stake to the strategist
     */
    function _deleteCandidateStrategy() internal {
        require(block.timestamp.sub(enteredAt) > MAX_CANDIDATE_PERIOD, 'Voters still have time');
        require(executedAt == 0, 'This strategy has executed');
        require(!finalized, 'This strategy already exited');
        IGarden(garden).expireCandidateStrategy(address(this));
        // TODO: Call selfdestruct??
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
    ) internal returns (bytes memory _returnValue) {
        _returnValue = _target.functionCallWithValue(_data, _value);
        emit Invoked(_target, _value, _data, _returnValue);
        return _returnValue;
    }

    /**
     * Function that calculates the price using the oracle and executes a trade.
     * Must call the exchange to get the price and pass minReceiveQuantity accordingly.
     * @param _sendToken                    Token to exchange
     * @param _sendQuantity                 Amount of tokens to send
     * @param _receiveToken                 Token to receive
     */
    function _trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken
    ) internal returns (uint256) {
        address tradeIntegration = IBabController(controller).getIntegrationByName('1inch');
        // Uses on chain oracle for all internal strategy operations to avoid attacks
        uint256 pricePerTokenUnit = _getPrice(_sendToken, _receiveToken);
        uint256 exactAmount = _sendQuantity.preciseMul(pricePerTokenUnit);
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
        ITradeIntegration(tradeIntegration).trade(_sendToken, _sendQuantity, _receiveToken, minAmountExpected);
        return minAmountExpected;
    }

    function _transferStrategyRewards(uint256 _fee) internal {
        capitalReturned = ERC20(garden.reserveAsset()).balanceOf(address(this)).sub(_fee).sub(MAX_STRATEGY_KEEPER_FEES);
        address reserveAsset = garden.reserveAsset();
        int256 reserveAssetDelta = capitalReturned.toInt256().sub(capitalAllocated.toInt256());
        uint256 protocolProfits = 0;
        // Idea returns were positive
        if (capitalReturned >= capitalAllocated) {
            uint256 profits = capitalReturned - capitalAllocated; // in reserve asset (weth)
            // Send weth performance fee to the protocol
            protocolProfits = IBabController(controller).getProtocolPerformanceFee().preciseMul(profits);
            require(
                ERC20(reserveAsset).transferFrom(
                    address(this),
                    IBabController(controller).getTreasury(),
                    protocolProfits
                ),
                'Protocol perf fee failed'
            );
            reserveAssetDelta.add(int256(-protocolProfits));
            capitalReturned = capitalReturned.sub(protocolProfits);
        } else {
            // Returns were negative
            // Burn strategist stake and add the amount to the garden
            garden.burnStrategistStake(strategist, capitalReturned.preciseDiv(capitalAllocated).preciseMul(stake));
            reserveAssetDelta.add(int256(stake));
        }
        // Return the balance back to the garden
        require(
            ERC20(reserveAsset).transferFrom(address(this), address(garden), capitalReturned),
            'Idea capital return failed'
        );

        // Updates reserve asset
        uint256 _newTotal = garden.principal().toInt256().add(reserveAssetDelta).toUint256();
        garden.updatePrincipal(_newTotal);
        // Start a redemption window in the garden with this capital
        garden.startRedemptionWindow(capitalReturned);

        // Moves strategy to finalized
        IGarden(garden).moveStrategyToFinalized(reserveAssetDelta, address(this));
        IRewardsDistributor rewardsDistributor =
            IRewardsDistributor(IBabController(controller).getRewardsDistributor());
        // Substract the Principal in the Rewards Distributor to update the Protocol power value
        rewardsDistributor.substractProtocolPrincipal(capitalAllocated);
        strategyRewards = rewardsDistributor.getStrategyRewards(address(this));
    }

    function _getPrice(address _assetOne, address _assetTwo) internal returns (uint256) {
        IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
        // Updates UniSwap TWAP
        oracle.updateAdapters(_assetOne, _assetTwo);
        return oracle.getPrice(_assetOne, _assetTwo);
    }

    receive() external payable {} // solium-disable-line quotes
}
