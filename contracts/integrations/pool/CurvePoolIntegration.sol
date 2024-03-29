// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {ICurveMetaRegistry} from '../../interfaces/ICurveMetaRegistry.sol';
import {PoolIntegration} from './PoolIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {ControllerLib} from '../../lib/ControllerLib.sol';

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
    using ControllerLib for IBabController;

    /* ============ Constant ============ */
    address private constant TRICRYPTO2 = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46; // Pool only takes ETH
    address private constant cvxCRVPool = 0x9D0464996170c6B9e75eED71c68B99dDEDf279e8; // Pool only takes CRV for us
    address private constant palstkaave = 0x48536EC5233297C367fd0b6979B75d9270bB6B15; // Pool only takes CRV for us
    address private constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52; // crv
    address private constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // cvx
    ICurveMetaRegistry private immutable curveMetaRegistry;

    /* ============ State Variables ============ */

    // Registry of first party pools

    // Mapping of pools to deposit contract
    mapping(address => address) private poolToDeposit;

    // Whether to deposit using the underlying coins
    mapping(address => bool) private usesUnderlying;

    // Whether it supports the underlying param in add liquidity and remove liquidity
    mapping(address => bool) private supportsUnderlyingParam;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller, ICurveMetaRegistry _curveMetaRegistry)
        PoolIntegration('curve_pool', _controller)
    {
        require(address(_controller) != address(0), 'invalid address');
        require(address(_curveMetaRegistry) != address(0), 'invalid address');

        usesUnderlying[0xDeBF20617708857ebe4F679508E7b7863a8A8EeE] = true; // aave
        usesUnderlying[0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56] = true; // compound
        usesUnderlying[0x52EA46506B9CC5Ef470C5bf89f17Dc28bB35D85C] = true; // usdt
        usesUnderlying[0x06364f10B501e868329afBc005b3492902d6C763] = true; // PAX
        usesUnderlying[0x2dded6Da1BF5DBdF597C45fcFaa3194e53EcfeAF] = true; // ironbank
        usesUnderlying[0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27] = true; // busd
        usesUnderlying[0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51] = true; // y
        usesUnderlying[0xA5407eAE9Ba41422680e2e00537571bcC53efBfD] = true; // susd
        usesUnderlying[0x8925D9d9B4569D737a48499DeF3f67BaA5a144b9] = true; // yv2
        usesUnderlying[0xEB16Ae0052ed37f479f7fe63849198Df1765a733] = true; // saave

        poolToDeposit[0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56] = 0xeB21209ae4C2c9FF2a86ACA31E123764A3B6Bc06; // compound
        poolToDeposit[0x52EA46506B9CC5Ef470C5bf89f17Dc28bB35D85C] = 0xac795D2c97e60DF6a99ff1c814727302fD747a80; // usdt
        poolToDeposit[0x06364f10B501e868329afBc005b3492902d6C763] = 0xA50cCc70b6a011CffDdf45057E39679379187287; // pax
        poolToDeposit[0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27] = 0xb6c057591E073249F2D9D88Ba59a46CFC9B59EdB; // busd
        poolToDeposit[0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51] = 0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3; // y
        poolToDeposit[0xA5407eAE9Ba41422680e2e00537571bcC53efBfD] = 0xFCBa3E75865d2d561BE8D220616520c171F12851; // susd

        supportsUnderlyingParam[0xDeBF20617708857ebe4F679508E7b7863a8A8EeE] = true; // aave
        supportsUnderlyingParam[0x2dded6Da1BF5DBdF597C45fcFaa3194e53EcfeAF] = true; // ironbank
        supportsUnderlyingParam[0x8925D9d9B4569D737a48499DeF3f67BaA5a144b9] = true; // yv2
        supportsUnderlyingParam[0xEB16Ae0052ed37f479f7fe63849198Df1765a733] = true; // saave

        curveMetaRegistry = _curveMetaRegistry;
    }

    /* ============ External Functions ============ */

    function getPoolTokens(bytes calldata _pool, bool forNAV) public view override returns (address[] memory) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        uint256 ncoins = curveMetaRegistry.getNCoins(poolAddress);
        address[] memory result = new address[](ncoins);
        address[8] memory coins =
            curveMetaRegistry.getCoinAddresses(poolAddress, usesUnderlying[poolAddress] && !forNAV);
        for (uint8 i = 0; i < ncoins; i++) {
            result[i] = coins[i];
        }
        return result;
    }

    function getPoolWeights(bytes calldata _pool) external view override returns (uint256[] memory) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        address[] memory poolTokens = getPoolTokens(_pool, false);
        uint256[] memory result = new uint256[](curveMetaRegistry.getNCoins(poolAddress));
        if (poolAddress == TRICRYPTO2) {
            result[0] = 0;
            result[1] = 0;
            result[2] = uint256(1e18);
            return result;
        }
        // cvxCRV
        if (poolAddress == cvxCRVPool) {
            result[0] = uint256(1e18);
            result[1] = 0;
            return result;
        }
        // If it's a meta pool, deposit and withdraw from the stable one
        if (curveMetaRegistry.isMeta(poolAddress)) {
            result[0] = uint256(1e18);
        } else {
            for (uint8 i = 0; i < poolTokens.length; i++) {
                result[i] = uint256(1e18).div(poolTokens.length);
            }
        }
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

    function getPoolMinAmountsOut(
        bytes calldata _pool,
        uint256 /* _liquidity */
    ) external view override returns (uint256[] memory _minAmountsOut) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        uint256[] memory result = new uint256[](curveMetaRegistry.getNCoins(poolAddress));
        return result;
    }

    /* ============ Internal Functions ============ */

    function _isPool(bytes memory _pool) internal view override returns (bool) {
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 12);
        return curveMetaRegistry.isPool(poolAddress);
    }

    function _getSpender(
        bytes calldata _pool,
        uint8 /* _opType */
    ) internal view override returns (address) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        if (poolToDeposit[poolAddress] != address(0)) {
            poolAddress = poolToDeposit[poolAddress];
        }
        return poolAddress;
    }

    function _totalSupply(
        address /* _pool */
    ) internal pure override returns (uint256) {
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
        uint256 poolCoins = curveMetaRegistry.getNCoins(poolAddress); //_decodeOpDataAsUint8(_pool, 0);
        // Encode method data for Garden to invoke
        bytes memory methodData = _getAddLiquidityMethodData(poolAddress, poolCoins, _maxAmountsIn, _poolTokensOut);

        uint256 value = 0;
        // If any is eth, set as value
        for (uint256 i = 0; i < poolCoins; i++) {
            if (_tokensIn[i] == address(0) || _tokensIn[i] == ETH_ADD_CURVE) {
                value = _maxAmountsIn[i];
            }
        }
        // If we need a deposit contract to deposit underlying, switch
        if (poolToDeposit[poolAddress] != address(0)) {
            poolAddress = poolToDeposit[poolAddress];
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
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 12);
        uint256 poolCoins = curveMetaRegistry.getNCoins(poolAddress); //_decodeOpDataAsUint8(_pool, 0);

        require(_poolTokensIn > 0, '_poolTokensIn has to not 0');
        require(_minAmountsOut.length > 1, 'Has to provide _minAmountsOut');
        // Encode method data for Garden to invoke
        bytes memory methodData = _getRemoveLiquidityMethodData(poolAddress, poolCoins, _minAmountsOut, _poolTokensIn);
        if (poolToDeposit[poolAddress] != address(0)) {
            poolAddress = poolToDeposit[poolAddress];
        }
        return (poolAddress, 0, methodData);
    }

    function _getAddLiquidityMethodData(
        address _poolAddress,
        uint256 ncoins,
        uint256[] calldata _maxAmountsIn,
        uint256 minMintAmount
    ) private view returns (bytes memory) {
        if (ncoins == 2) {
            if (supportsUnderlyingParam[_poolAddress]) {
                return
                    abi.encodeWithSignature(
                        'add_liquidity(uint256[2],uint256,bool)',
                        _maxAmountsIn[0],
                        _maxAmountsIn[1],
                        minMintAmount,
                        true
                    );
            } else {
                return
                    abi.encodeWithSignature(
                        'add_liquidity(uint256[2],uint256)',
                        _maxAmountsIn[0],
                        _maxAmountsIn[1],
                        minMintAmount
                    );
            }
        }
        if (ncoins == 3) {
            if (supportsUnderlyingParam[_poolAddress]) {
                return
                    abi.encodeWithSignature(
                        'add_liquidity(uint256[3],uint256,bool)',
                        _maxAmountsIn[0],
                        _maxAmountsIn[1],
                        _maxAmountsIn[2],
                        minMintAmount,
                        true
                    );
            } else {
                return
                    abi.encodeWithSignature(
                        'add_liquidity(uint256[3],uint256)',
                        _maxAmountsIn[0],
                        _maxAmountsIn[1],
                        _maxAmountsIn[2],
                        minMintAmount
                    );
            }
        }
        if (ncoins == 4) {
            if (supportsUnderlyingParam[_poolAddress]) {
                return
                    abi.encodeWithSignature(
                        'add_liquidity(uint256[4],uint256,bool)',
                        _maxAmountsIn[0],
                        _maxAmountsIn[1],
                        _maxAmountsIn[2],
                        _maxAmountsIn[3],
                        minMintAmount,
                        true
                    );
            } else {
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
        }
        if (ncoins == 5) {
            if (supportsUnderlyingParam[_poolAddress]) {
                return
                    abi.encodeWithSignature(
                        'add_liquidity(uint256[5],uint256,bool)',
                        _maxAmountsIn[0],
                        _maxAmountsIn[1],
                        _maxAmountsIn[2],
                        _maxAmountsIn[3],
                        _maxAmountsIn[4],
                        minMintAmount,
                        true
                    );
            } else {
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
        return bytes('');
    }

    function _getRemoveLiquidityMethodData(
        address _poolAddress,
        uint256 ncoins,
        uint256[] calldata _minAmountsOut,
        uint256 _poolTokensIn
    ) private view returns (bytes memory) {
        // For meta remove everything in the stable coin
        if (curveMetaRegistry.isMeta(_poolAddress) || _poolAddress == cvxCRVPool) {
            return
                abi.encodeWithSignature(
                    'remove_liquidity_one_coin(uint256,int128,uint256)',
                    _poolTokensIn,
                    int128(0),
                    _minAmountsOut[0]
                );
        }
        if (ncoins == 2) {
            if (supportsUnderlyingParam[_poolAddress]) {
                return
                    abi.encodeWithSignature(
                        'remove_liquidity(uint256,uint256[2],bool)',
                        _poolTokensIn,
                        _minAmountsOut[0],
                        _minAmountsOut[1],
                        true
                    );
            } else {
                if (_poolAddress == palstkaave) {
                    return
                        abi.encodeWithSignature(
                            'remove_liquidity_one_coin(uint256,uint256,uint256)',
                            _poolTokensIn,
                            uint256(0),
                            _minAmountsOut[0]
                        );
                }
                return
                    abi.encodeWithSignature(
                        'remove_liquidity(uint256,uint256[2])',
                        _poolTokensIn,
                        _minAmountsOut[0],
                        _minAmountsOut[1]
                    );
            }
        }
        if (ncoins == 3) {
            if (supportsUnderlyingParam[_poolAddress]) {
                return
                    abi.encodeWithSignature(
                        'remove_liquidity(uint256,uint256[3],bool)',
                        _poolTokensIn,
                        _minAmountsOut[0],
                        _minAmountsOut[1],
                        _minAmountsOut[2],
                        true
                    );
            } else {
                return
                    abi.encodeWithSignature(
                        'remove_liquidity(uint256,uint256[3])',
                        _poolTokensIn,
                        _minAmountsOut[0],
                        _minAmountsOut[1],
                        _minAmountsOut[2]
                    );
            }
        }
        if (ncoins == 4) {
            if (supportsUnderlyingParam[_poolAddress]) {
                return
                    abi.encodeWithSignature(
                        'remove_liquidity(uint256,uint256[4],bool)',
                        _poolTokensIn,
                        _minAmountsOut[0],
                        _minAmountsOut[1],
                        _minAmountsOut[2],
                        _minAmountsOut[3],
                        true
                    );
            } else {
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
        }
        if (ncoins == 5) {
            if (supportsUnderlyingParam[_poolAddress]) {
                return
                    abi.encodeWithSignature(
                        'remove_liquidity(uint256,uint256[5],bool)',
                        _poolTokensIn,
                        _minAmountsOut[0],
                        _minAmountsOut[1],
                        _minAmountsOut[3],
                        _minAmountsOut[4],
                        true
                    );
            } else {
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
        return bytes('');
    }

    function _getLpToken(address _pool) internal view override returns (address) {
        // For Deposits & stable swaps that support it get the LP token, otherwise get the pool
        return curveMetaRegistry.getLpToken(_pool);
    }

    function _getUnderlyingAndRate(bytes calldata _pool, uint256 _i) internal view override returns (address, uint256) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        return curveMetaRegistry.getUnderlyingAndRate(poolAddress, _i);
    }

    function _getRewardTokens(
        address /* _pool */
    ) internal pure override returns (address[] memory) {
        address[] memory rewards = new address[](2);
        rewards[0] = CRV;
        rewards[1] = CVX;
        return rewards;
    }
}
