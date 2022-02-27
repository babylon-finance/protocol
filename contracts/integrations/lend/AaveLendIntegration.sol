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

pragma solidity 0.7.6;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import {AaveToken} from '../../interfaces/external/aave/AaveToken.sol';
import {ILendingPool} from '../../interfaces/external/aave/ILendingPool.sol';
import {ILendingPoolAddressesProvider} from '../../interfaces/external/aave/ILendingPoolAddressesProvider.sol';
import {IProtocolDataProvider} from '../../interfaces/external/aave/IProtocolDataProvider.sol';
import {IStakedAave} from '../../interfaces/external/aave/IStakedAave.sol';

import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {LendIntegration} from './LendIntegration.sol';

/**
 * @title AaveLendIntegration
 * @author Babylon Finance Protocol
 *
 * Aave lend integration.
 */
contract AaveLendIntegration is LendIntegration {
    using SafeMath for uint256;
    using SafeCast for uint256;

    /* ============ Constant ============ */

    ILendingPool constant lendingPool = ILendingPool(address(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9)); // Mainnet
    IProtocolDataProvider constant dataProvider =
        IProtocolDataProvider(address(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d)); // Mainnet

    address private constant stkAAVE = 0x4da27a545c0c5B758a6BA100e3a049001de870f5;

    /* ============ Struct ============ */

    /* ============ Events ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller             Address of the controller
     */
    constructor(IBabController _controller) LendIntegration('aavelend', _controller) {}

    function getInvestmentTokenAmount(address _address, address _assetToken) public view override returns (uint256) {
        return IERC20(_getInvestmentToken(_assetToken)).balanceOf(_address);
    }

    /* ============ Internal Functions ============ */

    function _getRewardToken() internal pure override returns (address) {
        return AAVE;
    }

    function _getCollateralFactor(address _assetToken) internal view virtual override returns (uint256) {
        (, , uint256 collateral, , , , , , , ) = dataProvider.getReserveConfigurationData(_assetToken);
        return collateral.mul(1e14);
    }

    function _getRewardsAccrued(address _strategy) internal view override returns (uint256) {
        return IStakedAave(stkAAVE).stakerRewardsToClaim(_strategy);
    }

    function _isInvestment(address _assetToken) internal view override returns (bool) {
        (address aTokenAddress, , ) = dataProvider.getReserveTokensAddresses(_assetToken);
        return aTokenAddress != address(0);
    }

    function _getExpectedShares(
        address, /* _assetToken */
        uint256 _numTokensToSupply
    ) internal pure override returns (uint256) {
        // love it 😍
        return _numTokensToSupply;
    }

    function _getExchangeRatePerToken(
        address /* _assetToken */
    ) internal pure override returns (uint256) {
        // love it 😍
        return 1;
    }

    /**
     * Claim rewards calldata
     *
     * hparam  _strategy                 Address of the strategy
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _claimRewardsCallData(address _strategy)
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
            abi.encodeWithSignature('claimRewards(address,uint256)', _strategy, IERC20(stkAAVE).balanceOf(_strategy));

        return (stkAAVE, 0, methodData);
    }

    /**
     * Return pre action calldata
     *
     * hparam  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * hparam  _borrowOp                Type of Borrow op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address, /* _asset */
        uint256, /* _amount */
        uint256 /* _borrowOp */
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
     * Returns calldata for supplying tokens.
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getSupplyCalldata(
        address _strategy,
        address _assetToken,
        uint256 _numTokensToSupply
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
        // Encode method data for Garden to invoke
        bytes memory methodData =
            abi.encodeWithSignature(
                'deposit(address,uint256,address,uint16)',
                _assetToken,
                _numTokensToSupply,
                _strategy,
                0
            );
        return (address(lendingPool), 0, methodData);
    }

    /**
     * Returns calldata for redeeming the collateral
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getRedeemCalldata(
        address _strategy,
        address _assetToken,
        uint256 _numTokensToSupply
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
        // Encode method data for Garden to invoke
        bytes memory methodData =
            abi.encodeWithSignature('withdraw(address,uint256,address)', _assetToken, _numTokensToSupply, _strategy);
        return (address(lendingPool), 0, methodData);
    }

    function _getSpender(
        address /* _investmentAddress */
    ) internal pure override returns (address) {
        return address(lendingPool);
    }

    function _getInvestmentToken(address _assetToken) internal view override returns (address) {
        (address aTokenAddress, , ) = dataProvider.getReserveTokensAddresses(_assetToken);
        return aTokenAddress;
    }
}
