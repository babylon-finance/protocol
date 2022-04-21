// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';

import {IStrategy} from '../../interfaces/IStrategy.sol';
import {ITradeIntegration} from '../../interfaces/ITradeIntegration.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

import {BaseIntegration} from '../BaseIntegration.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {UniversalERC20} from '../../lib/UniversalERC20.sol';

/**
 * @title TradeIntegration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with trading protocols
 */
abstract contract TradeIntegration is BaseIntegration, ReentrancyGuard, ITradeIntegration {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;
    using PreciseUnitMath for uint256;
    using UniversalERC20 for IERC20;

    /* ============ Struct ============ */

    /* ============ Events ============ */

    /* ============ Constants ============ */

    uint24 internal constant FEE_LOW = 500;
    uint24 internal constant FEE_MEDIUM = 3000;
    uint24 internal constant FEE_HIGH = 10000;
    IUniswapV3Factory internal constant uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, IBabController _controller) BaseIntegration(_name, _controller) {}

    /* ============ External Functions ============ */

    /**
     * Executes a trade on a supported DEX.
     * @dev
     *
     * @param _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _minReceiveQuantity   Min units of wanted token to be received from the exchange
     */
    function trade(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity,
        address _hopToken
    ) public override nonReentrant onlySystemContract returns (uint256) {
        return _trade(IStrategy(_strategy), _sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity, _hopToken);
    }

    /**
     * Executes a trade on a supported DEX.
     * @dev
     *
     * @param _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _minReceiveQuantity   Min units of wanted token to be received from the exchange
     */
    function trade(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) external override nonReentrant onlySystemContract returns (uint256) {
        return _trade(IStrategy(_strategy), _sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity, address(0));
    }

    /* ============ Internal Functions ============ */

    function _preTradeAction(
        IStrategy _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) private {
        // Pre actions
        (address targetAddress, uint256 callValue, bytes memory methodData) =
            _getPreActionCallData(_sendToken, _receiveToken, _sendQuantity);
        if (targetAddress != address(0)) {
            // Invoke protocol specific call
            if (_getPreApprovalSpender(targetAddress) != address(0)) {
                _strategy.invokeApprove(_getPreApprovalSpender(targetAddress), _sendToken, _sendQuantity);
            }
            _strategy.invokeFromIntegration(targetAddress, callValue, methodData);
        }
        (targetAddress, callValue, methodData) = (address(0), 0, '');
    }

    function _tradeAction(
        IStrategy _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity,
        address _hopToken
    ) private {
        // Get spender address from exchange adapter and invoke approve for exact amount on sendToken
        (address targetAddress, uint256 callValue, bytes memory methodData) =
            _hopToken != address(0)
                ? _getTradeCallData(address(_strategy), _sendToken, _sendQuantity, _receiveToken, _hopToken)
                : _getTradeCallData(address(_strategy), _sendToken, _sendQuantity, _receiveToken);
        if (targetAddress != address(0)) {
            // Get spender address from exchange adapter and invoke approve for exact amount on sendToken
            _strategy.invokeApprove(_getSpender(targetAddress), _sendToken, _sendQuantity);
            _strategy.invokeFromIntegration(targetAddress, callValue, methodData);
        }
    }

    function _postTradeAction(
        IStrategy _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) private {
        // Post actions
        uint256 receiveTokenAmount =
            IERC20(_getPostActionToken(_receiveToken)).universalBalanceOf(address(_strategy));
        (address targetAddress, uint256 callValue, bytes memory methodData) =
            _getPostActionCallData(_sendToken, _receiveToken, receiveTokenAmount);
        if (targetAddress != address(0)) {
            // Invoke protocol specific call
            if (_getPostApprovalSpender(targetAddress) != address(0)) {
                _strategy.invokeApprove(
                    _getPostApprovalSpender(targetAddress),
                    _getPostActionToken(_receiveToken),
                    receiveTokenAmount
                );
            }
            // Invoke protocol specific call
            _strategy.invokeFromIntegration(targetAddress, callValue, methodData);
        }
    }

    /**
     * Executes a trade on a supported DEX.
     * @dev
     *
     * @param _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _minReceiveQuantity   Min units of wanted token to be received from the exchange
     */
    function _trade(
        IStrategy _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity,
        address _hopToken
    ) internal returns (uint256) {
        uint256 preSendQuantity = ERC20(_sendToken).balanceOf(address(_strategy));
        uint256 preReceiveQuantity = ERC20(_receiveToken).balanceOf(address(_strategy));

        require(_sendQuantity > 0, '_sendQuantity is 0');
        require(
            preSendQuantity >= _sendQuantity,
            string(
                abi.encodePacked(
                    'Strategy balance < send quantity: ',
                    Strings.toString(preSendQuantity),
                    ' ',
                    Strings.toString(_sendQuantity)
                )
            )
        );

        _preTradeAction(_strategy, _sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity);
        _tradeAction(_strategy, _sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity, _hopToken);
        _postTradeAction(_strategy, _sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity);

        uint256 receivedQuantity = ERC20(_receiveToken).balanceOf(address(_strategy)).sub(preReceiveQuantity);

        uint256 spentQuantity = preSendQuantity.sub(ERC20(_sendToken).balanceOf(address(_strategy)));

        // Unfortunatelly some protocols, e.g., Curve, leave dust and do not use
        // full send token quantity
        require(
            spentQuantity >= _sendQuantity.sub(1),
            string(abi.encodePacked('Partial trade diff: ', Strings.toString(_sendQuantity.sub(spentQuantity))))
        );
        require(
            receivedQuantity >= _minReceiveQuantity,
            string(
                abi.encodePacked(
                    'Slippage :',
                    Strings.toString(receivedQuantity),
                    ' ',
                    Strings.toString(_minReceiveQuantity)
                )
            )
        );

        return receivedQuantity;
    }

    /**
     * Return exchange calldata which is already generated from the exchange API
     *
     * hparam _strategy             Address of the strategy
     * hparam _sendToken            Address of the token to be sent to the exchange
     * hparam _sendQuantity         Units of reserve asset token sent to the exchange
     * hparam _receiveToken         Address of the token that will be received from the exchange
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getTradeCallData(
        address, /* _strategy */
        address, /* _sendToken */
        uint256, /* _sendQuantity */
        address, /* _receiveToken */
        address /* _hopToken */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        return (address(0), 0, bytes(''));
    }

    /**
     * Return exchange calldata which is already generated from the exchange API
     *
     * hparam _strategy             Address of the strategy
     * hparam _sendToken            Address of the token to be sent to the exchange
     * hparam _sendQuantity         Units of reserve asset token sent to the exchange
     * hparam _receiveToken         Address of the token that will be received from the exchange
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getTradeCallData(
        address, /* _strategy */
        address, /* _sendToken */
        uint256, /*_sendQuantity */
        address /* _receiveToken */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        );

    /**
     * Return pre action calldata
     *
     * hparam  _sendToken               Address of the asset to send
     * hparam  _receiveToken            Address of the asset to receive
     * hparam  _sendQuantity            Amount of the asset to send
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address, /* _sendToken */
        address, /* _receiveToken */
        uint256 /* _sendQuantity */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        return (address(0), 0, bytes(''));
    }

    /**
     * Return pre action calldata
     *
     * hparam  _sendToken               Address of the asset to send
     * hparam  _receiveToken            Address of the asset to receive
     * hparam  _sendQuantity            Amount of the asset to send
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPostActionCallData(
        address, /* _sendToken */
        address, /* _receiveToken */
        uint256 /* _sendQuantity */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        return (address(0), 0, bytes(''));
    }

    /**
     * Returns the address to approve source tokens to for trading. This is the TokenTaker address
     *
     * @param _swapTarget      Address of the contracts that executes the swap
     * @return address         Address of the contract to approve tokens to
     */
    function _getSpender(address _swapTarget) internal view virtual returns (address);

    /**
     * Returns the address to approve the pre action. This is the TokenTaker address
     *
     * hparam _swapTarget      Address of the contracts that executes the swap
     * @return address         Address of the contract to approve tokens to
     */
    function _getPreApprovalSpender(
        address /* _swapTarget */
    ) internal view virtual returns (address) {
        return address(0);
    }

    /**
     * Returns the address to approve the post action. This is the TokenTaker address
     *
     * hparam _swapTarget      Address of the contracts that executes the swap
     * @return address         Address of the contract to approve tokens to
     */
    function _getPostApprovalSpender(
        address /* _swapTarget */
    ) internal view virtual returns (address) {
        return address(0);
    }

    function _getPostActionToken(address _receiveToken) internal view virtual returns (address) {
        return _receiveToken;
    }
}
