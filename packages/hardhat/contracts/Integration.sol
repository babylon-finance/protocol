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

import "hardhat/console.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFund } from "./interfaces/IFund.sol";
import { IIntegration } from "./interfaces/IFund.sol";

/**
 * @title FolioController
 * @author dFolio Protocol
 *
 * FolioController is a smart contract used to deploy new funds contracts and house the
 * integrations and resources of the system.
 */
abstract contract Integration is IIntegration {
    using AddressArrayUtils for address[];
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    /* ============ State Variables ============ */

    // Folio Controller address
    IFolioController public controller;
    // Wrapped ETH address
    IWETH public immutable weth;
    mapping(address => bool) public initializedByFund;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     */

    constructor(IWETH _weth, IFolioController _controller) public {
      require(_controller != address(0), "Controller must be non-zero address.");
      controller = _controller;
      weth = _weth;
      initialized = false;
    }

    /* ============ External Functions ============ */

    /**
     * Initializes the integration.
     * @param _fund addres of the fund
     */
    function initialize(address _fund) virtual public {
      require(!initializedByFund[_fund], "integration has already been initialized");
      IFund(_fund).initializeIntegration();
      initializedByFund[_fund] = true;
    }

    /**
     * Updates the position in the fund with the new units
     *
     * @param _fund                     Address of the fund
     * @param _component                Address of the ERC20
     * @param _newUnit                  New unit of the fund position
     */
    function updateFundPosition(address _fund, address _component, int256 _newUnit) external {
      IFund(_fund).calculateAndEditPosition(_fund, _component, _newUnit);
    }

}
