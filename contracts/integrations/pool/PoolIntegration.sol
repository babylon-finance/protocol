/*
    Copyright 2021 Babylon Finance

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

pragma solidity 0.7.6;

import 'hardhat/console.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {AddressArrayUtils} from '../../lib/AddressArrayUtils.sol';

import {IPoolIntegration} from '../../interfaces/IPoolIntegration.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';

import {BaseIntegration} from '../BaseIntegration.sol';

/**
 * @title PoolIntegration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with pool protocols
 */
abstract contract PoolIntegration is BaseIntegration, ReentrancyGuard, IPoolIntegration {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;
    using BytesLib for bytes;

    /* ============ Struct ============ */

    struct PoolInfo {
        IGarden garden; // Garden address
        IStrategy strategy; // Strategy address
        bytes pool; // OpData 64 bytes each OpData
        address lpToken; // LP address
        uint256 totalSupply; // Total Supply of the pool
        uint256 poolTokensInTransaction; // Pool tokens affected by this transaction
        uint256 poolTokensInStrategy; // Pool tokens strategy balance
        uint256[] limitPoolTokenQuantities;
    }

    /* ============ Events ============ */

    event PoolEntered(address indexed _strategy, address indexed _garden, address _pool, uint256 _poolTokensOut);

    event PoolExited(address indexed _strategy, address indexed _garden, address _pool, uint256 _poolTokensIn);

    /* ============ Constants ============ */

    uint256 internal constant SLIPPAGE_ALLOWED = 5e16; // 5%

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, IBabController _controller) BaseIntegration(_name, _controller) {}

    /* ============ External Functions ============ */

    /**
     * Joins a pool
     *
     * @param _strategy             Address of the strategy
     * @param _pool                 OpData e.g. Address of the pool token to join
     * @param _poolTokensOut        Min amount of pool tokens to receive
     * @param _tokensIn             Array of token addresses to deposit
     * @param _maxAmountsIn         Array of max token quantities to pull out from the garden
     */
    function joinPool(
        address _strategy,
        bytes calldata _pool,
        uint256 _poolTokensOut,
        address[] calldata _tokensIn,
        uint256[] calldata _maxAmountsIn
    ) external override nonReentrant onlySystemContract {
        PoolInfo memory poolInfo = _createPoolInfo(_strategy, _pool, _poolTokensOut, _tokensIn, _maxAmountsIn);
        _validatePreJoinPoolData(poolInfo);
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        // Approve spending of the tokens
        for (uint256 i = 0; i < _tokensIn.length; i++) {
            // No need to approve ETH
            if (_tokensIn[i] != address(0)) {
                poolInfo.strategy.invokeApprove(_getSpender(_pool), _tokensIn[i], _maxAmountsIn[i]);
            }
        }
        (address targetPool, uint256 callValue, bytes memory methodData) =
            _getJoinPoolCalldata(_strategy, _pool, _poolTokensOut, _tokensIn, _maxAmountsIn);
        poolInfo.strategy.invokeFromIntegration(targetPool, callValue, methodData);
        poolInfo.poolTokensInTransaction = IERC20(poolInfo.lpToken).balanceOf(address(poolInfo.strategy)).sub(
            poolInfo.poolTokensInStrategy
        );
        _validatePostJoinPoolData(poolInfo);
        emit PoolEntered(address(poolInfo.strategy), address(poolInfo.garden), poolAddress, _poolTokensOut);
    }

    /**
     * Exits a liquidity pool. Accrue protocol fee (if any)
     *
     * @param _strategy               Address of the strategy
     * @param _pool                   Pool info e.g. PoolId or Address of the pool token to join + metadata
     * @param _poolTokensIn           Pool tokens to exchange for the underlying tokens
     * @param _tokensOut              Array of token addresses to withdraw
     * @param _minAmountsOut          Array of min token quantities to receive from the pool
     */
    function exitPool(
        address _strategy,
        bytes calldata _pool,
        uint256 _poolTokensIn,
        address[] calldata _tokensOut,
        uint256[] calldata _minAmountsOut
    ) external override nonReentrant onlySystemContract {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        PoolInfo memory poolInfo = _createPoolInfo(_strategy, _pool, _poolTokensIn, _tokensOut, _minAmountsOut);
        _validatePreExitPoolData(poolInfo);
        // Approve spending of the pool token
        poolInfo.strategy.invokeApprove(_getSpender(_pool), poolInfo.lpToken, _poolTokensIn);

        (address targetPool, uint256 callValue, bytes memory methodData) =
            _getExitPoolCalldata(_strategy, _pool, _poolTokensIn, _tokensOut, _minAmountsOut);
        poolInfo.strategy.invokeFromIntegration(targetPool, callValue, methodData);
        _validatePostExitPoolData(poolInfo);

        emit PoolExited(address(poolInfo.strategy), address(poolInfo.garden), poolAddress, _poolTokensIn);
    }

    /**
     * Checks whether a pool address is valid
     *
     * @param _pool                 OpData e.g. Pool address to check
     * @return bool                 True if the address is a pool
     */
    function isPool(bytes memory _pool) external view override returns (bool) {
        return _isPool(_pool);
    }

    /**
     * Returns the actual address of the LP token. Different for curve.
     * @param _pool                    Address of the pool
     * @return address                 Address of the LP token
     */
    function getLPToken(address _pool) external view override returns (address) {
        return _getLpToken(_pool);
    }

    /**
     * Gets the underlying pool that holds the internal tokens. Different for curve.
     * @param _pool                    Address of the maybe pool
     * @return address                 Address of the pool itself
     */
    function getPool(address _pool) external view override returns (address) {
        return _getPool(_pool);
    }

    /**
     * Returns the total supply of the pool tokens
     * @param _pool                    Address of the pool
     * @return address                 Total supply of the token
     */
    function totalSupply(address _pool) external view returns (uint256) {
        return _totalSupply(_pool);
    }

    function getPoolTokens(
        bytes calldata /* _pool */,
        bool /* forNAV */
    ) external view virtual override returns (address[] memory);

    function getPoolWeights(
        bytes calldata /*_pool */
    ) external view virtual override returns (uint256[] memory);

    /* ============ Internal Functions ============ */

    /**
     * Create and return PoolInfo struct
     *
     * @param _strategy                      Address of the strategy
     * @param _pool                          Pool info e.g. Address of the pool + metadata
     * @param _poolTokensInTransaction       Number of pool tokens involved
     * hparam _poolTokens                    Addresseses of the pool tokens
     * @param _limitPoolTokenQuantities      Limit quantity of the pool tokens
     *
     * return PoolInfo             Struct containing data for pool
     */
    function _createPoolInfo(
        address _strategy,
        bytes calldata _pool,
        uint256 _poolTokensInTransaction,
        address[] calldata, /* _poolTokens */
        uint256[] calldata _limitPoolTokenQuantities
    ) internal view returns (PoolInfo memory) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        PoolInfo memory poolInfo;
        poolInfo.lpToken = _getLpToken(poolAddress);
        poolInfo.strategy = IStrategy(_strategy);
        poolInfo.garden = IGarden(poolInfo.strategy.garden());
        poolInfo.pool = _pool;
        poolInfo.poolTokensInStrategy = IERC20(poolInfo.lpToken).balanceOf(_strategy);
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
        require(_isPool(_poolInfo.pool), 'The pool address is not valid');
        require(_poolInfo.poolTokensInTransaction > 0, 'Min pool tokens to receive must be greater than 0');
    }

    /**
     * Validate pre pool data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     */
    function _validatePreExitPoolData(PoolInfo memory _poolInfo) internal view {
        require(_isPool(_poolInfo.pool), 'The pool address is not valid');
        require(_poolInfo.poolTokensInTransaction > 0, 'Pool tokens to exchange must be greater than 0');
        require(
            _poolInfo.poolTokensInStrategy >= _poolInfo.poolTokensInTransaction,
            'The strategy does not have enough pool tokens'
        );
    }

    /**
     * Validate post join pool data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     */
    function _validatePostJoinPoolData(PoolInfo memory _poolInfo) internal view {
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_poolInfo.pool, 12);
        require(
            (IERC20(_poolInfo.lpToken).balanceOf(address(_poolInfo.strategy)) > _poolInfo.poolTokensInStrategy),
            'The strategy did not receive the pool tokens'
        );
    }

    /**
     * Validate post exit pool data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     */
    function _validatePostExitPoolData(PoolInfo memory _poolInfo) internal view {
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_poolInfo.pool, 12);
        require(
            IERC20(_poolInfo.lpToken).balanceOf(address(_poolInfo.strategy)) ==
                _poolInfo.poolTokensInStrategy - _poolInfo.poolTokensInTransaction,
            'The strategy did not return the pool tokens'
        );
        // TODO: validate individual tokens received
    }

    /**
     * Return join pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * hparam  _pool                     OpData e.g. Address of the pool
     * hparam  _poolTokensOut            Amount of pool tokens to send
     * hparam  _tokensIn                 Addresses of tokens to send to the pool
     * hparam  _maxAmountsIn             Amounts of tokens to send to the pool
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getJoinPoolCalldata(
        address, /* _strategy */
        bytes calldata, /* _pool */
        uint256, /* _poolTokensOut */
        address[] calldata, /* _tokensIn */
        uint256[] calldata /* _maxAmountsIn */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        );

    /**
     * Return exit pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * hparam  _pool                     OpData e.g. Address of the pool
     * hparam  _poolTokensIn             Amount of pool tokens to receive
     * hparam  _tokensOut                Addresses of tokens to receive
     * hparam  _minAmountsOut            Amounts of pool tokens to receive
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getExitPoolCalldata(
        address, /* _strategy */
        bytes memory, /* _pool */
        uint256, /* _poolTokensIn */
        address[] calldata, /* _tokensOut */
        uint256[] calldata /* _minAmountsOut */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        );

    function _isPool(bytes memory _pool) internal view virtual returns (bool);

    function _totalSupply(address _pool) internal view virtual returns (uint256) {
        return IERC20(_pool).totalSupply();
    }

    function _getSpender(
        bytes calldata /* _pool */
    ) internal view virtual returns (address);

    function _getLpToken(address _pool) internal view virtual returns (address) {
        return _pool;
    }

    function _getPool(address _pool) internal view virtual returns (address) {
        return _pool;
    }
}
