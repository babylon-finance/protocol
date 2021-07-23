/*
    Copyright 2021 Babylon Finance.

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

pragma solidity >=0.7.0 <0.9.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ILendingPool} from '../../interfaces/external/aave/ILendingPool.sol';
import {IProtocolDataProvider} from '../../interfaces/external/aave/IProtocolDataProvider.sol';
import {IWETH} from '../../interfaces/external/weth/IWETH.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {BorrowIntegration} from './BorrowIntegration.sol';

/**
 * @title AaveBorrowIntegration
 * @author Babylon Finance
 *
 * Abstract class that houses aave borring/lending logic.
 */
contract AaveBorrowIntegration is BorrowIntegration {
    using SafeERC20 for IERC20;

    ILendingPool constant lendingPool = ILendingPool(address(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9)); // Mainnet
    IProtocolDataProvider constant dataProvider =
        IProtocolDataProvider(address(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d)); // Mainnet
    uint256 constant interestRateMode = 1; // Stable Interest

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller             Address of the controller
     * @param _maxCollateralFactor    Max collateral factor allowed (from 0 to a 100)
     */
    constructor(IBabController _controller, uint256 _maxCollateralFactor)
        BorrowIntegration('aaveborrow', _controller, _maxCollateralFactor)
    {}

    /* ============ External Functions ============ */
    /**
     * Get the amount of borrowed debt that needs to be repaid
     * @param asset   The underlying asset
     *
     */
    function getBorrowBalance(address _strategy, address asset) public view override returns (uint256) {
        (, uint256 stableDebt, , , , , , , ) = dataProvider.getUserReserveData(asset, _strategy);
        return stableDebt;
    }

    /**
     * Get the amount of collateral supplied
     * hparam asset   The collateral asset
     *
     */
    function getCollateralBalance(
        address _strategy,
        address /* asset */
    ) external view override returns (uint256) {
        (
            uint256 totalCollateral, // uint256 totalDebt, // uint256 borrowingPower, // uint256 liquidationThreshold, // uint256 ltv,
            ,
            ,
            ,
            ,

        ) =
            // uint256 healthFactor
            lendingPool.getUserAccountData(_strategy);
        return totalCollateral;
    }

    /**
     * Get the remaining liquidity available to borrow
     *
     */
    function getRemainingLiquidity(address _strategy) public view override returns (uint256) {
        (
            ,
            ,
            // uint256 totalCollateral,
            // uint256 totalDebt,
            uint256 borrowingPower, // uint256 borrowingPower, // uint256 liquidationThreshold, // uint256 ltv,
            ,
            ,

        ) =
            // uint256 healthFactor
            lendingPool.getUserAccountData(_strategy);
        return borrowingPower;
    }

    /* ============ Internal Functions ============ */

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
     * Return borrow token calldata
     *
     * @param  _strategy                 Address of the strategy executing
     * @param  _asset                    Address of the asset to deposit
     * @param  _amount                   Amount of the token to deposit
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getBorrowCalldata(
        address _strategy,
        address _asset,
        uint256 _amount
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
                'borrow(address,uint256,uint256,uint16,address)',
                _asset,
                _amount,
                interestRateMode,
                0,
                _strategy
            );

        return (address(lendingPool), 0, methodData);
    }

    /**
     * Return repay borrowed asset calldata
     *
     * @param  _strategy                 Address of the strategy executing it
     * @param  _asset                    Address of the asset to deposit
     * @param  _amount                   Amount of the token to deposit
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getRepayCalldata(
        address _strategy,
        address _asset,
        uint256 _amount
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
                'repay(address,uint256,uint256,address)',
                _asset,
                _amount,
                interestRateMode,
                _strategy
            );
        return (address(lendingPool), 0, methodData);
    }

    function _getCollateralAsset(
        address asset,
        uint8 /* _borrowOp */
    ) internal pure override returns (address) {
        return asset;
    }

    function _getSpender(
        address /* asset */
    ) internal pure override returns (address) {
        return address(lendingPool);
    }

    function _getDebtToken(address asset) internal view returns (address) {
        // Get the relevant debt token address
        (, address stableDebtTokenAddress, ) = dataProvider.getReserveTokensAddresses(asset);
        return stableDebtTokenAddress;
    }
}
