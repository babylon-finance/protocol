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
 * @title IReservePool
 * @author Babylon Finance
 *
 * Interface for ReservePool
 */
interface IReservePool {

  function editMaxPercentageGardenOwnership(uint256 _newMax) external;
  function editMinGardenNAV(uint256 _newMinGardenNav) external;
  function deposit() external payable;
  function claim(uint256 _amount, address payable _to) external;

  function sellTokensToLiquidityPool(address _garden, uint256 _amount) external returns (uint256);
  function redeemETHFromGardenTokens(address _garden, uint256 _amount) external;

  function isReservePoolAllowedToBuy(address _garden, uint256 _newAmount) external view returns (bool);
}
