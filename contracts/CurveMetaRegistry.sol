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

import {IBabController} from './interfaces/IBabController.sol';
import {ICurveMetaRegistry} from './interfaces/ICurveMetaRegistry.sol';
import {ICurveAddressProvider} from './interfaces/external/curve/ICurveAddressProvider.sol';
import {ICurveRegistry} from './interfaces/external/curve/ICurveRegistry.sol';
import {ICryptoRegistry} from './interfaces/external/curve/ICryptoRegistry.sol';

/**
 * @title CurveMetaRegistry
 * @author Babylon Finance Protocol
 *
 * Abstraction for all the different curve registries
 */
contract CurveMetaRegistry is ICurveMetaRegistry {
    /* ============ Constants ============ */

    // Address of Curve Address provider
    ICurveAddressProvider internal constant curveAddressProvider =
        ICurveAddressProvider(0x0000000022D53366457F9d5E68Ec105046FC4383);

    /* ============ State Variables ============ */

    IBabController public immutable controller;

    // Registry of first party pools
    ICurveRegistry public curveRegistry;

    // Registry of user created pools
    ICurveRegistry public factoryRegistry;

    // Registry of first party crypto pools
    ICryptoRegistry public cryptoRegistry;

    // Registry of third party crypto pools
    ICryptoRegistry public cryptoRegistryF;

    // Mapping of pool to registryId
    mapping(address => uint8) public poolToRegistry;

    // 0 means doesnt exist
    // 1 means first party normal
    // 2 means factory pools
    // 3 means crypto first party
    // 4 means crypto third party

    /* ============ Modifiers ============ */

    modifier onlyGovernanceOrEmergency {
        require(
            msg.sender == controller.owner() || msg.sender == controller.EMERGENCY_OWNER(),
            'Not enough privileges'
        );
        _;
    }

    /* ============ Constructor ============ */

    constructor(IBabController _controller) {
        controller = _controller;
        curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        factoryRegistry = ICurveRegistry(curveAddressProvider.get_address(3));
        cryptoRegistry = ICryptoRegistry(curveAddressProvider.get_address(5));
        cryptoRegistryF = ICryptoRegistry(0xF18056Bbd320E96A48e3Fbf8bC061322531aac99);
        _updateMapping(1, curveRegistry);
        _updateMapping(2, factoryRegistry);
        _updateMapping(3, ICurveRegistry(address(cryptoRegistry)));
        _updateMapping(4, ICurveRegistry(address(cryptoRegistryF)));
    }

    /* ============ External Functions ============ */

    /**
     * Updates the mapping of pools for gas efficiency
     *
     */
    function updatePoolsList() public override onlyGovernanceOrEmergency {
        _updateMapping(1, curveRegistry);
        _updateMapping(2, factoryRegistry);
        _updateMapping(3, ICurveRegistry(address(cryptoRegistry)));
        _updateMapping(4, ICurveRegistry(address(cryptoRegistryF)));
    }

    /**
     * Updates the addresses of the registries themselves
     *
     */
    function updateCryptoRegistries(address _cryptoRegistryF) external override onlyGovernanceOrEmergency {
        curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        factoryRegistry = ICurveRegistry(curveAddressProvider.get_address(3));
        cryptoRegistry = ICryptoRegistry(curveAddressProvider.get_address(5));
        cryptoRegistryF = ICryptoRegistry(_cryptoRegistryF);
        updatePoolsList();
    }

    /**
     * Gets the coin addresses of a pool
     * @param _getUnderlying          Whether or not to get the underlying coins
     *
     * @return address[8]             Addresses of the pool assets. Array of size 8 (filled with 0)
     */
    function getCoinAddresses(address _pool, bool _getUnderlying) external view override returns (address[8] memory) {
        uint256 registryKind = poolToRegistry[_pool];
        if (_getUnderlying) {
            if (registryKind == 1) {
                return curveRegistry.get_underlying_coins(_pool);
            }
            if (registryKind == 2) {
                return factoryRegistry.get_underlying_coins(_pool);
            }
            revert('Crypto curve pools cannot use underlying');
        }
        if (!_getUnderlying) {
            if (registryKind == 1) {
                return curveRegistry.get_coins(_pool);
            }
            if (registryKind == 2) {
                return factoryRegistry.get_coins(_pool);
            }
            if (registryKind == 3) {
                return cryptoRegistry.get_coins(_pool);
            }
            if (registryKind == 4) {
                return cryptoRegistryF.get_coins(_pool);
            }
        }
    }

    /**
     * Gets the number of coins of a curve pool
     * @param _pool                   Pool Address
     *
     * @return uint256                Number of coins in the pool
     */
    function getNCoins(address _pool) external view override returns (uint256) {
        uint256 registryKind = poolToRegistry[_pool];
        if (registryKind == 1) {
            return curveRegistry.get_n_coins(_pool)[0];
        }
        if (registryKind == 2) {
            return factoryRegistry.get_n_coins(_pool)[0];
        }
        if (registryKind == 3) {
            return cryptoRegistry.get_n_coins(_pool);
        }
        return cryptoRegistryF.get_n_coins(_pool);
    }

    /**
     * Gets the lp token from a curve pool address
     * @param _pool                   Pool Address
     *
     * @return address                Address of the lp token
     */
    function getLpToken(address _pool) external view override returns (address) {
        uint256 registryKind = poolToRegistry[_pool];
        // For Deposits & stable swaps that support it get the LP token, otherwise get the pool
        if (registryKind == 1) {
            return curveRegistry.get_lp_token(_pool);
        }
        if (registryKind == 3) {
            return cryptoRegistry.get_lp_token(_pool);
        }
        // Factory pools use the pool as the token
        return _pool;
    }

    /**
     * Gets the pool from a curve lp token
     * @param _lpToken                Address of the lp token
     *
     * @return address                Address of the pool
     */
    function getPoolFromLpToken(address _lpToken) external view override returns (address) {
        // For Deposits & stable swaps that support it get the LP token, otherwise get the pool
        try curveRegistry.get_pool_from_lp_token(_lpToken) returns (address pool) {
            return pool;
        } catch {
            try cryptoRegistry.get_pool_from_lp_token(_lpToken) returns (address pool2) {
                return pool2;
            } catch {
                // Factory pools use the pool as the token
                return _lpToken;
            }
        }
    }

    /**
     * Returns whether the pool is a meta pool
     * @param _pool                   Pool Address
     *
     * @return bool                Whether the pool is a meta pool or not
     */
    function isMeta(address _pool) external view override returns (bool) {
        uint256 registryKind = poolToRegistry[_pool];
        if (registryKind != 1 && registryKind != 2) {
            return false;
        }
        if (registryKind == 1) {
            return curveRegistry.is_meta(_pool);
        }
        return factoryRegistry.is_meta(_pool);
    }

    /**
     * Returns the virtual price of an lp token from curve
     * @param _pool                   Pool Address
     *
     * @return uint256                Whether the pool is a meta pool or not
     */
    function getVirtualPriceFromLpToken(address _pool) external view override returns (uint256) {
        uint256 registryKind = poolToRegistry[_pool];
        if (registryKind != 1 && registryKind != 3) {
            return 1e18;
        }
        if (registryKind == 1) {
            return curveRegistry.get_virtual_price_from_lp_token(_pool);
        }
        return cryptoRegistry.get_virtual_price_from_lp_token(_pool);
    }

    /**
     * Returns the underlying asset and the rate of conversion at the index i
     * @param _pool                   Pool Address
     * @param _i                      Asset index
     *
     * @return address                Address of the underlying asset. 0 if none
     * @return uint256                Rate of conversion between the underlying and the asset
     */
    function getUnderlyingAndRate(address _pool, uint256 _i) external view override returns (address, uint256) {
        uint256 registryKind = poolToRegistry[_pool];

        if (registryKind == 1) {
            return (curveRegistry.get_underlying_coins(_pool)[_i], curveRegistry.get_rates(_pool)[_i]);
        }
        if (registryKind == 2) {
            return (factoryRegistry.get_underlying_coins(_pool)[_i], factoryRegistry.get_rates(_pool)[_i]);
        }
        // No underlying
        return (address(0), 0);
    }

    /**
     * Finds a pool given those tokens and the index _i
     * @param _fromToken              Token 1
     * @param _toToken                Token 2
     * @param _i                      Index of the pool to retrieve (if more than one)
     *
     * @return address                Address of the pool
     */
    function findPoolForCoins(
        address _fromToken,
        address _toToken,
        uint256 _i
    ) external view override returns (address) {
        address result = curveRegistry.find_pool_for_coins(_fromToken, _toToken, _i);
        if (result != address(0)) {
            return result;
        }
        result = factoryRegistry.find_pool_for_coins(_fromToken, _toToken, _i);
        if (result != address(0)) {
            return result;
        }
        result = cryptoRegistry.find_pool_for_coins(_fromToken, _toToken, _i);
        if (result != address(0)) {
            return result;
        }
        return cryptoRegistryF.find_pool_for_coins(_fromToken, _toToken, _i);
    }

    /**
     * Gets the indices of two tokens given a pool address
     * @param _pool                   Pool address
     * @param _fromToken              Token 1
     * @param _toToken                Token 2
     *
     * @return uint256                Index of token 1
     * @return uint256                Index of token 2
     * @return bool                   Whether or not is underlying
     */
    function getCoinIndices(
        address _pool,
        address _fromToken,
        address _toToken
    )
        external
        view
        override
        returns (
            uint256,
            uint256,
            bool
        )
    {
        uint256 registryKind = poolToRegistry[_pool];
        bool underlying = false;
        uint256 oneIndex;
        uint256 twoIndex;
        if (registryKind == 1) {
            (int128 oneIndexI, int128 twoIndexI, bool underlyingI) =
                curveRegistry.get_coin_indices(_pool, _fromToken, _toToken);
            oneIndex = uint256(oneIndexI);
            twoIndex = uint256(twoIndexI);
            underlying = underlyingI;
        }
        if (registryKind == 2) {
            (int128 oneIndexI, int128 twoIndexI, bool underlyingI) =
                factoryRegistry.get_coin_indices(_pool, _fromToken, _toToken);
            oneIndex = uint256(oneIndexI);
            twoIndex = uint256(twoIndexI);
            underlying = underlyingI;
        }
        if (registryKind == 3) {
            (oneIndex, twoIndex) = cryptoRegistry.get_coin_indices(_pool, _fromToken, _toToken);
        }
        if (registryKind == 4) {
            (oneIndex, twoIndex) = cryptoRegistryF.get_coin_indices(_pool, _fromToken, _toToken);
        }
        return (oneIndex, twoIndex, underlying);
    }

    /**
     * Returns whether or not a given address is a curve pool
     * @param _poolAddress            Pool address
     *
     * @return bool                   Whether or not is underlying
     */
    function isPool(address _poolAddress) external view override returns (bool) {
        return poolToRegistry[_poolAddress] != 0;
    }

    /* ============ Internal Functions ============ */

    // Function to the update the registry mappings
    function _updateMapping(uint8 _index, ICurveRegistry _registry) internal {
        for (uint256 i = 0; i < _registry.pool_count(); i++) {
            poolToRegistry[_registry.pool_list(i)] = _index;
        }
    }
}
