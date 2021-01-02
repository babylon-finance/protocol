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
      IERC20[] poolTokens;                            // Token addresses of the pool
      uint256[] poolTokenQuantities;                  // Quantities of pool tokens
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
     * @param _poolTokensOut     Min amount of pool tokens to receive
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
      )
      _validatePreJoinPoolData(poolInfo, _poolTokensOut);
      // Approve spendning of the tokens
      for (uint i = 0; i < _tokensIn.length; i++) {
        _poolInfo.fund.invokeApprove(
          _poolAddress,
          _tokensIn[i],
          _maxAmountsIn[i]
        );
      }

      (
          address targetPool,
          uint256 callValue,
          bytes memory methodData
      ) = _getJoinPoolCalldata(
          _tradeInfo.sendToken,
          _tradeInfo.receiveToken,
          address(_tradeInfo.fund),
          _tradeInfo.totalSendQuantity,
          _tradeInfo.totalMinReceiveQuantity,
          _data
      );
      _poolInfo.fund.invokeFromIntegration(targetPool, callValue, methodData);
      _validatePostJoinPool(poolInfo);

      _updateFundPositions(poolInfo);

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
      )
      _validatePreExitPoolData(poolInfo, _poolTokensIn);

      (
          address targetPool,
          uint256 callValue,
          bytes memory methodData
      ) = _getExitPoolCalldata(
          _tradeInfo.sendToken,
          _tradeInfo.receiveToken,
          address(_tradeInfo.fund),
          _tradeInfo.totalSendQuantity,
          _tradeInfo.totalMinReceiveQuantity,
          _data
      );
      _poolInfo.fund.invokeFromIntegration(targetPool, callValue, methodData);
      _validatePostExitPool(poolInfo);
      uint256 protocolFee = _accrueProtocolFee(poolInfo, _minAmountsOut[0]);

      _updateFundPositions(poolInfo);

      emit PoolExited(
        poolInfo.pool,
        _poolTokensIn
      );
    }

    /* ============ Internal Functions ============ */

    /**
     * Retrieve fee from controller and calculate total protocol fee and send from fund to protocol recipient
     *
     * @param _poolInfo                 Struct containing trade information used in internal functions
     * @return uint256                  Amount of receive token taken as protocol fee
     */
    function _accrueProtocolFee(PoolInfo memory _poolInfo, uint256 _exchangedQuantity) internal returns (uint256) {
      uint256 protocolFeeTotal = getIntegrationFee(0, _exchangedQuantity);

      payProtocolFeeFromFund(address(_poolInfo.fund), _poolInfo.poolTokens[0], protocolFeeTotal);

      return protocolFeeTotal;
    }

    /**
     * Create and return PoolInfo struct
     *
     * @param _pool                          Human readable name of the exchange in the integrations registry
     * @param _poolTokensInTransaction       Address of the token to be sent to the exchange
     * @param _poolTokens                    Address of the token to be sent to the exchange
     * @param _limitPoolTokenQuantities      Address of the token to be sent to the exchange
     *
     * return PoolInfo             Struct containing data for pool
     */
    function _createPoolInfo(
      address _pool,
      uint256 _poolTokensInTransaction,
      address[] _poolTokens,
      address[] _limitPoolTokenQuantities
    )
      internal
      view
      returns (TradeInfo memory)
    {
      PoolInfo memory poolInfo;
      poolInfo.fund = IFund(msg.sender);
      poolInfo.pool = _pool;
      poolInfo.poolTokens = _poolTokens;
      poolInfo.totalSupply = IERC20(pool).totalSupply();
      poolInfo.poolTokensInFund = IERC20(pool).balanceOf(address(msg.sender));
      poolInfo.poolTokensInTransaction = _poolTokensInTransaction
      for (uint i = 0; i < _poolTokens.length; i++) {
        poolInfo.poolTokens[i] = IERC20(_poolTokens[i]);
        poolInfo.poolTokenQuantities[i] = IERC20(_poolTokens[i]).balanceOf(_pool);
      }
      poolInfo.limitPoolTokenQuantities = _limitPoolTokenQuantities;

      return poolInfo;
    }

    /**
     * Validate pre pool join data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     * @param _minPoolTokensOut       Min amount of pool tokens to get
     */
    function _validatePreJoinPoolData(PoolInfo memory _poolInfo, uint256 _minPoolTokensOut) internal view {
      require(_poolInfo.poolTokens > 0, "Min pool tokens to receive must be greater than 0");
    }

    /**
     * Validate pre pool data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     * @param _poolTokensIn           Amount of tokens to exchange
     */
    function _validatePreExitPoolData(PoolInfo memory _poolInfo) internal view {
      require(_poolInfo.poolTokens > 0, "Pool tokens to exchange must be greater than 0");
      require(_poolInfo.poolTokensInFund > _poolInfo.poolTokens, "The fund does not have enough pool tokens");
    }

    /**
     * Validate post join pool data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     */
    function _validatePostJoinPoolData(PoolInfo memory _poolInfo) internal view {

    }

    /**
     * Validate post exit pool data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     */
    function _validatePostExitPoolData(PoolInfo memory _poolInfo) internal view {

    }

    /**
     * Update Fund positions
     *
     * @param _poolInfo                Struct containing pool information used in internal functions
     */
    function _updateFundPositions(PoolInfo memory _poolInfo) internal {
      // balance pool individual component
      for (uint i = 0; i < _poolInfo.poolTokens.length; i++) {
        uint256 newAmountReceiveTokens = _tradeInfo.preTradeReceiveTokenBalance.add(exchangedQuantity);
        updateFundPosition(address(_poolInfo.fund), address(_poolInfo.poolTokens[i]), _poolInfo.poolTokens[i].balanceOf(_poolInfo.fund));
      }
      // balance pool token
      updateFundPosition(address(_poolInfo.fund), _poolInfo.pool, IERC20(_poolInfo.pool).balanaceOf(_poolInfo.fund));
    }

    /**
     * Return join pool calldata which is already generated from the pool API
     *
     * @param  _sourceToken              Address of source token to be sold
     * @param  _destinationToken         Address of destination token to buy
     * @param  _sourceQuantity           Amount of source token to sell
     * @param  _minDestinationQuantity   Min amount of destination token to buy
     * @param  _data                    Arbitrage bytes containing trade call data
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getJoinPoolCalldata(
      address _sourceToken,
      address _destinationToken,
      address _destinationAddress,
      uint256 _sourceQuantity,
      uint256 _minDestinationQuantity,
      bytes memory _data
    ) internal virtual view returns (address, uint256, bytes memory) {
      require(false, "This needs to be overriden");
    }

    /**
     * Return exit pool calldata which is already generated from the pool API
     *
     * @param  _sourceToken              Address of source token to be sold
     * @param  _destinationToken         Address of destination token to buy
     * @param  _sourceQuantity           Amount of source token to sell
     * @param  _minDestinationQuantity   Min amount of destination token to buy
     * @param  _data                    Arbitrage bytes containing trade call data
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getExitPoolCalldata(
      address _sourceToken,
      address _destinationToken,
      address _destinationAddress,
      uint256 _sourceQuantity,
      uint256 _minDestinationQuantity,
      bytes memory _data
    ) internal virtual view returns (address, uint256, bytes memory) {
      require(false, "This needs to be overriden");
    }
}
