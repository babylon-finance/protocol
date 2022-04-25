// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import {IPassiveIntegration} from '../../interfaces/IPassiveIntegration.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

import {BaseIntegration} from '../BaseIntegration.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';

/**
 * @title PassiveIntegration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with passive investments like Yearn, Indexed
 */
abstract contract PassiveIntegration is BaseIntegration, ReentrancyGuard, IPassiveIntegration {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;

    /* ============ Struct ============ */

    struct InvestmentInfo {
        IStrategy strategy; // Strategy address
        IGarden garden; // Garden address
        address investment; // Investment address
        uint256 totalSupply; // Total Supply of the investment
        uint256 investmentTokensInTransaction; // Investment tokens affected by this transaction
        uint256 investmentTokensInStrategy; // Investment tokens garden balance
        uint256 limitDepositTokenQuantity; // Limit deposit/withdrawal token amount
    }

    /* ============ Events ============ */

    event InvestmentEntered(
        address indexed garden,
        address indexed strategy,
        address indexed investment,
        address tokenIn,
        uint256 investmentTokensOut
    );

    event InvestmentExited(
        address indexed garden,
        address indexed strategy,
        address indexed investment,
        uint256 investmentTokensOut
    );

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
     * Deposits tokens into an investment
     *
     * @param _strategy                   Address of the strategy
     * @param _investmentAddress          Address of the investment token to join
     * @param _investmentTokensOut        Min amount of investment tokens to receive
     * @param _tokenIn                    Token address to deposit
     * @param _maxAmountIn                Max amount of the token to deposit
     */
    function enterInvestment(
        address _strategy,
        address _investmentAddress,
        uint256 _investmentTokensOut,
        address _tokenIn,
        uint256 _maxAmountIn
    ) external override nonReentrant onlySystemContract {
        InvestmentInfo memory investmentInfo =
            _createInvestmentInfo(_strategy, _investmentAddress, _investmentTokensOut, _tokenIn, _maxAmountIn);
        _validatePreJoinInvestmentData(investmentInfo);

        // Pre actions
        (address targetAddressP, uint256 callValueP, bytes memory methodDataP) =
            _getPreActionCallData(_strategy, _investmentAddress, _maxAmountIn, 0);
        if (targetAddressP != address(0)) {
            // Approve spending of the pre action token
            address approvalAsset = _preActionNeedsApproval(_investmentAddress);
            if (approvalAsset != address(0)) {
                uint256 bal = IERC20(approvalAsset).balanceOf(_strategy);
                investmentInfo.strategy.invokeApprove(_getSpender(_investmentAddress, 0), approvalAsset, bal);
            }
            // Invoke protocol specific call
            investmentInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }

        // Approve spending of the token
        if (_tokenIn != address(0)) {
            investmentInfo.strategy.invokeApprove(_getSpender(_investmentAddress, 0), _tokenIn, _maxAmountIn);
            address extraApproval = _getExtraAssetToApproveEnter(_investmentAddress);
            if (extraApproval != address(0)) {
              investmentInfo.strategy.invokeApprove(_getSpender(_investmentAddress, 0), extraApproval, IERC20(extraApproval).balanceOf(_strategy));
            }
        }

        (address targetInvestment, uint256 callValue, bytes memory methodData) =
            _getEnterInvestmentCalldata(_strategy, _investmentAddress, _investmentTokensOut, _tokenIn, _maxAmountIn);
        investmentInfo.strategy.invokeFromIntegration(targetInvestment, callValue, methodData);

        // Post actions
        (targetAddressP, callValueP, methodDataP) = _getPostActionCallData(
            _strategy,
            _investmentAddress,
            _investmentTokensOut,
            0
        );

        if (targetAddressP != address(0)) {
            // Approve spending of the post action token
            address approvalAsset = _postActionNeedsApproval(_investmentAddress);
            if (approvalAsset != address(0)) {
                uint256 bal = IERC20(approvalAsset).balanceOf(_strategy);
                investmentInfo.strategy.invokeApprove(_getSpender(_investmentAddress, 1), approvalAsset, bal);
            }
            // Invoke protocol specific call
            investmentInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }

        _validatePostEnterInvestmentData(investmentInfo);

        emit InvestmentEntered(
            address(investmentInfo.garden),
            address(investmentInfo.strategy),
            _investmentAddress,
            _tokenIn,
            _investmentTokensOut
        );
    }

    /**
     * Exits an outside passive investment
     *
     * @param _strategy                   Address of the strategy
     * @param _investmentAddress          Address of the investment token to exit
     * @param _investmentTokenIn          Quantity of investment tokens to return
     * @param _tokenOut                   Token address to withdraw
     * @param _minAmountOut               Min token quantities to receive from the investment
     */
    function exitInvestment(
        address _strategy,
        address _investmentAddress,
        uint256 _investmentTokenIn,
        address _tokenOut,
        uint256 _minAmountOut
    ) external override nonReentrant onlySystemContract {
        InvestmentInfo memory investmentInfo =
            _createInvestmentInfo(_strategy, _investmentAddress, _investmentTokenIn, _tokenOut, _minAmountOut);
        _validatePreExitInvestmentData(investmentInfo);

        // Pre actions
        (address targetAddressP, uint256 callValueP, bytes memory methodDataP) =
            _getPreActionCallData(_strategy, _investmentAddress, _investmentTokenIn, 1);

        if (targetAddressP != address(0)) {
            // Approve spending of the pre action token
            address approvalAsset = _preActionNeedsApproval(_investmentAddress);
            if (approvalAsset != address(0)) {
                investmentInfo.strategy.invokeApprove(
                    _getSpender(_investmentAddress, 1),
                    approvalAsset,
                    IERC20(approvalAsset).balanceOf(_strategy)
                );
            }
            // Invoke protocol specific call
            investmentInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
            _investmentAddress = _getAssetAfterExitPreAction(_investmentAddress);
            // BUG: Does not respect _investmentTokenIn/percentage
            _investmentTokenIn = IERC20(_investmentAddress).balanceOf(_strategy);
        }

        // Approve spending of the investment token
        investmentInfo.strategy.invokeApprove(
            _getSpender(_investmentAddress, 1),
            _investmentAddress,
            _investmentTokenIn
        );
        (address targetInvestment, uint256 callValue, bytes memory methodData) =
            _getExitInvestmentCalldata(_strategy, _investmentAddress, _investmentTokenIn, _tokenOut, _minAmountOut);
        investmentInfo.strategy.invokeFromIntegration(targetInvestment, callValue, methodData);

        // Post actions
        (targetAddressP, callValueP, methodDataP) = _getPostActionCallData(
            _strategy,
            _investmentAddress,
            _investmentTokenIn,
            1
        );

        if (targetAddressP != address(0)) {
            // Approve spending of the post action token
            address approvalAsset = _postActionNeedsApproval(_investmentAddress);
            if (approvalAsset != address(0)) {
                uint256 bal = IERC20(approvalAsset).balanceOf(_strategy);
                investmentInfo.strategy.invokeApprove(_getSpender(_investmentAddress, 1), approvalAsset, bal);
            }
            // Invoke protocol specific call
            investmentInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }

        _validatePostExitInvestmentData(investmentInfo);

        emit InvestmentExited(
            address(investmentInfo.garden),
            address(investmentInfo.strategy),
            investmentInfo.investment,
            _investmentTokenIn
        );
    }

    /**
     * Gets the asset needed to enter the investment
     *
     * @return address                           Returns the asset that this investment needs
     */
    function getInvestmentAsset(address _investmentAddress) external view override returns (address) {
        return _getInvestmentAsset(_investmentAddress);
    }

    /**
     * Gets the asset you obtained after entering the investment
     *
     * @return address                            Returns the asset that this investment obtains
     */
    function getResultAsset(address _investmentAddress) external view override returns (address) {
        return _getResultAsset(_investmentAddress);
    }

    /**
     * Gets the rewards and the token that they are denominated in
     *
     * @param _strategy                           Address of the strategy
     * @param _investmentAddress                  Address of the investment
     * @return address                            Returns the address with the token of extra rewards
     * @return uint256                            Extra rewards received so far
     */
    function getRewards(address _strategy, address _investmentAddress)
        external
        view
        override
        returns (address, uint256)
    {
        return _getRewards(_strategy, _investmentAddress);
    }

    /* ============ Internal Functions ============ */

    /**
     * Create and return InvestmentInfo struct
     *
     * @param _strategy                                 Address of the strategy
     * @param _investment                               Address of the investment
     * @param _investmentTokensInTransaction            Number of investment tokens involved
     * hparam _tokenIn                                  Addresseses of the deposit token
     * @param _limitDepositToken                        Limit quantity of the deposit/withdrawal token
     *
     * return InvestmentInfo                            Struct containing data for the investment
     */
    function _createInvestmentInfo(
        address _strategy,
        address _investment,
        uint256 _investmentTokensInTransaction,
        address, /*_tokenIn*/
        uint256 _limitDepositToken
    ) internal view returns (InvestmentInfo memory) {
        InvestmentInfo memory investmentInfo;
        investmentInfo.strategy = IStrategy(_strategy);
        investmentInfo.garden = IGarden(investmentInfo.strategy.garden());
        investmentInfo.investment = _getResultAsset(_investment);
        investmentInfo.totalSupply = IERC20(_investment).totalSupply();
        investmentInfo.investmentTokensInStrategy = IERC20(investmentInfo.investment).balanceOf(_strategy);
        investmentInfo.investmentTokensInTransaction = _investmentTokensInTransaction;
        investmentInfo.limitDepositTokenQuantity = _limitDepositToken;

        return investmentInfo;
    }

    /**
     * Validate pre investment join data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePreJoinInvestmentData(InvestmentInfo memory _investmentInfo) internal pure {
        require(
            _investmentInfo.investmentTokensInTransaction > 0,
            'Min investment tokens to receive must be greater than 0'
        );
    }

    /**
     * Validate pre investment data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePreExitInvestmentData(InvestmentInfo memory _investmentInfo) internal pure {
        require(
            _investmentInfo.investmentTokensInTransaction > 0,
            'Investment tokens to exchange must be greater than 0'
        );
        require(
            _investmentInfo.investmentTokensInStrategy >= _investmentInfo.investmentTokensInTransaction,
            'The strategy does not have enough investment tokens'
        );
    }

    /**
     * Validate post enter investment data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePostEnterInvestmentData(InvestmentInfo memory _investmentInfo) internal view {
        require(
            IERC20(_investmentInfo.investment).balanceOf(address(_investmentInfo.strategy)) >=
                _investmentInfo.investmentTokensInStrategy,
            'The strategy did not receive the investment tokens'
        );
    }

    /**
     * Validate post exit investment data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePostExitInvestmentData(InvestmentInfo memory _investmentInfo) internal view {
        require(
            IERC20(_investmentInfo.investment).balanceOf(address(_investmentInfo.strategy)) <=
                (_investmentInfo.investmentTokensInStrategy - _investmentInfo.investmentTokensInTransaction) + 100,
            'The strategy did not return the investment tokens'
        );
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _investmentAddress              Address of the investment
     * hparam  _investmentTokensOut            Amount of investment tokens to send
     * hparam  _tokenIn                       Addresses of tokens to send to the investment
     * hparam  _maxAmountIn                   Amounts of tokens to send to the investment
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getEnterInvestmentCalldata(
        address, /* _strategy */
        address, /* _investmentAddress */
        uint256, /* _investmentTokensOut */
        address, /* _tokenIn */
        uint256 /* _maxAmountIn */
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
     * hparam  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * hparam  _borrowOp                 Type of Passive op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address, /* _strategy */
        address, /* _asset */
        uint256, /* _amount */
        uint256 /* _borrowOp */
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
     * hparam  _strategy                 Address of the asset to deposit
     * hparam  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * hparam  _passiveOp                 Type of op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPostActionCallData(
        address, /* _strategy */
        address, /* _asset */
        uint256, /* _amount */
        uint256 /* _passiveOp */
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
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _investmentAddress              Address of the investment
     * hparam  _investmentTokensIn             Amount of investment tokens to receive
     * hparam  _tokenOut                       Addresses of token to receive
     * hparam  _minAmountOut                   Amount of investment tokens to receive
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getExitInvestmentCalldata(
        address, /*_strategy */
        address, /*_investmentAddress */
        uint256, /*_investmentTokensIn */
        address, /*_tokenOut */
        uint256 /* _minAmountOut */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        );

    function _getInvestmentAsset(
        address //_investmentAddress
    ) internal view virtual returns (address);

    function _getSpender(
        address, //_investmentAddress,
        uint8 // op
    ) internal view virtual returns (address);

    function _getRewards(
        address, // _strategy
        address //_investmentAddress
    ) internal view virtual returns (address, uint256) {
        return (address(0), 0);
    }

    function _preActionNeedsApproval(
        address /* _asset */
    ) internal view virtual returns (address) {
        return address(0);
    }

    function _postActionNeedsApproval(
        address /* _asset */
    ) internal view virtual returns (address) {
        return address(0);
    }

    function _getAssetAfterExitPreAction(address _asset) internal view virtual returns (address) {
        return _asset;
    }

    function _getResultAsset(address _investment) internal view virtual returns (address) {
        return _investment;
    }

    function _getExtraAssetToApproveEnter(address _asset) internal view virtual returns (address) {
        return address(0);
    }
}
