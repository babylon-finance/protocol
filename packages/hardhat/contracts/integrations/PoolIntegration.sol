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
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFund } from "../interfaces/IFund.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IFolioController } from "../interfaces/IFolioController.sol";
import { BaseIntegration } from "./BaseIntegration.sol";

/**
 * @title PoolIntegration
 * @author dFolio Protocol
 *
 * Base class for integration with trading protocols
 */
abstract contract PoolIntegration is BaseIntegration, ReentrancyGuard {
    using SafeMath for uint256;

    /* ============ Struct ============ */

    struct PoolInfo {
      IFund fund;                                     // Fund address
      address pool;                                   // Pool address
      uint256 totalSupply;                            // Total Supply of the pool
      uint256 poolTokensInTransaction;                // Pool tokens affected by this transaction
      uint256 poolTokensInFund;                       // Pool tokens fund balance
      uint256[] limitPoolTokenQuantities;
    }


    /* ============ Events ============ */

    event PoolEntered(
      address _pool,
      uint256 _poolTokensOut
    );

    event PoolExited(
      address _pool,
      uint256 _poolTokensIn,
      uint256 _protocolFee
    );


    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _weth, address _controller) BaseIntegration(_name, _weth, _controller) {
    }

    /* ============ External Functions ============ */

    /**
     * Joins a pool
     *
     * @param _poolAddress          Address of the pool token to join
     * @param _poolTokensOut        Min amount of pool tokens to receive
     * @param _tokensIn             Array of token addresses to deposit
     * @param _maxAmountsIn         Array of max token quantities to pull out from the fund
     */
    function joinPool(
      address _poolAddress,
      uint256 _poolTokensOut,
      address[] calldata _tokensIn,
      uint256[] calldata _maxAmountsIn
    )
      external
      nonReentrant
      onlyFund
    {
      PoolInfo memory poolInfo = _createPoolInfo(
        _poolAddress,
        _poolTokensOut,
        _tokensIn,
        _maxAmountsIn
      );
      _validatePreJoinPoolData(poolInfo);
      // Approve spending of the tokens
      for (uint i = 0; i < _tokensIn.length; i++) {
        poolInfo.fund.invokeApprove(
          _getSpender(_poolAddress),
          _tokensIn[i],
          _maxAmountsIn[i]
        );
      }

      (
          address targetPool,
          uint256 callValue,
          bytes memory methodData
      ) = _getJoinPoolCalldata(
          _poolAddress,
          _poolTokensOut,
          _tokensIn,
          _maxAmountsIn
      );
      poolInfo.fund.invokeFromIntegration(targetPool, callValue, methodData);
      _validatePostJoinPoolData(poolInfo);
      _updateFundPositions(poolInfo, _tokensIn);

      emit PoolEntered(
        poolInfo.pool,
        _poolTokensOut
      );
    }

    /**
     * Exits a liquidity pool. Accrue protocol fee (if any)
     *
     * @param _poolAddress          Address of the pool token to join
     * @param _poolTokensIn           Pool tokens to exchange for the underlying tokens
     * @param _tokensOut             Array of token addresses to withdraw
     * @param _minAmountsOut         Array of min token quantities to receive from the pool
     */
    function exitPool(
      address _poolAddress,
      uint256 _poolTokensIn,
      address[] calldata _tokensOut,
      uint256[] calldata _minAmountsOut
    )
      external
      nonReentrant
      onlyFund
    {
      PoolInfo memory poolInfo = _createPoolInfo(
        _poolAddress,
        _poolTokensIn,
        _tokensOut,
        _minAmountsOut
      );
      _validatePreExitPoolData(poolInfo);
      // Approve spending of the pool token
      poolInfo.fund.invokeApprove(
        _getSpender(_poolAddress),
        _poolAddress,
        _poolTokensIn
      );

      (
          address targetPool,
          uint256 callValue,
          bytes memory methodData
      ) = _getExitPoolCalldata(
          _poolAddress,
          _poolTokensIn,
          _tokensOut,
          _minAmountsOut
      );
      poolInfo.fund.invokeFromIntegration(targetPool, callValue, methodData);
      _validatePostExitPoolData(poolInfo);
      uint256 protocolFee = _accrueProtocolFee(poolInfo, _tokensOut[0], _minAmountsOut[0]);

      _updateFundPositions(poolInfo, _tokensOut);

      emit PoolExited(
        poolInfo.pool,
        _poolTokensIn,
        protocolFee
      );
    }

    /**
     * Checks whether a pool address is valid
     *
     * @param _poolAddress                 Pool address to check
     * @return bool                        True if the address is a pool
     */
     function isPool(address _poolAddress) view external returns (bool) {
       return _isPool(_poolAddress);
     }

    /* ============ Internal Functions ============ */


    /**
     * Retrieve fee from controller and calculate total protocol fee and send from fund to protocol recipient
     *
     * @param _poolInfo                 Struct containing trade information used in internal functions
     * @param _feeToken                 Address of the token to pay the fee with
     * @return uint256                  Amount of receive token taken as protocol fee
     */
    function _accrueProtocolFee(PoolInfo memory _poolInfo, address _feeToken, uint256 _exchangedQuantity) internal returns (uint256) {
      uint256 protocolFeeTotal = getIntegrationFee(0, _exchangedQuantity);

      payProtocolFeeFromFund(address(_poolInfo.fund), _feeToken, protocolFeeTotal);

      return protocolFeeTotal;
    }

    /**
     * Create and return PoolInfo struct
     *
     * @param _pool                          Address of the pool
     * @param _poolTokensInTransaction       Number of pool tokens involved
     * hparam _poolTokens                    Addresseses of the pool tokens
     * @param _limitPoolTokenQuantities      Limit quantity of the pool tokens
     *
     * return PoolInfo             Struct containing data for pool
     */
    function _createPoolInfo(
      address _pool,
      uint256 _poolTokensInTransaction,
      address[] calldata /* _poolTokens */,
      uint256[] calldata _limitPoolTokenQuantities
    )
      internal
      view
      returns (PoolInfo memory)
    {
      PoolInfo memory poolInfo;
      poolInfo.fund = IFund(msg.sender);
      poolInfo.pool = _pool;
      poolInfo.totalSupply = IERC20(_pool).totalSupply();
      poolInfo.poolTokensInFund = IERC20(_pool).balanceOf(address(msg.sender));
      poolInfo.poolTokensInTransaction = _poolTokensInTransaction;
      poolInfo.limitPoolTokenQuantities = _limitPoolTokenQuantities;

      return poolInfo;
    }

    /**
     * Validate pre pool join data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     */
    function _validatePreJoinPoolData(PoolInfo memory _poolInfo) internal view {
      require(_isPool(_poolInfo.pool), "The pool address is not valid");
      require(_poolInfo.poolTokensInTransaction > 0, "Min pool tokens to receive must be greater than 0");
    }

    /**
     * Validate pre pool data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     */
    function _validatePreExitPoolData(PoolInfo memory _poolInfo) internal view {
      require(_isPool(_poolInfo.pool), "The pool address is not valid");
      require(_poolInfo.poolTokensInTransaction > 0, "Pool tokens to exchange must be greater than 0");
      require(_poolInfo.poolTokensInFund >= _poolInfo.poolTokensInTransaction, "The fund does not have enough pool tokens");
    }

    /**
     * Validate post join pool data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     */
    function _validatePostJoinPoolData(PoolInfo memory _poolInfo) internal view {
      require((IERC20(_poolInfo.pool).balanceOf(address(_poolInfo.fund)) > _poolInfo.poolTokensInFund), "The fund did not receive the pool tokens");
    }

    /**
     * Validate post exit pool data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     */
    function _validatePostExitPoolData(PoolInfo memory _poolInfo) internal view {
      require(IERC20(_poolInfo.pool).balanceOf(address(_poolInfo.fund)) == _poolInfo.poolTokensInFund - _poolInfo.poolTokensInTransaction, "The fund did not return the pool tokens");
      // TODO: validate individual tokens received
    }

    /**
     * Update Fund positions
     *
     * @param _poolInfo                Struct containing pool information used in internal functions
     */
    function _updateFundPositions(PoolInfo memory _poolInfo, address[] calldata _poolTokens) internal {
      // balance pool individual component
      for (uint i = 0; i < _poolTokens.length; i++) {
        updateFundPosition(address(_poolInfo.fund), _poolTokens[i], IERC20(_poolTokens[i]).balanceOf(address(_poolInfo.fund)));
      }
      // balance pool token
      updateFundPosition(address(_poolInfo.fund), _poolInfo.pool, IERC20(_poolInfo.pool).balanceOf(address(_poolInfo.fund)));
    }

    /**
     * Return join pool calldata which is already generated from the pool API
     *
     * hparam  _poolAddress              Address of the pool
     * hparam  _poolTokensOut            Amount of pool tokens to send
     * hparam  _tokensIn                 Addresses of tokens to send to the pool
     * hparam  _maxAmountsIn             Amounts of tokens to send to the pool
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getJoinPoolCalldata(
      address /* _poolAddress */,
      uint256 /* _poolTokensOut */,
      address[] calldata /* _tokensIn */,
      uint256[] calldata /* _maxAmountsIn */
    ) internal virtual view returns (address, uint256, bytes memory) {
      require(false, "This needs to be overriden");
      return (address(0),0,bytes(""));
    }

    /**
     * Return exit pool calldata which is already generated from the pool API
     *
     * hparam  _poolAddress              Address of the pool
     * hparam  _poolTokensIn             Amount of pool tokens to receive
     * hparam  _tokensOut                Addresses of tokens to receive
     * hparam  _minAmountsOut            Amounts of pool tokens to receive
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getExitPoolCalldata(
      address /* _poolAddress */,
      uint256 /* _poolTokensIn */,
      address[] calldata /* _tokensOut */,
      uint256[] calldata /* _minAmountsOut */
    ) internal virtual view returns (address, uint256, bytes memory) {
      require(false, "This needs to be overriden");
      return (address(0),0,bytes(""));
    }

    function _isPool(
      address /* _poolAddress */
    ) view virtual internal returns (bool) {
      require(false, "This needs to be overriden");
      return false;
    }

    function _getSpender(
      address /* _poolAddress */
    ) view virtual internal returns (address) {
      require(false, "This must be overriden");
      return address(0);
    }

}
