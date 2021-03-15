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

import { IIntegration } from "./IIntegration.sol";

/**
 * @title IGardenFactory
 * @author Babylon Finance
 *
 * Interface for the garden factory
 */
interface IGardenFactory {

  function createRollingGarden(
    address[] memory _integrations,
    address _weth,
    address _controller,
    address _creator,
    string memory _name,
    string memory _symbol
  ) external returns(address);
}
