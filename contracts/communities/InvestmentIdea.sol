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

import "hardhat/console.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/Initializable.sol";
import { AddressArrayUtils } from "../lib/AddressArrayUtils.sol";
import { IWETH } from "../interfaces/external/weth/IWETH.sol";
import { PreciseUnitMath } from "../lib/PreciseUnitMath.sol";
import { IBabController } from "../interfaces/IBabController.sol";
import { ICommunity } from "../interfaces/ICommunity.sol";
import { ITradeIntegration } from "../interfaces/ITradeIntegration.sol";
import { IPriceOracle } from "../interfaces/IPriceOracle.sol";

/**
 * @title InvestmentIdea
 * @author Babylon Finance
 *
 * Holds the data for an investment idea
 */
contract InvestmentIdea is ReentrancyGuard, Initializable {
  using SignedSafeMath for int256;
  using SafeMath for uint256;
  using SafeCast for uint256;
  using SafeCast for int256;
  using PreciseUnitMath for int256;
  using PreciseUnitMath for uint256;
  using AddressArrayUtils for address[];
  using Address for address;

  /* ============ Events ============ */
  event Invoked(address indexed _target, uint indexed _value, bytes _data, bytes _returnValue);
  event PositionAdded(address indexed _component);
  event PositionRemoved(address indexed _component);
  event PositionBalanceEdited(address indexed _component, int256 _realBalance);

  /* ============ Modifiers ============ */
  /**
   * Throws if the sender is not the creator of the idea
   */
  modifier onlyController {
    require(msg.sender == address(controller), "Only Controller can access this");
    _;
  }

  modifier onlyIdeator {
    require(msg.sender == ideator, "Only Ideator can access this");
    _;
  }

  modifier onlyContributor {
    require(
        ERC20(address(community)).balanceOf(msg.sender) > 0,
        "Only someone with the community token can withdraw"
    );
    _;
  }

  /**
   * Throws if the sender is not a Communities's integration or integration not enabled
   */
  modifier onlyIntegration() {
    // Internal function used to reduce bytecode size
    require(community.isValidIntegration(msg.sender), "Integration must be valid");
    _;
  }

  /**
   * Throws if the community is not active
   */
  modifier onlyActiveCommunity() {
    require(community.active() == true, "Community must be active");
    _;
  }

  /**
   * Throws if the sender is not a keeper in the protocol
   */
  modifier onlyKeeper() {
    require(controller.isValidKeeper(msg.sender), "Only a keeper can call this");
    _;
  }

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
   * @param balance                Balance of this component
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

  // Community that these ideas belong to
  ICommunity public community;

  address public ideator;           // Address of the ideator that submitted the bet
  uint256 public enteredAt;                 // Timestamp when the idea was submitted
  uint256 public enteredCooldownAt;         // Timestamp when the idea reached quorum
  uint256 public executedAt;                // Timestamp when the idea was executed
  uint256 public exitedAt;                  // Timestamp when the idea was submitted
  uint256 public stake;                     // Amount of stake by the ideator (in reserve asset) Neds to be positive
  uint256 public maxCapitalRequested;       // Amount of max capital to allocate
  uint256 public capitalAllocated;          // Current amount of capital allocated
  uint256 public expectedReturn;            // Expect return by this investment idea
  uint256 public minRebalanceCapital;       // Min amount of capital so that it is worth to rebalance the capital here
  address[] public enterTokensNeeded;       // Positions that need to be taken prior to enter trade
  uint256[] public enterTokensAmounts;      // Amount of these positions
  address[] public voters;                  // Addresses with the voters
  uint256 public duration;                  // Duration of the bet
  int256 public totalVotes;                 // Total votes staked
  uint256 public absoluteTotalVotes;        // Absolute number of votes staked
  uint256 public totalVoters;               // Total amount of curators that voted
  address public integration;               // Address of the integration
  bytes public enterPayload;                // Calldata to execute when entering
  bytes public exitPayload;                 // Calldata to execute when exiting the trade
  bool public finalized;                    // Flag that indicates whether we exited the idea
  bool public active;                       // Whether the idea has met the voting quorum
  bool public dataSet;                      // Whether integration data is set

  // Votes mapping
  mapping(address => int256) public votes;

  // List of positions
  address[] public positions;
  mapping(address => Position) public positionsByComponent;

  /* ============ Constructor ============ */

  /**
   * Before a community is initialized, the community ideas need to be created and passed to community initialization.
   *
   * @param _community                        Address of the community
   * @param _controller                       Address of the controller
   * @param _maxCapitalRequested           Max Capital requested denominated in the reserve asset (0 to be unlimited)
   * @param _stake                         Stake with community participations absolute amounts 1e18
   * @param _investmentDuration            Investment duration in seconds
   * @param _expectedReturn                Expected return
   * @param _minRebalanceCapital           Min capital that is worth it to deposit into this idea
   */
  function initialize(
    address _community,
    address _controller,
    uint256 _maxCapitalRequested,
    uint256 _stake,
    uint256 _investmentDuration,
    uint256 _expectedReturn,
    uint256 _minRebalanceCapital
  ) public initializer
  {
    controller = IBabController(_controller);
    community = ICommunity(_community);
    require(controller.isSystemContract(_community), "Must be a valid community");
    require(_stake > community.totalSupply().div(100), "Stake amount must be at least 1% of the community");
    require(_investmentDuration >= community.minIdeaDuration() && _investmentDuration <= community.maxIdeaDuration(), "Investment duration must be in range");
    require(_stake > 0, "Stake amount must be greater than 0");
    require(_minRebalanceCapital > 0, "Min Capital requested amount must be greater than 0");
    require(_maxCapitalRequested >= _minRebalanceCapital, "The max amount of capital must be greater than one chunk");
    // Check than enter and exit data call integrations
    ideator = msg.sender;
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
    * @param _enterData                     Operation to perform to enter the investment
    * @param _exitData                      Operation to perform to exit the investment
    * @param _integration                   Address of the integration
    * @param _enterTokensNeeded             Tokens that we need to acquire to enter this investment
    * @param _enterTokensAmounts            Token amounts of these assets we need
    */
  function setIntegrationData(
    bytes memory _enterData,
    bytes memory _exitData,
    address _integration,
    address[] memory _enterTokensNeeded,
    uint256[] memory _enterTokensAmounts
  ) public onlyIdeator {
    require(!dataSet, "Data is set already");
    require(community.isValidIntegration(_integration), "Integration must be valid");
    require(enterTokensNeeded.length == _enterTokensAmounts.length, "Tokens and amounts must match");
    integration = _integration;
    enterPayload = _enterData;
    exitPayload = _exitData;
    enterTokensNeeded = _enterTokensNeeded;
    enterTokensAmounts = _enterTokensAmounts;
    dataSet = true;
  }

  /**
   * Curates an investment idea from the contenders array for this epoch.
   * This can happen at any time. As long as there are investment ideas.
   * @param _amount                   Amount to curate, positive to endorse, negative to downvote
   * TODO: Meta Transaction
   */
  function curateIdea(int256 _amount) external onlyContributor onlyActiveCommunity {
    require(_amount.toUint256() < community.balanceOf(msg.sender), "Participant does not have enough balance");
    if (votes[msg.sender] == 0) {
      totalVoters++;
      voters = [msg.sender];
    } else {
      voters.push(msg.sender);
    }
    votes[msg.sender] = votes[msg.sender].add(_amount);
    totalVotes.add(_amount);
    absoluteTotalVotes = absoluteTotalVotes.add(abs(_amount).toUint256());
    totalVotes = totalVotes.add(_amount);
    // TODO: Introduce conviction voting
    uint256 votingThreshold = community.minVotersQuorum().preciseMul(community.totalSupply());
    if (_amount > 0 && totalVotes.toUint256() >= votingThreshold) {
      active = true;
      enteredCooldownAt = block.timestamp;
    }
    if (_amount < 0 && totalVotes.toUint256() < votingThreshold && active && executedAt == 0) {
      active = false;
    }
  }

  /**
   * Executes an idea that has been activated and gone through the cooldown period.
   * @param _capital                  The capital to allocate to this idea
   */
  function executeInvestment(uint256 _capital) public onlyKeeper nonReentrant onlyActiveCommunity {
    require(executedAt == 0, "Idea has already been executed");
    uint256 liquidReserveAsset = community.getReserveBalance();
    require(_capital <= liquidReserveAsset, "Not enough capital");
    require(capitalAllocated.add(_capital) <= maxCapitalRequested, "Max capital reached");
    require(liquidReserveAsset >= minRebalanceCapital, "Community does not have enough capital to enter the idea");
    require(block.timestamp.sub(enteredCooldownAt) >= community.ideaCooldownPeriod(), "Idea has not completed the cooldown period");
    // Execute enter trade
    capitalAllocated = capitalAllocated.add(_capital);
    bytes memory _data = enterPayload;
    community.callIntegration(integration, 0, _data, enterTokensNeeded, enterTokensAmounts);
    // Sets the executed timestamp
    executedAt = block.timestamp;
  }

  /**
   * Exits from an executed investment.
   * Sends rewards to the person that created the idea, the voters, and the rest to the community.
   * If there are profits
   * Updates the reserve asset position accordingly.
   */
  function finalizeInvestment() external onlyKeeper nonReentrant onlyActiveCommunity {
    require(executedAt > 0, "This idea has not been executed");
    require(block.timestamp > executedAt.add(duration), "Idea can only be finalized after the minimum period has elapsed");
    require(!finalized, "This investment was already exited");
    address[] memory _tokensNeeded;
    uint256[] memory _tokenAmounts;
    // Execute exit trade
    bytes memory _data = exitPayload;
    address reserveAsset = community.getReserveAsset();
    uint256 reserveAssetBeforeExiting = community.getReserveBalance();
    _callIntegration(integration, 0, _data, _tokensNeeded, _tokenAmounts);
    // Exchange the tokens back to the reserve asset
    bytes memory _emptyTradeData;
    for (uint i = 0; i < enterTokensNeeded.length; i++) {
      if (enterTokensNeeded[i] != reserveAsset) {
        uint pricePerTokenUnit = _getPrice(reserveAsset, enterTokensNeeded[i]);
        // TODO: The actual amount must be supposedly higher when we exit
        _trade("kyber", enterTokensNeeded[i], enterTokensAmounts[i], reserveAsset, enterTokensAmounts[i].preciseDiv(pricePerTokenUnit), _emptyTradeData);
      }
    }
    uint256 capitalReturned = community.getReserveBalance().sub(reserveAssetBeforeExiting);
    // Mark as finalized
    finalized = true;
    exitedAt = block.timestamp;
    // Transfer rewards and update positions
    _transferIdeaRewards(capitalReturned);
  }

  /**
   * Lets the ideator change the duration of the investment
   * @param _newDuration            New duration of the idea
   */
  function changeInvestmentDuration(uint256 _newDuration) external onlyIdeator {
    require(!finalized, "This investment was already exited");
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
    external
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

  /* ============ Integration hooks ============ */

  /**
   * Function that allows the manager to call an integration
   *
   * @param _integration            Address of the integration to call
   * @param _value                  Quantity of Ether to provide the call (typically 0)
   * @param _data                   Encoded function selector and arguments
   * @param _tokensNeeded           Tokens that we need to acquire more of before executing the investment
   * @param _tokenAmountsNeeded     Tokens amounts that we need. Same index.
   * @return _returnValue           Bytes encoded return value
   */
  function callIntegration(
    address _integration,
    uint256 _value,
    bytes memory _data,
    address[] memory _tokensNeeded,
    uint256[] memory _tokenAmountsNeeded
  ) public onlyController returns (bytes memory _returnValue) {
    return _callIntegration(_integration, _value, _data, _tokensNeeded, _tokenAmountsNeeded);
  }

  /* ============ External Getter Functions ============ */

  /**
   * Returns whether this idea is currently active or not
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
   * Returns whether the community component  position real balance is greater than or equal to balances passed in.
   */
  function hasSufficientBalance(address _component, uint256 _balance)
      external
      view
      returns (bool)
  {
    return _getPositionBalance(_component).toUint256() >= _balance;
  }

  /**
   * Get the position of a component
   *
   * @param _component          Address of the component
   * @return                    Balance
   */
  function getPositionBalance(address _component)
      external
      view
      returns (int256)
  {
    return _getPositionBalance(_component);
  }

  /* ============ Internal Functions ============ */

  /**
   * Low level function that allows an integration to make an arbitrary function
   * call to any contract from the community (community as msg.sender).
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
  )
      internal
      returns (bytes memory _returnValue)
  {
      _returnValue = _target.functionCallWithValue(_data, _value);
      emit Invoked(_target, _value, _data, _returnValue);
      return _returnValue;
  }

  function invokeApprove(address _spender, address _asset, uint256 _quantity) external onlyIntegration {
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

  /**
   * Function that allows the manager to call an integration
   *
   * @param _integration            Address of the integration to call
   * @param _value                  Quantity of Ether to provide the call (typically 0)
   * @param _data                   Encoded function selector and arguments
   * @param _tokensNeeded           Tokens that we need to acquire more of before executing the investment
   * @param _tokenAmountsNeeded     Tokens amounts that we need. Same index.
   * @return _returnValue           Bytes encoded return value
   */
  function _callIntegration(
    address _integration,
    uint256 _value,
    bytes memory _data,
    address[] memory _tokensNeeded,
    uint256[] memory _tokenAmountsNeeded
  ) internal returns (bytes memory _returnValue) {
    require(_tokensNeeded.length == _tokenAmountsNeeded.length);
    // _validateOnlyIntegration(_integration);
    // Exchange the tokens needed
    for (uint i = 0; i < _tokensNeeded.length; i++) {
      if (_tokensNeeded[i] != community.getReserveAsset()) {
        uint pricePerTokenUnit = _getPrice(community.getReserveAsset(), _tokensNeeded[i]);
        uint slippageAllowed = 1e16; // 1%
        uint exactAmount = _tokenAmountsNeeded[i].preciseDiv(pricePerTokenUnit);
        uint amountOfReserveAssetToAllow = exactAmount.add(exactAmount.preciseMul(slippageAllowed));
        require(ERC20(community.getReserveAsset()).balanceOf(address(this)) >= amountOfReserveAssetToAllow, "Need enough liquid reserve asset");
        _trade("kyber", community.getReserveAsset(), amountOfReserveAssetToAllow,_tokensNeeded[i], _tokenAmountsNeeded[i], _data);
      }
    }
    return _invoke(_integration, _value, _data);
  }

  /**
   * Function that calculates the price using the oracle and executes a trade.
   * Must call the exchange to get the price and pass minReceiveQuantity accordingly.
   * @param _integrationName        Name of the integration to call
   * @param _sendToken              Token to exchange
   * @param _sendQuantity           Amount of tokens to send
   * @param _receiveToken           Token to receive
   * @param _minReceiveQuantity     Min amount of tokens to receive
   * @param _data                   Bytes call data
   */
  function _trade(
    string memory _integrationName,
    address _sendToken,
    uint256 _sendQuantity,
    address _receiveToken,
    uint256 _minReceiveQuantity,
    bytes memory _data) internal
  {
    address tradeIntegration = IBabController(controller).getIntegrationByName(_integrationName);
    require(community.isValidIntegration(tradeIntegration), "Integration is not valid");
    // Updates UniSwap TWAP
    IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
    oracle.updateAdapters(_sendToken, _receiveToken);
    return ITradeIntegration(tradeIntegration).trade(_sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity, _data);
  }

  function _transferIdeaRewards(uint capitalReturned) internal {
    address reserveAsset = community.getReserveAsset();
    int256 reserveAssetDelta = 0;
    // Idea returns were positive
    if (capitalReturned > capitalAllocated) {
      uint256 profits = capitalReturned - capitalAllocated; // in reserve asset (weth)
      // Send stake back to the ideator
      require(ERC20(address(community)).transferFrom(
        address(community),
        ideator,
        stake
      ), "Ideator stake return failed");
      // Send weth rewards to the ideator
      uint256 ideatorProfits = community.ideaCreatorProfitPercentage().preciseMul(profits);
      require(ERC20(reserveAsset).transferFrom(
        address(community),
        ideator,
        ideatorProfits
      ), "Ideator perf fee failed");
      reserveAssetDelta.add(int256(-ideatorProfits));
      // Send weth rewards to the commmunity lead
      uint256 creatorProfits = community.communityCreatorProfitPercentage().preciseMul(profits);
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
      uint256 votersProfits = community.ideaVotersProfitPercentage().preciseMul(profits);
      for (uint256 i = 0; i < voters.length; i++) {
        int256 voterWeight = votes[voters[i]];
        if (voterWeight > 0) {
          require(ERC20(reserveAsset).transferFrom(
            address(community),
            voters[i],
            votersProfits.mul(voterWeight.toUint256()).div(totalVotes.toUint256())
          ), "Voter perf fee failed");
        }
      }
      reserveAssetDelta.add(int256(-votersProfits));
    } else {
      // Returns were negative
      uint256 stakeToSlash = stake;
      if (capitalReturned.add(stake) > capitalAllocated) {
        stakeToSlash = capitalReturned.add(stake).sub(capitalAllocated);
      }
      // We slash and add to the community the stake from the creator
      IWETH(community.weth()).deposit{value: stakeToSlash}();
      reserveAssetDelta.add(stakeToSlash.toInt256());
      uint256 votersRewards = community.ideaVotersProfitPercentage().preciseMul(stakeToSlash);
      // Send weth rewards to voters that voted against
      for (uint256 i = 0; i < voters.length; i++) {
        int256 voterWeight = votes[voters[i]];
        if (voterWeight < 0) {
          require(ERC20(reserveAsset).transferFrom(
            address(community),
            voters[i],
            votersRewards.mul(voterWeight.toUint256()).div(totalVotes.toUint256())
          ), "Voter perf fee failed");
        }
      }
      reserveAssetDelta.add(int256(-stakeToSlash));
    }
    // Start a redemption window in the community with this capital
    community.startRedemptionWindow(capitalReturned);
    // Updates reserve asset position in the community
    uint256 _newTotal = community.getReserveBalance().toInt256().add(reserveAssetDelta).toUint256();
    community.updateReserveBalance(_newTotal);
  }

  /**
   * Internal MODULE FUNCTION. Low level function that adds a component to the positions array.
   */
  function _addPosition(address _component, address _integration) internal{
    Position storage position = positionsByComponent[_component];

    position.subpositions.push(SubPosition({
      integration: _integration,
      balance: 0,
      status: 0
    }));
    position.subpositionsCount ++;
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
   position.subpositions.push(SubPosition({
     integration: _integration,
     balance: _deltaBalance,
     status: _subpositionStatus
   }));
  } else {
   position.subpositions[subpositionIndex.toUint256()].balance = _deltaBalance;
   position.subpositions[subpositionIndex.toUint256()].status = _subpositionStatus;
  }

  emit PositionBalanceEdited(_component, _amount);
 }

 function _getSubpositionIndex(address _component, address _integration) view internal returns (int256) {
    Position storage position = positionsByComponent[_component];
    for (uint8 i = 0; i < position.subpositionsCount; i++) {
      if (position.subpositions[i].integration == _integration) {
        return i;
      }
    }
    return -1;
  }

  /**
   * Returns whether the community has a position for a given component (if the real balance is > 0)
   */
  function _hasPosition(address _component) internal view returns (bool) {
      return _getPositionBalance(_component) > 0;
  }

  function _getPositionBalance(address _component) internal view returns (int256) {
    return positionsByComponent[_component].balance;
  }

  function abs(int x) private pure returns (int) {
    return x >= 0 ? x : -x;
  }

  function _getPrice(address _assetOne, address _assetTwo) internal returns (uint256) {
    IPriceOracle oracle = IPriceOracle(IBabController(controller).getPriceOracle());
    // Updates UniSwap TWAP
    oracle.updateAdapters(_assetOne, _assetTwo);
    return oracle.getPrice(_assetOne, _assetTwo);
  }
}
