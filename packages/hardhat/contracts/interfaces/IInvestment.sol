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

interface IInvestment {

  function contractImpl() external view returns (address);
  function getFunds() external view returns (uint);

  // Yearn
  function want() external view returns (address);

  function deposit() external;

  // NOTE: must exclude any tokens used in the yield
  // Controller role - withdraw should return to Controller
  function withdraw(address) external;

  // Controller | Vault role - withdraw should always return to Vault
  function withdraw(uint256) external;

  function skim() external;

  // Controller | Vault role - withdraw should always return to Vault
  function withdrawAll() external returns (uint256);

  function balanceOf() external view returns (uint256);

}
