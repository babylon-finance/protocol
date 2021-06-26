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
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {PoolIntegration} from './PoolIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {IUniswapV2Router} from '../../interfaces/external/uniswap/IUniswapV2Router.sol';

/**
 * @title BalancerIntegration
 * @author Babylon Finance Protocol
 *
 * Uniswap protocol pool integration
 */
contract UniswapPoolIntegration is PoolIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ State Variables ============ */

    // Address of Uniswap V2 Router
    IUniswapV2Router public uniRouter;

    /* ============ Constants ============ */

    uint8 public immutable MAX_DELTA_BLOCKS = 5;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _weth                         Address of the WETH ERC20
     * @param _uniswapRouterAddress         Address of Uniswap router
     */
    constructor(
        IBabController _controller,
        address _weth,
        address _uniswapRouterAddress
    ) PoolIntegration('uniswap_pool', _weth, _controller) {
        uniRouter = IUniswapV2Router(_uniswapRouterAddress);
    }

    /* ============ External Functions ============ */

    function getPoolTokens(address _poolAddress) external view override returns (address[] memory) {
        address[] memory result = new address[](2);
        result[0] = IUniswapV2Pair(_poolAddress).token0();
        result[1] = IUniswapV2Pair(_poolAddress).token1();
        return result;
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
    ) external pure override returns (uint256) {
        // return 1 since _poolTokensOut are not used
        return 1;
    }

    function getPoolMinAmountsOut(address _poolAddress, uint256 _liquidity)
        external
        view
        override
        returns (uint256[] memory _minAmountsOut)
    {
        uint256 totalSupply = IUniswapV2Pair(_poolAddress).totalSupply();
        uint256[] memory result = new uint256[](2);
        result[0] = IERC20(IUniswapV2Pair(_poolAddress).token0())
            .balanceOf(_poolAddress)
            .mul(_liquidity)
            .div(totalSupply)
            .preciseMul(1e18 - SLIPPAGE_ALLOWED);
        result[1] = IERC20(IUniswapV2Pair(_poolAddress).token1())
            .balanceOf(_poolAddress)
            .mul(_liquidity)
            .div(totalSupply)
            .preciseMul(1e18 - SLIPPAGE_ALLOWED);
        return result;
    }

    /* ============ Internal Functions ============ */

    function _isPool(address _poolAddress) internal pure override returns (bool) {
        return IUniswapV2Pair(_poolAddress).MINIMUM_LIQUIDITY() > 0;
    }

    function _getSpender(
        address //_poolAddress
    ) internal view override returns (address) {
        return address(uniRouter);
    }

    /**
     * Return join pool calldata which is already generated from the pool API
     *
     * @param  _strategy                 Address of the strategy
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
        address _strategy,
        address, /* _poolAddress */
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
        // Encode method data for Garden to invoke
        require(_tokensIn.length == 2, 'Two tokens required');
        require(_maxAmountsIn.length == 2, 'Two amounts required');
        return (address(uniRouter), 0, _getMethodData(_strategy, _tokensIn, _maxAmountsIn));
    }

    function _getMethodData(
        address _strategy,
        address[] calldata _tokensIn,
        uint256[] calldata _maxAmountsIn
    ) private view returns (bytes memory) {
        return
            abi.encodeWithSignature(
                'addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)',
                _tokensIn[0],
                _tokensIn[1],
                _maxAmountsIn[0],
                _maxAmountsIn[1],
                _maxAmountsIn[0].sub(_maxAmountsIn[0].preciseMul(SLIPPAGE_ALLOWED)),
                _maxAmountsIn[1].sub(_maxAmountsIn[1].preciseMul(SLIPPAGE_ALLOWED)),
                _strategy,
                block.timestamp.add(MAX_DELTA_BLOCKS)
            );
    }

    /**
     * Return exit pool calldata which is already generated from the pool API
     *
     * @param  _strategy                 Address of the strategy
     * hparam  _poolAddress              Address of the pool
     * @param  _poolTokensIn             Amount of pool tokens to liquidate
     * @param  _tokensOut                Addresses of tokens to receive
     * @param  _minAmountsOut            Amounts of tokens to receive
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getExitPoolCalldata(
        address _strategy,
        address, /* _poolAddress */
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
        bytes memory methodData =
            abi.encodeWithSignature(
                'removeLiquidity(address,address,uint256,uint256,uint256,address,uint256)',
                _tokensOut[0],
                _tokensOut[1],
                _poolTokensIn,
                _minAmountsOut[0],
                _minAmountsOut[1],
                _strategy,
                block.timestamp.add(MAX_DELTA_BLOCKS)
            );

        return (address(uniRouter), 0, methodData);
    }
}
