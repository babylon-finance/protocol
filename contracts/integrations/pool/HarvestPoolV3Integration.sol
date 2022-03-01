// SPDX-License-Identifier: Apache-2.0



pragma solidity 0.8.9;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {PoolIntegration} from './PoolIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {IUniVaultStorage} from '../../interfaces/external/uniswap-v3/IUniVaultStorage.sol';
import {IUniswapViewer} from '../../interfaces/external/uniswap-v3/IUniswapViewer.sol';
import {IHarvestUniv3Pool} from '../../interfaces/external/harvest/IHarvestUniv3Pool.sol';

/**
 * @title Harvest Uni V3 Pool Integration
 * @author Babylon Finance Protocol
 *
 * HarvestUniV3 protocol integration
 */
contract HarvestPoolV3Integration is PoolIntegration {
    using PreciseUnitMath for uint256;
    using BytesLib for uint256;

    /* ============ State Variables ============ */

    /* ============ Constants ============ */
    uint256 private constant TOLERANCE = 150;
    IUniswapViewer private constant uniswapViewer = IUniswapViewer(0x25c81e249F913C94F263923421622bA731E6555b);

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PoolIntegration('harvest_univ3', _controller) {
        require(address(_controller) != address(0), 'invalid address');
    }

    /* ============ External Functions ============ */

    function getPoolTokens(
        bytes calldata _pool,
        bool /* forNAV */
    ) public view override returns (address[] memory) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        address[] memory result = new address[](2);
        result[0] = IHarvestUniv3Pool(poolAddress).token0();
        result[1] = IHarvestUniv3Pool(poolAddress).token1();
        return result;
    }

    function poolWeightsByPrice(
        bytes calldata /* _pool */
    ) external pure override returns (bool) {
        return true;
    }

    function getPoolWeights(bytes calldata _pool) external view override returns (uint256[] memory) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        uint256[] memory result = new uint256[](2);
        uint256 uniswapPosId = IUniVaultStorage(IHarvestUniv3Pool(poolAddress).getStorage()).posId();
        (result[0], result[1]) = uniswapViewer.getAmountsForPosition(uniswapPosId);
        return result;
    }

    function getPricePerShare(bytes calldata _pool) external view override returns (uint256) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        return IHarvestUniv3Pool(poolAddress).getPricePerFullShare();
    }

    function getPoolTokensOut(
        bytes calldata, /* _pool */
        address, /* _poolToken */
        uint256 /* _maxAmountsIn */
    ) external pure override returns (uint256) {
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
        uint256 totalSupply = IHarvestUniv3Pool(poolAddress).totalSupply();
        uint256[] memory result = new uint256[](2);
        result[0] = IERC20(IHarvestUniv3Pool(poolAddress).token0())
            .balanceOf(poolAddress)
            .mul(_liquidity)
            .div(totalSupply)
            .preciseMul(1e18 - SLIPPAGE_ALLOWED);
        result[1] = IERC20(IHarvestUniv3Pool(poolAddress).token1())
            .balanceOf(poolAddress)
            .mul(_liquidity)
            .div(totalSupply)
            .preciseMul(1e18 - SLIPPAGE_ALLOWED);
        return result;
    }

    /* ============ Internal Functions ============ */

    function _isPool(bytes memory _pool) internal view override returns (bool) {
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 12);
        return IHarvestUniv3Pool(poolAddress).totalSupply() > 0;
    }

    function _getSpender(bytes calldata _pool) internal pure override returns (address) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        return poolAddress;
    }

    /**
     * Return join pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * @param  _pool                     OpData e.g. Address of the pool
     * hparam  _poolTokensOut            Amount of pool tokens to send
     * @param  _tokensIn                 Addresses of tokens to send to the pool
     * @param  _maxAmountsIn             Amounts of tokens to send to the pool
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getJoinPoolCalldata(
        address, /* _strategy */
        bytes calldata _pool,
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
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        uint256 sqrtPriceX96 = IHarvestUniv3Pool(poolAddress).getSqrtPriceX96();
        return (poolAddress, 0, _getMethodData(sqrtPriceX96, _maxAmountsIn));
    }

    function _getMethodData(uint256 sqrtPriceX96, uint256[] calldata _maxAmountsIn)
        private
        pure
        returns (bytes memory)
    {
        return
            abi.encodeWithSignature(
                'deposit(uint256,uint256,bool,uint256,uint256,uint256,uint256,uint160)',
                _maxAmountsIn[0], //amount0
                _maxAmountsIn[1], // amount1
                false, // zap
                sqrtPriceX96, // sqrtRatioX96
                TOLERANCE, //tolerance
                0, // maxamountzap0
                0, // maxamountzap1
                uint160(sqrtPriceX96) // maxprice
            );
    }

    /**
     * Return exit pool calldata which is already generated from the pool API
     *
     * hparam  _strategy                 Address of the strategy
     * @param  _pool                     OpData e.g. Address of the pool
     * @param  _poolTokensIn             Amount of pool tokens to liquidate
     * @param  _tokensOut                Addresses of tokens to receive
     * @param  _minAmountsOut            Amounts of tokens to receive
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getExitPoolCalldata(
        address, /* _strategy */
        bytes memory _pool,
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
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 12);
        uint256 sqrtPriceX96 = IHarvestUniv3Pool(poolAddress).getSqrtPriceX96();
        require(_tokensOut.length == 2, 'Two tokens required');
        require(_minAmountsOut.length == 2, 'Two amounts required');
        // Encode method data for Garden to invoke
        bytes memory methodData =
            abi.encodeWithSignature(
                'withdraw(uint256,bool,bool,uint256,uint256)',
                _poolTokensIn,
                true,
                true,
                sqrtPriceX96,
                TOLERANCE
            );

        return (poolAddress, 0, methodData);
    }
}
