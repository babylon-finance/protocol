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

import {TimeLockedToken} from './TimeLockedToken.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';

import {IBabController} from '../interfaces/IBabController.sol';
import {IRollingGarden} from '../interfaces/IRollingGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {TimeLockedToken} from './TimeLockedToken.sol';

import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {RewardsSupplySchedule} from './RewardsSupplySchedule.sol';

import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';
import {Safe3296} from '../lib/Safe3296.sol';

contract RewardsDistributor is Ownable {
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
    event ClaimMyRewards(address indexed user, IRollingGarden indexed pid, uint256 indexed amount);

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    // Garden that these strategies belong to
    IRollingGarden public garden;

    // Strategies that the reward calculations belong to
    IStrategy public strategy;

    // Supply Schedule contract
    RewardsSupplySchedule public supplySchedule;

    // BABL Token contract
    TimeLockedToken public babltoken;

    struct UserInfo {
        uint256 lastUserClaim; // Last claim (tx) when amount equals rewardDebt
        uint96 amount; // How many BABL rewards the user has been granted.
        uint96 rewardDebt; // Reward debt - BABLs already claimed and transferred to the user.
        int256 votes; // The number of votes (if any) of the user in the corresponding strategy
        uint96 userPrincipal; // User principal invested in this strategy as LP
        bool isLP; // If the user has been LP for this strategy
        bool isGardenCreator; // If the user is the garden creator
        bool isStrategist; // If the user is the strategy creator
        bool isSteward; // If the user has been voted as steward in the strategy
    }

    mapping(address => mapping(address => UserInfo)) public userInfo;

    struct StrategyPoolInfo {
        IRollingGarden lpToken; // Address of the Garden token contract that the strategy belong to
        uint96 strategyRewards; // How many BABL rewards are allocated to this strategy
        uint96 strategyPower; // The strategy power (Duration * Principal)
        int256 strategyProfit; // The final profit of the strategy to be user in case of negative profit
        uint96 bablPerShare; // Accumulated BABL per share of the Garden associated to this strategy
        uint96 strategyPrincipal; // How many allocation points assigned to this pool. Used when BABLs are distributed per block.
        uint256 strategyStart; // Timestamp when the strategy started its execution
        uint256 strategyEnd; // Timestamp when the strategy ended its execution
        uint256 strategyDuration; // Total number of blocks the strategy was active
        uint256 lastRewardBlock; // Last block number that BABLs distribution occurs //TODO CHECK vs. strategyEnds
        uint256 lastUpdate; // Last update of this information
        address strategist; // Who is the strategist of this strategy
    }

    mapping(address => StrategyPoolInfo) public strategyPoolInfo;
    mapping(address => bool) public strategyIncluded; // Mapping to control updates - for gas efficiency

    //StrategyPoolInfo[] public strategyPoolInfo;
    address[] public strategyList; // Ordered list of executed strategies

    uint256 public bablPerBlock; // Rewards per block // TODO CHECK ARRAY TO CONTROL THE CHANGE OF SUPPLY ALONG THE TIME
    uint256 public protocolPrincipal = 0; // Total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all strategy pools.
    mapping(uint256 => uint256) protocolPerTimestamp; // Total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all strategy pools.
    uint256 public protocolDuration = 0;
    mapping(uint256 => uint256) durationPerTimestamp; // Total allocation points. Must be the sum of all allocation points (strategyPrincipal) in all strategy pools.

    uint256 public startBlock; // Starting block of the Rewards Distribution (set-up during construction)
    uint256 public protocolDuration; // Total Duration of the procotol (total execution blocks of all strategies in the pool)
    uint256 public lastProtocolUpdate; // Last update of the protocol global variables

    struct QuarterRewards {
        // TODO CHECK its final usage for controlling EPOCH changes on the supply and evolution of the Distribution Rewards
        uint256 quarterStart;
        uint256 quarterEnd;
        uint96 potentialQuarterTokenRewards;
        uint96 availableQuarterTokenRewards;
        uint256 lastUpdate;
    }
    mapping(uint256 => QuarterRewards) public quarterRewards;

    uint256 public EPOCH_DURATION = 90 days; // Duration of its EPOCH in days
    uint256 public START_TIME; // Starting time of the rewards distribution

    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    constructor(RewardsSupplySchedule _supply, TimeLockedToken _bablToken) {
        supplySchedule = _supply;
        babltoken = _bablToken;
        //START_TIME = block.timestamp; // TODO RECOVER FOR PRODUCTION
        START_TIME = 1614618000; // March the 1st for TESTING PURPOSES ONLY
    }

    /* ============ External Functions ============ */

    // Set a TEST STRATEGY.
    function setTestStrategy() public {
        require(!strategyIncluded[address(msg.sender)], 'RewardsDistributor::add: strategy already included');

        //uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        StrategyPoolInfo storage newStrategyPoolInfo = strategyPoolInfo[address(msg.sender)];

        //newStrategyPoolInfo.lpToken = address(msg.sender); // Rolling Garden repsonsible of the strategy
        newStrategyPoolInfo.strategyProfit = 10;
        newStrategyPoolInfo.bablPerShare = uint96(1); // TODO - NEED TO BE UPDATED FOR REWARDS CALCULATION
        newStrategyPoolInfo.lastRewardBlock = block.timestamp.add(EPOCH_DURATION); // TODO - DEFINE HOW TO HANDLE REWARDS BASED ON BLOCKS
        newStrategyPoolInfo.strategyPrincipal = uint96(100);
        newStrategyPoolInfo.strategyStart = block.timestamp;
        newStrategyPoolInfo.strategyEnd = block.timestamp.add(EPOCH_DURATION);
        newStrategyPoolInfo.strategyDuration = EPOCH_DURATION;
        newStrategyPoolInfo.lastUpdate = block.timestamp;
        newStrategyPoolInfo.strategist = address(msg.sender);
        newStrategyPoolInfo.strategyPower = uint96(
            newStrategyPoolInfo.strategyDuration.mul(newStrategyPoolInfo.strategyPrincipal)
        );

        // Include it to avoid gas cost on massive updating and/ or data corruption
        strategyIncluded[address(msg.sender)] = true;
        // For counting we also include it in the strategy array
        strategyList.push(address(msg.sender));
        // We update the Total Allocation of the Protocol
        protocolPrincipal = protocolPrincipal.add(newStrategyPoolInfo.strategyPrincipal);
        // We update the Total Duration of the Protocol
        protocolDuration = protocolDuration.add(newStrategyPoolInfo.strategyDuration);
    }

    // Set a TEST USER FOR A STRATEGY
    function setTestUser(address _pid) public {
        require(strategyIncluded[_pid], 'RewardsDistributor::add: strategy not yet included');

        //uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        StrategyPoolInfo storage newStrategyPoolInfo = strategyPoolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        user.lastUserClaim = 0;
        user.amount = 0;
        user.rewardDebt; // Reward debt - BABLs already claimed and transferred to the user.
        user.votes = 100; // The number of votes (if any) of the user in the corresponding strategy
        user.userPrincipal = 10; // User principal invested in this strategy as LP
        user.isLP = true; // If the user has been LP for this strategy
        user.isGardenCreator = false; // If the user is the garden creator
        user.isStrategist = (newStrategyPoolInfo.strategist == msg.sender); // If the user is the strategy creator
        user.isSteward = true; // If the user has been voted as steward in the strategy
    }

    function addProtocolPrincipalAndDuration(uint256 _capital, uint256 _duration) {
        protocolPrincipal = protocolPrincipal.add(_capital);
        protocolDuration = protocolDuration.add(_duration);
        principalPerTimestamp[block.timestamp] = protocolPrincipal;
        durationPerTimestamp[block.timestamp] = _duration;
    }

    function substractProtocolPrincipalAndDuration(uint256 _capital, uint256 _duration) {
        protocolPrincipal = protocolPrincipal.sub(_capital);
        protocolDuration = protocolPrincipal.sub(_capital);
        principalPerTimestamp[block.timestamp] = protocolPrincipal;
        durationPerTimestamp[block.timestamp] = _duration;
    }

    function getProtocolPrincipalByTimestamp(uint256 _timestamp) {
        return principalPerTimestamp[block.timestamp];
    }

    function getProtocolDurationByTimestamp(uint256 _timestamp) {
        return durationPerTimestamp[block.timestamp];
    }

    function getStrategyRewards(address _strategy) returns (uint256) {}

    function sendTokensToContributor(address _to, uint256 _amount) {
        require(controller.isSystemContract(msg.sender));
        safeBABLTransfer(_to, _amount);
    }

    // TEST CLAIM STRATEGY REWARDS
    function claimStrategyRewards() public {
        uint256 strategyLength = strategyList.length;
        for (uint256 i = 0; i <= strategyLength - 1; i++) {
            StrategyPoolInfo storage pool = strategyPoolInfo[strategyList[i]];
            // check number of quarters and what quarters are they
            (uint256 numQuarters, uint256 startingQuarter, uint256 endingQuarter) =
                getRewardsWindow(pool.strategyStart, pool.strategyEnd);
            uint96[] memory quarters = new uint96[](numQuarters);
            uint256 percentage = uint256(pool.strategyPower).div(protocolPrincipal.mul(protocolDuration));
            uint96 rewards = 0;
            uint256 counter = 0;
            for (uint256 j = 0; j <= numQuarters.sub(1); j++) {
                quarters[j] = Safe3296.safe96(
                    supplySchedule.tokenSupplyPerQuarter(startingQuarter.add(1)),
                    'overflow 96 bits'
                );
                rewards = Safe3296.safe96(uint256(rewards).add(percentage.mul(quarters[j])), 'overflow 96 bits');
                counter++;

                //user.amount = Safe3296.safe96(uint256(user.amount).sub(_amount), 'overflow of 96 bits'); // TODO - CHECK DECIMALS
                //user.rewardDebt = Safe3296.safe96(uint256(user.amount).mul(pool.bablPerShare), 'overflow of 96 bits'); // TODO - CHECK DECIMALS
                //safeBABLTransfer(msg.sender, pending);
                //emit ClaimMyRewards(msg.sender, _pid, _amount);
            }
            require(endingQuarter == startingQuarter.add(counter).sub(1), 'reward window mismatch');
            pool.strategyRewards = rewards;
        }
    }

    // Set a new Supply Schedule contract. Can only be called by the owner.
    function setNewSupplyScheduler(RewardsSupplySchedule _newSupply) public onlyOwner {
        supplySchedule = _newSupply;
    }

    // Add a new strategy to the pool. Can only be called by the owner / strategy // TODO CHECK.
    function add(IRollingGarden _lpToken, IStrategy _strategy) public onlyOwner {
        require(!strategyIncluded[address(_strategy)], 'RewardsDistributor::add: strategy already included');

        //uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        StrategyPoolInfo storage newStrategyPoolInfo = strategyPoolInfo[address(_strategy)];

        newStrategyPoolInfo.lpToken = _lpToken; // Rolling Garden repsonsible of the strategy
        newStrategyPoolInfo.strategyProfit = int256(_strategy.capitalReturned().sub(_strategy.capitalAllocated()));
        newStrategyPoolInfo.bablPerShare = uint96(0); // TODO - NEED TO BE UPDATED FOR REWARDS CALCULATION
        newStrategyPoolInfo.lastRewardBlock = 0; // TODO - DEFINE HOW TO HANDLE REWARDS BASED ON BLOCKS
        newStrategyPoolInfo.strategyPrincipal = uint96(_strategy.capitalAllocated());
        newStrategyPoolInfo.strategyStart = _strategy.executedAt();
        newStrategyPoolInfo.strategyEnd = _strategy.exitedAt();
        newStrategyPoolInfo.strategyDuration = newStrategyPoolInfo.strategyEnd.sub(newStrategyPoolInfo.strategyStart);
        newStrategyPoolInfo.lastUpdate = block.timestamp;
        newStrategyPoolInfo.strategist = _strategy.strategist();
        newStrategyPoolInfo.strategyPower = uint96(
            newStrategyPoolInfo.strategyDuration.mul(newStrategyPoolInfo.strategyPrincipal)
        );

        // Include it to avoid gas cost on massive updating and/ or data corruption
        strategyIncluded[address(_strategy)] = true;
        // For counting we also include it in the strategy array
        strategyList.push(address(_strategy));
        // We update the Total Allocation of the Protocol
        protocolPrincipal = protocolPrincipal.add(newStrategyPoolInfo.strategyPrincipal);
    }

    // Update the given strategy its BABL allocation point. Can only be called by the owner.
    function updateStrategy(
        address _address, // Address of the Strategy to be set / updated
        uint96 _strategyPrincipal,
        bool _withMassGardenUpdate
    ) public onlyOwner {
        if (_withMassGardenUpdate) {
            massUpdatePools(strategyPoolInfo[_address].lpToken);
        }
        // If we introduce a value DIFFERENT FROM ZERO, as Owners, the strategy principal will be overrided as well as the protocol (USE IT SAFE TO AVOID DIFFERENT DATA in the STRATEGY AND THE REWARDS)
        if (_strategyPrincipal != 0) {
            // We also update Protocol Principal and the Strategy Principal with the new value
            protocolPrincipal = protocolPrincipal.sub(strategyPoolInfo[_address].strategyPrincipal).add(
                _strategyPrincipal
            );
            strategyPoolInfo[_address].strategyPrincipal = _strategyPrincipal;
        }
    }

    function massUpdatePools(IRollingGarden _garden) public returns (uint256) {
        // TODO CHECK GAS REDUCTION IT UPDATES ALL FINALIZED STRATEGIES WITHIN A GARDEN
        // SPLIT A MASS UPDATE FROM A SINGLE UPDATEPOOL

        address[] memory finalizedStrategies = _garden.getFinalizedStrategies();
        uint256 strategiesCount = 0;

        for (uint256 i = 0; i <= finalizedStrategies.length; i++) {
            if (!strategyIncluded[address(finalizedStrategies[i])]) {
                // It only updates new finalized strategies
                IStrategy updatingStrategy = IStrategy(finalizedStrategies[i]);

                strategiesCount++;
                StrategyPoolInfo storage newFinalizedStrategy = strategyPoolInfo[address(updatingStrategy)];
                newFinalizedStrategy.lpToken = _garden; // Rolling Garden repsonsible of the strategy
                newFinalizedStrategy.strategyProfit = int256(
                    updatingStrategy.capitalReturned().sub(updatingStrategy.capitalAllocated())
                );
                newFinalizedStrategy.bablPerShare = uint96(0); // TODO - NEED TO BE UPDATED FOR REWARDS CALCULATION
                newFinalizedStrategy.lastRewardBlock = 0; // TODO - DEFINE HOW TO HANDLE REWARDS BASED ON BLOCKS
                newFinalizedStrategy.strategyPrincipal = uint96(updatingStrategy.capitalAllocated());
                newFinalizedStrategy.strategyStart = updatingStrategy.executedAt();
                newFinalizedStrategy.strategyEnd = updatingStrategy.exitedAt();
                newFinalizedStrategy.strategyDuration = newFinalizedStrategy.strategyEnd.sub(
                    newFinalizedStrategy.strategyStart
                );
                newFinalizedStrategy.lastUpdate = block.timestamp;
                newFinalizedStrategy.strategist = updatingStrategy.strategist();
                newFinalizedStrategy.strategyPower = uint96(
                    newFinalizedStrategy.strategyDuration.mul(newFinalizedStrategy.strategyPrincipal)
                );

                // we include it in the mapping to use a filter for updates
                strategyIncluded[address(updatingStrategy)] = true;
                // For counting we also include it in the strategy array
                strategyList.push(address(updatingStrategy));
            } else if (!strategyIncluded[address(finalizedStrategies[i])]) {
                // We only update Profit and Principal
                IStrategy updatingStrategy = IStrategy(finalizedStrategies[i]);
                StrategyPoolInfo storage newFinalizedStrategy = strategyPoolInfo[address(updatingStrategy)];
                newFinalizedStrategy.strategyProfit = int256(
                    updatingStrategy.capitalReturned().sub(updatingStrategy.capitalAllocated())
                );
                newFinalizedStrategy.strategyPrincipal = uint96(updatingStrategy.capitalAllocated());
                strategiesCount++;
            }
        }

        return strategiesCount; // Returns the number of strategies updated
    }

    function updateEpochRewards(uint256 epochs) public onlyOwner {
        uint256 timestamp = block.timestamp;
        for (uint256 i = 0; i <= epochs; i++) {
            quarterRewards[i].potentialQuarterTokenRewards = uint96(supplySchedule.tokenSupplyPerQuarter(i.add(1)));
            quarterRewards[i].lastUpdate = timestamp;
        }
    }

    // Claim BABL from Rewards Distributor
    function claimMyRewards(IRollingGarden _pid, uint256 _amount) public {
        StrategyPoolInfo storage pool = strategyPoolInfo[address(_pid)];
        UserInfo storage user = userInfo[address(_pid)][msg.sender];
        require(user.amount >= _amount, 'withdraw: not good');
        massUpdatePools(_pid);
        uint96 pending =
            Safe3296.safe96(uint256(user.amount).mul(pool.bablPerShare).sub(user.rewardDebt), 'overflow of 96 bits');
        user.amount = Safe3296.safe96(uint256(user.amount).sub(_amount), 'overflow of 96 bits'); // TODO - CHECK DECIMALS
        user.rewardDebt = Safe3296.safe96(uint256(user.amount).mul(pool.bablPerShare), 'overflow of 96 bits'); // TODO - CHECK DECIMALS
        safeBABLTransfer(msg.sender, pending);
        emit ClaimMyRewards(msg.sender, _pid, _amount);
    }

    /* ============ Getter Functions ============ */
    /* ========== View functions ========== */

    // View function to see pending BABL on frontend.
    function pendingRewards(
        address _pid,
        address _user // TODO - Remove babl per share (OR USE IT RIGHT), add real tokens (voting, strategist, etc)
    ) external view returns (uint96) {
        StrategyPoolInfo storage pool = strategyPoolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint96 bablPerShare = pool.bablPerShare;
        uint96 bablPerStrategy = pool.strategyRewards;
        //require(pool.lpToken.balanceOf(_user) > 0,'The user must have Garden Tokens');
        uint96 lpSupply = Safe3296.safe96(babltoken.balanceOf(address(this)), 'overflow of 96 bits'); // Distributor must have available tokens to allocate
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 bablPercentPerBlock = (bablPerBlock.mul(pool.strategyPrincipal).div(protocolPrincipal)); // TODO - Mul by number of blocks since last claim and reconsider the whole calculation
            bablPerShare = Safe3296.safe96(
                uint256(bablPerShare).add(bablPercentPerBlock.div(bablPerStrategy)),
                'overflow 96 bits'
            );
        }
        return Safe3296.safe96(uint256(user.amount).mul(bablPerShare).sub(user.rewardDebt), 'overflow 96 bits');
    }

    function poolLength() external view returns (uint256) {
        return strategyList.length;
    }

    function getEpochRewards(uint256 epochs) public view returns (uint96[] memory) {
        uint96[] memory tokensPerEpoch = new uint96[](epochs);
        for (uint256 i = 0; i <= epochs - 1; i++) {
            tokensPerEpoch[i] = (uint96(supplySchedule.tokenSupplyPerQuarter(i.add(1))));
        }
        return tokensPerEpoch;
    }

    /**
     * @notice Retrieve the length of the finalized strategies in a garden array
     */
    function finalizedStrategiesinGardenLength(IRollingGarden _garden) external view returns (uint256) {
        return _garden.getFinalizedStrategies().length;
    }

    function getRewardsWindow(uint256 _from, uint256 _to)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 quarters = (_to.sub(_from).preciseDivCeil(EPOCH_DURATION)).div(1e18);
        uint256 startingQuarter = (_from.sub(START_TIME).preciseDivCeil(EPOCH_DURATION)).div(1e18);
        uint256 endingQuarter = startingQuarter.add(quarters);

        return (quarters.add(1), startingQuarter, endingQuarter);
    }

    function getSupplyForPeriod(uint256 _from, uint256 _to) public view returns (uint96[] memory) {
        // check number of quarters and what quarters are they
        (uint256 quarters, uint256 startingQuarter, uint256 endingQuarter) = getRewardsWindow(_from, _to);
        uint96[] memory supplyPerQuarter = new uint96[](quarters);
        if (quarters <= 1) {
            // Strategy Duration less than a quarter
            supplyPerQuarter[0] = Safe3296.safe96(
                supplySchedule.tokenSupplyPerQuarter(endingQuarter.add(1)),
                'overflow 96 bits'
            );
            return supplyPerQuarter;
        } else if (quarters <= 2) {
            // Strategy Duration less or equal of 2 quarters - we assume that high % of strategies will have a duration <= 2 quarters avoiding the launch of a for loop
            supplyPerQuarter[0] = Safe3296.safe96(
                supplySchedule.tokenSupplyPerQuarter(startingQuarter),
                'overflow 96 bits'
            );
            supplyPerQuarter[1] = Safe3296.safe96(
                supplySchedule.tokenSupplyPerQuarter(endingQuarter),
                'overflow 96 bits'
            );
            return supplyPerQuarter;
        } else {
            for (uint256 i = 0; i <= quarters.sub(1); i++) {
                supplyPerQuarter[i] = Safe3296.safe96(
                    supplySchedule.tokenSupplyPerQuarter(startingQuarter.add(1).add(i)),
                    'overflow 96 bits'
                );
            }
            return supplyPerQuarter;
        }
    }

    /* ============ Internal Functions ============ */

    // Safe BABL transfer function, just in case if rounding error causes DistributorRewards to not have enough BABL.
    function safeBABLTransfer(address _to, uint256 _amount) internal {
        uint256 bablBal = babltoken.balanceOf(address(this));
        if (_amount > bablBal) {
            babltoken.transfer(_to, bablBal);
        } else {
            babltoken.transfer(_to, _amount);
        }
    }
}
