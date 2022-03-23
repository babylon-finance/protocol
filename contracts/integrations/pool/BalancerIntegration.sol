// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {PoolIntegration} from './PoolIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
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
    using BytesLib for uint256;

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
        require(address(_controller) != address(0) && _coreFactoryAddress != address(0), 'invalid address');
        coreFactory = IBFactory(_coreFactoryAddress);
    }

    /* ============ External Functions ============ */

    function getPoolTokens(
        bytes calldata _pool,
        bool /* forNAV */
    ) public view override returns (address[] memory) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        return IBPool(poolAddress).getCurrentTokens();
    }

    function getPoolWeights(bytes calldata _pool) external view override returns (uint256[] memory) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        address[] memory poolTokens = IBPool(poolAddress).getCurrentTokens();
        uint256[] memory result = new uint256[](poolTokens.length);
        for (uint8 i = 0; i < poolTokens.length; i++) {
            result[i] = IBPool(poolAddress).getNormalizedWeight(poolTokens[i]);
        }
        return result;
    }

    function getPoolTokensOut(
        bytes calldata _pool,
        address _poolToken,
        uint256 _maxAmountsIn
    ) external view override returns (uint256) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        uint256 tokenBalance = IBPool(poolAddress).getBalance(_poolToken);
        return IBPool(poolAddress).totalSupply().preciseMul(_maxAmountsIn.preciseDiv(tokenBalance));
    }

    function getPoolMinAmountsOut(bytes calldata _pool, uint256 _liquidity)
        external
        view
        override
        returns (uint256[] memory _minAmountsOut)
    {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        uint256 lpTokensTotalSupply = IBPool(poolAddress).totalSupply();
        address[] memory poolTokens = IBPool(poolAddress).getCurrentTokens();
        uint256[] memory result = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            result[i] = IERC20(poolTokens[i])
                .balanceOf(poolAddress)
                .mul(_liquidity)
                .div(lpTokensTotalSupply)
                .preciseMul(1e18 - SLIPPAGE_ALLOWED);
        }
        return result;
    }

    /* ============ Internal Functions ============ */

    function _isPool(bytes memory _pool) internal view override returns (bool) {
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 12);
        return coreFactory.isBPool(poolAddress);
    }

    function _getSpender(
        bytes calldata _pool,
        uint8 /* _opType */
    ) internal pure override returns (address) {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
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
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address poolAddress = BytesLib.decodeOpDataAddress(_pool);
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('joinPool(uint256,uint256[])', _poolTokensOut, _maxAmountsIn);

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
        pure
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address poolAddress = BytesLib.decodeOpDataAddressAssembly(_pool, 12);
        require(_poolTokensIn > 0, '_poolTokensIn has to not 0');
        require(_minAmountsOut.length > 1, 'Has to provide _minAmountsOut');
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('exitPool(uint256,uint256[])', _poolTokensIn, _minAmountsOut);

        return (poolAddress, 0, methodData);
    }
}
