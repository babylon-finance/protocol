// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {AddressArrayUtils} from '../../lib/AddressArrayUtils.sol';

import {ICustomIntegration} from '../../interfaces/ICustomIntegration.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';

import {BaseIntegration} from '../BaseIntegration.sol';

/**
 * @title CustomIntegration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with custom protocols
 */
abstract contract CustomIntegration is BaseIntegration, ReentrancyGuard, ICustomIntegration {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;
    using BytesLib for bytes;

    /* ============ Struct ============ */

    struct CustomInfo {
        IGarden garden; // Garden address
        IStrategy strategy; // Strategy address
        bytes data; // OpData 64 bytes each OpData
        address addressParam; // Address param
        address resultToken; // LP address
        uint256 resultTokensInTransaction; // Result tokens affected by this transaction
        uint256 resultTokensInStrategy; // Result tokens strategy balance
    }

    /* ============ Events ============ */

    event CustomEntered(address indexed _strategy, address indexed _garden, address _integration, address _resultToken);

    event CustomExited(address indexed _strategy, address indexed _garden, address _integration, address _resultToken);

    /* ============ Constants ============ */

    uint256 internal constant SLIPPAGE_ALLOWED = 5e16; // 5%

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
     * Enters a custom integration
     *
     * @param _strategy             Address of the strategy
     * @param _data                 OpData e.g. Address of the pool token to join
     * @param _resultTokensOut      Min amount of result tokens to receive
     * @param _tokensIn             Array of token addresses to deposit
     * @param _maxAmountsIn         Array of max token quantities to pull out from the garden
     */
    function enter(
        address _strategy,
        bytes calldata _data,
        uint256 _resultTokensOut,
        address[] calldata _tokensIn,
        uint256[] calldata _maxAmountsIn
    ) external override nonReentrant onlySystemContract {
        CustomInfo memory customInfo = _createCustomInfo(_strategy, _data, _resultTokensOut);
        _validatePreJoinCustomData(customInfo);

        // Pre actions
        (address targetAddressP, uint256 callValueP, bytes memory methodDataP) =
            _getPreActionCallData(_strategy, customInfo.addressParam, _resultTokensOut, 1);
        if (targetAddressP != address(0)) {
            // Approve spending of the pre action token
            (address approvalAsset, address spenderPre) = _preActionNeedsApproval(customInfo.addressParam, 0);
            if (approvalAsset != address(0)) {
                customInfo.strategy.invokeApprove(spenderPre, approvalAsset, 2 ^ (256 - 1));
            }
            // Invoke protocol specific call
            customInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }

        // Approve spending of the tokens
        if (_getSpender(_data, 0) != address(0)) {
            for (uint256 i = 0; i < _tokensIn.length; i++) {
                // No need to approve ETH
                if (_tokensIn[i] != address(0) && _tokensIn[i] != ETH_ADD_CURVE && _maxAmountsIn[i] > 0) {
                    customInfo.strategy.invokeApprove(_getSpender(_data, 0), _tokensIn[i], _maxAmountsIn[i]);
                }
            }
        }
        (address target, uint256 callValue, bytes memory methodData) =
            _getEnterCalldata(_strategy, _data, _resultTokensOut, _tokensIn, _maxAmountsIn);
        customInfo.strategy.invokeFromIntegration(target, callValue, methodData);
        customInfo.resultTokensInTransaction = IERC20(customInfo.resultToken)
            .balanceOf(address(customInfo.strategy))
            .sub(customInfo.resultTokensInStrategy);

        // Post actions
        (targetAddressP, callValueP, methodDataP) = _getPostActionCallData(
            _strategy,
            customInfo.addressParam,
            customInfo.resultTokensInTransaction,
            0
        );

        if (targetAddressP != address(0)) {
            // Approve spending of the post action token
            (address approvalAsset, address spenderPost) = _postActionNeedsApproval(customInfo.addressParam, 0);
            if (approvalAsset != address(0)) {
                customInfo.strategy.invokeApprove(spenderPost, approvalAsset, 2 ^ (256 - 1));
            }
            // Invoke protocol specific call
            customInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }

        _validatePostJoinCustomData(customInfo);
        emit CustomEntered(
            address(customInfo.strategy),
            address(customInfo.garden),
            address(this),
            customInfo.resultToken
        );
    }

    /**
     * Exits a custom integration.
     *
     * @param _strategy               Address of the strategy
     * @param _data                   Passed data e.g. PoolId or Address of the pool token to join + metadata
     * @param _resultTokensIn         Amount of result tokens to exchange for the underlying tokens
     * @param _tokensOut              Array of token addresses to withdraw
     * @param _minAmountsOut          Array of min token quantities to receive from the op
     */
    function exit(
        address _strategy,
        bytes calldata _data,
        uint256 _resultTokensIn,
        address[] calldata _tokensOut,
        uint256[] calldata _minAmountsOut
    ) external override nonReentrant onlySystemContract {
        CustomInfo memory customInfo = _createCustomInfo(_strategy, _data, _resultTokensIn);
        _validatePreExitCustomData(customInfo);

        // Pre actions
        (address targetAddressP, uint256 callValueP, bytes memory methodDataP) =
            _getPreActionCallData(_strategy, customInfo.addressParam, _resultTokensIn, 1);
        if (targetAddressP != address(0)) {
            // Approve spending of the pre action token
            (address approvalAsset, address spenderPre) = _preActionNeedsApproval(customInfo.addressParam, 1);
            if (approvalAsset != address(0)) {
                customInfo.strategy.invokeApprove(spenderPre, approvalAsset, 2 ^ (256 - 1));
            }
            // Invoke protocol specific call
            customInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }

        // Approve spending of the result token
        customInfo.strategy.invokeApprove(_getSpender(_data, 1), customInfo.resultToken, _resultTokensIn);
        (address target, uint256 callValue, bytes memory methodData) =
            _getExitCalldata(_strategy, _data, _resultTokensIn, _tokensOut, _minAmountsOut);
        customInfo.strategy.invokeFromIntegration(target, callValue, methodData);

        // Post actions
        (targetAddressP, callValueP, methodDataP) = _getPostActionCallData(
            _strategy,
            customInfo.addressParam,
            _resultTokensIn,
            1
        );

        if (targetAddressP != address(0)) {
            // Approve spending of the post action token
            (address approvalAsset, address spenderPost) = _postActionNeedsApproval(customInfo.addressParam, 1);
            if (approvalAsset != address(0)) {
                customInfo.strategy.invokeApprove(spenderPost, approvalAsset, 2 ^ (256 - 1));
            }
            // Invoke protocol specific call
            customInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }

        _validatePostExitCustomData(customInfo);

        emit CustomExited(
            address(customInfo.strategy),
            address(customInfo.garden),
            address(this),
            customInfo.resultToken
        );
    }

    /**
     * Checks whether data passed is valid
     *
     * @param _data                 OpData e.g. Pool address to check
     * @return bool                 True if the data is valid
     */
    function isValid(bytes memory _data) external view override returns (bool) {
        return _isValid(_data);
    }

    /**
     * Returns the actual address of the result token
     * @param _addr                    Address given as a param
     * @return address                 Address of the result token
     */
    function getResultToken(address _addr) external view override returns (address) {
        return _getResultToken(_addr);
    }

    function getRewardTokens(bytes calldata _data) external view override returns (address[] memory) {
        address inputAddr = BytesLib.decodeOpDataAddress(_data);
        return _getRewardTokens(inputAddr);
    }

    function getInputTokensAndWeights(
        bytes calldata /* _data */
    ) external view virtual override returns (address[] memory, uint256[] memory);

    function getOutputTokensAndMinAmountOut(bytes calldata _data, uint256 _liquidity)
        external
        view
        virtual
        override
        returns (address[] memory exitTokens, uint256[] memory _minAmountsOut);

    /* ============ Internal Functions ============ */

    /**
     * Create and return CustomInfo struct
     *
     * @param _strategy                      Address of the strategy
     * @param _data                          Data info e.g. Address of the pool + metadata
     * @param _resultTokensInTransaction     Number of result tokens involved
     *
     * return CustomInfo             Struct containing data for the integration
     */
    function _createCustomInfo(
        address _strategy,
        bytes calldata _data,
        uint256 _resultTokensInTransaction
    ) internal view returns (CustomInfo memory) {
        address add = BytesLib.decodeOpDataAddress(_data);
        CustomInfo memory customInfo;
        customInfo.resultToken = _getResultToken(add);
        customInfo.addressParam = add;
        customInfo.data = _data;
        customInfo.strategy = IStrategy(_strategy);
        customInfo.garden = IGarden(customInfo.strategy.garden());
        customInfo.resultTokensInStrategy = IERC20(customInfo.resultToken).balanceOf(_strategy);
        customInfo.resultTokensInTransaction = _resultTokensInTransaction;
        return customInfo;
    }

    /**
     * Validate pre custom enter data. Check data is valid, token quantity is valid.
     *
     * @param _customInfo               Struct containing custom information used in internal functions
     */
    function _validatePreJoinCustomData(CustomInfo memory _customInfo) internal view {
        require(_isValid(_customInfo.data), 'The passed data is not valid');
        require(_customInfo.resultTokensInTransaction > 0, 'Min result tokens to receive must be greater than 0');
    }

    /**
     * Validate pre custom exit data. Check data is valid, token quantity is valid.
     *
     * @param _customInfo               Struct containing custom information used in internal functions
     */
    function _validatePreExitCustomData(CustomInfo memory _customInfo) internal view {
        require(_isValid(_customInfo.data), 'The passed data is not valid');
        require(_customInfo.resultTokensInTransaction > 0, 'Result tokens to exchange must be greater than 0');
        require(
            _customInfo.resultTokensInStrategy >= _customInfo.resultTokensInTransaction,
            'The strategy does not have enough result tokens'
        );
    }

    /**
     * Validate post join custom data. Check data is valid, token quantity is valid.
     *
     * @param _customInfo               Struct containing custom information used in internal functions
     */
    function _validatePostJoinCustomData(CustomInfo memory _customInfo) internal view {
        require(
            (IERC20(_customInfo.resultToken).balanceOf(address(_customInfo.strategy)) >
                _customInfo.resultTokensInStrategy),
            'The strategy did not receive the result tokens'
        );
    }

    /**
     * Validate post exit custom data. Check data is valid, token quantity is valid.
     *
     * @param _customInfo               Struct containing custom information used in internal functions
     */
    function _validatePostExitCustomData(CustomInfo memory _customInfo) internal view {
        require(
            IERC20(_customInfo.resultToken).balanceOf(address(_customInfo.strategy)) ==
                _customInfo.resultTokensInStrategy - _customInfo.resultTokensInTransaction,
            'The strategy did not return the result tokens'
        );
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
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        );

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
     * Return post action calldata
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

    function _isValid(bytes memory _data) internal view virtual returns (bool);

    function _getSpender(
        bytes calldata, /* _data */
        uint8 /* _opType */
    ) internal view virtual returns (address);

    function _getResultToken(address _token) internal view virtual returns (address) {
        return _token;
    }

    function _preActionNeedsApproval(
        address, /* _asset */
        uint8 /* _customOp */
    ) internal view virtual returns (address, address) {
        return (address(0), address(0));
    }

    function _postActionNeedsApproval(
        address, /* _asset */
        uint8 /* _customOp */
    ) internal view virtual returns (address, address) {
        return (address(0), address(0));
    }

    function _getRewardTokens(
        address /* _data */
    ) internal view virtual returns (address[] memory) {
        return new address[](1);
    }
}
