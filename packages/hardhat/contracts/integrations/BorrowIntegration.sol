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
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFund } from "../interfaces/IFund.sol";
import { IWETH } from "../interfaces/external/weth/IWETH.sol";
import { IBorrowIntegration } from "../interfaces/IBorrowIntegration.sol";
import { IFolioController } from "../interfaces/IFolioController.sol";
import { BaseIntegration } from "../BaseIntegration.sol";

/**
 * @title BorrowIntetration
 * @author dFolio Protocol
 *
 * Base class for integration with lending protocols
 */
abstract contract BorrowIntegration is BaseIntegration {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    /* ============ State Variables ============ */
    uint256 public maxCollateralFactor;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     * @param _maxCollateralFactor    Max collateral factor allowed
     */
    constructor(IWETH _weth, IFolioController _controller, uint256 _maxCollateralFactor) public BaseIntegration(_weth, _controller) {
      maxCollateralFactor = _maxCollateralFactor;
    }

    /* ============ External Functions ============ */
    function updateMaxCollateralFactor(uint256 _newMaxCollateralFactor) public onlyProtocol {
      maxCollateralFactor = _newMaxCollateralFactor;
    }

}
