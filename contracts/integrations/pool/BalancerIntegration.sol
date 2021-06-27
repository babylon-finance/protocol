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
import {PoolIntegration} from './PoolIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {IBFactory} from '../../interfaces/external/balancer/IBFactory.sol';
import {IBPool} from '../../interfaces/external/balancer/IBPool.sol';

/**
 * @title BalancerIntegration
 * @author Babylon Finance Protocol
 *
 * Balancer protocol trade integration
 */
contract BalancerIntegration is PoolIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ State Variables ============ */

    IBFactory public coreFactory;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _coreFactoryAddress           Address of Balancer core factory address
     */
    constructor(IBabController _controller, address _coreFactoryAddress) PoolIntegration('balancer', _controller) {
        coreFactory = IBFactory(_coreFactoryAddress);
    }

    /* ============ External Functions ============ */

    function getPoolTokens(address _poolAddress) external view override returns (address[] memory) {
        return IBPool(_poolAddress).getCurrentTokens();
    }

    function getPoolWeights(address _poolAddress) external view override returns (uint256[] memory) {
        address[] memory poolTokens = IBPool(_poolAddress).getCurrentTokens();
        uint256[] memory result = new uint256[](poolTokens.length);
        for (uint8 i = 0; i < poolTokens.length; i++) {
            result[i] = IBPool(_poolAddress).getNormalizedWeight(poolTokens[i]);
        }
        return result;
    }

    function getPoolTokensOut(
        address _poolAddress,
        address _poolToken,
        uint256 _maxAmountsIn
    ) external view override returns (uint256) {
        uint256 tokenBalance = IBPool(_poolAddress).getBalance(_poolToken);
        return IBPool(_poolAddress).totalSupply().preciseMul(_maxAmountsIn.preciseDiv(tokenBalance));
    }

    function getPoolMinAmountsOut(address _poolAddress, uint256 _liquidity)
        external
        view
        override
        returns (uint256[] memory _minAmountsOut)
    {
        uint256 lpTokensTotalSupply = IBPool(_poolAddress).totalSupply();
        address[] memory poolTokens = IBPool(_poolAddress).getCurrentTokens();
        uint256[] memory result = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            result[i] = IERC20(poolTokens[i])
                .balanceOf(_poolAddress)
                .mul(_liquidity)
                .div(lpTokensTotalSupply)
                .preciseMul(1e18 - SLIPPAGE_ALLOWED);
        }
        return result;
    }

    /* ============ Internal Functions ============ */

    function _isPool(address _poolAddress) internal view override returns (bool) {
        return coreFactory.isBPool(_poolAddress);
    }

    function _getSpender(address _poolAddress) internal pure override returns (address) {
        return _poolAddress;
    }

    /**
     * Return join pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * @param  _poolAddress              Address of the pool
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
        address _poolAddress,
        uint256 _poolTokensOut,
        address[] calldata, /* _tokensIn */
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
        bytes memory methodData = abi.encodeWithSignature('joinPool(uint256,uint256[])', _poolTokensOut, _maxAmountsIn);

        return (_poolAddress, 0, methodData);
    }

    /**
     * Return exit pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * @param  _poolAddress              Address of the pool
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
        address _poolAddress,
        uint256 _poolTokensIn,
        address[] calldata, /* _tokensOut */
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
        require(_poolTokensIn > 0, '_poolTokensIn has to not 0');
        require(_minAmountsOut.length > 1, 'Has to provide _minAmountsOut');
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('exitPool(uint256,uint256[])', _poolTokensIn, _minAmountsOut);

        return (_poolAddress, 0, methodData);
    }
}
