/*
    Copyright 2020 Babylon Finance.

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
import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {ITradeIntegration} from '../interfaces/ITradeIntegration.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';

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
     * Throws if the sender is not a Communities's integration or integration not enabled
     */
    modifier onlyIntegration() {
        // Internal function used to reduce bytecode size
        require(garden.isValidIntegration(msg.sender), 'Integration must be valid');
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
        require(IBabController(controller).isValidKeeper(msg.sender), 'Only a keeper can call this');
        // We assume that calling keeper functions should be less expensive than 1 million gas and the gas price should be lower than 1000 gwei.
        require(_fee < MAX_KEEPER_FEE, 'Fee is too high');
        _;
    }

    /* ============ Constants ============ */

    // Subposition constants
    uint8 constant LIQUID_STATUS = 0;
    uint8 constant LOCKED_AS_COLLATERAL_STATUS = 1;
    uint8 constant IN_INVESTMENT_STATUS = 2;
    uint8 constant BORROWED_STATUS = 3;

    // Max candidate period
    uint256 constant MAX_CANDIDATE_PERIOD = 7 days;
    uint256 constant MIN_VOTERS_TO_BECOME_ACTIVE = 2;

    // Keeper max fee
    uint256 internal constant MAX_KEEPER_FEE = (1e6 * 1e3 gwei);

    /* ============ Struct ============ */

    struct SubPosition {
        address integration;
        int256 balance;
        uint8 status;
    }

    /**
     * A struct that stores a component's cash position details and external positions
     * This data structure allows O(1) access to a component's cash position units and
     * virtual units.
     *
     * @param component           Address of token in the Position
     * @param balance             Balance of this component
     * @param enteredAt           Timestamp when this position was entered
     * @param exitedAt            Timestamp when this position was exited
     * @param updatedAt           Timestamp when this position was updated
     */
    struct Position {
        address component;
        uint8 positionState;
        int256 balance;
        SubPosition[] subpositions;
        uint8 subpositionsCount;
        uint256 enteredAt;
        uint256 exitedAt;
        uint256[] updatedAt;
    }

    /* ============ State Variables ============ */

    // Babylon Controller Address
    IBabController public controller;

    uint8 public kind; //Type of strategy. 0 = long, 1 = pool...

    // Garden that these strategies belong to
    IGarden public garden;
    address public integration; // Address of the integration
    address public strategist; // Address of the strategist that submitted the bet
    uint256 public enteredAt; // Timestamp when the strategy was submitted
    uint256 public enteredCooldownAt; // Timestamp when the strategy reached quorum
    uint256 public executedAt; // Timestamp when the strategy was executed
    uint256 public exitedAt; // Timestamp when the strategy was submitted
    address[] public voters; // Addresses with the voters
    int256 public totalVotes; // Total votes staked
    uint256 public absoluteTotalVotes; // Absolute number of votes staked
    bool public finalized; // Flag that indicates whether we exited the strategy
    bool public active; // Whether the strategy has met the voting quorum
    bool public dataSet;

    uint256 public duration; // Duration of the bet
    uint256 public stake; // Amount of stake by the strategist (in reserve asset) Neds to be positive
    uint256 public maxCapitalRequested; // Amount of max capital to allocate
    uint256 public capitalAllocated; // Current amount of capital allocated
    uint256 public expectedReturn; // Expect return by this investment strategy
    uint256 public capitalReturned; // Actual return by this investment strategy
    uint256 public minRebalanceCapital; // Min amount of capital so that it is worth to rebalance the capital here
    address[] public tokensNeeded; // Positions that need to be taken prior to enter trade
    uint256[] public tokenAmountsNeeded; // Amount of these positions

    // Voters mapped to their votes.
    mapping(address => int256) public votes;

    // List of positions
    address[] public positions;
    mapping(address => Position) public positionsByComponent;

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
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _investmentDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital
    ) public initializer {
        controller = IBabController(_controller);
        garden = IGarden(_garden);
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
        dataSet = false;
    }

    /* ============ External Functions ============ */

    /**
     * Sets integration data for the investment
     *
     * @param _integration                    Address of the integration
     * @param _tokensNeeded                   Tokens that we need to acquire to enter this investment
     * @param _tokenAmountsNeeded             Token amounts of these assets we need
     */
    function setIntegrationData(
        address _integration,
        address[] memory _tokensNeeded,
        uint256[] memory _tokenAmountsNeeded
    ) public onlyIdeator {
        require(!dataSet, 'Data is set already');
        require(garden.isValidIntegration(_integration), 'Integration must be valid');
        require(_tokensNeeded.length == _tokenAmountsNeeded.length, 'Tokens and amounts must match');
        integration = _integration;
        tokensNeeded = _tokensNeeded;
        tokenAmountsNeeded = _tokenAmountsNeeded;
        dataSet = true;
    }

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
        garden.payKeeper(msg.sender, _fee);
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
        calculateAndEditPosition(garden.getReserveAsset(), _capital, _capital.toInt256(), LIQUID_STATUS);
        capitalAllocated = capitalAllocated.add(_capital);
        _enterStrategyPositions();
        _enterStrategy();
        // Sets the executed timestamp
        executedAt = block.timestamp;
        garden.payKeeper(msg.sender, _fee);
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
        uint256 reserveAssetBeforeExiting = garden.getPrincipal();
        // Execute exit trade
        _exitStrategy();
        _exitStrategyPositions();
        capitalReturned = garden.getPrincipal().sub(reserveAssetBeforeExiting);
        // Mark as finalized
        finalized = true;
        active = false;
        exitedAt = block.timestamp;
        // Transfer rewards and update positions
        _transferIdeaRewards();
        // Moves strategy to finalized
        IGarden(garden).moveStrategyToFinalized(
            capitalReturned.toInt256().sub(capitalAllocated.toInt256()),
            address(this)
        );
        garden.payKeeper(msg.sender, _fee);
    }

    /**
     * Expires a candidate that has spent more than CANDIDATE_PERIOD without
     * reaching quorum
     */
    function expireStrategy(uint256 _fee) external onlyKeeper(_fee) nonReentrant onlyActiveGarden {
        _deleteCandidateStrategy();
        garden.payKeeper(msg.sender, _fee);
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

    /**
     * Calculates the new  position balance and performs the edit with new balance
     *
     * @param _component                Address of the component
     * @param _newBalance               Current balance of the component
     * @param _deltaBalance             Delta applied on this op
     * @param _subpositionStatus        Status of the position
     * @return                          Current component balance
     * @return                          Previous position balance
     * @return                          New position balance
     */
    function calculateAndEditPosition(
        address _component,
        uint256 _newBalance,
        int256 _deltaBalance,
        uint8 _subpositionStatus
    )
        public
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 positionBalance = _getPositionBalance(_component).toUint256();

        bool isPositionFound = _hasPosition(_component);
        if (!isPositionFound && _newBalance > 0) {
            _addPosition(_component, msg.sender);
        } else if (isPositionFound && _newBalance == 0) {
            _removePosition(_component);
        }
        _editPositionBalance(_component, _newBalance.toInt256(), msg.sender, _deltaBalance, _subpositionStatus);

        return (_newBalance, positionBalance, _newBalance);
    }

    // Any tokens (other than the target) that are sent here by mistake are recoverable by contributors
    // Exchange for WETH
    function sweep(address _token) external onlyContributor {
        require(positionsByComponent[_token].balance == 0, 'Token is not one of the active positions');
        uint256 balance = ERC20(_token).balanceOf(address(this));
        require(balance > 0, 'Token balance > 0');
        // TODO: probably use uniswap or 1inch. Don't go through TWAP
        _trade('_kyber', _token, balance, garden.getReserveAsset(), 0);
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

    function isPosition(address _component) external view returns (bool) {
        return positions.contains(_component);
    }

    /**
     * Gets the total number of positions
     */
    function getPositionCount() external view returns (uint256) {
        return positions.length;
    }

    /**
     * Returns a list of Positions, through traversing the components.
     * balances are converted to real balances. This function is typically used off-chain for data presentation purposes.
     */
    function getPositions() external view returns (address[] memory) {
        return positions;
    }

    /**
     * Returns whether the garden component  position real balance is greater than or equal to balances passed in.
     */
    function hasSufficientBalance(address _component, uint256 _balance) external view returns (bool) {
        return _getPositionBalance(_component).toUint256() >= _balance;
    }

    /**
     * Get the position of a component
     *
     * @param _component          Address of the component
     * @return                    Balance
     */
    function getPositionBalance(address _component) external view returns (int256) {
        return _getPositionBalance(_component);
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
            uint256,
            uint256
        )
    {
        return (address(this), active, finalized, executedAt, exitedAt);
    }

    /* ============ Internal Functions ============ */

    /**
     * Enters the strategy. Virtual method.
     * Needs to be overriden in base class.
     *
     */
    function _enterStrategy() internal virtual {
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
     * Forcefully quits the strategy. Virtual method.
     * Needs to be overriden in base class.
     *
     */
    function _quitStrategy() internal virtual {
        require(false, 'This needs to be overriden');
    }

    /**
     * Deletes this strategy and returns the stake to the strategist
     */
    function _deleteCandidateStrategy() internal {
        require(block.timestamp.sub(enteredAt) > MAX_CANDIDATE_PERIOD, 'Voters still have time');
        require(executedAt == 0, 'This strategy has executed');
        require(!finalized, 'This strategy already exited');
        _returnStake();
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
     * Function that buys the assets required to enter the strategy
     */
    function _enterStrategyPositions() internal {
        // Exchange the tokens needed
        for (uint256 i = 0; i < tokensNeeded.length; i++) {
            if (tokensNeeded[i] != garden.getReserveAsset()) {
                uint256 pricePerTokenUnit = _getPrice(garden.getReserveAsset(), tokensNeeded[i]);
                uint256 slippageAllowed = 1e16; // 1%
                uint256 exactAmount = tokenAmountsNeeded[i].preciseDiv(pricePerTokenUnit);
                uint256 amountOfReserveAssetToAllow = exactAmount.add(exactAmount.preciseMul(slippageAllowed));
                require(
                    ERC20(garden.getReserveAsset()).balanceOf(address(this)) >= amountOfReserveAssetToAllow,
                    'Need enough liquid reserve asset'
                );
                _trade(
                    'kyber',
                    garden.getReserveAsset(),
                    amountOfReserveAssetToAllow,
                    tokensNeeded[i],
                    tokenAmountsNeeded[i]
                );
            }
        }
    }

    /**
     * Function that sells the strategy positions back to the reserve asset
     */
    function _exitStrategyPositions() internal {
        // Exchange the positions back to the reserve asset
        address reserveAsset = garden.getReserveAsset();
        for (uint256 i = 0; i < positions.length; i++) {
            if (positions[i] != reserveAsset) {
                _trade(
                    'kyber',
                    positions[i],
                    ERC20(positions[i]).balanceOf(address(this)),
                    reserveAsset,
                    0 // TODO: currently no minimum. use onchain oracle?
                );
            }
        }
    }

    /**
     * Function that calculates the price using the oracle and executes a trade.
     * Must call the exchange to get the price and pass minReceiveQuantity accordingly.
     * @param _integrationName        Name of the integration to call
     * @param _sendToken              Token to exchange
     * @param _sendQuantity           Amount of tokens to send
     * @param _receiveToken           Token to receive
     * @param _minReceiveQuantity     Min amount of tokens to receive
     */
    function _trade(
        string memory _integrationName,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) internal {
        address tradeIntegration = IBabController(controller).getIntegrationByName(_integrationName);
        require(garden.isValidIntegration(tradeIntegration), 'Integration is not valid');
        // Updates UniSwap TWAP
        IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
        oracle.updateAdapters(_sendToken, _receiveToken);
        return ITradeIntegration(tradeIntegration).trade(_sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity);
    }

    function _transferIdeaRewards() internal {
        address reserveAsset = garden.getReserveAsset();
        int256 reserveAssetDelta = 0;

        // Idea returns were positive
        if (capitalReturned > capitalAllocated) {
            uint256 profits = capitalReturned - capitalAllocated; // in reserve asset (weth)
            _returnStake();
            // Send weth performance fee to the protocol
            uint256 protocolProfits = IBabController(controller).getProtocolPerformanceFee().preciseMul(profits);
            require(
                ERC20(reserveAsset).transferFrom(
                    address(this),
                    IBabController(controller).getTreasury(),
                    protocolProfits
                ),
                'Protocol perf fee failed'
            );
            reserveAssetDelta.add(int256(-protocolProfits));

            // Send weth rewards to the strategist
            uint256 strategistProfits = garden.strategyCreatorProfitPercentage().preciseMul(profits);
            // Creator Bonus
            if (strategist == garden.creator()) {
                strategistProfits = strategistProfits.mul(2);
            }
            require(
                ERC20(reserveAsset).transferFrom(address(this), strategist, strategistProfits),
                'Ideator perf fee failed'
            );
            reserveAssetDelta.add(int256(-strategistProfits));

            // Send weth rewards to voters that voted in favor
            uint256 votersProfits = garden.strategyVotersProfitPercentage().preciseMul(profits);
            // TODO: Pull rewards
            for (uint256 i = 0; i < voters.length; i++) {
                int256 voterWeight = votes[voters[i]];
                if (voterWeight > 0) {
                    uint256 voterProfits = votersProfits.mul(voterWeight.toUint256()).div(totalVotes.toUint256());
                    if (strategist == garden.creator()) {
                        // Creator Bonus
                        voterProfits = voterProfits.mul(2);
                    }
                    require(
                        ERC20(reserveAsset).transferFrom(address(this), voters[i], voterProfits),
                        'Voter perf fee failed'
                    );
                }
            }
            reserveAssetDelta.add(int256(-votersProfits));
        } else {
            // Returns were negative
            uint256 stakeToSlash = stake;
            if (capitalReturned.add(stake) > capitalAllocated) {
                stakeToSlash = capitalReturned.add(stake).sub(capitalAllocated);
            }
            // We slash and add to the garden the stake from the creator
            uint256 votersRewards = garden.strategyVotersProfitPercentage().preciseMul(stakeToSlash);
            // Send weth rewards to voters that voted against
            // TODO: Pull rewards
            for (uint256 i = 0; i < voters.length; i++) {
                int256 voterWeight = votes[voters[i]];
                if (voterWeight < 0) {
                    require(
                        ERC20(reserveAsset).transferFrom(
                            address(this),
                            voters[i],
                            votersRewards.mul(voterWeight.toUint256()).div(totalVotes.toUint256())
                        ),
                        'Voter perf fee failed'
                    );
                }
            }
            reserveAssetDelta.add(int256(-stakeToSlash));
        }
        // Return the balance back to the garden
        require(
            ERC20(reserveAsset).transferFrom(address(this), address(garden), capitalReturned),
            'Idea capital return failed'
        );
        // Updates strategy posiiton
        calculateAndEditPosition(
            reserveAsset,
            ERC20(reserveAsset).balanceOf(address(this)),
            int256(-capitalReturned),
            LIQUID_STATUS
        );
        // Updates reserve asset position in the garden
        uint256 _newTotal = garden.getPrincipal().toInt256().add(reserveAssetDelta).toUint256();
        garden.updatePrincipal(_newTotal);
        // Start a redemption window in the garden with this capital
        garden.startRedemptionWindow(capitalReturned);
    }

    function _returnStake() internal {
        // Send stake back to the strategist
        require(ERC20(address(garden)).transferFrom(address(this), strategist, stake), 'Ideator stake return failed');
    }

    /**
     * Internal MODULE FUNCTION. Low level function that adds a component to the positions array.
     */
    function _addPosition(address _component, address _integration) internal {
        Position storage position = positionsByComponent[_component];

        position.subpositions.push(SubPosition({integration: _integration, balance: 0, status: 0}));
        position.subpositionsCount++;
        position.enteredAt = block.timestamp;

        positions.push(_component);
        emit PositionAdded(_component);
    }

    /**
     * Internal MODULE FUNCTION. Low level function that removes a component from the positions array.
     */
    function _removePosition(address _component) internal {
        Position storage position = positionsByComponent[_component];
        positions = positions.remove(_component);
        position.exitedAt = block.timestamp;
        emit PositionRemoved(_component);
    }

    /**
     * Internal MODULE FUNCTION. Low level function that edits a component's position
     */
    function _editPositionBalance(
        address _component,
        int256 _amount,
        address _integration,
        int256 _deltaBalance,
        uint8 _subpositionStatus
    ) internal {
        Position storage position = positionsByComponent[_component];
        position.balance = _amount;
        position.updatedAt.push(block.timestamp);
        int256 subpositionIndex = _getSubpositionIndex(_component, _integration);
        if (subpositionIndex == -1) {
            position.subpositions.push(
                SubPosition({integration: _integration, balance: _deltaBalance, status: _subpositionStatus})
            );
        } else {
            position.subpositions[subpositionIndex.toUint256()].balance = _deltaBalance;
            position.subpositions[subpositionIndex.toUint256()].status = _subpositionStatus;
        }

        emit PositionBalanceEdited(_component, _amount);
    }

    function _getSubpositionIndex(address _component, address _integration) internal view returns (int256) {
        Position storage position = positionsByComponent[_component];
        for (uint8 i = 0; i < position.subpositionsCount; i++) {
            if (position.subpositions[i].integration == _integration) {
                return i;
            }
        }
        return -1;
    }

    /**
     * Returns whether the garden has a position for a given component (if the real balance is > 0)
     */
    function _hasPosition(address _component) internal view returns (bool) {
        return _getPositionBalance(_component) > 0;
    }

    function _getPositionBalance(address _component) internal view returns (int256) {
        return positionsByComponent[_component].balance;
    }

    function abs(int256 x) private pure returns (int256) {
        return x >= 0 ? x : -x;
    }

    function _getPrice(address _assetOne, address _assetTwo) internal returns (uint256) {
        IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
        // Updates UniSwap TWAP
        oracle.updateAdapters(_assetOne, _assetTwo);
        return oracle.getPrice(_assetOne, _assetTwo);
    }
}
