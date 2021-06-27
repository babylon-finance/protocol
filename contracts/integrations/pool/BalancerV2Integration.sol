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
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {PoolIntegration} from './PoolIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {IBasePool} from '../../interfaces/external/balancer/IBasePool.sol';
import {IVault} from '../../interfaces/external/balancer/IVault.sol';
import {IAuthorizer} from '../../interfaces/external/balancer/IAuthorizer.sol';

import {IAsset} from '../../interfaces/external/balancer/IAsset.sol';
import {IBPool} from '../../interfaces/external/balancer/IBPool.sol';
import {IBFactory} from '../../interfaces/external/balancer/IBFactory.sol';

/**
 * @title BalancerIntegration
 * @author Babylon Finance Protocol
 *
 * Balancer V2 protocol pool integration
 */
contract BalancerV2Integration is PoolIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ State Variables ============ */

    // Address of Balancer Vault
    IVault public vault; // 0xBA12222222228d8Ba445958a75a0704d566BF2C8
    IBasePool public weightedFactory; // 0x8E9aa87E45e92bad84D5F8DD1bff34Fb92637dE9
    IBasePool public oracleFactory; // 0xA5bf2ddF098bb0Ef6d120C98217dD6B141c74EE0
    IBasePool public stableFactory; // 0x791F9fD8CFa2Ea408322e172af10186b2D73baBD
    IBFactory public coreFactory;

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

    struct PoolSpecialization {
        // GENERAL, MINIMAL_SWAP_INFO, TWO_TOKEN
        string GENERAL;
        string MINIMAL_SWAP_INFO;
        string TWO_TOKEN;
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
        address _vaultAddress,
        address _weighedFactory,
        address _oracleFactory,
        address _stableFactory
    ) PoolIntegration('balancer', _weth, _controller) {
        vault = IVault(_vaultAddress);
        weightedFactory = IBasePool(_weighedFactory);
        oracleFactory = IBasePool(_oracleFactory);
        stableFactory = IBasePool(_stableFactory);
    }

    /* ============ External Functions ============ */

    /**
    function getPool(bytes32 _poolId) external view override returns (address poolAddress, PoolSpecialization memory specialization) {
        (address poolAddress, PoolSpecialization memory specialization) = IVault(vault).getPool(_poolId); 

    }
    
    /** 
    function getPoolTokens2(bytes32 _poolId) external view returns (IERC20[] memory, uint256[] memory, uint256) {
        //(IERC20[] storage tokens, uint256[] memory balances, uint256 lastChangeBlock) =  IVault(vault).getPoolTokens(_poolId);
        //return (tokens, balances, lastChangeBlock);
    }
    */
    function getPoolTokens(address _poolAddress) external view override returns (address[] memory) {
        return IBPool(_poolAddress).getCurrentTokens();
    }

    /** 
    function getPoolWeights2(bytes32 _poolId) external view override returns (uint256[] memory) {
        address[] storage poolTokens = IVault(vault).getPoolTokens(_poolId);
        uint256[] storage result = new uint256[](poolTokens.length);
        for (uint8 i = 0; i < poolTokens.length; i++) {
            result[i] = IVault(vault).getNormalizedWeight(poolTokens[i]);
        }
        return result;
    }
    */

    function getPoolWeights(address _poolAddress) external view override returns (uint256[] memory) {
        address[] memory poolTokens = IBPool(_poolAddress).getCurrentTokens();
        uint256[] memory result = new uint256[](poolTokens.length);
        for (uint8 i = 0; i < poolTokens.length; i++) {
            result[i] = IBPool(_poolAddress).getNormalizedWeight(poolTokens[i]);
        }
        return result;
    }

    function getAuthorizer() external view returns (IAuthorizer) {
        return IVault(vault).getAuthorizer();
    }

    /**
    function getPoolTokenInfo(bytes32 _poolId, IERC20 _token) external view override returns (uint256 cash, uint256 managed, uint256 blockNumber, address assetManager) {
        (uint256 cash, uint256 managed, uint256 blockNumber, address assetManager) =  IVault(vault).getPoolTokenInfo(_poolId, _token);
    }

    function getVault() external view returns (IVault vaultAddress) {
        IVault vaultAddress = IVault(vault).getVault();
    }

    function getSwapFeePercentage() external view returns (uint256 swapFeePercentage) {
        uint256 swapFeePercentage = IVault(vault).getSwapFeePercentage();
    }

    function getPoolId() external view returns (bytes32 poolID) {
        bytes32 poolID = IVault(vault).getPoolId();
    }

    // Can only be called by an authorized account
    function setSwapFeePercentage(uint256 _swapFeePercentage) external {
        IVault(vault).setSwapFeePercentage(_swapFeePercentage);
    }

    // Can only be called by an authorized account (emergency stop)
    function setPaused(bool _paused) external {
        IVault(vault).setPaused(_paused);
    }

    /** 
    onJoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] currentBalances,
        uint256 latestBlockNumberUsed,
        uint256 protocolSwapFeePercentage,
        bytes userData
    ) returns (uint256[] amountsIn, uint256[] dueProtocolFeeAmounts)
    
    onExitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] currentBalances,
        uint256 latestBlockNumberUsed,
        uint256 protocolSwapFeePercentage,
        bytes userData
    ) returns (uint256[] amountsOut, uint256[] dueProtocolFeeAmounts) {
    */

    function getPoolTokensOut(
        address _poolAddress,
        address _poolToken,
        uint256 _maxAmountsIn
    ) external view override returns (uint256) {
        return 0;
    }

    function getPoolMinAmountsOut(address _poolAddress, uint256 _liquidity)
        external
        view
        override
        returns (uint256[] memory _minAmountsOut)
    {
        //return 0;
    }

    /* ============ Internal Functions ============ */

    function _isPool(address _poolAddress) internal view override returns (bool) {
        return coreFactory.isBPool(_poolAddress);
    }

    function _isPool2(bytes32 _poolId) internal view returns (bool) {
        (address pool, ) = IVault(vault).getPool(_poolId);
        return pool != address(0);
    }

    function _getSpender(address _poolAddress) internal pure override returns (address) {
        return _poolAddress;
    }

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
    function _getJoinPoolCalldata2(
        address _strategy,
        bytes32 _poolId,
        address _sender,
        address _recipient,
        JoinPoolRequest memory _request
    )
        internal
        pure
        returns (
            /* override */
            bytes32,
            uint256,
            bytes memory
        )
    {
        //JoinPoolRequest storage requestData = joinRequest[_strategy];
        //requestData.assets = _request.assets;
        //requestData.maxAmountsIn = _request.maxAmountsIn;
        //requestData.userData = _request.userData;
        //requestData.fromInternalBalance = _request.fromInternalBalance;

        // Encode method data for Garden to invoke
        //bytes memory methodData = abi.encodeWithSignature('joinPool(bytes32,address, address, JoinPoolRequest)', _poolId, _sender, _recipient, _request);

        bytes memory methodData =
            abi.encodeWithSignature(
                'joinPool(bytes32,address, address, JoinPoolRequest)',
                _poolId,
                _sender,
                _recipient
            );

        return (_poolId, 0, methodData);
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
    function _getExitPoolCalldata2(
        address, /* _strategy */
        bytes32 _poolId,
        address _sender,
        address payable _recipient,
        ExitPoolRequest memory _request
    )
        internal
        pure
        returns (
            /* override */
            bytes32,
            uint256,
            bytes memory
        )
    {
        require(_request.assets.length > 0, '_Has to provide assets');
        require(_request.minAmountsOut.length > 1, 'Has to provide _minAmountsOut');
        require(_request.assets.length == _request.minAmountsOut.length, 'Length mismatch');
        // Encode method data for Garden to invoke
        //bytes memory methodData = abi.encodeWithSignature('exitPool(bytes32, address, address, ExitPoolRequest)', _poolId, _sender, _recipient, _request);

        bytes memory methodData =
            abi.encodeWithSignature(
                'exitPool(bytes32, address, address, ExitPoolRequest)',
                _poolId,
                _sender,
                _recipient
            );

        return (_poolId, 0, methodData);
    }
}
