/*
    Copyright 2020 Babylon Finance

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

import 'hardhat/console.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {BaseIntegration} from './BaseIntegration.sol';

/**
 * @title PoolIntegration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with trading protocols
 */
abstract contract PoolIntegration is BaseIntegration, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeCast for uint256;

    /* ============ Struct ============ */

    struct PoolInfo {
        IGarden garden; // Garden address
        IStrategy strategy; // Idea address
        address pool; // Pool address
        uint256 totalSupply; // Total Supply of the pool
        uint256 poolTokensInTransaction; // Pool tokens affected by this transaction
        uint256 poolTokensInIdea; // Pool tokens strategy balance
        uint256[] limitPoolTokenQuantities;
    }

    /* ============ Events ============ */

    event PoolEntered(address indexed _strategy, address indexed _garden, address _pool, uint256 _poolTokensOut);

    event PoolExited(
        address indexed _strategy,
        address indexed _garden,
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
    constructor(
        string memory _name,
        address _weth,
        address _controller
    ) BaseIntegration(_name, _weth, _controller) {}

    /* ============ External Functions ============ */

    /**
     * Joins a pool
     *
     * @param _poolAddress          Address of the pool token to join
     * @param _poolTokensOut        Min amount of pool tokens to receive
     * @param _tokensIn             Array of token addresses to deposit
     * @param _maxAmountsIn         Array of max token quantities to pull out from the garden
     */
    function joinPool(
        address _poolAddress,
        uint256 _poolTokensOut,
        address[] calldata _tokensIn,
        uint256[] calldata _maxAmountsIn
    ) external nonReentrant onlyIdea {
        PoolInfo memory poolInfo = _createPoolInfo(_poolAddress, _poolTokensOut, _tokensIn, _maxAmountsIn);
        _validatePreJoinPoolData(poolInfo);
        // Approve spending of the tokens
        for (uint256 i = 0; i < _tokensIn.length; i++) {
            poolInfo.strategy.invokeApprove(_getSpender(_poolAddress), _tokensIn[i], _maxAmountsIn[i]);
        }

        (address targetPool, uint256 callValue, bytes memory methodData) =
            _getJoinPoolCalldata(_poolAddress, _poolTokensOut, _tokensIn, _maxAmountsIn);
        poolInfo.strategy.invokeFromIntegration(targetPool, callValue, methodData);
        _validatePostJoinPoolData(poolInfo);
        _updateGardenPositions(poolInfo, _tokensIn, true);

        emit PoolEntered(address(poolInfo.strategy), address(poolInfo.garden), poolInfo.pool, _poolTokensOut);
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
    ) external nonReentrant onlyIdea {
        PoolInfo memory poolInfo = _createPoolInfo(_poolAddress, _poolTokensIn, _tokensOut, _minAmountsOut);
        _validatePreExitPoolData(poolInfo);
        // Approve spending of the pool token
        poolInfo.strategy.invokeApprove(_getSpender(_poolAddress), _poolAddress, _poolTokensIn);

        (address targetPool, uint256 callValue, bytes memory methodData) =
            _getExitPoolCalldata(_poolAddress, _poolTokensIn, _tokensOut, _minAmountsOut);
        poolInfo.strategy.invokeFromIntegration(targetPool, callValue, methodData);
        _validatePostExitPoolData(poolInfo);
        uint256 protocolFee = _accrueProtocolFee(address(poolInfo.strategy), _tokensOut[0], _minAmountsOut[0]);

        _updateGardenPositions(poolInfo, _tokensOut, false);

        emit PoolExited(
            address(poolInfo.strategy),
            address(poolInfo.garden),
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
    function isPool(address _poolAddress) external view returns (bool) {
        return _isPool(_poolAddress);
    }

    /* ============ Internal Functions ============ */

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
        address[] calldata, /* _poolTokens */
        uint256[] calldata _limitPoolTokenQuantities
    ) internal view returns (PoolInfo memory) {
        PoolInfo memory poolInfo;
        poolInfo.strategy = IStrategy(msg.sender);
        poolInfo.garden = IGarden(poolInfo.strategy.garden());
        poolInfo.pool = _pool;
        poolInfo.totalSupply = IERC20(_pool).totalSupply();
        poolInfo.poolTokensInIdea = IERC20(_pool).balanceOf(address(msg.sender));
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
            _poolInfo.poolTokensInIdea >= _poolInfo.poolTokensInTransaction,
            'The strategy does not have enough pool tokens'
        );
    }

    /**
     * Validate post join pool data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     */
    function _validatePostJoinPoolData(PoolInfo memory _poolInfo) internal view {
        require(
            (IERC20(_poolInfo.pool).balanceOf(address(_poolInfo.strategy)) > _poolInfo.poolTokensInIdea),
            'The strategy did not receive the pool tokens'
        );
    }

    /**
     * Validate post exit pool data. Check pool is valid, token quantity is valid.
     *
     * @param _poolInfo               Struct containing pool information used in internal functions
     */
    function _validatePostExitPoolData(PoolInfo memory _poolInfo) internal view {
        require(
            IERC20(_poolInfo.pool).balanceOf(address(_poolInfo.strategy)) ==
                _poolInfo.poolTokensInIdea - _poolInfo.poolTokensInTransaction,
            'The strategy did not return the pool tokens'
        );
        // TODO: validate individual tokens received
    }

    /**
     * Update Garden positions
     *
     * @param _poolInfo                Struct containing pool information used in internal functions
     */
    function _updateGardenPositions(
        PoolInfo memory _poolInfo,
        address[] calldata _poolTokens,
        bool isDeposit
    ) internal {
        // balance pool individual component
        // TODO: Grab actual min tokens on added and withdrawed on exit
        for (uint256 i = 0; i < _poolTokens.length; i++) {
            _updateStrategyPosition(
                address(_poolInfo.strategy),
                _poolTokens[i],
                isDeposit
                    ? int256(-_poolInfo.limitPoolTokenQuantities[i])
                    : _poolInfo.limitPoolTokenQuantities[i].toInt256(),
                isDeposit ? 2 : 0
            );
        }
        // balance pool token
        _updateStrategyPosition(
            address(_poolInfo.strategy),
            _poolInfo.pool,
            isDeposit ? _poolInfo.poolTokensInTransaction.toInt256() : int256(-_poolInfo.poolTokensInTransaction),
            0
        );
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
        address, /* _poolAddress */
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
        )
    {
        require(false, 'This needs to be overriden');
        return (address(0), 0, bytes(''));
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
        address, /* _poolAddress */
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
        )
    {
        require(false, 'This needs to be overriden');
        return (address(0), 0, bytes(''));
    }

    function _isPool(
        address /* _poolAddress */
    ) internal view virtual returns (bool) {
        require(false, 'This needs to be overriden');
        return false;
    }

    function _getSpender(
        address /* _poolAddress */
    ) internal view virtual returns (address) {
        require(false, 'This must be overriden');
        return address(0);
    }
}
