/*
    Copyright 2020 DFolio

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

import { IIntegration } from "./IIntegration.sol";

/**
 * @title IBorrowIntegration
 * @author DFolio
 *
 * Interface for lending protocol integrations
 */
interface IBorrowIntegration is IIntegration {

  function depositCollateral(address asset, uint256 amount) external;
  function removeCollateral(address asset, uint256 amount) external;
  function borrow(address asset, uint256 borrowAmount) external;
  function repay(address asset, uint256 amount) external;
  function updateMaxCollateralFactor(uint256 _newMaxCollateralFactor) external;

  function getBorrowBalance(address asset) external view returns (uint256);
  function getDebtToken(address asset) external returns (address);
  function getHealthFactor() external view returns (uint256);
}
