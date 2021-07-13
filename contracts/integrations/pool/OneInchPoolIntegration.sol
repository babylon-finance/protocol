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
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {PoolIntegration} from './PoolIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {IMooniswapFactory} from '../../interfaces/external/1inch/IMooniswapFactory.sol';
import {IMooniswap} from '../../interfaces/external/1inch/IMooniswap.sol';

/**
 * @title BalancerIntegration
 * @author Babylon Finance Protocol
 *
 * OneInchPoolIntegration protocol trade integration
 */
contract OneInchPoolIntegration is PoolIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using BytesLib for uint256;

    /* ============ State Variables ============ */

    // Address of Uniswap V2 Router
    IMooniswapFactory public mooniswapFactory;

    /* ============ Constants ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _mooniswapFactoryAddress         Address of the Mooniswap factory
     */
    constructor(IBabController _controller, address _mooniswapFactoryAddress)
        PoolIntegration('oneinch_pool', _controller)
    {
        mooniswapFactory = IMooniswapFactory(_mooniswapFactoryAddress);
    }

    /* ============ External Functions ============ */

    function getPoolTokens(bytes calldata _pool, bool forNAV) external view override returns (address[] memory) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        return IMooniswap(poolAddress).getTokens();
    }

    function getPoolWeights(
        bytes calldata /* _pool */
    ) external pure override returns (uint256[] memory) {
        uint256[] memory result = new uint256[](2);
        result[0] = 5e17; // 50%
        result[1] = 5e17; // 50%
        return result;
    }

    function getPoolTokensOut(
        bytes calldata, /* _pool */
        address, /* _poolToken */
        uint256 /* _maxAmountsIn */
    ) external pure override returns (uint256) {
        // return 1 since _poolTokensOut are not used
        return 1;
    }

    function getPoolMinAmountsOut(bytes calldata _pool, uint256 _liquidity)
        external
        view
        override
        returns (uint256[] memory _minAmountsOut)
    {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        address[] memory tokens = IMooniswap(poolAddress).getTokens();
        uint256 totalSupply = IMooniswap(poolAddress).totalSupply();
        uint256[] memory result = new uint256[](2);
        uint256 token0Balance =
            (tokens[0] != address(0) ? IERC20(tokens[0]).balanceOf(poolAddress) : poolAddress.balance);
        uint256 token1Balance =
            (tokens[1] != address(0) ? IERC20(tokens[1]).balanceOf(poolAddress) : poolAddress.balance);
        result[0] = token0Balance.mul(_liquidity).div(totalSupply).preciseMul(1e18 - SLIPPAGE_ALLOWED);
        result[1] = token1Balance.mul(_liquidity).div(totalSupply).preciseMul(1e18 - SLIPPAGE_ALLOWED);
        return result;
    }

    /* ============ Internal Functions ============ */

    function _isPool(bytes memory _pool) internal view override returns (bool) {
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 12);
        return IMooniswapFactory(mooniswapFactory).isPool(IMooniswap(poolAddress));
    }

    function _getSpender(bytes calldata _pool) internal view override returns (address) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        return poolAddress;
    }

    /**
     * Return join pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * hparam  _pool                     OpData e.g. Address of the pool
     * hparam  _poolTokensOut            Amount of pool tokens to send
     * @param  _tokensIn                 Addresses of tokens to send to the pool
     * @param  _maxAmountsIn             Amounts of tokens to send to the pool
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getJoinPoolCalldata(
        address, /* _strategy */
        bytes calldata _pool,
        uint256, /* _poolTokensOut */
        address[] calldata _tokensIn,
        uint256[] calldata _maxAmountsIn
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        // Encode method data for Garden to invoke
        require(_tokensIn.length == 2, 'Two tokens required');
        require(_maxAmountsIn.length == 2, 'Two amounts required');
        bytes memory methodData =
            abi.encodeWithSignature(
                'deposit(uint256[2],uint256[2])',
                _maxAmountsIn[0],
                _maxAmountsIn[1],
                _maxAmountsIn[0].sub(_maxAmountsIn[0].preciseMul(SLIPPAGE_ALLOWED * 2)),
                _maxAmountsIn[1].sub(_maxAmountsIn[1].preciseMul(SLIPPAGE_ALLOWED * 2))
            );
        uint256 value = 0;
        // Add ETH if one of the tokens
        if (_tokensIn[0] == address(0)) {
            value = _maxAmountsIn[0];
        }
        if (_tokensIn[1] == address(0)) {
            value = _maxAmountsIn[1];
        }

        return (poolAddress, value, methodData);
    }

    /**
     * Return exit pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * @param  _pool                     OpData e.g. Address of the pool
     * @param  _poolTokensIn             Amount of pool tokens to receive
     * @param  _tokensOut                Addresses of tokens to receive
     * @param  _minAmountsOut            Amounts of pool tokens to receive
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getExitPoolCalldata(
        address, /* _strategy */
        bytes memory _pool,
        uint256 _poolTokensIn,
        address[] calldata _tokensOut,
        uint256[] calldata _minAmountsOut
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 12);
        require(_tokensOut.length == 2, 'Two tokens required');
        require(_minAmountsOut.length == 2, 'Two amounts required');
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('withdraw(uint256,uint256[])', _poolTokensIn, _minAmountsOut);

        return (poolAddress, 0, methodData);
    }
}
