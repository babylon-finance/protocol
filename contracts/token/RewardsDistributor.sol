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

import {TimeLockedToken} from './TimeLockedToken.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';
import {Safe3296} from '../lib/Safe3296.sol';

import {IBabController} from '../interfaces/IBabController.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {TimeLockedToken} from './TimeLockedToken.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';

/**
 * @title Rewards Distributor implementing the BABL Mining Program
 * @author Babylon Finance
 * Rewards Distributor contract is a smart contract used to calculate and distribute all the BABL rewards of the BABL Mining Program
 * along the time reserve for executed strategies. It implements a supply curve to distribute 500K BABL along the time.
 * The supply curve is designed to optimize the long-term sustainability of the protocol.
 * The rewards are front-loaded but they last for more than 10 years, slowly decreasing quarter by quarter.
 * For that, it houses the state of the protocol power along the time as each strategy power is compared to the whole protocol usage.
 */
contract RewardsDistributor is Ownable, IRewardsDistributor {
    using SafeMath for uint256;
    using SafeMath for int256;
    using PreciseUnitMath for uint256;
    using PreciseUnitMath for int256;
    using SafeDecimalMath for uint256;
    using SafeDecimalMath for int256;
    using Math for uint256;
    using Math for int256;
    using Safe3296 for uint256;
    using Safe3296 for int256;
    using Safe3296 for uint96;
    using Safe3296 for uint32;

    /* ========== Events ========== */

    /* ============ Modifiers ============ */

    modifier onlyStrategy {
        require(controller.isSystemContract(address(IStrategy(msg.sender).garden())));
        _;
    }

    /* ============ Constants ============ */
    // 500K BABL allocated to this BABL Mining Program, the first quarter is Q1_REWARDS
    // and the following quarters will follow the supply curve using a decay rate
    uint256 public constant override Q1_REWARDS = 53_571_428_571_428_600e6; // First quarter (epoch) BABL rewards
    // 12% quarterly decay rate (each 90 days)
    // (Rewards on Q1 = 1,12 * Rewards on Q2) being Q1= Quarter 1, Q2 = Quarter 2
    uint256 public constant override DECAY_RATE = 120000000000000000;
    // Duration of its EPOCH in days  // BABL & profits split from the protocol
    uint256 public constant override EPOCH_DURATION = 90 days;

    // solhint-disable-next-line
    uint256 public immutable override START_TIME; // Starting time of the rewards distribution

    // solhint-disable-next-line
    uint256 public immutable BABL_STRATEGIST_SHARE;
    // solhint-disable-next-line
    uint256 public immutable BABL_STEWARD_SHARE;
    // solhint-disable-next-line
    uint256 public immutable BABL_LP_SHARE;
    // solhint-disable-next-line
    uint256 public immutable PROFIT_STRATEGIST_SHARE;
    // solhint-disable-next-line
    uint256 public immutable PROFIT_STEWARD_SHARE;
    // solhint-disable-next-line
    uint256 public immutable PROFIT_LP_SHARE;
    // solhint-disable-next-line
    uint256 public immutable PROFIT_PROTOCOL_FEE;
    // solhint-disable-next-line
    uint256 public immutable CREATOR_BONUS;

    /* ============ Structs ============ */
    struct ProtocolPerTimestamp {
        // Allocation points per timestamp along the time
        uint256 principal; // Checkpoint principal
        uint256 time; // Checkpoint time
        uint256 quarterBelonging; // Checkpoint quarter
        uint256 timeListPointer; // Pointer to the array of times in order to enable the possibility of iteration
        uint256 power; // Protocol power checkpoint
    }

    struct ProtocolPerQuarter {
        // Allocation points per timestamp along the time
        uint256 quarterPrincipal; //
        uint256 quarterNumber; // # Quarter since START_TIME
        uint256 quarterPower; // Protocol power checkpoint
        uint96 supplyPerQuarter; // Supply per quarter
    }

    /* ============ State Variables ============ */

    // Controller contract
    IBabController public controller;

    // BABL Token contract
    TimeLockedToken public babltoken;

    // Total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all strategy pools.
    uint256 public override protocolPrincipal;
    // Total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all strategy pools.
    mapping(uint256 => ProtocolPerTimestamp) public protocolPerTimestamp;
    uint256[] public timeList; // TODO needs to be updated anytime there is a checkpoint of new strategy changing
    uint256 public override pid; // Initialization of the ID assigning timeListPointer to the checkpoint number

    mapping(uint256 => ProtocolPerQuarter) public protocolPerQuarter; //
    mapping(uint256 => bool) public isProtocolPerQuarter; // Check if the protocol per quarter data has been initialized

    // Only used if each strategy has power overhead due to changes overtime
    mapping(address => mapping(uint256 => uint256)) public rewardsPowerOverhead;

    /* ============ Constructor ============ */

    constructor(TimeLockedToken _bablToken, IBabController _controller) {
        require(address(_bablToken) != address(0), 'Token needs to exist');
        require(address(_controller) != address(0), 'Controller needs to exist');
        babltoken = _bablToken;
        controller = _controller;
        START_TIME = block.timestamp;

        (BABL_STRATEGIST_SHARE, BABL_STEWARD_SHARE, BABL_LP_SHARE, CREATOR_BONUS) = controller.getBABLSharing();
        (PROFIT_STRATEGIST_SHARE, PROFIT_STEWARD_SHARE, PROFIT_LP_SHARE) = controller.getProfitSharing();
        PROFIT_PROTOCOL_FEE = controller.protocolPerformanceFee();
    }

    /* ============ External Functions ============ */

    /**
     * Function that adds the capital received to the total principal of the protocol per timestamp
     * @param _capital                Amount of capital in WETH
     */
    function addProtocolPrincipal(uint256 _capital) external override onlyStrategy {
        IStrategy strategy = IStrategy(msg.sender);
        protocolPrincipal = protocolPrincipal.add(_capital);
        ProtocolPerTimestamp storage protocolCheckpoint = protocolPerTimestamp[block.timestamp];
        protocolCheckpoint.principal = protocolPrincipal;
        protocolCheckpoint.time = block.timestamp;
        protocolCheckpoint.quarterBelonging = getQuarter(block.timestamp);
        protocolCheckpoint.timeListPointer = pid;
        if (pid == 0) {
            // The very first strategy of all strategies in the mining program
            protocolCheckpoint.power = 0;
        } else {
            // Any other strategy different from the very first one (will have an antecesor)
            protocolCheckpoint.power = protocolPerTimestamp[timeList[pid.sub(1)]].power.add(
                protocolCheckpoint.time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time).mul(
                    protocolPerTimestamp[timeList[pid.sub(1)]].principal
                )
            );
        }

        timeList.push(block.timestamp); // Register of added strategies timestamps in the array for iteration
        // Here we control the accumulated protocol power per each quarter
        // Create the quarter checkpoint in case the checkpoint is the first in the epoch
        _addProtocolPerQuarter(block.timestamp);
        // We update the rewards overhead if any
        //rewardsPowerOverhead[address(strategy)][getQuarter(block.timestamp)] = rewardsPowerOverhead[address(strategy)][getQuarter(block.timestamp)].add(_capital.mul(block.timestamp.sub(strategy.updatedAt())));
        _updatePowerOverhead(strategy, _capital);
        pid++;
    }

    /**
     * Function that removes the capital received to the total principal of the protocol per timestamp
     * @param _capital                Amount of capital in WETH
     */
    function substractProtocolPrincipal(uint256 _capital) external override onlyStrategy {
        protocolPrincipal = protocolPrincipal.sub(_capital);
        ProtocolPerTimestamp storage protocolCheckpoint = protocolPerTimestamp[block.timestamp];
        protocolCheckpoint.principal = protocolPrincipal;
        protocolCheckpoint.time = block.timestamp;
        protocolCheckpoint.quarterBelonging = getQuarter(block.timestamp);
        protocolCheckpoint.timeListPointer = pid;
        protocolCheckpoint.power = protocolPerTimestamp[timeList[pid.sub(1)]].power.add(
            protocolCheckpoint.time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time).mul(
                protocolPerTimestamp[timeList[pid.sub(1)]].principal
            )
        );
        timeList.push(block.timestamp);
        // Here we control the accumulated protocol power per each quarter
        // Create the quarter checkpoint in case the checkpoint is the first in the epoch or there were epochs without checkpoints
        _addProtocolPerQuarter(block.timestamp);
        pid++;
    }

    /**
     * Gets the total amount of rewards for a given strategy
     * @param _strategy                Strategy to check
     */
    function getStrategyRewards(address _strategy) external override returns (uint96) {
        IStrategy strategy = IStrategy(_strategy);
        require(strategy.exitedAt() != 0, 'The strategy has to be finished');
        // We avoid gas consuming once a strategy got its BABL rewards during its finalization
        uint256 rewards = strategy.strategyRewards();
        if (rewards != 0) {
            return Safe3296.safe96(rewards, 'overflow 96 bits');
        }

        // If the calculation was not done earlier we go for it
        (uint256 numQuarters, uint256 startingQuarter) = getRewardsWindow(strategy.executedAt(), strategy.exitedAt());
        uint256 bablRewards = 0;
        if (numQuarters <= 1) {
            bablRewards = _getStrategyRewardsOneQuarter(_strategy, startingQuarter); // Proportional supply till that moment within the same epoch
            require(bablRewards <= protocolPerQuarter[startingQuarter].supplyPerQuarter, 'overflow in supply');
            require(
                strategy.capitalAllocated().mul(strategy.exitedAt().sub(strategy.executedAt())).sub(
                    strategy.rewardsTotalOverhead()
                ) <= protocolPerQuarter[startingQuarter].quarterPower,
                'overflow in power'
            );
        } else {
            // The strategy takes longer than one quarter / epoch
            // We need to calculate the strategy vs. protocol power ratio per each quarter
            uint256[] memory strategyPower = new uint256[](numQuarters); // Strategy power in each Epoch
            uint256[] memory protocolPower = new uint256[](numQuarters); // Protocol power in each Epoch
            for (uint256 i = 0; i <= numQuarters.sub(1); i++) {
                uint256 slotEnding = START_TIME.add(startingQuarter.add(i).mul(EPOCH_DURATION)); // Initialization timestamp at the end of the first slot where the strategy starts its execution

                // We iterate all the quarters where the strategy was active
                uint256 percentage = 1e18;
                if (strategy.executedAt().add(EPOCH_DURATION) > slotEnding) {
                    // We are in the first quarter of the strategy

                    strategyPower[i] = strategy.capitalAllocated().mul(slotEnding.sub(strategy.executedAt())).sub(
                        rewardsPowerOverhead[address(strategy)][getQuarter(strategy.executedAt())]
                    );
                } else if (strategy.executedAt() < slotEnding.sub(EPOCH_DURATION) && slotEnding < strategy.exitedAt()) {
                    // We are in an intermediate quarter different from starting or ending quarters
                    strategyPower[i] = strategy
                        .capitalAllocated()
                        .mul(slotEnding.sub(slotEnding.sub(EPOCH_DURATION)))
                        .sub(rewardsPowerOverhead[address(strategy)][getQuarter(slotEnding.sub(45 days))]);
                } else {
                    // We are in the last quarter of the strategy
                    percentage = block.timestamp.sub(slotEnding.sub(EPOCH_DURATION)).preciseDiv(
                        slotEnding.sub(slotEnding.sub(EPOCH_DURATION))
                    );

                    strategyPower[i] = strategy
                        .capitalAllocated()
                        .mul(strategy.exitedAt().sub(slotEnding.sub(EPOCH_DURATION)))
                        .sub(rewardsPowerOverhead[address(strategy)][getQuarter(strategy.exitedAt())]);
                }
                protocolPower[i] = protocolPerQuarter[startingQuarter.add(i)].quarterPower;

                require(strategyPower[i] <= protocolPower[i], 'overflow str over protocol in an epoch');

                bablRewards = bablRewards.add(
                    strategyPower[i]
                        .preciseDiv(protocolPower[i])
                        .preciseMul(uint256(protocolPerQuarter[startingQuarter.add(i)].supplyPerQuarter))
                        .preciseMul(percentage)
                );
            }
        }

        // Babl rewards will be proportional to the total return (profit) with a max cap of x2
        uint256 percentageMul = strategy.capitalReturned().preciseDiv(strategy.capitalAllocated());
        if (percentageMul > 2e18) percentageMul = 2e18;
        bablRewards = bablRewards.preciseMul(percentageMul);

        return Safe3296.safe96(bablRewards, 'overflow 96 bits');
    }

    /**
     * Sends BABL tokens to a contributor.
     * @param _to                Address to send the tokens to
     * @param _amount            Amount of tokens to send the address to
     */
    function sendTokensToContributor(address _to, uint96 _amount) external override {
        require(controller.isSystemContract(msg.sender), 'The caller is not a system contract');
        _safeBABLTransfer(_to, _amount);
    }

    /**
     * Calculates the profits and BABL that a contributor should receive from a series of finalized strategies
     * @param _contributor              Address of the contributor to check
     * @param _finalizedStrategies      List of addresses of the finalized strategies
     */
    function getProfitsAndBabl(address _contributor, address[] calldata _finalizedStrategies)
        external
        view
        override
        returns (uint256, uint96)
    {
        require(controller.isSystemContract(msg.sender), 'The caller is not a system contract');
        uint256 contributorTotalProfits = 0;
        uint256 bablTotalRewards = 0;
        for (uint256 i = 0; i < _finalizedStrategies.length; i++) {
            (uint256 strategyProfits, uint256 strategyBABL) =
                _getStrategyProfitsAndBABL(_finalizedStrategies[i], _contributor);
            contributorTotalProfits = contributorTotalProfits.add(strategyProfits);
            bablTotalRewards = bablTotalRewards.add(strategyBABL);
        }

        return (contributorTotalProfits, Safe3296.safe96(bablTotalRewards, 'R28'));
    }

    /* ========== View functions ========== */

    function getProtocolPrincipalByTimestamp(uint256 _timestamp) external view override onlyOwner returns (uint256) {
        return protocolPerTimestamp[_timestamp].principal;
    }

    function getProtocolPowerPerQuarterByTimestamp(uint256 _timestamp)
        external
        view
        override
        onlyOwner
        returns (uint256)
    {
        return protocolPerQuarter[getQuarter(_timestamp)].quarterPower;
    }

    function getProtocolPowerPerQuarterById(uint256 _id) external view override onlyOwner returns (uint256) {
        return protocolPerQuarter[_id].quarterPower;
    }

    function getProtocolSupplyPerQuarterByTimestamp(uint256 _timestamp)
        external
        view
        override
        onlyOwner
        returns (uint256)
    {
        return protocolPerQuarter[getQuarter(_timestamp)].supplyPerQuarter;
    }

    function getEpochRewards(uint256 epochs) external pure override returns (uint96[] memory) {
        uint96[] memory tokensPerEpoch = new uint96[](epochs);
        for (uint256 i = 0; i <= epochs - 1; i++) {
            tokensPerEpoch[i] = (uint96(tokenSupplyPerQuarter(i.add(1))));
        }
        return tokensPerEpoch;
    }

    function getCheckpoints() external view override returns (uint256) {
        return pid;
    }

    function getQuarter(uint256 _now) public view override returns (uint256) {
        uint256 quarter = (_now.sub(START_TIME).preciseDivCeil(EPOCH_DURATION)).div(1e18);
        return quarter.add(1);
    }

    function getRewardsWindow(uint256 _from, uint256 _to) public view override returns (uint256, uint256) {
        uint256 quarters = (_to.sub(_from).preciseDivCeil(EPOCH_DURATION)).div(1e18);
        uint256 startingQuarter = (_from.sub(START_TIME).preciseDivCeil(EPOCH_DURATION)).div(1e18);
        return (quarters.add(1), startingQuarter.add(1));
    }

    function getSupplyForPeriod(uint256 _from, uint256 _to) external view override returns (uint96[] memory) {
        // check number of quarters and what quarters are they
        (uint256 quarters, uint256 startingQuarter) = getRewardsWindow(_from, _to);
        uint96[] memory supplyPerQuarter = new uint96[](quarters);
        if (quarters <= 1) {
            // Strategy Duration less than a quarter
            supplyPerQuarter[0] = Safe3296.safe96(tokenSupplyPerQuarter(startingQuarter.add(1)), 'overflow 96 bits');
            return supplyPerQuarter;
        } else if (quarters == 2) {
            // Strategy Duration less or equal of 2 quarters - we assume that high % of strategies will have a duration <= 2 quarters avoiding the launch of a for loop
            supplyPerQuarter[0] = Safe3296.safe96(tokenSupplyPerQuarter(startingQuarter), 'overflow 96 bits');
            supplyPerQuarter[1] = Safe3296.safe96(tokenSupplyPerQuarter(startingQuarter.add(1)), 'overflow 96 bits');
            return supplyPerQuarter;
        } else {
            for (uint256 i = 0; i <= quarters.sub(1); i++) {
                supplyPerQuarter[i] = Safe3296.safe96(
                    tokenSupplyPerQuarter(startingQuarter.add(1).add(i)),
                    'overflow 96 bits'
                );
            }
            return supplyPerQuarter;
        }
    }

    function tokenSupplyPerQuarter(uint256 quarter) public pure override returns (uint96) {
        require(quarter >= 1, 'There are only 1 or more quarters');
        //require(quarter < 513, 'overflow'); // TODO CHECK FUTURE MAX PROJECTION
        uint256 firstFactor = (SafeDecimalMath.unit().add(DECAY_RATE)).powDecimal(quarter.sub(1));
        uint256 supplyForQuarter = Q1_REWARDS.divideDecimal(firstFactor);

        return Safe3296.safe96(supplyForQuarter, 'overflow 96 bits');
    }

    function checkProtocol(uint256 _time)
        external
        view
        override
        returns (
            uint256 principal,
            uint256 time,
            uint256 quarterBelonging,
            uint256 timeListPointer,
            uint256 power
        )
    {
        return (
            protocolPerTimestamp[_time].principal,
            protocolPerTimestamp[_time].time,
            protocolPerTimestamp[_time].quarterBelonging,
            protocolPerTimestamp[_time].timeListPointer,
            protocolPerTimestamp[_time].power
        );
    }

    function checkQuarter(uint256 _num)
        external
        view
        override
        returns (
            uint256 quarterPrincipal,
            uint256 quarterNumber,
            uint256 quarterPower,
            uint96 supplyPerQuarter
        )
    {
        return (
            protocolPerQuarter[_num].quarterPrincipal,
            protocolPerQuarter[_num].quarterNumber,
            protocolPerQuarter[_num].quarterPower,
            protocolPerQuarter[_num].supplyPerQuarter
        );
    }

    /* ============ Internal Functions ============ */

    function _getStrategyProfitsAndBABL(address _strategy, address _contributor)
        private
        view
        returns (uint256, uint256)
    {
        IStrategy strategy = IStrategy(_strategy);
        uint256 contributorProfits = 0;
        uint256 contributorBABL = 0;
        // We get the state of the strategy in terms of profit and distance from expected to accurately calculate profits and rewards
        (bool profit, uint256 profitValue, bool distance, uint256 distanceValue) =
            _getStrategyRewardsContext(address(strategy));

        (, uint256 initialDepositAt, uint256 claimedAt, , , , , ) = IGarden(msg.sender).getContributor(_contributor);
        // Positive strategies not yet claimed
        if (strategy.exitedAt() > claimedAt && strategy.executedAt() >= initialDepositAt) {
            uint256 contributorPower =
                IGarden(msg.sender).getContributorPower(_contributor, strategy.executedAt(), strategy.exitedAt());
            // If strategy returned money we give out the profits
            if (profit == true) {
                // We reserve 5% of profits for performance fees
                profitValue = profitValue.sub(profitValue.multiplyDecimal(PROFIT_PROTOCOL_FEE));
            }
            // Get strategist rewards in case the contributor is also the strategist of the strategy
            contributorBABL = contributorBABL.add(
                _getStrategyStrategistBabl(
                    address(strategy),
                    _contributor,
                    profit,
                    profitValue,
                    distance,
                    distanceValue
                )
            );

            contributorProfits = contributorProfits.add(
                _getStrategyStrategistProfits(
                    address(strategy),
                    _contributor,
                    profit,
                    profitValue,
                    distance,
                    distanceValue
                )
            );

            // Get steward rewards
            contributorBABL = contributorBABL.add(
                _getStrategyStewardBabl(address(strategy), _contributor, profit, profitValue, distance, distanceValue)
            );
            contributorProfits = contributorProfits.add(
                _getStrategyStewardProfits(
                    address(strategy),
                    _contributor,
                    profit,
                    profitValue,
                    distance,
                    distanceValue
                )
            );

            // Get LP rewards
            contributorBABL = contributorBABL.add(
                uint256(strategy.strategyRewards()).multiplyDecimal(BABL_LP_SHARE).preciseMul(
                    contributorPower.preciseDiv(strategy.capitalAllocated())
                )
            );

            if (profit == true) {
                contributorProfits = contributorProfits.add(
                    contributorPower.preciseMul(profitValue).multiplyDecimal(PROFIT_LP_SHARE)
                );
            }

            // Get a multiplier bonus in case the contributor is the garden creator
            if (_contributor == IGarden(msg.sender).creator()) {
                contributorBABL = contributorBABL.add(contributorBABL.multiplyDecimal(CREATOR_BONUS));
            }
        }
        return (contributorProfits, contributorBABL);
    }

    function _getStrategyRewardsContext(address _strategy)
        private
        view
        returns (
            bool,
            uint256,
            bool,
            uint256
        )
    {
        IStrategy strategy = IStrategy(_strategy);
        uint256 returned = strategy.capitalReturned();
        uint256 expected =
            strategy.capitalAllocated().add(strategy.capitalAllocated().preciseMul(strategy.expectedReturn()));
        uint256 allocated = strategy.capitalAllocated();
        bool _profit;
        bool _distance;
        uint256 _profitValue;
        uint256 _distanceValue;
        if (returned > allocated && returned >= expected) {
            // The strategy went equal or above expectations
            _profit = true; // positive
            _distance = true; // positive
            _profitValue = returned.sub(allocated);
            _distanceValue = returned.sub(expected);
        } else if (returned >= allocated && returned < expected) {
            // The strategy went worse than expected but with some profits
            _profit = true; // positive or zero profits
            _distance = false; // negative vs expected return (got less than expected)
            _profitValue = returned.sub(allocated);
            _distanceValue = expected.sub(returned);
        } else if (returned < allocated && returned < expected) {
            // Negative profits - bad investments has penalties
            _profit = false; // negative - loosing capital
            _distance = false; // negative vs expected return (got less than expected)
            _profitValue = allocated.sub(returned); // Negative number, there were no profits at all
            _distanceValue = expected.sub(returned);
        }

        return (_profit, _profitValue, _distance, _distanceValue);
    }

    function _getStrategyStewardBabl(
        address _strategy,
        address _contributor,
        bool _profit,
        uint256 _profitValue,
        bool _distance,
        uint256 _distanceValue
    ) private view returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        uint256 strategyRewards = strategy.strategyRewards();
        int256 userVotes = strategy.getUserVotes(_contributor);
        uint256 bablCap;
        uint256 expected =
            strategy.capitalAllocated().add(strategy.capitalAllocated().preciseMul(strategy.expectedReturn()));

        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        uint256 babl = 0;
        if (userVotes > 0 && _profit == true && _distance == true) {
            // Voting in favor of the execution of the strategy with profits and positive distance
            babl = strategyRewards.multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
                uint256(userVotes).preciseDiv(strategy.totalPositiveVotes())
            ); // TODO CHECK absolute total votes vs. totalvotes usage
        } else if (userVotes > 0 && _profit == true && _distance == false) {
            // Voting in favor positive profits but below expected return
            babl = strategyRewards.multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
                uint256(userVotes).preciseDiv(strategy.totalPositiveVotes())
            ); // TODO CHECK absolute total votes vs. totalvotes usage
            babl = babl.sub(babl.preciseMul(_distanceValue.preciseDiv(expected))); // We discount the error of expected return vs real returns
        } else if (userVotes > 0 && _profit == false) {
            // Voting in favor of a non profitable strategy get nothing
            babl = 0;
        } else if (userVotes < 0 && _distance == false) {
            // Voting against a strategy that got results below expected return provides rewards to the voter (helping the protocol to only have good strategies)
            babl = strategyRewards.multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
                uint256(Math.abs(userVotes)).preciseDiv(strategy.totalNegativeVotes())
            ); // TODO CHECK absolute total votes vs. totalvotes usage

            bablCap = babl.mul(2); // Max cap
            babl = babl.add(babl.preciseMul(_distanceValue.preciseDiv(expected))); // We add a bonus inverse to the error of expected return vs real returns

            if (babl > bablCap) babl = bablCap; // We limit 2x by a Cap
        } else if (userVotes < 0 && _distance == true) {
            babl = 0;
        }
        return babl;
    }

    function _getStrategyStewardProfits(
        address _strategy,
        address _contributor,
        bool _profit,
        uint256 _profitValue,
        bool _distance,
        uint256 _distanceValue
    ) private view returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        uint256 profits = 0;
        int256 userVotes = strategy.getUserVotes(_contributor);
        if (_profit == true) {
            if (userVotes > 0) {
                profits = _profitValue.multiplyDecimal(PROFIT_STEWARD_SHARE).preciseMul(uint256(userVotes)).preciseDiv(
                    strategy.totalPositiveVotes()
                );
            } else if ((userVotes < 0) && _distance == false) {
                profits = _profitValue
                    .multiplyDecimal(PROFIT_STEWARD_SHARE)
                    .preciseMul(uint256(Math.abs(userVotes)))
                    .preciseDiv(strategy.totalNegativeVotes());
            } else if ((userVotes < 0) && _distance == true) {
                // Voted against a very profit strategy above expected returns, get no profit at all
                profits = 0;
            }
        } else profits = 0; // No profits at all

        return profits;
    }

    function _getStrategyStrategistBabl(
        address _strategy,
        address _contributor,
        bool _profit,
        uint256 _profitValue,
        bool _distance,
        uint256 _distanceValue
    ) private view returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        uint256 strategyRewards = strategy.strategyRewards();
        uint256 babl = 0;
        uint256 bablCap;
        uint256 expected =
            strategy.capitalAllocated().add(strategy.capitalAllocated().preciseMul(strategy.expectedReturn()));

        if (strategy.strategist() == _contributor) {
            babl = strategyRewards.multiplyDecimal(BABL_STRATEGIST_SHARE); // Standard calculation to be ponderated
            if (_profit == true && _distance == true) {
                // Strategy with equal or higher profits than expected
                bablCap = babl.mul(2); // Max cap
                // The more the results are close to the expected the more bonus will get (limited by a x2 cap)
                babl = babl.add(babl.preciseMul(expected.preciseDiv(strategy.capitalReturned())));
                if (babl > bablCap) babl = bablCap; // We limit 2x by a Cap
            } else if (_profit == true && _distance == false) {
                //under expectations
                // The more the results are close to the expected the less penalization it might have
                babl = babl.sub(babl.sub(babl.preciseMul(strategy.capitalReturned().preciseDiv(expected))));
            } else {
                // No positive profit
                return 0;
            }
        } else {
            return 0;
        }

        return babl;
    }

    function _getStrategyStrategistProfits(
        address _strategy,
        address _contributor,
        bool _profit,
        uint256 _profitValue,
        bool _distance,
        uint256 _distanceValue
    ) private view returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
        uint256 profits = 0;
        if (_profit == true) {
            if (strategy.strategist() == _contributor) {
                // If the contributor was the strategist of the strategy
                profits = _profitValue.multiplyDecimal(PROFIT_STRATEGIST_SHARE);
            }
        } else profits = 0; // No profits at all

        return profits;
    }

    function _addProtocolPerQuarter(uint256 _time) private {
        ProtocolPerQuarter storage protocolCheckpoint = protocolPerQuarter[getQuarter(_time)];

        if (!isProtocolPerQuarter[getQuarter(_time).sub(1)]) {
            // The quarter is not yet initialized then we create it
            protocolCheckpoint.quarterNumber = getQuarter(_time);
            if (pid == 0) {
                // The first strategy added in the first epoch
                protocolCheckpoint.quarterPower = 0;
                protocolCheckpoint.supplyPerQuarter = tokenSupplyPerQuarter(getQuarter(_time));
            } else {
                // Each time a new epoch starts with either a new strategy execution or finalization
                // We just take the proportional power for this quarter from previous checkpoint
                uint256 powerToSplit =
                    protocolPerTimestamp[_time].power.sub(protocolPerTimestamp[timeList[pid.sub(1)]].power);
                if (protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging == getQuarter(_time).sub(1)) {
                    // There were no intermediate epochs without checkpoints
                    // We re-initialize the protocol power counting for this new quarter
                    protocolCheckpoint.quarterPower = powerToSplit
                        .mul(_time.sub(START_TIME.add(getQuarter(_time).mul(EPOCH_DURATION).sub(EPOCH_DURATION))))
                        .div(_time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time));
                    protocolCheckpoint.supplyPerQuarter = tokenSupplyPerQuarter(getQuarter(_time));

                    protocolPerQuarter[getQuarter(_time).sub(1)].quarterPower = protocolPerQuarter[
                        getQuarter(_time).sub(1)
                    ]
                        .quarterPower
                        .add(powerToSplit.sub(protocolCheckpoint.quarterPower));
                } else {
                    // There were intermediate epochs without checkpoints - we need to create their protocolPerQuarter's and update the last one
                    // We have to update all the quarters including where the previous checkpoint is and the one were we are now
                    for (
                        uint256 i = 0;
                        i <= getQuarter(_time).sub(protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging);
                        i++
                    ) {
                        ProtocolPerQuarter storage newCheckpoint =
                            protocolPerQuarter[protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging.add(i)];
                        uint256 slotEnding =
                            START_TIME.add(
                                protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging.add(i).mul(EPOCH_DURATION)
                            );
                        if (i == 0) {
                            // We are in the first quarter to update, we add the corresponding part

                            newCheckpoint.quarterPower = newCheckpoint.quarterPower.add(
                                powerToSplit.mul(slotEnding.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time)).div(
                                    _time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time)
                                )
                            );
                            newCheckpoint.quarterPrincipal = protocolPerTimestamp[timeList[pid.sub(1)]].principal;
                        } else if (
                            i < getQuarter(_time).sub(protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging)
                        ) {
                            // We are in an intermediate quarter
                            newCheckpoint.quarterPower = powerToSplit.mul(EPOCH_DURATION).div(
                                _time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time)
                            );
                            newCheckpoint.supplyPerQuarter = tokenSupplyPerQuarter(
                                protocolPerTimestamp[timeList[pid.sub(1)]].quarterBelonging.add(i)
                            );
                            newCheckpoint.quarterNumber = protocolPerTimestamp[timeList[pid.sub(1)]]
                                .quarterBelonging
                                .add(i);
                            newCheckpoint.quarterPrincipal = protocolPerTimestamp[timeList[pid.sub(1)]].principal;
                        } else {
                            // We are in the last quarter of the strategy
                            protocolCheckpoint.quarterPower = powerToSplit
                                .mul(
                                _time.sub(START_TIME.add(getQuarter(_time).mul(EPOCH_DURATION).sub(EPOCH_DURATION)))
                            )
                                .div(_time.sub(protocolPerTimestamp[timeList[pid.sub(1)]].time));
                            protocolCheckpoint.supplyPerQuarter = tokenSupplyPerQuarter(getQuarter(_time));
                            protocolCheckpoint.quarterNumber = getQuarter(_time);
                            protocolCheckpoint.quarterPrincipal = protocolPrincipal;
                        }
                    }
                }
            }
            isProtocolPerQuarter[getQuarter(_time).sub(1)] = true;
        } else {
            // Quarter checkpoint already created, it must have been filled with general info
            // We update the power of the quarter by adding the new difference between last quarter checkpoint and this checkpoint
            protocolCheckpoint.quarterPower = protocolCheckpoint.quarterPower.add(
                protocolPerTimestamp[_time].power.sub(protocolPerTimestamp[timeList[pid.sub(1)]].power)
            );
        }
        protocolCheckpoint.quarterPrincipal = protocolPrincipal;
    }

    function _updatePowerOverhead(IStrategy _strategy, uint256 _capital) private {
        if (_strategy.updatedAt() != 0) {
            // There will be overhead after the first execution not before
            if (getQuarter(block.timestamp) == getQuarter(_strategy.updatedAt())) {
                // The overhead will remain within the same epoch
                rewardsPowerOverhead[address(_strategy)][getQuarter(block.timestamp)] = rewardsPowerOverhead[
                    address(_strategy)
                ][getQuarter(block.timestamp)]
                    .add(_capital.mul(block.timestamp.sub(_strategy.updatedAt())));
            } else {
                // We need to iterate since last update of the strategy capital
                (uint256 numQuarters, uint256 startingQuarter) =
                    getRewardsWindow(_strategy.updatedAt(), block.timestamp);
                uint256 overheadPerQuarter = _capital.mul(block.timestamp.sub(_strategy.updatedAt())).div(numQuarters);
                for (uint256 i = 0; i <= numQuarters.sub(1); i++) {
                    rewardsPowerOverhead[address(_strategy)][startingQuarter.add(i)] = rewardsPowerOverhead[
                        address(_strategy)
                    ][startingQuarter.add(i)]
                        .add(overheadPerQuarter);
                }
            }
        }
    }

    function _getStrategyRewardsOneQuarter(address _strategy, uint256 _startingQuarter) private view returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        uint256 strategyOverTime =
            strategy.capitalAllocated().mul(strategy.exitedAt().sub(strategy.executedAt())).sub(
                strategy.rewardsTotalOverhead()
            );
        return
            strategyOverTime
                .preciseDiv(protocolPerQuarter[_startingQuarter].quarterPower)
                .preciseMul(uint256(protocolPerQuarter[_startingQuarter].supplyPerQuarter))
                .mul(strategy.exitedAt().sub(_startingQuarter))
                .div(block.timestamp.sub(_startingQuarter));
    }

    // Safe BABL transfer function, just in case if rounding error causes DistributorRewards to not have enough BABL.
    function _safeBABLTransfer(address _to, uint96 _amount) private {
        uint256 bablBal = babltoken.balanceOf(address(this));
        if (_amount > bablBal) {
            SafeERC20.safeTransfer(babltoken, _to, bablBal);
        } else {
            SafeERC20.safeTransfer(babltoken, _to, _amount);
        }
    }
}
