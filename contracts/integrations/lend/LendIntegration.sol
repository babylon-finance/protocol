/*
    Copyright 2021 Babylon Finance

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

import 'hardhat/console.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {ILendIntegration} from '../../interfaces/ILendIntegration.sol';

import {BaseIntegration} from '../BaseIntegration.sol';

/**
 * @title LendIntegration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with passive investments like Yearn, Indexed
 */
abstract contract LendIntegration is BaseIntegration, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeCast for uint256;

    /* ============ Struct ============ */
    struct InvestmentInfo {
        IStrategy strategy; // Idea address
        IGarden garden; // Garden address
        address investment; // Investment address
    }

    /* ============ Events ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     */
    constructor(
        string memory _name,
        address _weth,
        address _controller
    ) BaseIntegration(_name, _weth, _controller) {}

    /* ============ External Functions ============ */
    function supplyTokens(address _tokenAddress) external {
        InvestmentInfo memory investmentInfo = _createInvestmentInfo(_tokenAddress);
        (address targetInvestment, uint256 callValue, bytes memory methodData) = _getSupplyCalldata(_tokenAddress);
        investmentInfo.strategy.invokeFromIntegration(targetInvestment, callValue, methodData);
    }

    function redeemTokens() external {}

    /* ============ Internal Functions ============ */

    /**
     * Create and return InvestmentInfo struct
     *
     * @param _tokenAddress                             Address of the investment
     *
     * return InvestmentInfo                            Struct containing data for the investment
     */
    function _createInvestmentInfo(address _tokenAddress) internal view returns (InvestmentInfo memory) {
        InvestmentInfo memory investmentInfo;
        investmentInfo.strategy = IStrategy(msg.sender);
        investmentInfo.garden = IGarden(investmentInfo.strategy.garden());
        investmentInfo.investment = _tokenAddress;

        return investmentInfo;
    }

    /**
     * Returns calldata for supplying tokens.
     *
     * hparam  _tokenAddress              Address of the token
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getSupplyCalldata(
        address /* _tokenAddress */
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
        require(false, 'This needs to be overriden');
        return (address(0), 0, bytes(''));
    }

    /**
     * Returns calldata to redeem tokens.
     *
     * hparam  _tokenAddress              Address of the token
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getExitInvestmentCalldata(
        address /*_tokenAddress */
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
        require(false, 'This needs to be overriden');
        return (address(0), 0, bytes(''));
    }
}
