// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;
pragma abicoder v1;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IStETH} from '../../interfaces/external/lido/IStETH.sol';
import {IWstETH} from '../../interfaces/external/lido/IWstETH.sol';

/**
 * @title LidoStakeIntegration
 * @author Babylon Finance Protocol
 *
 * Lido Integration
 */
contract LidoStakeIntegration is PassiveIntegration {
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State Variables ============ */

    IStETH private constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH private constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address private constant curveSteth = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PassiveIntegration('lidostaking', _controller) {}

    /* ============ Internal Functions ============ */

    function _getSpender(address _asset, uint8 _op) internal pure override returns (address) {
        if (_op == 1) {
            return curveSteth;
        }
        return _asset;
    }

    function _getExpectedShares(address _asset, uint256 _amount) internal view override returns (uint256) {
        uint256 shares = stETH.getSharesByPooledEth(_amount);
        if (_asset == address(wstETH)) {
            return wstETH.getWstETHByStETH(shares);
        }
        return shares;
    }

    function _getPricePerShare(address _asset) internal view override returns (uint256) {
        uint256 shares = 1e18;
        // wrapped steth
        if (_asset == address(wstETH)) {
            shares = wstETH.getStETHByWstETH(shares);
        }
        return stETH.getPooledEthByShares(shares);
    }

    function _getInvestmentAsset(
        address /* _asset */
    ) internal pure override returns (address) {
        // Both take ETH
        return address(0);
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _asset                          Address of the vault
     * hparam  _investmentTokensOut            Amount of investment tokens to send
     * hparam  _tokenIn                        Addresses of tokens to send to the investment
     * @param  _maxAmountIn                    Amounts of tokens to send to the investment
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getEnterInvestmentCalldata(
        address, /* _strategy */
        address _asset,
        uint256, /* _investmentTokensOut */
        address, /* _tokenIn */
        uint256 _maxAmountIn
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
        bytes memory methodData;
        if (_asset == address(stETH)) {
            methodData = abi.encodeWithSignature('submit(address)', controller.treasury());
        } else {
            // wstETH is just a raw transfer and does both
            methodData = bytes('');
        }

        return (_asset, _maxAmountIn, methodData);
    }

    /**
     * Return pre action calldata
     *
     * @param  _asset                    Address of the asset to deposit
     * @param  _amount                   Amount of the token to deposit
     * @param  _op                       Type of op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address _asset,
        uint256 _amount,
        uint256 _op,
        address /* _strategy */
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
        if (_op == 1 && _asset == address(wstETH)) {
            // Exit 0p && wsteth need to unwrap before redeeming
            bytes memory methodData = abi.encodeWithSignature('unwrap(uint256)', _amount);
            return (address(wstETH), 0, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _asset              Address of the investment
     * @param  _investmentTokensIn             Amount of investment tokens to receive
     * hparam  _tokenOut                       Addresses of tokens to receive
     * hparam  _minAmountOut                   Amounts of investment tokens to receive
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getExitInvestmentCalldata(
        address, /* _strategy */
        address, /* _asset */
        uint256 _investmentTokensIn,
        address, /* _tokenOut */
        uint256 /* _minAmountOut */
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
        bytes memory methodData =
            abi.encodeWithSignature('exchange(int128,int128,uint256,uint256)', 1, 0, _investmentTokensIn, 1);
        // Need to swap via curve. Lido doesn't implement withdraw yet
        return (curveSteth, 0, methodData);
    }

    function _preActionNeedsApproval() internal pure override returns (bool) {
        return true;
    }

    function _getAssetAfterExitPreAction(
        address /* _asset */
    ) internal pure override returns (address) {
        return address(stETH);
    }
}
