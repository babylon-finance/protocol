/*
    Copyright 2020 Babylon Finance

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.7.4;

import "hardhat/console.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICommunity } from "../interfaces/ICommunity.sol";
import { IInvestmentIdea } from "../interfaces/IInvestmentIdea.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IBabController } from "../interfaces/IBabController.sol";
import { BaseIntegration } from "./BaseIntegration.sol";

/**
 * @title PassiveIntegration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with passive investments like Yearn, Indexed
 */
abstract contract PassiveIntegration is BaseIntegration, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeCast for uint256;

    /* ============ Struct ============ */

    struct InvestmentInfo {
      IInvestmentIdea idea;                           // Idea address
      ICommunity community;                           // Community address
      address investment;                             // Investment address
      uint256 totalSupply;                            // Total Supply of the investment
      uint256 investmentTokensInTransaction;          // Investment tokens affected by this transaction
      uint256 investmentTokensInCommunity;                 // Investment tokens community balance
      uint256 limitDepositTokenQuantity;              // Limit deposit/withdrawal token amount
    }


    /* ============ Events ============ */

    event InvestmentEntered(
      address indexed community,
      address indexed idea,
      address indexed investment,
      address tokenIn,
      uint256 investmentTokensOut
    );

    event InvestmentExited(
      address indexed community,
      address indexed idea,
      address indexed investment,
      uint256 investmentTokensOut,
      uint256 protocolFee
    );


    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _weth, address _controller) BaseIntegration(_name, _weth, _controller) {}

    /* ============ External Functions ============ */

    /**
     * Deposits tokens into an investment
     *
     * @param _investmentAddress          Address of the investment token to join
     * @param _investmentTokensOut        Min amount of investment tokens to receive
     * @param _tokenIn                    Token aaddress to deposit
     * @param _maxAmountIn                Max amount of the token to deposit
     */
    function enterInvestment(
      address _investmentAddress,
      uint256 _investmentTokensOut,
      address _tokenIn,
      uint256 _maxAmountIn
    )
      external
      nonReentrant
      onlyIdea
    {
      InvestmentInfo memory investmentInfo = _createInvestmentInfo(
        _investmentAddress,
        _investmentTokensOut,
        _tokenIn,
        _maxAmountIn
      );
      _validatePreJoinInvestmentData(investmentInfo);
      // Approve spending of the token
      investmentInfo.idea.invokeApprove(
        _getSpender(_investmentAddress),
        _tokenIn,
        _maxAmountIn
      );

      (
          address targetInvestment,
          uint256 callValue,
          bytes memory methodData
      ) = _getEnterInvestmentCalldata(
          _investmentAddress,
          _investmentTokensOut,
          _tokenIn,
          _maxAmountIn
      );
      investmentInfo.idea.invokeFromIntegration(targetInvestment, callValue, methodData);
      _validatePostEnterInvestmentData(investmentInfo);

      _updateCommunityPositions(investmentInfo, _tokenIn, true);

      emit InvestmentEntered(
        address(investmentInfo.community),
        address(investmentInfo.idea),
        _investmentAddress,
        _tokenIn,
        _investmentTokensOut
      );
    }

    /**
     * Exits an outside passive investment
     *
     * @param _investmentAddress          Address of the investment token to join
     * @param _investmentTokenIn          Quantity of investment tokens to return
     * @param _tokenOut                   Token address to withdraw
     * @param _minAmountOut               Min token quantities to receive from the investment
     */
    function exitInvestment(
      address _investmentAddress,
      uint256 _investmentTokenIn,
      address _tokenOut,
      uint256 _minAmountOut
    )
      external
      nonReentrant
      onlyIdea
    {
      InvestmentInfo memory investmentInfo = _createInvestmentInfo(
        _investmentAddress,
        _investmentTokenIn,
        _tokenOut,
        _minAmountOut
      );
      _validatePreExitInvestmentData(investmentInfo);
      // Approve spending of the investment token
      investmentInfo.idea.invokeApprove(
        _getSpender(_investmentAddress),
        _investmentAddress,
        _investmentTokenIn
      );

      (
          address targetInvestment,
          uint256 callValue,
          bytes memory methodData
      ) = _getExitInvestmentCalldata(
          _investmentAddress,
          _investmentTokenIn,
          _tokenOut,
          _minAmountOut
      );
      investmentInfo.idea.invokeFromIntegration(targetInvestment, callValue, methodData);
      _validatePostExitInvestmentData(investmentInfo);
      uint256 protocolFee = _accrueProtocolFee(investmentInfo, _tokenOut, _minAmountOut);

      _updateCommunityPositions(investmentInfo, _tokenOut, false);

      emit InvestmentExited(
        address(investmentInfo.community),
        address(investmentInfo.idea),
        investmentInfo.investment,
        _investmentTokenIn,
        protocolFee
      );
    }

    /**
     * Checks whether an investment address is valid
     *
     * @param _investmentAddress                 Investment address to check
     * @return bool                              True if the address is a investment
     */
     function isInvestment(address _investmentAddress) view external returns (bool) {
       return _isInvestment(_investmentAddress);
     }

    /* ============ Internal Functions ============ */


    /**
     * Retrieve fee from controller and calculate total protocol fee and send from community to protocol recipient
     *
     * @param _investmentInfo                 Struct containing trade information used in internal functions
     * @param _feeToken                       Address of the token to pay the fee with
     * @return uint256                        Amount of receive token taken as protocol fee
     */
    function _accrueProtocolFee(InvestmentInfo memory _investmentInfo, address _feeToken, uint256 _exchangedQuantity) internal returns (uint256) {
      uint256 protocolFeeTotal = getIntegrationFee(0, _exchangedQuantity);

      payProtocolFeeFromCommunity(address(_investmentInfo.community), _feeToken, protocolFeeTotal);

      return protocolFeeTotal;
    }

    /**
     * Create and return InvestmentInfo struct
     *
     * @param _investment                               Address of the investment
     * @param _investmentTokensInTransaction            Number of investment tokens involved
     * hparam _tokenIn                                  Addresseses of the deposit token
     * @param _limitDepositToken                        Limit quantity of the deposit/withdrawal token
     *
     * return InvestmentInfo                            Struct containing data for the investment
     */
    function _createInvestmentInfo(
      address _investment,
      uint256 _investmentTokensInTransaction,
      address /*_tokenIn*/,
      uint256 _limitDepositToken
    )
      internal
      view
      returns (InvestmentInfo memory)
    {
      InvestmentInfo memory investmentInfo;
      investmentInfo.idea = IInvestmentIdea(msg.sender);
      investmentInfo.community = ICommunity(investmentInfo.idea.community());
      investmentInfo.investment = _investment;
      investmentInfo.totalSupply = IERC20(_investment).totalSupply();
      investmentInfo.investmentTokensInCommunity = IERC20(_investment).balanceOf(address(msg.sender));
      investmentInfo.investmentTokensInTransaction = _investmentTokensInTransaction;
      investmentInfo.limitDepositTokenQuantity = _limitDepositToken;

      return investmentInfo;
    }

    /**
     * Validate pre investment join data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePreJoinInvestmentData(InvestmentInfo memory _investmentInfo) internal view {
      require(_isInvestment(_investmentInfo.investment), "The investment address is not valid");
      require(_investmentInfo.investmentTokensInTransaction > 0, "Min investment tokens to receive must be greater than 0");
    }

    /**
     * Validate pre investment data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePreExitInvestmentData(InvestmentInfo memory _investmentInfo) internal view {
      require(_isInvestment(_investmentInfo.investment), "The investment address is not valid");
      require(_investmentInfo.investmentTokensInTransaction > 0, "Investment tokens to exchange must be greater than 0");
      require(_investmentInfo.investmentTokensInCommunity >= _investmentInfo.investmentTokensInTransaction, "The community does not have enough investment tokens");
    }

    /**
     * Validate post enter investment data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePostEnterInvestmentData(InvestmentInfo memory _investmentInfo) internal view {
      require((IERC20(_investmentInfo.investment).balanceOf(address(_investmentInfo.idea)) > _investmentInfo.investmentTokensInCommunity), "The community did not receive the investment tokens");
    }

    /**
     * Validate post exit investment data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePostExitInvestmentData(InvestmentInfo memory _investmentInfo) internal view {
      require(IERC20(_investmentInfo.investment).balanceOf(address(_investmentInfo.idea)) == _investmentInfo.investmentTokensInCommunity - _investmentInfo.investmentTokensInTransaction, "The community did not return the investment tokens");
    }

    /**
     * Update Community positions
     *
     * @param _investmentInfo                Struct containing investment information used in internal functions
     */
    function _updateCommunityPositions(InvestmentInfo memory _investmentInfo, address _depositToken, bool isDeposit) internal {
      int256 depositTokenDelta = isDeposit ? int256(-_investmentInfo.limitDepositTokenQuantity) : _investmentInfo.limitDepositTokenQuantity.toInt256();
      int256 investmentTokenDelta = isDeposit ? _investmentInfo.investmentTokensInTransaction.toInt256() : _investmentInfo.investmentTokensInTransaction.toInt256();
      // balance deposit/withdrawal token
      _updateInvestmentIdeaPosition(address(_investmentInfo.idea), _depositToken, depositTokenDelta, isDeposit ? 2 : 0);
      // balance investment token
      _updateInvestmentIdeaPosition(address(_investmentInfo.idea), _investmentInfo.investment, investmentTokenDelta, 0);
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
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
      address /* _investmentAddress */,
      uint256 /* _investmentTokensOut */,
      address /* _tokenIn */,
      uint256 /* _maxAmountIn */
    ) internal virtual view returns (address, uint256, bytes memory) {
      require(false, "This needs to be overriden");
      return (address(0),0,bytes(""));
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
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
      address /*_investmentAddress */,
      uint256 /*_investmentTokensIn */,
      address /*_tokenOut */,
      uint256 /* _minAmountOut */
    ) internal virtual view returns (address, uint256, bytes memory) {
      require(false, "This needs to be overriden");
      return (address(0),0,bytes(""));
    }

    function _isInvestment(
      address //_investmentAddress
    ) view virtual internal returns (bool) {
      require(false, "This needs to be overriden");
      return false;
    }

    function _getSpender(
      address //_investmentAddress
    ) view virtual internal returns (address) {
      require(false, "This must be overriden");
      return address(0);
    }

}
