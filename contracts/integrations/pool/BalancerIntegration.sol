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

//import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {PoolIntegration} from './PoolIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {IBasePool} from '../../interfaces/external/balancer/IBasePool.sol';
import {IVault} from '../../interfaces/external/balancer/IVault.sol';
import {IAsset} from '../../interfaces/external/balancer/IAsset.sol';

/**
 * @title BalancerIntegration
 * @author Babylon Finance Protocol
 *
 * Balancer V2 protocol pool integration
 */
contract BalancerIntegration is PoolIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ State Variables ============ */

    // Address of Balancer Vault
    IVault public vault; // 0xBA12222222228d8Ba445958a75a0704d566BF2C8

    struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct ExitPoolRequest {
        IAsset[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }
    // Mapping for each strategy
    mapping(address => JoinPoolRequest) private joinRequest;
    mapping(address => ExitPoolRequest) private exitRequest;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _weth                         Address of the WETH ERC20
     * @param _vaultAddress           Address of Balancer core factory address
     */
    constructor(
        IBabController _controller,
        address _weth,
        address _vaultAddress
    ) PoolIntegration('balancer', _weth, _controller) {
        vault = IVault(_vaultAddress);
    }

    /* ============ External Functions ============ */

    /**
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

    /**
    function _isPool(address _poolAddress) internal view override returns (bool) {
        return vault.isBPool(_poolAddress);
    }

    function _getSpender(address _poolAddress) internal pure override returns (address) {
        return _poolAddress;
    }
    */
    /**
     * Return join pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * @param  _poolId                   Balancer V2 poolID
     * @param  _sender                   Sender address
     * @param  _recipient                Addresses of recipient
     * @param  _request                  Struct mapping
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getJoinPoolCalldata(
        address, /* _strategy */
        bytes32 _poolId,
        address _sender,
        address _recipient,
        JoinPoolRequest memory _request
    )
        internal
        pure
        override
        returns (
            bytes32,
            uint256,
            bytes memory
        )
    {
        // Encode method data for Garden to invoke
        bytes memory methodData =
            abi.encodeWithSignature(
                'joinPool(bytes32,address, address, JoinPoolRequest)',
                _poolId,
                _sender,
                _recipient,
                _request
            );

        return (_poolId, 0, methodData);
    }

    /**
     * Return exit pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * @param  _poolId                   PoolID
     * @param  _sender                   Sender address
     * @param  _recipient                Recipient address
     * @param  _request                  Struct request
     *
     * @return bytes32                   Target poolId
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getExitPoolCalldata(
        address, /* _strategy */
        bytes32 _poolId,
        address _sender,
        address payable _recipient,
        ExitPoolRequest memory _request
    )
        internal
        pure
        override
        returns (
            bytes32,
            uint256,
            bytes memory
        )
    {
        require(_request.assets.length > 0, '_Has to provide assets');
        require(_request.minAmountsOut.length > 1, 'Has to provide _minAmountsOut');
        require(_request.assets.length == _request.minAmountsOut.length, 'Length mismatch');
        // Encode method data for Garden to invoke
        bytes memory methodData =
            abi.encodeWithSignature(
                'exitPool(bytes32, address, address, ExitPoolRequest)',
                _poolId,
                _sender,
                _recipient,
                _request
            );

        return (_poolId, 0, methodData);
    }
}
