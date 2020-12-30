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
import { ICToken } from '../interfaces/external/compound/ICToken.sol';
import { ICEther } from '../interfaces/external/compound/ICEther.sol';
import { ICompoundPriceOracle } from '../interfaces/external/compound/ICompoundPriceOracle.sol';
import { IComptroller } from '../interfaces/external/compound/IComptroller.sol';
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH } from "../interfaces/external/weth/IWETH.sol";

import { BorrowIntegration } from "./BorrowIntegration.sol";
import { IFolioController } from "../interfaces/IFolioController.sol";
import { BaseIntegration } from "./BaseIntegration.sol";

/**
 * @title CompoundIntegration
 * @author DFolio
 *
 * Abstract class that houses compound borring/lending logic.
 */
contract CompoundIntegration is BorrowIntegration {
  using SafeMath for uint256;

  /* ============ State Variables ============ */

  address constant CompoundComptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
  address constant CEtherAddress = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

  /* ============ Constructor ============ */

  /**
   * Creates the integration
   *
   * @param _weth                   Address of the WETH ERC20
   * @param _controller             Address of the controller
   * @param _maxCollateralFactor    Max collateral factor allowed
   */
  constructor(
    address _controller,
    address _weth,
    uint256 _maxCollateralFactor
  ) public BorrowIntegration('Compound Borrowing', _weth, _controller, _maxCollateralFactor) {
  }

  /* ============ External Functions ============ */


  /**
   * Deposits collateral into the Compound protocol.
   * This would be called by a fund within a strategy
   * @param asset The cAsset to be deposited as collateral
   * @param amount The amount to be deposited as collateral
   *
   */
  function depositCollateral(address asset, uint256 amount) onlyFund external payable {
    address cToken = assetToCtoken[asset];
    // Amount of current exchange rate from cToken to underlying
    if (cToken == CEtherAddress) {
      require(msg.value == amount, "The amount of eth needs to match");

      ICEther(CEtherAddress).mint{value: msg.value, gas: 250000 }();
    } else {
      // Approves CToken contract to call `transferFrom`
      amount = normalizeDecimals(asset, amount);
      approveCToken(cToken, amount);
      ICToken cTokenInstance = ICToken(cToken);
      // uint256 exchangeRateMantissa = cTokenInstance.exchangeRateCurrent();
      // emit MyLog("Exchange Rate (scaled up by 1e18): ", exchangeRateMantissa);
      //
      // // Amount added to you supply balance this block
      // uint256 supplyRateMantissa = cTokenInstance.supplyRatePerBlock();
      // emit MyLog("Supply Rate: (scaled up by 1e18)", supplyRateMantissa);

      require(
          cTokenInstance.mint(amount) == 0,
          "cmpnd-mgr-ctoken-supply-failed"
      );
    }
    updateFundPosition(msg.sender, asset, amount);
  }

  /**
   * Borrows an asset
   * @param asset The asset to be borrowed
   * @param amount The amount to borrow
   */
  function borrow(address asset, uint256 amount) onlyFund external {
    address cToken = assetToCtoken[asset];
    require(
        ICToken(cToken).borrow(normalizeDecimals(asset, amount)) == 0,
        "cmpnd-mgr-ctoken-borrow-failed"
    );
    updateFundPosition(msg.sender, asset, 0 - amount);
  }

  /**
   * Repays a borrowed asset debt
   * @param asset The asset to be repaid
   * @param amount The amount to repay
   */
  function repay(address asset, uint256 amount) onlyFund external payable {
    address cToken = assetToCtoken[asset];
    if (cToken == CEtherAddress) {
        ICEther(cToken).repayBorrow{ value: amount }();
    } else {
      amount = normalizeDecimals(asset, amount);
      approveCToken(cToken, amount);
      require(
          ICToken(cToken).repayBorrow(amount) == 0,
          "cmpnd-mgr-ctoken-repay-failed"
      );
    }
  }

  /**
   * Repays all the borrowed asset debt
   * @param asset The asset to be repaid
   */
  function repayAll(address asset) onlyFund external payable {
    address cToken = assetToCtoken[asset];
    if (cToken == CEtherAddress) {
        ICEther(cToken).repayBorrow{ value: _getBorrowBalance(asset)}();
    } else {
      uint256 amount = normalizeDecimals(asset, _getBorrowBalance(asset));
      approveCToken(cToken, amount);
      require(
          ICToken(cToken).repayBorrow(amount) == 0,
          "cmpnd-mgr-ctoken-repay-failed"
      );
    }
  }

  /**
   * Withdraw an amount of collateral as the underlying asset
   * @param asset   The underlying asset to withdraw
   * @param amount The amount of the underlying to withdraw
   *
   */
  function withdrawCollateral(address asset, uint256 amount) onlyFund external payable {
    address cToken = assetToCtoken[asset];
    // Retrieve your asset based on a cToken amount
    amount = normalizeDecimals(asset, amount);
    require(
        ICToken(cToken).redeem(amount) == 0,
        "cmpnd-mgr-ctoken-redeem-failed"
    );
  }

  /**
   * Withdraw all of a collateral as the underlying asset
   * @param asset   The underlying asset to withdraw
   *
   */
  function withdrawAllCollateral(address asset) onlyFund external payable {
    address cToken = assetToCtoken[asset];
    // Retrieve your asset based on a cToken amount
    uint amount = normalizeDecimals(asset, _getCollateralBalance(asset));
    require(
        ICToken(cToken).redeem(amount) == 0,
        "cmpnd-mgr-ctoken-redeem-failed"
    );
  }

  /**
   * Get the amount of borrowed debt that needs to be repaid
   * @param asset   The underlying asset
   *
   */
  function getBorrowBalance(
    address asset
  )
    onlyFund
    external
    view
    returns (uint256)
  {
    return _getBorrowBalance(asset);
  }

  /**
   * Get the health factor of the total debt situation
   *
   */
  function getHealthFactor() onlyFund external view returns (uint256) {
    IComptroller comptroller = IComptroller(CompoundComptrollerAddress);
    (uint256 error, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(msg.sender);
    return liquidity;
  }

  /* ============ Internal Functions ============ */

  function enterMarkets(
    address[] memory cTokens // Address of the Compound derivation token (e.g. cDAI)
  ) private {
    // Enter the compound markets for all the specified tokens
    uint256[] memory errors = IComptroller(CompoundComptrollerAddress)
      .enterMarkets(cTokens);

    for (uint256 i = 0; i < errors.length; i++) {
      require(errors[i] == 0, "cmpnd-mgr-enter-markets-failed");
    }
  }

  function approveCToken(address cToken, uint256 amount) private {
    // Approves CToken contract to call `transferFrom`
    address underlying = ICToken(cToken).underlying();
    require(
        IERC20(underlying).approve(cToken, amount) == true,
        "cmpnd-mgr-ctoken-approved-failed"
    );
  }

  function approveCTokens(
      address[] memory cTokens // Tokens to approve
  ) private {
    for (uint256 i = 0; i < cTokens.length; i++) {
      // Don't need to approve ICEther
      if (cTokens[i] != CEtherAddress) {
          approveCToken(cTokens[i], uint256(-1));
      }
    }
  }

  function _getBorrowBalance(address asset) private view returns (uint256) {
    address cToken = assetToCtoken[asset];
    (
      uint256 err,
      uint256 cTokenBalance,
      uint256 borrowBalance,
      uint256 exchangeRateMantissa
    ) = ICToken(cToken).getAccountSnapshot(msg.sender);
    return borrowBalance.mul(exchangeRateMantissa).div(1e18);
  }

  function _getCollateralBalance(address asset) private view returns (uint256) {
    address cToken = assetToCtoken[asset];
    (
      uint256 err,
      uint256 cTokenBalance,
      uint256 borrowBalance,
      uint256 exchangeRateMantissa
    ) = ICToken(cToken).getAccountSnapshot(msg.sender);

    // Source: balanceOfUnderlying from any ctoken
    return cTokenBalance.mul(exchangeRateMantissa).div(1e18);
  }

  function safeBorrow(address asset, uint256 borrowAmount) private {
    address cToken = assetToCtoken[asset];
    // Get my account's total liquidity value in Compound
    (uint256 error, uint256 liquidity, uint256 shortfall) = IComptroller(CompoundComptrollerAddress)
        .getAccountLiquidity(address(this));
    if (error != 0) {
        revert("Comptroller.getAccountLiquidity failed.");
    }
    require(shortfall == 0, "account underwater");
    require(liquidity > 0, "account does not have collateral");

    // Get the underlying price in USD from the Price Feed,
    // so we can find out the maximum amount of underlying we can borrow.
    // uint256 underlyingPrice = compoundPriceOracle.getUnderlyingPrice(_cTokenAddress);
    // uint256 maxBorrowUnderlying = liquidity / underlyingPrice;

    // Borrowing near the max amount will result
    // in your account being liquidated instantly
    // emit MyLog("Maximum underlying Borrow (borrow far less!)", maxBorrowUnderlying);
    require(
        ICToken(cToken).borrow(normalizeDecimals(asset, borrowAmount)) == 0,
        "cmpnd-mgr-ctoken-borrow-failed"
    );
  }

  // function repayBorrowBehalf(
  //     address recipient,
  //     address asset,
  //     uint256 amount
  // ) private payable {
  //   address cToken = assetToCtoken[asset];
  //   if (cToken == CEtherAddress) {
  //     ICEther(cToken).repayBorrowBehalf{ value: amount}(recipient);
  //   } else {
  //     amount = normalizeDecimals(asset, amount);
  //     approveCToken(cToken, amount);
  //     require(
  //         ICToken(cToken).repayBorrowBehalf(recipient, amount) == 0,
  //         "cmpnd-mgr-ctoken-repaybehalf-failed"
  //     );
  //   }
  // }
  //
  // function redeemUnderlying(address asset, uint256 redeemTokens) private payable
  // {
  //   address cToken = assetToCtoken[asset];
  //   redeemTokens = normalizeDecimals(asset, redeemTokens);
  //   // Retrieve your asset based on an amount of the asset
  //   require(
  //       ICToken(cToken).redeemUnderlying(redeemTokens) == 0,
  //       "cmpnd-mgr-ctoken-redeem-underlying-failed"
  //   );
  // }

  // Need this to receive ETH when `borrowEthExample` and calling `redeemCEth` executes
  fallback() external payable {}
}
