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
import { BaseIntegration } from "./BaseIntegration.sol";
import { IFund } from "../interfaces/IFund.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BorrowIntetration
 * @author dFolio Protocol
 *
 * Base class for integration with lending protocols
 */
abstract contract BorrowIntegration is BaseIntegration, ReentrancyGuard {
  using SafeMath for uint256;

  /* ============ Struct ============ */

  struct DebtInfo {
    IFund fund;         // Fund address
  }

  uint8 constant BORROW_OPERATION_DEPOSIT = 0;
  uint8 constant BORROW_OPERATION_REMOVAL = 1;
  uint8 constant BORROW_OPERATION_BORROW = 2;
  uint8 constant BORROW_OPERATION_REPAY = 3;


  /* ============ Events ============ */

  event CollateralDeposited(
    IFund fund,
    address asset,
    uint256 amount,
    uint256 protocolFee
  );

  event CollateralRemoved(
    IFund fund,
    address asset,
    uint256 amount,
    uint256 protocolFee
  );

  event AmountBorrowed(
    IFund fund,
    address asset,
    uint256 amount,
    uint256 protocolFee
  );

  event AmountRepaid(
    IFund fund,
    address asset,
    uint256 amount,
    uint256 protocolFee
  );

  /* ============ State Variables ============ */
  uint256 public maxCollateralFactor;


  /* ============ Constructor ============ */

  /**
   * Creates the integration
   *
   * @param _name                   Name of the integration
   * @param _weth                   Address of the WETH ERC20
   * @param _controller             Address of the controller
   * @param _maxCollateralFactor    Max collateral factor allowed
   */
  constructor(string memory _name, address _weth, address _controller, uint256 _maxCollateralFactor) BaseIntegration(_name, _weth, _controller) {
    maxCollateralFactor = _maxCollateralFactor;
  }

  /* ============ External Functions ============ */
  // Governance function
  function updateMaxCollateralFactor(uint256 _newMaxCollateralFactor) external onlyProtocol {
    maxCollateralFactor = _newMaxCollateralFactor;
  }

  /**
   * Deposits collateral into the lending protocol.
   * This would be called by a fund
   * @param asset The asset to be deposited as collateral
   * @param amount The amount to be deposited as collateral
   *
   */
  function depositCollateral(address asset, uint256 amount) nonReentrant onlyFund external {
    address assetToDeposit = _getCollateralAsset(asset, BORROW_OPERATION_DEPOSIT);
    amount = normalizeDecimals(asset, amount);

    DebtInfo memory debtInfo = _createDebtInfo(
    );

    _validatePreDeposit(debtInfo);

    // Approve the collateral
    debtInfo.fund.invokeApprove(
      _getSpender(assetToDeposit),
      assetToDeposit,
      amount
    );

    // Pre actions (enter markets for compound)
    (
      address targetAddressP,
      uint256 callValueP,
      bytes memory methodDataP
    ) = _getPreActionCallData(
      asset,
      amount,
      BORROW_OPERATION_DEPOSIT
    );

    // Invoke protocol specific call
    debtInfo.fund.invokeFromIntegration(targetAddressP, callValueP, methodDataP);

    (
      address targetAddress,
      uint256 callValue,
      bytes memory methodData
    ) = _getDepositCalldata(
      assetToDeposit,
      amount
    );

    // // Need to enter markets
    // Invoke protocol specific call
    debtInfo.fund.invokeFromIntegration(targetAddress, callValue, methodData);
    // Validate deposit
    _validatePostDeposit(debtInfo);
    // Protocol Fee
    uint256 protocolFee = _accrueProtocolFee(debtInfo, assetToDeposit, amount, BORROW_OPERATION_DEPOSIT);
    // updateFundPosition(msg.sender, asset, amount); TODO: Do we need to update? maybe say it's locked somewhere

    emit CollateralDeposited(
      debtInfo.fund,
      asset,
      amount,
      protocolFee
    );
  }

  /**
   * Deposits collateral into the lending protocol.
   * This would be called by a fund
   * @param asset The asset to be deposited as collateral
   * @param amount The amount to be deposited as collateral
   *
   */
  function removeCollateral(address asset, uint256 amount) nonReentrant onlyFund external {
    address assetToDeposit = _getCollateralAsset(asset, BORROW_OPERATION_REMOVAL);
    amount = normalizeDecimals(asset, amount);

    DebtInfo memory debtInfo = _createDebtInfo(
    );

    _validatePreRemoval(debtInfo);

    // Pre actions (enter markets for compound)
    (
      address targetAddressP,
      uint256 callValueP,
      bytes memory methodDataP
    ) = _getPreActionCallData(
      asset,
      amount,
      BORROW_OPERATION_REMOVAL
    );

    // Invoke protocol prespecific call
    debtInfo.fund.invokeFromIntegration(targetAddressP, callValueP, methodDataP);

    (
      address targetAddress,
      uint256 callValue,
      bytes memory methodData
    ) = _getRemovalCalldata(
      assetToDeposit,
      amount
    );

    // Invoke protocol specific call
    debtInfo.fund.invokeFromIntegration(targetAddress, callValue, methodData);
    // Validate deposit
    _validatePostRemoval(debtInfo);
    // Protocol Fee
    uint256 protocolFee = _accrueProtocolFee(debtInfo, assetToDeposit, amount, BORROW_OPERATION_REMOVAL);
    // updateFundPosition(msg.sender, asset, amount); // TODO: Unlock position

    emit CollateralRemoved(
      debtInfo.fund,
      asset,
      amount,
      protocolFee
    );
  }

  /**
   * Borrows an asset
   * @param asset The asset to be borrowed
   * @param amount The amount to borrow
   */
  function borrow(address asset, uint256 amount) nonReentrant onlyFund external {
    amount = normalizeDecimals(asset, amount);

    DebtInfo memory debtInfo = _createDebtInfo();

    _validatePreBorrow(debtInfo);

    // Pre actions (enter markets for compound)
    (
      address targetAddressP,
      uint256 callValueP,
      bytes memory methodDataP
    ) = _getPreActionCallData(
      asset,
      amount,
      BORROW_OPERATION_BORROW
    );

    // Invoke protocol prespecific call
    debtInfo.fund.invokeFromIntegration(targetAddressP, callValueP, methodDataP);


    (
      address targetAddress,
      uint256 callValue,
      bytes memory methodData
    ) = _getBorrowCalldata(
      asset,
      amount
    );

    // Invoke protocol specific call
    debtInfo.fund.invokeFromIntegration(targetAddress, callValue, methodData);
    // Validate borrow
    _validatePostBorrow(debtInfo);
    // Protocol Fee
    uint256 protocolFee = _accrueProtocolFee(debtInfo, asset, amount, BORROW_OPERATION_BORROW);
    updateFundPosition(msg.sender, asset, 0 - amount);

    emit AmountBorrowed(
      debtInfo.fund,
      asset,
      amount,
      protocolFee
    );
  }

  /**
   * Repays a borrowed asset debt
   * @param asset The asset to be repaid
   * @param amount The amount to repay
   */
  function repay(address asset, uint256 amount) nonReentrant onlyFund external {
    amount = normalizeDecimals(asset, amount);

    DebtInfo memory debtInfo = _createDebtInfo();

    _validatePreRepay(debtInfo);

    // Pre actions (enter markets for compound)
    (
      address targetAddressP,
      uint256 callValueP,
      bytes memory methodDataP
    ) = _getPreActionCallData(
      asset,
      amount,
      BORROW_OPERATION_REPAY
    );

    // Invoke protocol prespecific call
    debtInfo.fund.invokeFromIntegration(targetAddressP, callValueP, methodDataP);

    (
      address targetAddress,
      uint256 callValue,
      bytes memory methodData
    ) = _getRepayCalldata(
      asset,
      amount
    );

    // Invoke protocol specific call
    debtInfo.fund.invokeFromIntegration(targetAddress, callValue, methodData);
    // Validate borrow
    _validatePostRepay(debtInfo);
    // Protocol Fee
    uint256 protocolFee = _accrueProtocolFee(debtInfo, asset, amount, BORROW_OPERATION_REPAY);
    updateFundPosition(msg.sender, asset, amount); //TODO: is this absolute or delta

    emit AmountRepaid(
      debtInfo.fund,
      asset,
      amount,
      protocolFee
    );
  }

  /* ============ Internal Functions ============ */

  /**
   * Retrieve fee from controller and calculate total protocol fee and send from fund to protocol recipient
   *
   * @param _debtInfo                 Struct containing trade information used in internal functions
   * @param _feeToken                 Address of the token to pay the fee with
   * @param _exchangedQuantity        Amount of exchanged amounts
   * @param _borrowOp                 Type of borrow operation
   * @return uint256                  Amount of receive token taken as protocol fee
   */
  function _accrueProtocolFee(DebtInfo memory _debtInfo, address _feeToken, uint256 _exchangedQuantity, uint8 _borrowOp) internal returns (uint256) {
    uint256 protocolFeeTotal = getIntegrationFee(0, _exchangedQuantity);
    payProtocolFeeFromFund(address(_debtInfo.fund), _feeToken, protocolFeeTotal);
    return protocolFeeTotal;
  }

  function _getCollateralAsset(address _asset, uint8 _borrowOp) internal virtual view returns (address) {
    require(false, "This method must be overriden");
  }

  function _getSpender(address asset) internal virtual view returns (address) {
    require(false, "This method must be overriden");
  }

  /**
   * Create and return DebtInfo struct
   *
   *
   * return DebtInfo             Struct containing data for the debt position
   */
  function _createDebtInfo(

  )
    internal
    view
    returns (DebtInfo memory)
  {
    DebtInfo memory debtInfo;
    debtInfo.fund = IFund(msg.sender);

    return debtInfo;
  }

  /**
   * Validate pre deposit collateral.
   *
   * @param _debtInfo               Struct containing debt information used in internal functions
   */
  function _validatePreDeposit(DebtInfo memory _debtInfo) internal view {
  }

  /**
   * Validate post deposit collateral.
   *
   * @param _debtInfo               Struct containing debt information used in internal functions
   */
  function _validatePostDeposit(DebtInfo memory _debtInfo) internal view {
  }

  /**
   * Validate pre borrow.
   *
   * @param _debtInfo               Struct containing debt information used in internal functions
   */
  function _validatePreBorrow(DebtInfo memory _debtInfo) internal view {
  }

  /**
   * Validate post borrow.
   *
   * @param _debtInfo               Struct containing debt information used in internal functions
   */
  function _validatePostBorrow(DebtInfo memory _debtInfo) internal view {
  }

  /**
   * Validate pre withdrawal of collateral.
   *
   * @param _debtInfo               Struct containing debt information used in internal functions
   */
  function _validatePreRemoval(DebtInfo memory _debtInfo) internal view {
  }

  /**
   * Validate pre deposit collateral.
   *
   * @param _debtInfo               Struct containing debt information used in internal functions
   */
  function _validatePostRemoval(DebtInfo memory _debtInfo) internal view {
  }

  /**
   * Validate pre repaid.
   *
   * @param _debtInfo               Struct containing debt information used in internal functions
   */
  function _validatePreRepay(DebtInfo memory _debtInfo) internal view {
  }

  /**
   * Validate post repaid.
   *
   * @param _debtInfo               Struct containing debt information used in internal functions
   */
  function _validatePostRepay(DebtInfo memory _debtInfo) internal view {
  }

  /* ============ Virtual Functions ============ */

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
  ) internal virtual view returns (address, uint256, bytes memory) {
    require(false, "This needs to be overriden");
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
  ) internal virtual view returns (address, uint256, bytes memory) {
    require(false, "This needs to be overriden");
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
  ) internal virtual view returns (address, uint256, bytes memory) {
    require(false, "This needs to be overriden");
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
  ) internal virtual view returns (address, uint256, bytes memory) {
    require(false, "This needs to be overriden");
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
  ) internal virtual view returns (address, uint256, bytes memory) {
    require(false, "This needs to be overriden");
  }

}
