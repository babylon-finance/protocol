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
    ) BorrowIntegration('aave', _weth, _controller, _maxCollateralFactor) {
    }

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
    ) internal override pure returns (address, uint256, bytes memory) {
      return (address(0),0,bytes(""));
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
        "deposit(address,uint256,address,uint16)",
        _asset,
        _amount,
        msg.sender,
        0
      );

      return (address(lendingPool), 0, methodData);
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
        "withdraw(address,uint256,address)",
        _asset,
        _amount,
        msg.sender
      );

      return (address(lendingPool), 0, methodData);
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
        "borrow(address,uint256,uint256,uint16,address)",
        _asset,
        _amount,
        interestRateMode,
        0,
        msg.sender
      );

      return (address(lendingPool), 0, methodData);
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
        "repay(address,uint256,uint256,address)",
        _asset,
        _amount,
        interestRateMode,
        msg.sender
      );
      return (address(lendingPool), 0, methodData);
    }


    /* ============ Internal Functions ============ */

    function _getCollateralAsset(address asset, uint8 _borrowOp) internal override view  returns (address) {
      return asset;
    }

    function _getSpender(address asset) internal override view returns (address) {
      return address(lendingPool);
    }

    function _getDebtToken(address asset) view internal returns (address) {
      // Get the relevant debt token address
      (, address stableDebtTokenAddress,) = dataProvider.getReserveTokensAddresses(asset);
      return stableDebtTokenAddress;
    }

    /**
     * Get the amount of borrowed debt that needs to be repaid
     * @param asset   The underlying asset
     *
     */
    function _getBorrowBalance(address asset) internal view returns (uint256) {
      (uint256 assetLended, uint256 stableDebt,,,,,,,) = dataProvider.getUserReserveData(asset, msg.sender);
      return stableDebt;
    }

    /**
     * Get the health factor of the total debt
     *
     */
    function getHealthFactor() internal view returns (uint256) {
      (
        uint256 totalCollateral,
        uint256 totalDebt,
        uint256 borrowingPower,
        uint256 liquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
      ) = lendingPool.getUserAccountData(msg.sender);
      return healthFactor;
    }
}
