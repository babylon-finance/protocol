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

// import "hardhat/console.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IWETH } from "./interfaces/external/weth/IWETH.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { IBabController } from "./interfaces/IBabController.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IRollingCommunity } from "./interfaces/IRollingCommunity.sol";

/**
 * @title CommunityIdeas
 * @author Babylon Finance
 *
 * Holds the investment ideas for a single community.
 */
contract CommunityIdeas is ReentrancyGuard {
  using SafeCast for uint256;
  using SafeCast for int256;
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using PreciseUnitMath for int256;
  using PreciseUnitMath for uint256;

  /* ============ Events ============ */

  /* ============ Modifiers ============ */

  modifier onlyContributor {
    require(
        ERC20(address(community)).balanceOf(msg.sender) > 0,
        "Only someone with the community token can withdraw"
    );
    _;
  }

  /**
   * Throws if the sender is not a keeper in the protocol
   */
  modifier onlyKeeper() {
    require(controller.isValidKeeper(msg.sender), "Only a keeper can call this");
    _;
  }

  /**
   * Throws if the community is not active
   */
  modifier onlyActive() {
    require(community.active() == true, "Community must be active");
    _;
  }

  /* ============ Structs ============ */

  struct InvestmentIdea {
    uint8 index;                       // Investment index (used for votes)
    address payable participant;       // Address of the participant that submitted the bet
    uint256 enteredAt;                 // Timestamp when the idea was submitted
    uint256 enteredCooldownAt;         // Timestamp when the idea reached quorum
    uint256 executedAt;                // Timestamp when the idea was executed
    uint256 exitedAt;                  // Timestamp when the idea was submitted
    uint256 stake;                     // Amount of stake by the ideator (in reserve asset) Neds to be positive
    uint256 maxCapitalRequested;       // Amount of max capital to allocate
    uint256 capitalAllocated;          // Current amount of capital allocated
    uint256 expectedReturn;            // Expect return by this investment idea
    uint256 minRebalanceCapital;       // Min amount of capital so that it is worth to rebalance the capital here
    address[] enterTokensNeeded;       // Positions that need to be taken prior to enter trade
    uint256[] enterTokensAmounts;      // Amount of these positions
    address[] voters;                  // Addresses with the voters
    uint256 duration;                  // Duration of the bet
    int256 totalVotes;                 // Total votes staked
    uint256 absoluteTotalVotes;        // Absolute number of votes staked
    uint256 totalVoters;               // Total amount of participants that voted
    address integration;               // Address of the integration
    bytes enterPayload;                // Calldata to execute when entering
    bytes exitPayload;                 // Calldata to execute when exiting the trade
    bool finalized;                    // Flag that indicates whether we exited the idea
    bool active;                       // Whether the idea has met the voting quorum
  }

  /* ============ State Variables ============ */

  uint8 constant MAX_TOTAL_IDEAS = 10;

  // Babylon Controller Address
  IBabController public controller;

  // Community that these ideas belong to
  IRollingCommunity public community;

  mapping(uint256 => mapping(address => int256)) public votes;  // Investment idea votes from participants (can be negative if downvoting)
  uint256 public totalStake = 0;

  uint256 public minVotersQuorum = 1e17;          // 10%. (0.01% = 1e14, 1% = 1e16)

  uint256 public minIdeaDuration;               // Min duration for an investment Idea
  uint256 public maxIdeaDuration;               // Max duration for an investment idea
  uint256 public ideaCooldownPeriod;            // Window for the idea to cooldown after approval before receiving capital

  InvestmentIdea[] ideas;

  uint256 public ideaCreatorProfitPercentage = 13e16; // (0.01% = 1e14, 1% = 1e16)
  uint256 public ideaVotersProfitPercentage = 5e16; // (0.01% = 1e14, 1% = 1e16)
  uint256 public communityCreatorProfitPercentage = 2e16; //

  /* ============ Constructor ============ */

  /**
   * Before a community is initialized, the community ideas need to be created and passed to community initialization.
   *
   * @param _community                        Address of the community
   * @param _controller                       Address of the controller
   * @param _ideaCooldownPeriod               How long after the idea has been activated, will it be ready to be executed
   * @param _ideaCreatorProfitPercentage      What percentage of the profits go to the idea creator
   * @param _ideaVotersProfitPercentage       What percentage of the profits go to the idea curators
   * @param _communityCreatorProfitPercentage What percentage of the profits go to the creator of the community
   * @param _minVotersQuorum                  Percentage of votes needed to activate an investment idea (0.01% = 1e14, 1% = 1e16)
   * @param _minIdeaDuration                  Min duration of an investment idea
   * @param _maxIdeaDuration                  Max duration of an investment idea
   */
  constructor(
    address _community,
    address _controller,
    uint256 _ideaCooldownPeriod,
    uint256 _ideaCreatorProfitPercentage,
    uint256 _ideaVotersProfitPercentage,
    uint256 _communityCreatorProfitPercentage,
    uint256 _minVotersQuorum,
    uint256 _minIdeaDuration,
    uint256 _maxIdeaDuration
  )
  {
    controller = IBabController(_controller);
    require(
        _ideaCooldownPeriod <= controller.getMaxCooldownPeriod() && _ideaCooldownPeriod >= controller.getMinCooldownPeriod() ,
        "Community cooldown must be within the range allowed by the protocol"
    );
    require(_minVotersQuorum >= 1e17, "You need at least 10% votes");
    require(controller.isSystemContract(_community), "Must be a valid community");
    // TODO: require(_maxCandidateIdeas.add(100.previseDiv(1e17)) < MAX_TOTAL_IDEAS, "Number of ideas must be less than the limit");
    community = IRollingCommunity(_community);
    ideaCreatorProfitPercentage = _ideaCreatorProfitPercentage;
    ideaVotersProfitPercentage = _ideaVotersProfitPercentage;
    communityCreatorProfitPercentage = _communityCreatorProfitPercentage;
    ideaCooldownPeriod = _ideaCooldownPeriod;
    minVotersQuorum = _minVotersQuorum;
    minIdeaDuration = _minIdeaDuration;
    maxIdeaDuration = _maxIdeaDuration;

    totalStake = 0;
  }


  /* ============ External Functions ============ */

  /**
   * Adds an investment idea to the contenders array for this epoch.
   * Investment stake is stored in the contract. (not converted to reserve asset).
   * If the array is already at the limit, replace the one with the lowest stake.
   * @param _maxCapitalRequested           Max Capital requested denominated in the reserve asset (0 to be unlimited)
   * @param _stake                         Stake with community participations absolute amounts 1e18
   * @param _investmentDuration            Investment duration in seconds
   * @param _enterData                     Operation to perform to enter the investment
   * @param _exitData                      Operation to perform to exit the investment
   * @param _integration                   Address of the integration
   * @param _expectedReturn                Expected return
   * @param _minRebalanceCapital           Min capital that is worth it to deposit into this idea
   * @param _enterTokensNeeded             Tokens that we need to acquire to enter this investment
   * @param _enterTokensAmounts            Token amounts of these assets we need
   * TODO: Meta Transaction
   */
  function addInvestmentIdea(
    uint256 _maxCapitalRequested,
    uint256 _stake,
    uint256 _investmentDuration,
    bytes memory _enterData,
    bytes memory _exitData,
    address _integration,
    uint256 _expectedReturn,
    uint256 _minRebalanceCapital,
    address[] memory _enterTokensNeeded,
    uint256[] memory _enterTokensAmounts
  ) external onlyContributor onlyActive {
    require(community.isValidIntegration(_integration), "Integration must be valid");
    require(_stake > community.totalSupply().div(100), "Stake amount must be at least 1% of the community");
    require(_investmentDuration >= minIdeaDuration && _investmentDuration <= maxIdeaDuration, "Investment duration must be in range");
    require(_stake > 0, "Stake amount must be greater than 0");
    require(_minRebalanceCapital > 0, "Min Capital requested amount must be greater than 0");
    require(_maxCapitalRequested >= _minRebalanceCapital, "The max amount of capital must be greater than one chunk");
    require(ideas.length < MAX_TOTAL_IDEAS, "Reached the limit of ideas");
    // Check than enter and exit data call integrations
    InvestmentIdea storage idea;
    idea.index = ideas.length.toUint8();
    idea.integration = _integration;
    idea.participant = msg.sender;
    idea.enteredAt = block.timestamp;
    idea.stake = _stake;
    idea.duration = _investmentDuration;
    idea.enterPayload = _enterData;
    idea.exitPayload = _exitData;
    idea.enterTokensNeeded = _enterTokensNeeded;
    idea.enterTokensAmounts = _enterTokensAmounts;
    idea.expectedReturn = _expectedReturn;
    idea.capitalAllocated = 0;
    idea.minRebalanceCapital = _minRebalanceCapital;
    idea.maxCapitalRequested = _maxCapitalRequested;
    idea.totalVotes = _stake.toInt256();
    idea.absoluteTotalVotes = _stake;
    totalStake = totalStake.add(_stake);

    ideas.push(idea);
  }

  function abs(int x) private pure returns (int) {
    return x >= 0 ? x : -x;
  }

  /**
   * Returns whether this idea is currently active or not
   * @param _idea               The idea struct
   * TODO: Meta Transaction
   */
  function isIdeaActive(InvestmentIdea memory _idea) private pure returns (bool) {
    return _idea.executedAt > 0 && _idea.exitedAt == 0;
  }

  /**
   * Curates an investment idea from the contenders array for this epoch.
   * This can happen at any time. As long as there are investment ideas.
   * @param _ideaIndex                The position of the idea index in the array
   * @param _amount                   Amount to curate, positive to endorse, negative to downvote
   * TODO: Meta Transaction
   */
  function curateInvestmentIdea(uint8 _ideaIndex, int256 _amount) external onlyContributor onlyActive {
    require(ideas.length > _ideaIndex, "The idea index does not exist");
    require(_amount.toUint256() < community.balanceOf(msg.sender), "Participant does not have enough balance");
    InvestmentIdea storage idea = ideas[_ideaIndex];
    if (votes[idea.index][msg.sender] == 0) {
      idea.totalVoters++;
      idea.voters = [msg.sender];
    } else {
      idea.voters.push(msg.sender);
    }
    votes[idea.index][msg.sender] = votes[idea.index][msg.sender].add(_amount);
    idea.totalVotes.add(_amount);
    idea.absoluteTotalVotes = idea.absoluteTotalVotes.add(abs(_amount).toUint256());
    idea.totalVotes = idea.totalVotes.add(_amount);
    totalStake = totalStake.add(abs(_amount).toUint256()); // Adds total amount staked at the moment
    // TODO: Introduce conviction voting
    uint256 votingThreshold = minVotersQuorum.preciseMul(community.totalSupply());
    if (_amount > 0 && idea.totalVotes.toUint256() >= votingThreshold) {
      idea.active = true;
      idea.enteredCooldownAt = block.timestamp;
    }
    if (_amount < 0 && idea.totalVotes.toUint256() < votingThreshold && idea.active && idea.executedAt == 0) {
      idea.active = false;
    }
  }

  /**
   * Executes an idea that has been activated and gone through the cooldown period.
   * @param _ideaIndex                The position of the idea index in the array
   * @param _capital                  The capital to allocate to this idea
   */
  function executeInvestmentIdea(uint8 _ideaIndex, uint256 _capital) public onlyKeeper onlyActive {
    require(_ideaIndex < ideas.length, "No idea available to execute");
    InvestmentIdea storage idea = ideas[_ideaIndex];
    require(idea.executedAt == 0, "Idea has already been executed");
    uint256 liquidReserveAsset = community.getPositionBalance(community.getReserveAsset()).toUint256();
    require(_capital <= liquidReserveAsset, "Not enough capital");
    require(idea.capitalAllocated.add(_capital) <= idea.maxCapitalRequested, "Max capital reached");
    require(liquidReserveAsset >= idea.minRebalanceCapital, "Community does not have enough capital to enter the idea");
    require(block.timestamp.sub(idea.enteredCooldownAt) >= ideaCooldownPeriod, "Idea has not completed the cooldown period");
    // Execute enter trade
    idea.capitalAllocated = idea.capitalAllocated.add(_capital);
    bytes memory _data = idea.enterPayload;
    community.callIntegration(idea.integration, 0, _data, idea.enterTokensNeeded, idea.enterTokensAmounts);
    // Sets the executed timestamp
    idea.executedAt = block.timestamp;
  }

  /**
   * Rebalances available capital of the community between the investment ideas that are active.
   * We enter into the investment and add it to the executed ideas array.
   */
  function rebalanceInvestments() external onlyKeeper onlyActive {
    uint256 liquidReserveAsset = community.getPositionBalance(community.getReserveAsset()).toUint256();
    for (uint i = 0; i < ideas.length; i++) {
      InvestmentIdea storage idea = ideas[i];
      uint256 percentage = idea.totalVotes.toUint256().preciseDiv(totalStake);
      uint256 toAllocate = liquidReserveAsset.preciseMul(percentage);
      if (toAllocate >= idea.minRebalanceCapital && toAllocate.add(idea.capitalAllocated) <= idea.maxCapitalRequested) {
        executeInvestmentIdea(idea.index, toAllocate);
      }
    }
  }

  /**
   * Exits from an executed investment.
   * Sends rewards to the person that created the idea, the voters, and the rest to the community.
   * If there are profits
   * Updates the reserve asset position accordingly.
   */
  function finalizeInvestment(uint _ideaIndex) external onlyKeeper nonReentrant onlyActive {
    require(ideas.length > _ideaIndex, "This idea index does not exist");
    InvestmentIdea storage idea = ideas[_ideaIndex];
    require(idea.executedAt > 0, "This idea has not been executed");
    require(block.timestamp > idea.executedAt.add(idea.duration), "Idea can only be finalized after the minimum period has elapsed");
    require(!idea.finalized, "This investment was already exited");
    address[] memory _tokensNeeded;
    uint256[] memory _tokenAmounts;
    // Execute exit trade
    bytes memory _data = idea.exitPayload;
    address reserveAsset = community.getReserveAsset();
    uint256 reserveAssetBeforeExiting = community.getPositionBalance(reserveAsset).toUint256();
    community.callIntegration(idea.integration, 0, _data, _tokensNeeded, _tokenAmounts);
    // Exchange the tokens back to the reserve asset
    bytes memory _emptyTradeData;
    for (uint i = 0; i < idea.enterTokensNeeded.length; i++) {
      if (idea.enterTokensNeeded[i] != reserveAsset) {
        uint pricePerTokenUnit = _getPrice(reserveAsset, idea.enterTokensNeeded[i]);
        // TODO: The actual amount must be supposedly higher when we exit
        community.tradeFromInvestmentIdea("kyber", idea.enterTokensNeeded[i], idea.enterTokensAmounts[i], reserveAsset, idea.enterTokensAmounts[i].preciseDiv(pricePerTokenUnit), _emptyTradeData);
      }
    }
    uint256 capitalReturned = community.getPositionBalance(reserveAsset).toUint256().sub(reserveAssetBeforeExiting);
    // Mark as finalized
    idea.finalized = true;
    idea.exitedAt = block.timestamp;
    totalStake = totalStake.sub(idea.absoluteTotalVotes);
    // Transfer rewards and update positions
     _transferIdeaRewards(_ideaIndex, capitalReturned);
  }

  /* ============ External Getter Functions ============ */

  /**
   * Gets active investment ideas sorted by stake
   * Uses the stake, the number of voters and the total weight behind the idea.
   *
   * @return  uint8        Returns indexes of the top active ideas in order
   */

  function getActiveIdeas() public view returns (uint8[] memory) {
    uint8[] memory result;
    for (uint8 i = 0; i < ideas.length; i++) {
      InvestmentIdea memory idea = ideas[i];
      // TODO: sort by score
      if (isIdeaActive(idea)) {
        result[i] = idea.index;
      }
    }
    return result;
  }

  /* ============ Internal Functions ============ */

  function _transferIdeaRewards(uint _ideaIndex, uint capitalReturned) internal {
    address reserveAsset = community.getReserveAsset();
    int256 reserveAssetDelta = 0;
    InvestmentIdea storage idea = ideas[_ideaIndex];
    // Idea returns were positive
    if (capitalReturned > idea.capitalAllocated) {
      uint256 profits = capitalReturned - idea.capitalAllocated; // in reserve asset (weth)
      // Send stake back to the ideator
      idea.participant.transfer(idea.stake);
      // Send weth rewards to the ideator
      uint256 ideatorProfits = ideaCreatorProfitPercentage.preciseMul(profits);
      require(ERC20(reserveAsset).transferFrom(
        address(community),
        idea.participant,
        ideatorProfits
      ), "Ideator perf fee failed");
      reserveAssetDelta.add(int256(-ideatorProfits));
      // Send weth rewards to the commmunity lead
      uint256 creatorProfits = communityCreatorProfitPercentage.preciseMul(profits);
      require(ERC20(reserveAsset).transferFrom(
        address(community),
        community.creator(),
        creatorProfits
      ), "Community lead perf fee failed");
      reserveAssetDelta.add(int256(-creatorProfits));
      // Send weth performance fee to the protocol
      uint256 protocolProfits = IBabController(controller).getProtocolPerformanceFee().preciseMul(profits);
      require(ERC20(reserveAsset).transferFrom(
        address(community),
        IBabController(controller).getTreasury(),
        protocolProfits
      ), "Protocol perf fee failed");
      reserveAssetDelta.add(int256(-protocolProfits));
      // Send weth rewards to voters that voted in favor
      uint256 votersProfits = ideaVotersProfitPercentage.preciseMul(profits);
      for (uint256 i = 0; i < idea.voters.length; i++) {
        int256 voterWeight = votes[_ideaIndex][idea.voters[i]];
        if (voterWeight > 0) {
          require(ERC20(reserveAsset).transferFrom(
            address(community),
            idea.voters[i],
            votersProfits.mul(voterWeight.toUint256()).div(idea.totalVotes.toUint256())
          ), "Voter perf fee failed");
        }
      }
      reserveAssetDelta.add(int256(-votersProfits));
    } else {
      // Returns were negative
      uint256 stakeToSlash = idea.stake;
      if (capitalReturned.add(idea.stake) > idea.capitalAllocated) {
        stakeToSlash = capitalReturned.add(idea.stake).sub(idea.capitalAllocated);
      }
      // We slash and add to the community the stake from the creator
      IWETH(community.weth()).deposit{value: stakeToSlash}();
      reserveAssetDelta.add(stakeToSlash.toInt256());
      uint256 votersRewards = ideaVotersProfitPercentage.preciseMul(stakeToSlash);
      // Send weth rewards to voters that voted against
      for (uint256 i = 0; i < idea.voters.length; i++) {
        int256 voterWeight = votes[_ideaIndex][idea.voters[i]];
        if (voterWeight < 0) {
          require(ERC20(reserveAsset).transferFrom(
            address(community),
            idea.voters[i],
            votersRewards.mul(voterWeight.toUint256()).div(idea.totalVotes.toUint256())
          ), "Voter perf fee failed");
        }
      }
      reserveAssetDelta.add(int256(-stakeToSlash));
    }
    // Updates reserve asset position in the community
    uint256 _newTotal = community.getPositionBalance(reserveAsset).add(int256(reserveAssetDelta)).toUint256();
    community.calculateAndEditPosition(reserveAsset, _newTotal, reserveAssetDelta, 0);
  }

  function _getPrice(address _assetOne, address _assetTwo) internal view returns (uint256) {
    IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
    return oracle.getPrice(_assetOne, _assetTwo);
  }

}
