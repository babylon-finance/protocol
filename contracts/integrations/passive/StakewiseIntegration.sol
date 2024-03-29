// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IrETH2} from '../../interfaces/external/stakewise/IrETH2.sol';

/**
 * @title StakewiseIntegration
 * @author Babylon Finance Protocol
 *
 * StakewiseIntegration
 */
contract StakewiseIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State Variables ============ */

    IERC20 private constant sETH2 = IERC20(0xFe2e637202056d30016725477c5da089Ab0A043A);
    IrETH2 private constant rETH2 = IrETH2(0x20BC832ca081b91433ff6c17f85701B6e92486c5);
    // uint256 private constant INSTANT_LIMIT = 321e18; // 32 ETH
    // address private constant stakeWisePool = 0xc874b064f465bdd6411d45734b56fac750cda29a;

    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;

    // Address of Uniswap V3 SwapRouter contract
    address private constant swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // Addres of stakewise deposit contract
    address private constant STAKEWISE_DEPOSIT = 0xC874b064f465bdD6411D45734b56fac750Cda29A;
    // Address for the referrer
    address private constant HEART_ADDRESS = 0x51e6775b7bE2eA1d20cA02cFEeB04453366e72C8;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PassiveIntegration('stakewise', _controller) {}

    /* ============ Internal Functions ============ */

    function _getSpender(
        address, /* _asset */
        uint8 /* _op */
    ) internal pure override returns (address) {
        return swapRouter;
    }

    function _getInvestmentAsset(
        address /* _asset */
    ) internal pure override returns (address) {
        return address(0);
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _asset                          Address of the vault
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
        address, /* _asset */
        uint256, /* _investmentTokensOut */
        address, /* _tokenIn */
        uint256 _maxAmountIn
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
        // Buy sETH2 on univ3
        bytes memory methodData = abi.encodeWithSignature('stakeWithReferrer(address)', HEART_ADDRESS);
        return (STAKEWISE_DEPOSIT, _maxAmountIn, methodData);
    }

    /**
     * Return pre action calldata
     *
     * hparam  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * @param  _op                       Type of op
     * @param  _strategy                 Address of the strategy
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address _strategy,
        address, /* _asset */
        uint256, /* _amount */
        uint256 _op
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
        // Sell rETH2 on exit
        if (_op == 1) {
            bytes memory path = abi.encodePacked(address(rETH2), FEE_LOW, address(sETH2));
            uint256 rewardsBalance = rETH2.balanceOf(_strategy);
            // Enough rewards
            if (rewardsBalance > 2e16) {
                ISwapRouter.ExactInputParams memory params =
                    ISwapRouter.ExactInputParams(
                        path,
                        _strategy,
                        block.timestamp,
                        rewardsBalance,
                        rewardsBalance.preciseMul(98e16) // 2% slippage
                    );

                // Sell rETH2 on univ3
                bytes memory methodData =
                    abi.encodeWithSignature('exactInput((bytes,address,uint256,uint256,uint256))', params);
                return (swapRouter, 0, methodData);
            }
        }
        return (address(0), 0, bytes(''));
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _asset                          Address of the investment
     * @param  _investmentTokensIn             Amount of investment tokens to receive
     * hparam  _tokenOut                       Addresses of tokens to receive
     * hparam  _minAmountOut                   Amounts of investment tokens to receive
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getExitInvestmentCalldata(
        address _strategy,
        address, /* _asset */
        uint256 _investmentTokensIn,
        address, /* _tokenOut */
        uint256 _minAmountOut
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
        bytes memory path = abi.encodePacked(address(sETH2), FEE_MEDIUM, WETH);
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams(path, _strategy, block.timestamp, _investmentTokensIn, _minAmountOut);

        // Sell sETH2 on univ3
        bytes memory methodData =
            abi.encodeWithSignature('exactInput((bytes,address,uint256,uint256,uint256))', params);
        return (swapRouter, 0, methodData);
    }

    /**
     * Return post action calldata
     *
     * hparam  _strategy                 Address of the asset to deposit
     * hparam  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * hparam  _passiveOp                Type of op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPostActionCallData(
        address _strategy,
        address, /* _asset */
        uint256, /* _amount */
        uint256 _passiveOp
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
        if (_passiveOp == 1) {
            bytes memory methodData = abi.encodeWithSignature('withdraw(uint256)', IERC20(WETH).balanceOf(_strategy));
            return (WETH, 0, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    function _preActionNeedsApproval(
        address /* _asset */
    ) internal pure override returns (address) {
        return address(rETH2);
    }

    function _postActionNeedsApproval(
        address /* _asset */
    ) internal pure override returns (address) {
        return address(WETH);
    }

    function _getRewards(
        address _strategy,
        address //_investmentAddress
    ) internal view override returns (address, uint256) {
        return (address(rETH2), rETH2.balanceOf(_strategy));
    }
}
