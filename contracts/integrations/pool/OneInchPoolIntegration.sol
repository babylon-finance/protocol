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
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
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

    /* ============ Constants ============ */

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

    /* ============ External Functions ============ */

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

    function getPoolTokensOut(
        address, /* _poolAddress */
        address, /* _poolToken */
        uint256 /* _maxAmountsIn */
    ) external view returns (uint256) {
        // return 1 since _poolTokensOut are not used
        return 1;
    }

    function getPoolMinAmountsOut(address _poolAddress, uint256 _liquidity)
        external
        view
        returns (uint256[] memory _minAmountsOut)
    {
        address[] memory tokens = IMooniswap(_poolAddress).getTokens();
        uint256 totalSupply = IMooniswap(_poolAddress).totalSupply();
        uint256[] memory result = new uint256[](2);
        uint256 token0Balance =
            (tokens[0] != address(0) ? IERC20(tokens[0]).balanceOf(_poolAddress) : _poolAddress.balance);
        uint256 token1Balance =
            (tokens[1] != address(0) ? IERC20(tokens[1]).balanceOf(_poolAddress) : _poolAddress.balance);
        result[0] = token0Balance.mul(_liquidity).div(totalSupply).preciseMul(1e18 - SLIPPAGE_ALLOWED);
        result[1] = token1Balance.mul(_liquidity).div(totalSupply).preciseMul(1e18 - SLIPPAGE_ALLOWED);
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

        return (address(_poolAddress), value, methodData);
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
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        require(_tokensOut.length == 2, 'Two tokens required');
        require(_minAmountsOut.length == 2, 'Two amounts required');
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('withdraw(uint256,uint256[])', _poolTokensIn, _minAmountsOut);

        return (address(_poolAddress), 0, methodData);
    }
}
