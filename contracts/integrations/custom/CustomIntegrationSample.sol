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
 * Sample integration
 */
contract CustomIntegrationSample is CustomIntegration {
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

    /* ============ External Functions ============ */

    function getInputTokensAndWeights(
        bytes calldata /* _data */
    ) external view override returns (address[] memory, uint256[] memory) {
        /*
      *
      FILL THIS
      */
        return (new address[](1), new uint256[](1));
    }

    function getOutputTokensAndMinAmountOut(
        bytes calldata, /* _data */
        uint256 /* _liquidity */
    ) external view override returns (address[] memory exitTokens, uint256[] memory _minAmountsOut) {
        /*
      *
      FILL THIS
      */
        return (new address[](1), new uint256[](1));
    }

    function getAmountResultToken(
        bytes calldata _data,
        address _tokenAddress,
        uint256 _maxAmountsIn
    ) external view override returns (uint256) {
        /*
      *
      FILL THIS
      */
        return 0;
    }

    /* =============== Internal Functions ============== */

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
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        /*
      *
      FILL THIS
      */
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
        bytes memory, /* _data */
        uint256, /* _resultTokensIn */
        address[] calldata, /* _tokensOut */
        uint256[] calldata /* _minAmountsOut */
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
        /*
          *
          FILL THIS
          */
        return (address(0), 0, bytes(''));
    }

    /**
     * Whether or not the data provided is valid
     *
     * @param  _data                     Data provided
     * @return bool                      True if the data is correct
     */
    function _isValid(bytes memory _data) internal view override returns (bool) {
        /*
      *
      FILL THIS
      */
        return true;
    }

    /**
     * Which address needs to be approved (IERC-20) for the input tokens.
     *
     * @param  _data                     Data provided
     * @return address                   Address to approve the tokens to
     */
    function _getSpender(
        bytes calldata, /* _data */
        uint8 /* _opType */
    ) internal view override returns (address) {
        /*
      *
      FILL THIS
      */
        return address(0);
    }

    /**
     * The address of the IERC-20 token obtained after entering this operation
     *
     * @param  _token                     Address provided as param
     * @return address                    Address of the resulting lp token
     */
    function _getResultToken(address _token) internal view override returns (address) {
        /*
      *
      FILL THIS
      */
        return _token;
    }

    /**
     * The list of addresses of the IERC-20 tokens mined as rewards during the strategy
     *
     * @param  _data                      Address provided as param
     * @return address[]                  List of reward token addresses
     */
    function _getRewardTokens(
        address /* _data */
    ) internal view override returns (address[] memory) {
        return new address[](1);
    }
}
