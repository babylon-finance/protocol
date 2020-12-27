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
 * Compound Borrowing primitive
 */

contract CompoundIntegration is BorrowIntegration {
  using SafeMath for uint256;


  address constant CompoundComptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
  address constant CEtherAddress = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
  address constant CUSDCAddress = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
  address constant CUSDTAddress = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
  address constant CWBTCAddress = 0xC11b1268C1A384e55C48c2391d8d480264A3A7F4;

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

  function getBorrowBalance(
      address cToken,
      address owner
  )
      external
      view
      returns (uint256)
  {
      (
          uint256 err,
          uint256 cTokenBalance,
          uint256 borrowBalance,
          uint256 exchangeRateMantissa
      ) = ICToken(cToken).getAccountSnapshot(owner);

      // Source: balanceOfUnderlying from any ctoken
      return cTokenBalance.mul(exchangeRateMantissa).div(1e18);
  }

  function enterMarkets(
      address[] memory cTokens // Address of the Compound derivation token (e.g. cDAI)
  ) public {
    // Enter the compound markets for all the specified tokens
    uint256[] memory errors = IComptroller(CompoundComptrollerAddress)
      .enterMarkets(cTokens);

    for (uint256 i = 0; i < errors.length; i++) {
      require(errors[i] == 0, "cmpnd-mgr-enter-markets-failed");
    }
  }

  function approveCToken(address cToken, uint256 amount) public {
    // Approves CToken contract to call `transferFrom`
    address underlying = ICToken(cToken).underlying();
    require(
        IERC20(underlying).approve(cToken, amount) == true,
        "cmpnd-mgr-ctoken-approved-failed"
    );
  }

  function approveCTokens(
      address[] memory cTokens // Tokens to approve
  ) public {
    for (uint256 i = 0; i < cTokens.length; i++) {
      // Don't need to approve ICEther
      if (cTokens[i] != CEtherAddress) {
          approveCToken(cTokens[i], uint256(-1));
      }
    }
  }

  function depositCollateral(address cToken, uint256 amount) external payable {
    // Amount of current exchange rate from cToken to underlying
    if (cToken == CEtherAddress) {
      require(msg.value == amount, "The amount of eth needs to match");

      ICEther(CEtherAddress).mint{value: msg.value, gas: 250000 }();
    } else {
      // Approves CToken contract to call `transferFrom`
      amount = normalizeDecimals(cToken, amount);
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
  }

  /**
    Normalize all the amounts of all tokens so all can be called with 10^18.
    e.g Call functions like borrow, supply with parseEther
  */
  function normalizeDecimals(address cToken, uint256 amount) view private returns (uint256)  {
    // cUSDC and CUSDT have only 6 decimals
    if (cToken == CUSDCAddress || cToken == CUSDTAddress) {
      amount =  amount.div(10**12);
    }
    // cWBTC has 8 decimals
    if (cToken == CWBTCAddress) {
      amount =  amount.div(10**10);
    }
    return amount;
  }

  function safeBorrow(address cToken, uint256 borrowAmount) private {
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
        ICToken(cToken).borrow(normalizeDecimals(cToken, borrowAmount)) == 0,
        "cmpnd-mgr-ctoken-borrow-failed"
    );
  }

  function borrow(address cToken, uint256 borrowAmount) external {
    require(
        ICToken(cToken).borrow(normalizeDecimals(cToken, borrowAmount)) == 0,
        "cmpnd-mgr-ctoken-borrow-failed"
    );
  }

  function repay(address cToken, uint256 amount) external payable {
      if (cToken == CEtherAddress) {
          ICEther(cToken).repayBorrow{ value: amount }();
      } else {
        amount = normalizeDecimals(cToken, amount);
        approveCToken(cToken, amount);
        require(
            ICToken(cToken).repayBorrow(amount) == 0,
            "cmpnd-mgr-ctoken-repay-failed"
        );
      }
  }

  function repayAll(address asset) external payable {

  }

  function repayBorrowBehalf(
      address recipient,
      address cToken,
      uint256 amount
  ) public payable {
    if (cToken == CEtherAddress) {
      ICEther(cToken).repayBorrowBehalf{ value: amount}(recipient);
    } else {
      amount = normalizeDecimals(cToken, amount);
      approveCToken(cToken, amount);
      require(
          ICToken(cToken).repayBorrowBehalf(recipient, amount) == 0,
          "cmpnd-mgr-ctoken-repaybehalf-failed"
      );
    }
  }

  function withdrawCollateral(address cToken, uint256 redeemTokens) external payable {
    // Retrieve your asset based on a cToken amount
    redeemTokens = normalizeDecimals(cToken, redeemTokens);
    require(
        ICToken(cToken).redeem(redeemTokens) == 0,
        "cmpnd-mgr-ctoken-redeem-failed"
    );
  }

  function withdrawAllCollateral(address cToken) external payable {
    // Retrieve your asset based on a cToken amount
    // TODO
    uint redeemTokens = normalizeDecimals(cToken, 0);
    require(
        ICToken(cToken).redeem(redeemTokens) == 0,
        "cmpnd-mgr-ctoken-redeem-failed"
    );
  }

  function redeemUnderlying(address cToken, uint256 redeemTokens) public payable
  {
    redeemTokens = normalizeDecimals(cToken, redeemTokens);
    // Retrieve your asset based on an amount of the asset
    require(
        ICToken(cToken).redeemUnderlying(redeemTokens) == 0,
        "cmpnd-mgr-ctoken-redeem-underlying-failed"
    );
  }

  // Need this to receive ETH when `borrowEthExample` and calling `redeemCEth` executes
  fallback() external payable {}
}
