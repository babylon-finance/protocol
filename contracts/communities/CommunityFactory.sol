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
import { RollingCommunity } from "./RollingCommunity.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title CommunityFactory
 * @author Babylon Finance
 *
 * Factory to create community contracts
 */
contract CommunityFactory {

  address immutable rollingCommunity;

  constructor() public {
    rollingCommunity = address(new RollingCommunity());
  }

  function createRollingCommunity(
    address[] memory _integrations,
    address _weth,
    address _controller,
    address _creator,
    string memory _name,
    string memory _symbol
  ) external returns (address) {
      address payable clone = payable(Clones.clone(rollingCommunity));
      RollingCommunity(clone).initialize(
        _integrations,
        _weth,
        _controller,
        _creator,
        _name,
        _symbol
      );
      return clone;
  }

}
