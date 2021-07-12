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

    /* ============ Constant ============ */
    address private constant TRICRYPTO = 0x331aF2E331bd619DefAa5DAc6c038f53FCF9F785; // Pool only takes ETH
    address private constant STETH = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022; // pool requires first amount to match msg.value

    /* ============ State Variables ============ */
    // Mapping of asset addresses to lp tokens
    // Some curve pools use lp_token() others token() and somes don't even have the methods public
    mapping(address => address) public depositToToken;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PoolIntegration('curve_pool', _controller) {
        depositToToken[0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7] = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // 3pool
        depositToToken[0x4CA9b3063Ec5866A4B82E437059D2C43d1be596F] = 0xb19059ebb43466C323583928285a49f558E572Fd; // hbtc
        depositToToken[0x93054188d876f558f4a66B2EF1d97d16eDf0895B] = 0x49849C98ae39Fff122806C06791Fa73784FB3675; // renbtc
        depositToToken[0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714] = 0x075b1bb99792c9E1041bA13afEf80C91a1e70fB3; // sbtc
        depositToToken[0xc5424B857f758E906013F3555Dad202e4bdB4567] = 0xA3D87FffcE63B53E0d54fAa1cc983B7eB0b74A9c; // seth
    }

    /* ============ External Functions ============ */

    function getPoolTokens(bytes calldata _pool) public view override returns (address[] memory) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        address[] memory result = new address[](_getNCoins(poolAddress));
        for (uint8 i = 0; i < _getNCoins(poolAddress); i++) {
            result[i] = ICurvePoolV3(poolAddress).coins(i);
        }
        return result;
    }

    function getPoolWeights(bytes calldata _pool) external view override returns (uint256[] memory) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        address[] memory poolTokens = getPoolTokens(_pool);
        uint256[] memory result = new uint256[](_getNCoins(poolAddress));
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
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        uint256[] memory result = new uint256[](_getNCoins(poolAddress));
        return result;
    }

    /* ============ Internal Functions ============ */

    function _isPool(bytes memory _pool) internal view override returns (bool) {
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 12);
        return ICurvePoolV3(poolAddress).coins(0) != address(0);
    }

    function _getSpender(bytes calldata _pool) internal view override returns (address) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        return poolAddress;
    }

    function _totalSupply(
        address /* _pool */
    ) internal view override returns (uint256) {
        return uint256(1e18);
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
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        uint256 poolCoins = _getNCoins(poolAddress); //_decodeOpDataAsUint8(_pool, 0);

        // Encode method data for Garden to invoke
        bytes memory methodData = _getAddLiquidityMethodData(poolCoins, _maxAmountsIn, _poolTokensOut);

        uint256 value = 0;
        if (poolAddress == TRICRYPTO) {
            // get the value of eth multiplied by 3
            value = _maxAmountsIn[2].mul(3);
            // TODO: probably better to override pool tokens and weight to only have ETH
        }
        return (poolAddress, value, methodData);
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
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 32 + 12);
        uint256 poolCoins = _getNCoins(poolAddress); //_decodeOpDataAsUint8(_pool, 0);

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

    function _getLpToken(address _pool) internal view override returns (address) {
        // For Deposits & stable swaps that support it get the LP token, otherwise get the pool
        try ICurvePoolV3(_pool).lp_token() returns (address result) {
            return result;
        } catch {
            try ICurvePoolV3(_pool).token() returns (address token) {
                return token;
            } catch {
                if (depositToToken[_pool] != address(0)) {
                    return depositToToken[_pool];
                }
                return _pool;
            }
        }
    }

    function _getNCoins(address _pool) private view returns (uint256) {
        try ICurvePoolV3(_pool).coins(4) returns (address result) {
            return 5;
        } catch {
            try ICurvePoolV3(_pool).coins(3) returns (address result) {
                return 4;
            } catch {
                try ICurvePoolV3(_pool).coins(2) returns (address result) {
                    return 3;
                } catch {
                    return 2;
                }
            }
        }
    }
}
