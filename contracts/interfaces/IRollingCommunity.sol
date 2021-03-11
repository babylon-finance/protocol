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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICommunity } from "./ICommunity.sol";


/**
 * @title ICommunity
 * @author Babylon Finance
 *
 * Interface for operating with SetTokens.
 */
interface IRollingCommunity is IERC20, ICommunity {

    function initialize(
      uint256 _maxDepositLimit,
      uint256 _premiumPercentage,
      uint256 _minCommunityTokenSupply,
      uint256 _communityActiveWindow,
      uint256 _communityWithdrawalWindow,
      address _communityIdeas
    ) external;

    function deposit(
        uint256 _reserveAssetQuantity,
        uint256 _minCommunityTokenReceiveQuantity,
        address _to
    ) external payable;

    function withdraw(
        uint256 _communityTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) external;
    function withdrawToReservePool(
      uint256 _communityTokenQuantity,
      uint256 _minReserveReceiveQuantity,
      address payable _to
    ) external;

    function setDepositLimit(uint limit) external;
    function getExpectedCommunityTokensDepositedQuantity(
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    ) external view returns (uint256);
    function getExpectedReserveWithdrawalQuantity(
        address _reserveAsset,
        uint256 _communityTokenQuantity
    ) external view returns (uint256);
    function isDepositValid(
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    ) external view returns (bool);
    function isWithdrawalValid(
        address _reserveAsset,
        uint256 _communityTokenQuantity
    ) external view returns (bool);

    function startRedemptionWindow(uint256 _amount) external;
    function reenableEthForInvestments() external;
    function burnAssetsFromSenderAndMintToReserve(address _contributor, uint256 _quantity) external;

    // Investment ideas
    function addInvestmentIdea(
      uint256 _capitalRequested,
      uint256 _stake,
      uint256 _investmentDuration,
      bytes memory _enterData,
      bytes memory _exitData,
      address _integration,
      uint256 _expectedReturn,
      address[] memory _enterTokensNeeded,
      uint256[] memory _enterTokensAmounts
    ) external payable;
    function curateInvestmentIdea(uint8 _ideaIndex, int256 _amount) external;
    function executeTopInvestment() external;
    function finalizeInvestment(uint _ideaIndex) external;
    function getCurrentTopInvestmentIdea() external view returns (uint8);
    function canWithdrawEthAmount(uint _amount) external view returns (bool);
}
