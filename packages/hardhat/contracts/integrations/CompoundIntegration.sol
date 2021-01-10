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
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { IWETH } from "../interfaces/external/weth/IWETH.sol";

import { BorrowIntegration } from "./BorrowIntegration.sol";
import { IFolioController } from "../interfaces/IFolioController.sol";
import { IFund } from "../interfaces/IFund.sol";
import { BaseIntegration } from "./BaseIntegration.sol";

/**
 * @title CompoundIntegration
 * @author DFolio
 *
 * Abstract class that houses compound borring/lending logic.
 */
contract CompoundIntegration is BorrowIntegration {
  using SafeMath for uint256;
  using SafeERC20 for ERC20;

  /* ============ State Variables ============ */

  address constant CompoundComptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
  address constant CEtherAddress = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
  // Mapping of asset addresses to cToken addresses
  mapping(address => address) public assetToCtoken;

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
  ) BorrowIntegration('Compound Borrowing', _weth, _controller, _maxCollateralFactor) {
    assetToCtoken[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643; // DAI
    assetToCtoken[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5; // WETH
    assetToCtoken[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 0x39AA39c021dfbaE8faC545936693aC917d5E7563; // USDC
    assetToCtoken[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9; // USDT
    assetToCtoken[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599] = 0xC11b1268C1A384e55C48c2391d8d480264A3A7F4; // WBTC
    assetToCtoken[0xc00e94Cb662C3520282E6f5717214004A7f26888] = 0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4; // COMP
  }

  /* ============ External Functions ============ */

  // TODO: Move this to protocol
  // Governance function
  function updateCTokenMapping(address _assetAddress, address _cTokenAddress) external onlyProtocol {
    assetToCtoken[_assetAddress] = _cTokenAddress;
  }


  /* ============ Overriden Functions ============ */

  /**
   * Return pre action calldata
   *
   * @param  _asset                    Address of the asset to deposit
   * @param  _amount                   Amount of the token to deposit
   * @param  _borrowOp                Type of Borrow op
   *
   * @return address                   Target contract address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getPreActionCallData(
    address _asset,
    uint256 _amount,
    uint _borrowOp
  ) internal override view returns (address, uint256, bytes memory) {
    if (_borrowOp == 2 || _borrowOp == 0) {
      // Encode method data for Fund to invoke
      bytes memory methodData = abi.encodeWithSignature(
        "enterMarkets(address[])",
        [_asset]
      );
      return (address(CompoundComptrollerAddress), 0, methodData);
    }
  }

  /**
   * Return deposit collateral calldata
   *
   * @param  _asset                    Address of the asset to deposit
   * @param  _amount                   Amount of the token to deposit
   *
   * @return address                   Target contract address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getDepositCalldata(
    address _asset,
    uint256 _amount
  ) internal override view returns (address, uint256, bytes memory) {
    // Encode method data for Fund to invoke
    bytes memory methodData = abi.encodeWithSignature(
      "mint(uint256)",
      _amount
    );
    return (assetToCtoken[_asset], 0, methodData);
  }

  /**
   * Return collateral removal calldata
   *
   * @param  _asset                    Address of the asset to deposit
   * @param  _amount                   Amount of the token to deposit
   *
   * @return address                   Target contract address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getRemovalCalldata(
    address _asset,
    uint256 _amount
  ) internal override view returns (address, uint256, bytes memory) {
    // Encode method data for Fund to invoke
    bytes memory methodData = abi.encodeWithSignature(
      "redeem(uint256)",
      _amount
    );

    return (assetToCtoken[_asset], 0, methodData);
  }

  /**
   * Return borrow token calldata
   *
   * @param  _asset                    Address of the asset to deposit
   * @param  _amount                   Amount of the token to deposit
   *
   * @return address                   Target contract address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getBorrowCalldata(
    address _asset,
    uint256 _amount
  ) internal override view returns (address, uint256, bytes memory) {
    // Encode method data for Fund to invoke
    bytes memory methodData = abi.encodeWithSignature(
      "borrow(uint256)",
      _amount
    );

    return (assetToCtoken[_asset], 0, methodData);
  }

  /**
   * Return repay borrowed asset calldata
   *
   * @param  _asset                    Address of the asset to deposit
   * @param  _amount                   Amount of the token to deposit
   *
   * @return address                   Target contract address
   * @return uint256                   Call value
   * @return bytes                     Trade calldata
   */
  function _getRepayCalldata(
    address _asset,
    uint256 _amount
  ) internal override view returns (address, uint256, bytes memory) {
    // Encode method data for Fund to invoke
    bytes memory methodData = abi.encodeWithSignature(
      "repayBorrow(uint256)",
      _amount
    );
    return (assetToCtoken[_asset], 0, methodData);
  }

  /* ============ Internal Functions ============ */

  /**
   * Get the health factor of the total debt situation
   *
   */
  function _getHealthFactor() onlyFund external view returns (uint256) {
    IComptroller comptroller = IComptroller(CompoundComptrollerAddress);
    (uint256 error, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(msg.sender);
    return liquidity;
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

  function _safeBorrow(address asset, uint256 borrowAmount) private {
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

  /* ============ Internal Functions ============ */

  function _getCollateralAsset(address _asset, uint8 _borrowOp) internal override view returns (address) {
    // TODO: check this
    return assetToCtoken[_asset];
  }

  function _getSpender(address _asset) internal override view returns (address) {
    return assetToCtoken[_asset];
  }

}
