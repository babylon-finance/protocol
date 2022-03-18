// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IGammaDeposit} from '../../interfaces/external/gamma/IGammaDeposit.sol';
import {IHypervisor} from '../../interfaces/IHypervisor.sol';
import {PoolIntegration} from './PoolIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

/**
 * @title Gamma Uni V3 Pool Integration
 * @author Babylon Finance Protocol
 *
 * Gamma protocol integration
 */
contract GammaIntegration is PoolIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using BytesLib for uint256;

    /* ============ State Variables ============ */

    /* ============ Constants ============ */
    IGammaDeposit private constant depositProxy = IGammaDeposit(0xF5BFA20F4A77933fEE0C7bB7F39E7642A070d599);

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PoolIntegration('gamma', _controller) {
        require(address(_controller) != address(0), 'invalid address');
    }

    /* ============ External Functions ============ */

    function getPoolTokens(
        bytes calldata _pool,
        bool /* forNAV */
    ) public view override returns (address[] memory) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        address[] memory result = new address[](2);
        result[0] = IUniswapV3Pool(poolAddress).token0();
        result[1] = IUniswapV3Pool(poolAddress).token1();
        return result;
    }

    function poolWeightsByPrice(
        bytes calldata /* _pool */
    ) external pure override returns (bool) {
        return true;
    }

    function getPoolWeights(bytes calldata _pool) external view override returns (uint256[] memory) {
        address visorAddress = BytesLib.decodeOpDataAddress(_pool);
        uint256[] memory result = new uint256[](2);
        (result[0], result[1]) = IHypervisor(visorAddress).getTotalAmounts();
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

    function getPoolMinAmountsOut(bytes calldata _pool, uint256 _liquidity)
        external
        view
        override
        returns (uint256[] memory _minAmountsOut)
    {
        address visorAddress = BytesLib.decodeOpDataAddress(_pool);
        uint256 totalSupply = IHypervisor(visorAddress).totalSupply();
        address pool = IHypervisor(visorAddress).pool();
        (uint256 amount0, uint256 amount1) = IHypervisor(visorAddress).getTotalAmounts();
        uint256[] memory result = new uint256[](2);
        result[0] = amount0.mul(_liquidity).div(totalSupply).preciseMul(1e18 - SLIPPAGE_ALLOWED);
        result[1] = amount1.mul(_liquidity).div(totalSupply).preciseMul(1e18 - SLIPPAGE_ALLOWED);
        return result;
    }

    /* ============ Internal Functions ============ */

    function _isPool(bytes memory _pool) internal view override returns (bool) {
        address visorAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 12);
        return IHypervisor(visorAddress).totalSupply() > 0;
    }

    function _getSpender(bytes calldata _pool, uint8 _opType) internal pure override returns (address) {
        if (_opType == 0) {
            return address(depositProxy);
        }
        return BytesLib.decodeOpDataAddress(_pool);
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
        address _strategy,
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
        address visorAddress = BytesLib.decodeOpDataAddress(_pool);

        bytes memory methodData =
            abi.encodeWithSignature(
                'deposit(uint256,uint256,address,address)',
                _maxAmountsIn[0], //amount0
                _maxAmountsIn[1], // amount1
                _strategy,
                IHypervisor(visorAddress).pool()
            );
        return (address(depositProxy), 0, methodData);
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
        address _strategy,
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
        address visorAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 12);
        require(_tokensOut.length == 2, 'Two tokens required');
        require(_minAmountsOut.length == 2, 'Two amounts required');
        // Encode method data for Garden to invoke
        bytes memory methodData =
            abi.encodeWithSignature('withdraw(uint256,address,address)', _poolTokensIn, _strategy, _strategy);
        return (visorAddress, 0, methodData);
    }
}
