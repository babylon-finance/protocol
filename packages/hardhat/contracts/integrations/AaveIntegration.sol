/*
    Copyright 2020 DFolio.

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

pragma solidity >=0.7.0 <0.9.0;

import "hardhat/console.sol";
import { ILendingPool } from '../interfaces/external/aave/ILendingPool.sol';
import { IProtocolDataProvider} from '../interfaces/external/aave/IProtocolDataProvider.sol';
import { IStableDebtToken } from '../interfaces/external/aave/IStableDebtToken.sol';
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { IWETH } from "../interfaces/external/weth/IWETH.sol";

import { BorrowIntegration } from "./BorrowIntegration.sol";
import { IFolioController } from "../interfaces/IFolioController.sol";
import { BaseIntegration } from "./BaseIntegration.sol";

/**
 * @title AaveIntegration
 * @author DFolio
 *
 * Abstract class that houses aave borring/lending logic.
 */
contract AaveIntegration is BorrowIntegration {
    using SafeERC20 for IERC20;

    ILendingPool constant lendingPool = ILendingPool(address(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9)); // Mainnet
    IProtocolDataProvider constant dataProvider = IProtocolDataProvider(address(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d)); // Mainnet
    uint constant interestRateMode = 1; // Stable Interest
    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     * @param _maxCollateralFactor    Max collateral factor allowed (from 0 to a 100)
     */
    constructor(
      address _controller,
      address _weth,
      uint256 _maxCollateralFactor
    ) BorrowIntegration('Aave Borrow', _weth, _controller, _maxCollateralFactor) {
    }

    /**
     * Deposits collateral into the Aave.
     * This would be called by a fund within a strategy
     * @param asset The asset to be deposited as collateral
     * @param amount The amount to be deposited as collateral
     *
     */
    function depositCollateral(address asset, uint256 amount) onlyFund external {
      amount = normalizeDecimals(asset, amount);
      IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
      IERC20(asset).safeIncreaseAllowance(address(lendingPool), amount);
      lendingPool.deposit(asset, amount, msg.sender, 0);
      updateFundPosition(msg.sender, asset, amount);
    }

    /**
     * Borrows an asset
     * @param asset The asset to be borrowed
     * @param amount The amount to borrow
     */
    function borrow(address asset, uint256 amount) onlyFund external {
      amount = normalizeDecimals(asset, amount);
      lendingPool.borrow(asset, amount, interestRateMode, 0, msg.sender);
      // Sends the borrowed assets back to the caller
      IERC20(asset).transfer(msg.sender, amount);
      updateFundPosition(msg.sender, asset, -amount);
    }

    /**
     * Repays a borrowed asset debt
     * @param asset The asset to be repaid
     * @param amount The amount to repay
     */
    function repay(address asset, uint256 amount) onlyFund external {
      amount = normalizeDecimals(asset, amount);
      IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
      IERC20(asset).safeApprove(address(lendingPool), amount);
      lendingPool.repay(asset, amount, interestRateMode, msg.sender);
    }

    /**
     * Repays all the borrowed asset debt
     * @param asset The asset to be repaid
     */
    function repayAll(address asset) onlyFund external {
      (uint256 assetLended, uint256 stableDebt,,,,,,,) = dataProvider.getUserReserveData(asset, msg.sender);
      IERC20(asset).safeTransferFrom(msg.sender, address(this), stableDebt);
      IERC20(asset).safeApprove(address(lendingPool), stableDebt);
      lendingPool.repay(asset, stableDebt, interestRateMode, msg.sender);
    }

    /**
     * Withdraw an amount of collateral as the underlying asset
     * @param asset   The underlying asset to withdraw
     * @param amount The amount of the underlying to withdraw
     *
     */
    function withdrawCollateral(address asset, uint256 amount) onlyFund external {
      amount = normalizeDecimals(asset, amount);
      lendingPool.withdraw(asset, amount, msg.sender);
    }

    /**
     * Withdraw all of a collateral as the underlying asset
     * @param asset   The underlying asset to withdraw
     *
     */
    function withdrawAllCollateral(address asset) onlyFund external {
      (address aTokenAddress,,) = dataProvider.getReserveTokensAddresses(asset);
      uint256 assetBalance = IERC20(aTokenAddress).balanceOf(msg.sender);
      lendingPool.withdraw(asset, assetBalance, msg.sender);
    }

    /**
     * Get the amount of borrowed debt that needs to be repaid
     * @param asset   The underlying asset
     *
     */
    function getBorrowBalance(address asset) onlyFund external view returns (uint256) {
      (uint256 assetLended, uint256 stableDebt,,,,,,,) = dataProvider.getUserReserveData(asset, msg.sender);
      return stableDebt;
    }

    /**
     * Get the health factor of the total debt
     *
     */
    function getHealthFactor() onlyFund external view returns (uint256) {
      (
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 borrowingPower,
        uint256 lituidationThreshold,
        uint256 ltv,
        uint256 healthFactor
      ) = lendingPool.getUserAccountData(address(this));
      return healthFactor;
    }
}
