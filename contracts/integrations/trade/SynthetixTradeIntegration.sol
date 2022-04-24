// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IBabController} from '../../interfaces/IBabController.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ISynthetix} from '../../interfaces/external/synthetix/ISynthetix.sol';
import {ISnxProxy} from '../../interfaces/external/synthetix/ISnxProxy.sol';
import {ISnxSynth} from '../../interfaces/external/synthetix/ISnxSynth.sol';
import {ISnxEtherWrapper} from '../../interfaces/external/synthetix/ISnxEtherWrapper.sol';
import {ISnxDepot} from '../../interfaces/external/synthetix/ISnxDepot.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {UniversalERC20} from '../../lib/UniversalERC20.sol';

import {TradeIntegration} from './TradeIntegration.sol';

/**
 * @title SynthetixTradeIntegration
 * @author Babylon Finance Protocol
 *
 * Synthethix trade integration
 */
contract SynthetixTradeIntegration is TradeIntegration {
    using SafeMath for uint256;
    using UniversalERC20 for IERC20;

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */
    /* ============ Constants ============ */

    address private constant curvesUSD = 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) TradeIntegration('synthetix_trade', _controller) {}

    /* ============ Internal Functions ============ */

    /**
     * Executes the trade through synthetix.
     *
     * @param _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     */
    function _getTradeCallData(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken
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
        (address sendTokenImpl, address receiveTokenImpl, uint256 realSendAmount) =
            _getTokens(_sendToken, _receiveToken, _sendQuantity, _strategy);
        require(sendTokenImpl != address(0) && receiveTokenImpl != address(0), 'Syntetix needs synth or DAI or USDC');
        if (sendTokenImpl == receiveTokenImpl) {
            return (address(0), 0, bytes(''));
        }
        bytes memory methodData =
            abi.encodeWithSignature(
                'exchange(bytes32,uint256,bytes32)',
                ISnxSynth(sendTokenImpl).currencyKey(),
                realSendAmount,
                ISnxSynth(receiveTokenImpl).currencyKey()
            );
        return (ISnxProxy(SNX).target(), 0, methodData);
    }

    /**
     * Return pre action calldata
     *
     * @param  _sendToken               Address of the asset to send
     * hparam  _receiveToken            Address of the asset to receive
     * @param  _sendQuantity            Amount of the asset to send
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address _sendToken,
        address, /* _receiveToken */
        uint256 _sendQuantity
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
        if (_sendToken == DAI) {
            bytes memory methodData =
                abi.encodeWithSignature('exchange(int128,int128,uint256,uint256)', 0, 3, _sendQuantity, 1);
            return (curvesUSD, 0, methodData);
        }
        if (_sendToken == USDC) {
            bytes memory methodData =
                abi.encodeWithSignature('exchange(int128,int128,uint256,uint256)', 0, 1, _sendQuantity, 1);
            return (curvesUSD, 0, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    /**
     * Return post action calldata
     *
     * hparam  _sendToken               Address of the asset to send
     * @param  _receiveToken            Address of the asset to receive
     * @param  _sendQuantity            Amount of the asset to send
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPostActionCallData(
        address, /* _sendToken */
        address _receiveToken,
        uint256 _sendQuantity
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
        // Burn sETH to WETH if needed
        if (_receiveToken == DAI) {
            bytes memory methodData =
                abi.encodeWithSignature('exchange(int128,int128,uint256,uint256)', 3, 0, _sendQuantity, 1);
            return (curvesUSD, 0, methodData);
        }
        if (_receiveToken == USDC) {
            bytes memory methodData =
                abi.encodeWithSignature('exchange(int128,int128,uint256,uint256)', 1, 0, _sendQuantity, 1);
            return (curvesUSD, 0, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @param _swapTarget          Address of the contract that will execute the swap
     * @return address             Address of the contract to approve tokens to
     */
    function _getSpender(address _swapTarget) internal pure override returns (address) {
        return _swapTarget;
    }

    /**
     * Returns the address to approve the pre action. This is the TokenTaker address
     *
     * @param _swapTarget          Address of the contract that will execute the swap
     * @return address             Address of the contract to approve tokens to
     */
    function _getPreApprovalSpender(address _swapTarget) internal pure override returns (address) {
        return _swapTarget;
    }

    /**
     * Returns the address to approve the post action. This is the TokenTaker address
     *
     * @param _swapTarget          Address of the contract that will execute the swap
     * @return address             Address of the contract to approve tokens to
     */
    function _getPostApprovalSpender(address _swapTarget) internal pure override returns (address) {
        return _swapTarget;
    }

    function _getPostActionToken(address _receiveToken) internal pure override returns (address) {
        if (_receiveToken == DAI || _receiveToken == USDC) {
            return sUSD;
        }
        return _receiveToken;
    }

    /* ============ Private Functions ============ */

    function _getTokens(
        address _sendToken,
        address _receiveToken,
        uint256, /* _sendQuantity */
        address _strategy
    )
        private
        view
        returns (
            address,
            address,
            uint256
        )
    {
        ISynthetix synthetix = ISynthetix(ISnxProxy(SNX).target());
        if (_sendToken == DAI || _sendToken == USDC) {
            _sendToken = sUSD;
        }
        if (_receiveToken == DAI || _receiveToken == USDC) {
            _receiveToken = sUSD;
        }
        address sendTokenImpl;
        address receiveTokenImpl;
        try synthetix.synths(stringToBytes32(ERC20(_sendToken).symbol())) returns (ISnxSynth _synth) {
            sendTokenImpl = address(_synth);
        } catch {
            sendTokenImpl = address(0);
        }
        try synthetix.synths(stringToBytes32(ERC20(_receiveToken).symbol())) returns (ISnxSynth _synth) {
            receiveTokenImpl = address(_synth);
        } catch {
            receiveTokenImpl = address(0);
        }
        return (sendTokenImpl, receiveTokenImpl, IERC20(_sendToken).universalBalanceOf(_strategy));
    }

    function stringToBytes32(string memory source) private pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
        assembly {
            result := mload(add(source, 32))
        }
    }
}
