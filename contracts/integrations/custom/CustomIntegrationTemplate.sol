// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {ICurveMetaRegistry} from '../../interfaces/ICurveMetaRegistry.sol';
import {CustomIntegration} from './CustomIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {ControllerLib} from '../../lib/ControllerLib.sol';

/**
 * @title CustomIntegrationSample
 * @author Babylon Finance Protocol
 *
 * Custom integration template
 */
contract CustomIntegrationTemplate is CustomIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using BytesLib for uint256;
    using ControllerLib for IBabController;

    /* ============ State Variables ============ */

    /* Add State variables here if any. Pass to the constructor */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) CustomIntegration('**test_sample_change_me**', _controller) {
        require(address(_controller) != address(0), 'invalid address');
    }

    /* =============== Internal Functions ============== */

    /**
     * Whether or not the data provided is valid
     *
     * hparam  _data                     Data provided
     * @return bool                      True if the data is correct
     */
    function _isValid(
        bytes memory /* _data */
    ) internal pure override returns (bool) {
        /** FILL THIS */
        return true;
    }

    /**
     * Which address needs to be approved (IERC-20) for the input tokens.
     *
     * hparam  _data                     Data provided
     * hparam  _opType                   O for enter, 1 for exit
     * @return address                   Address to approve the tokens to
     */
    function _getSpender(
        bytes calldata, /* _data */
        uint8 /* _opType */
    ) internal pure override returns (address) {
        /** FILL THIS */
        return address(0);
    }

    /**
     * The address of the IERC-20 token obtained after entering this operation
     *
     * @param  _token                     Address provided as param
     * @return address                    Address of the resulting lp token
     */
    function _getResultToken(address _token) internal pure override returns (address) {
        /** FILL THIS */
        return _token;
    }

    /**
     * Return enter custom calldata
     *
     * hparam  _strategy                 Address of the strategy
     * hparam  _data                     OpData e.g. Address of the pool
     * hparam  _resultTokensOut          Amount of result tokens to send
     * hparam  _tokensIn                 Addresses of tokens to send to spender to enter
     * hparam  _maxAmountsIn             Amounts of tokens to send to spender
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getEnterCalldata(
        address, /* _strategy */
        bytes calldata, /* _data */
        uint256, /* _resultTokensOut */
        address[] calldata, /* _tokensIn */
        uint256[] calldata /* _maxAmountsIn */
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
        /** FILL THIS */
        return (address(0), 0, bytes(''));
    }

    /**
     * Return exit custom calldata
     *
     * hparam  _strategy                 Address of the strategy
     * hparam  _data                     OpData e.g. Address of the pool
     * hparam  _resultTokensIn           Amount of result tokens to send
     * hparam  _tokensOut                Addresses of tokens to receive
     * hparam  _minAmountsOut            Amounts of input tokens to receive
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getExitCalldata(
        address, /* _strategy */
        bytes calldata, /* _data */
        uint256, /* _resultTokensIn */
        address[] calldata, /* _tokensOut */
        uint256[] calldata /* _minAmountsOut */
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
        /** FILL THIS */
        return (address(0), 0, bytes(''));
    }

    /**
     * The list of addresses of the IERC-20 tokens mined as rewards during the strategy
     *
     * hparam  _data                      Address provided as param
     * @return address[] memory           List of reward token addresses
     */
    function _getRewardTokens(
        address /* _data */
    ) internal pure override returns (address[] memory) {
        return new address[](1);
    }

    /* ============ External Functions ============ */

    /**
     * The tokens to be purchased by the strategy on enter according to the weights.
     * Weights must add up to 1e18 (100%)
     *
     * hparam  _data                      Address provided as param
     * @return _inputTokens               List of input tokens to buy
     * @return _inputWeights              List of weights for the tokens to buy
     */
    function getInputTokensAndWeights(
        bytes calldata /* _data */
    ) external pure override returns (address[] memory _inputTokens, uint256[] memory _inputWeights) {
        /** FILL THIS */
        return (new address[](1), new uint256[](1));
    }

    /**
     * The tokens to be received on exit.
     *
     * hparam  _strategy                  Strategy address
     * hparam  _data                      Bytes data
     * hparam  _liquidity                 Number with the amount of result tokens to exit
     * @return exitTokens                 List of output tokens to receive on exit
     * @return _minAmountsOut             List of min amounts for the output tokens to receive
     */
    function getOutputTokensAndMinAmountOut(
        address, /* _strategy */
        bytes calldata, /* _data */
        uint256 /* _liquidity */
    ) external pure override returns (address[] memory exitTokens, uint256[] memory _minAmountsOut) {
        /** FILL THIS */
        return (new address[](1), new uint256[](1));
    }

    /**
     * The price of the result token based on the asset received on enter
     *
     * hparam  _data                      Bytes data
     * hparam  _tokenDenominator          Token we receive the capital in
     * @return uint256                    Amount of result tokens to receive
     */
    function getPriceResultToken(
        bytes calldata, /* _data */
        address /* _tokenDenominator */
    ) external pure override returns (uint256) {
        /** FILL THIS */
        return 0;
    }

    /**
     * (OPTIONAL). Return pre action calldata
     *
     * hparam _strategy                  Address of the strategy
     * hparam  _asset                    Address param
     * hparam  _amount                   Amount
     * hparam  _customOp                 Type of Custom op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address, /* _strategy */
        address, /* _asset */
        uint256, /* _amount */
        uint256 /* _customOp */
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
        return (address(0), 0, bytes(''));
    }

    /**
     * (OPTIONAL) Return post action calldata
     *
     * hparam  _strategy                 Address of the strategy
     * hparam  _asset                    Address param
     * hparam  _amount                   Amount
     * hparam  _customOp                 Type of op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPostActionCallData(
        address, /* _strategy */
        address, /* _asset */
        uint256, /* _amount */
        uint256 /* _customOp */
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
        return (address(0), 0, bytes(''));
    }

    /**
     * (OPTIONAL). Whether or not the pre action needs an approval.
     * Only makes sense if _getPreActionCallData is filled.
     *
     * hparam  _asset                     Asset passed as param
     * hparam  _tokenDenominator          0 for enter, 1 for exit
     * @return address                    Address of the asset to approve
     * @return address                    Address to approve
     */
    function _preActionNeedsApproval(
        address, /* _asset */
        uint8 /* _customOp */
    ) internal pure override returns (address, address) {
        return (address(0), address(0));
    }

    /**
     * (OPTIONAL). Whether or not the post action needs an approval
     * Only makes sense if _getPostActionCallData is filled.
     *
     * hparam  _asset                     Asset passed as param
     * hparam  _tokenDenominator          0 for enter, 1 for exit
     * @return address                    Address of the asset to approve
     * @return address                    Address to approve
     */
    function _postActionNeedsApproval(
        address, /* _asset */
        uint8 /* _customOp */
    ) internal pure override returns (address, address) {
        return (address(0), address(0));
    }
}
