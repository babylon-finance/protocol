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

pragma solidity 0.7.4;

import 'hardhat/console.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import {PoolIntegration} from './PoolIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {IMooniswapFactory} from '../../interfaces/external/1inch/IMooniswapFactory.sol';
import {IMooniswap} from '../../interfaces/external/1inch/IMooniswap.sol';

/**
 * @title BalancerIntegration
 * @author Babylon Finance Protocol
 *
 * Kyber protocol trade integration
 */
contract OneInchPoolIntegration is PoolIntegration {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ State Variables ============ */

    // Address of Uniswap V2 Router
    IMooniswapFactory public mooniswapFactory;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _weth                         Address of the WETH ERC20
     * @param _mooniswapFactoryAddress         Address of the Mooniswap factory
     */
    constructor(
        address _controller,
        address _weth,
        address _mooniswapFactoryAddress
    ) PoolIntegration('oneinch_pool', _weth, _controller) {
        mooniswapFactory = IMooniswapFactory(_mooniswapFactoryAddress);
    }

    function getPoolTokens(address _poolAddress) external view override returns (address[] memory) {
        return IMooniswap(_poolAddress).getTokens();
    }

    function getPoolWeights(
        address /* _poolAddress */
    ) external pure override returns (uint256[] memory) {
        uint256[] memory result = new uint256[](2);
        result[0] = 5e17; // 50%
        result[1] = 5e17; // 50%
        return result;
    }

    /* ============ Internal Functions ============ */

    function _isPool(address _poolAddress) internal view override returns (bool) {
        return IMooniswapFactory(mooniswapFactory).isPool(IMooniswap(_poolAddress));
    }

    function _getSpender(address _poolAddress) internal pure override returns (address) {
        return _poolAddress;
    }

    /**
     * Return join pool calldata which is already generated from the pool API
     *
     * hparam  _poolAddress              Address of the pool
     * hparam  _poolTokensOut            Amount of pool tokens to send
     * @param  _tokensIn                 Addresses of tokens to send to the pool
     * @param  _maxAmountsIn             Amounts of tokens to send to the pool
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getJoinPoolCalldata(
        address _poolAddress,
        uint256, /* _poolTokensOut */
        address[] calldata _tokensIn,
        uint256[] calldata _maxAmountsIn
    )
        internal
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Encode method data for Garden to invoke
        require(_tokensIn.length == 2, 'Adding liquidity to a mooniswap pool requires exactly two tokens');
        require(_maxAmountsIn.length == 2, 'Adding liquidity to a mooniswap pool requires exactly two tokens');
        uint256[] memory minAmounts = new uint256[](2);
        bytes memory methodData =
            abi.encodeWithSignature(
                'deposit(uint256[] calldata amounts, uint256[] calldata minAmounts)',
                _maxAmountsIn,
                minAmounts // TODO: tighten this up
            );

        return (address(_poolAddress), 0, methodData);
    }

    /**
     * Return exit pool calldata which is already generated from the pool API
     *
     * hparam  _poolAddress              Address of the pool
     * @param  _poolTokensIn             Amount of pool tokens to receive
     * @param  _tokensOut                Addresses of tokens to receive
     * @param  _minAmountsOut            Amounts of pool tokens to receive
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getExitPoolCalldata(
        address _poolAddress,
        uint256 _poolTokensIn,
        address[] calldata _tokensOut,
        uint256[] calldata _minAmountsOut
    )
        internal
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        require(_tokensOut.length == 2, 'Removing liquidity from a mooniswap pool requires exactly two tokens');
        require(_minAmountsOut.length == 2, 'Removing liquidity from a mooniswap pool requires exactly two tokens');
        // Encode method data for Garden to invoke
        bytes memory methodData =
            abi.encodeWithSignature('uint256 amount, uint256[] memory minReturns', _poolTokensIn, _minAmountsOut);

        return (address(_poolAddress), 0, methodData);
    }
}
