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
import {IBabController} from '../../interfaces/IBabController.sol';
import {ICurvePoolV3} from '../../interfaces/external/curve/ICurvePoolV3.sol';
import {PoolIntegration} from './PoolIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';

/**
 * @title CurvePoolIntegration
 * @author Babylon Finance Protocol
 *
 * Curve liquidity providing integration
 */
contract CurvePoolIntegration is PoolIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using BytesLib for uint256;

    /* ============ State Variables ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PoolIntegration('curve_pool', _controller) {}

    /* ============ External Functions ============ */

    function getPoolTokens(bytes calldata _pool) external view override returns (address[] memory) {
        address poolAddress = _decodeOpDataAddress(_pool);
        return ICurvePoolV3(poolAddress).coins();
    }

    function getPoolWeights(bytes calldata _pool) external view override returns (uint256[] memory) {
        address poolAddress = _decodeOpDataAddress(_pool);
        address[] memory poolTokens = ICurvePoolV3(poolAddress).coins();
        uint256[] memory result = new uint256[](poolTokens.length);
        for (uint8 i = 0; i < poolTokens.length; i++) {
            result[i] = uint256(1e18).div(poolTokens.length);
        }
        return result;
    }

    function getPoolTokensOut(
        bytes calldata _pool,
        address _poolToken,
        uint256 _maxAmountsIn
    ) external view override returns (uint256) {
        // return 1 since _poolTokensOut are not used
        return 1;
    }

    function getPoolMinAmountsOut(bytes calldata _pool, uint256 _liquidity)
        external
        view
        override
        returns (uint256[] memory _minAmountsOut)
    {
        address poolAddress = _decodeOpDataAddress(_pool);
        address[] memory poolTokens = ICurvePoolV3(poolAddress).coins();
        uint256[] memory result = new uint256[](poolTokens.length);
        return result;
    }

    /* ============ Internal Functions ============ */

    function _isPool(bytes memory _pool) internal view override returns (bool) {
        address poolAddress = _decodeOpDataAddressAssembly(_pool, 32 + 12);
        return ICurvePoolV3(poolAddress).lp_token() != address(0);
    }

    function _getSpender(bytes calldata _pool) internal view override returns (address) {
        address poolAddress = _decodeOpDataAddress(_pool);
        return poolAddress;
    }

    /**
     * Return join pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * @param  _pool                     OpData e.g. Address of the pool
     * @param  _poolTokensOut            Amount of pool tokens to send
     * hparam  _tokensIn                 Addresses of tokens to send to the pool
     * @param  _maxAmountsIn             Amounts of tokens to send to the pool
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getJoinPoolCalldata(
        address, /* _strategy */
        bytes calldata _pool,
        uint256 _poolTokensOut,
        address[] calldata, /* _tokensIn */
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
        address poolAddress = _decodeOpDataAddress(_pool);
        uint256 poolCoins = ICurvePoolV3(poolAddress).coins().length; //_decodeOpDataAsUint8(_pool, 0);

        // Encode method data for Garden to invoke
        bytes memory methodData = _getAddLiquidityMethodData(poolCoins, _maxAmountsIn, _poolTokensOut);

        return (poolAddress, 0, methodData);
    }

    /**
     * Return exit pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * @param  _pool                     OpData e.g. Address of the pool
     * @param  _poolTokensIn             Amount of pool tokens to receive
     * hparam  _tokensOut                Addresses of tokens to receive
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
        address[] calldata, /* _tokensOut */
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
        address poolAddress = _decodeOpDataAddressAssembly(_pool, 32 + 12);
        uint256 poolCoins = ICurvePoolV3(poolAddress).coins().length; //_decodeOpDataAsUint8(_pool, 0);

        require(_poolTokensIn > 0, '_poolTokensIn has to not 0');
        require(_minAmountsOut.length > 1, 'Has to provide _minAmountsOut');
        // Encode method data for Garden to invoke
        bytes memory methodData = _getRemoveLiquidityMethodData(poolCoins, _minAmountsOut, _poolTokensIn);

        return (poolAddress, 0, methodData);
    }

    function _getAddLiquidityMethodData(
        uint256 ncoins,
        uint256[] calldata _maxAmountsIn,
        uint256 minMintAmount
    ) private view returns (bytes memory) {
        if (ncoins == 2) {
            return
                abi.encodeWithSignature(
                    'add_liquidity(uint256[2],uint256)',
                    _maxAmountsIn[0],
                    _maxAmountsIn[1],
                    minMintAmount
                );
        }
        if (ncoins == 3) {
            return
                abi.encodeWithSignature(
                    'add_liquidity(uint256[3],uint256)',
                    _maxAmountsIn[0],
                    _maxAmountsIn[1],
                    _maxAmountsIn[2],
                    minMintAmount
                );
        }
        if (ncoins == 4) {
            return
                abi.encodeWithSignature(
                    'add_liquidity(uint256[4],uint256)',
                    _maxAmountsIn[0],
                    _maxAmountsIn[1],
                    _maxAmountsIn[2],
                    _maxAmountsIn[3],
                    minMintAmount
                );
        }
        if (ncoins == 5) {
            return
                abi.encodeWithSignature(
                    'add_liquidity(uint256[5],uint256)',
                    _maxAmountsIn[0],
                    _maxAmountsIn[1],
                    _maxAmountsIn[2],
                    _maxAmountsIn[3],
                    _maxAmountsIn[4],
                    minMintAmount
                );
        }
    }

    function _getRemoveLiquidityMethodData(
        uint256 ncoins,
        uint256[] calldata _minAmountsOut,
        uint256 _poolTokensIn
    ) private view returns (bytes memory) {
        if (ncoins == 2) {
            return
                abi.encodeWithSignature(
                    'remove_liquidity(uint256,uint256[2])',
                    _poolTokensIn,
                    _minAmountsOut[0],
                    _minAmountsOut[1]
                );
        }
        if (ncoins == 3) {
            return
                abi.encodeWithSignature(
                    'remove_liquidity(uint256,uint256[3])',
                    _poolTokensIn,
                    _minAmountsOut[0],
                    _minAmountsOut[1],
                    _minAmountsOut[2]
                );
        }
        if (ncoins == 4) {
            return
                abi.encodeWithSignature(
                    'remove_liquidity(uint256,uint256[4])',
                    _poolTokensIn,
                    _minAmountsOut[0],
                    _minAmountsOut[1],
                    _minAmountsOut[2],
                    _minAmountsOut[3]
                );
        }
        if (ncoins == 5) {
            return
                abi.encodeWithSignature(
                    'remove_liquidity(uint256,uint256[5])',
                    _poolTokensIn,
                    _minAmountsOut[0],
                    _minAmountsOut[1],
                    _minAmountsOut[2],
                    _minAmountsOut[3],
                    _minAmountsOut[4]
                );
        }
    }
}
