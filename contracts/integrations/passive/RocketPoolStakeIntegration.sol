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
import {IRETH} from '../../interfaces/external/rocket-pool/IRETH.sol';
import {IRocketStorage} from '../../interfaces/external/rocket-pool/IRocketStorage.sol';

/**
 * @title RocketPoolStakeIntegration
 * @author Babylon Finance Protocol
 *
 * RocketPoolStakeIntegration
 */
contract RocketPoolStakeIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State Variables ============ */
    IRETH private constant RETH = IRETH(0xae78736Cd615f374D3085123A210448E74Fc6393);

    IRocketStorage immutable rocketStorage;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _rocketStorageAddress         Address of rocket storage
     */
    constructor(IBabController _controller, address _rocketStorageAddress)
        PassiveIntegration('rocket_pool', _controller)
    {
        rocketStorage = IRocketStorage(_rocketStorageAddress);
    }

    /* ============ Internal Functions ============ */

    function _getSpender(
        address, /* _asset */
        uint8 /* _op */
    ) internal view override returns (address) {
        return rocketStorage.getAddress(keccak256(abi.encodePacked('contract.address', 'rocketDepositPool')));
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
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address rocketPoolDeposit =
            rocketStorage.getAddress(keccak256(abi.encodePacked('contract.address', 'rocketDepositPool')));
        // Buy sETH2 on univ3
        bytes memory methodData = abi.encodeWithSignature('deposit()');
        return (rocketPoolDeposit, _maxAmountIn, methodData);
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
        // Encode method data for Garden to invoke
        bytes memory methodData =
            abi.encodeWithSignature(
                'trade(address,address,uint256,address,uint256)',
                _strategy,
                address(RETH),
                _investmentTokensIn,
                WETH,
                _minAmountOut
            );
        return (controller.masterSwapper(), 0, methodData);
        // Need to swap it via heart. No other way to do it
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

    function _postActionNeedsApproval(
        address /* _asset */
    ) internal pure override returns (address) {
        return address(WETH);
    }
}
