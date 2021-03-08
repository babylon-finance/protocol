/*
    Copyright 2020 Babylon Finance

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

/**
 * @title ICommunityIdeas
 * @author Babylon Finance
 *
 * Interface for community ideas
 */
interface ICommunityIdeas {
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
  ) external payable;

  function curateInvestmentIdea(uint8 _ideaIndex, int256 _amount) external;
  function rebalanceInvestments() external;
  function executeInvestmentIdea(uint8 _ideaIndex, uint256 _capital) external;
  function finalizeInvestment(uint _ideaIndex) external;

  function getActiveIdeas() external view returns (uint8[] memory);
  function controller() external pure returns (address);
  function community() external pure returns (address);
  function totalStake() external pure returns (uint256);
  function minVotersQuorum() external pure returns (uint256);
  function maxIdeaDuration() external pure returns (uint256);
  function ideaCooldownPeriod() external pure returns (uint256);
  function ideaCreatorProfitPercentage() external pure returns (uint256);
  function ideaVotersProfitPercentage() external pure returns (uint256);
  function communityCreatorProfitPercentage() external pure returns (uint256);
}
