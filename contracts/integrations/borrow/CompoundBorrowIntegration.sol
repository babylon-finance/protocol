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

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import {ICToken} from '../../interfaces/external/compound/ICToken.sol';
import {ICEther} from '../../interfaces/external/compound/ICEther.sol';
import {ICompoundPriceOracle} from '../../interfaces/external/compound/ICompoundPriceOracle.sol';
import {IComptroller} from '../../interfaces/external/compound/IComptroller.sol';
import {IWETH} from '../../interfaces/external/weth/IWETH.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IGarden} from '../../interfaces/IGarden.sol';

import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {UniversalERC20} from '../../lib/UniversalERC20.sol';

import {BorrowIntegration} from './BorrowIntegration.sol';

/**
 * @title CompoundBorrowIntegration
 * @author Babylon Finance
 *
 * Abstract class that houses compound borrowing logic.
 */
contract CompoundBorrowIntegration is BorrowIntegration {
    using LowGasSafeMath for uint256;
    using SafeERC20 for ERC20;
    using UniversalERC20 for IERC20;

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyGovernanceOrEmergency() {
        require(
            msg.sender == controller.owner() || msg.sender == controller.EMERGENCY_OWNER(),
            'Only governance or emergency can call this'
        );
        _;
    }

    /* ============ State Variables ============ */

    address internal immutable comptroller;

    // Mapping of asset addresses to cToken addresses
    mapping(address => address) public assetToCToken;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     * @param _maxCollateralFactor    Max collateral factor allowed
     * @param _comptroller            Address of the controller
     */
    constructor(
        string memory _name,
        IBabController _controller,
        uint256 _maxCollateralFactor,
        address _comptroller
    ) BorrowIntegration(_name, _controller, _maxCollateralFactor) {
        comptroller = _comptroller;
        overrideMappings(_comptroller);
    }

    /* ============ External Functions ============ */

    // Governance function
    function overrideMappings(address _comptroller) public onlyGovernanceOrEmergency {
        address[] memory markets = IComptroller(_comptroller).getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            address underlying = address(0);
            if (markets[i] != 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5) {
              underlying = ICToken(markets[i]).underlying();
            }
            assetToCToken[underlying] = markets[i];
        }
    }

    /**
     * Get the amount of borrowed debt that needs to be repaid
     * @param asset   The underlying asset
     *
     */
    function getBorrowBalance(address _strategy, address asset) public view override returns (uint256) {
        address cToken = assetToCToken[asset];
        (
            ,
            ,
            // err
            // cTokenBalance
            uint256 borrowBalance,

        ) = ICToken(cToken).getAccountSnapshot(_strategy);
        return borrowBalance;
    }

    /**
     * Get the amount of collateral depposited
     * @param asset   The collateral to check
     *
     */
    function getCollateralBalance(address _strategy, address asset) external view override returns (uint256) {
        address cToken = assetToCToken[asset];
        (
            ,
            // err
            uint256 cTokenBalance, // borrow balance
            ,
            uint256 exchangeRateMantissa
        ) = ICToken(cToken).getAccountSnapshot(_strategy);
        uint256 decimals = IERC20(asset).universalDecimals();
        // Source: balanceOfUnderlying from any ctoken
        return cTokenBalance.mul(exchangeRateMantissa).div(10**decimals);
    }

    /**
     * Get the remaining liquidity available to borrow
     *
     */
    function getRemainingLiquidity(address _strategy) public view override returns (uint256) {
        (
            ,
            /* error */
            uint256 liquidity, /* shortfall */

        ) = IComptroller(comptroller).getAccountLiquidity(_strategy);
        return liquidity;
    }

    /* ============ Overriden Functions ============ */

    /**
     * Return pre action calldata
     *
     * @param  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * @param  _borrowOp                Type of Borrow op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address _asset,
        uint256, /* _amount */
        uint256 _borrowOp
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
        if (_borrowOp == 0) {
            // Encode method data for Garden to invoke
            address[] memory markets = new address[](1);
            markets[0] = assetToCToken[_asset];
            bytes memory methodData = abi.encodeWithSignature('enterMarkets(address[])', markets);
            return (comptroller, 0, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    /**
     * Return borrow token calldata
     *
     * hparam  _strategy                 Address of the strategy executing it
     * @param  _asset                    Address of the asset to deposit
     * @param  _amount                   Amount of the token to deposit
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getBorrowCalldata(
        address, /* _strategy */
        address _asset,
        uint256 _amount
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
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('borrow(uint256)', _amount);

        return (assetToCToken[_asset], 0, methodData);
    }

    /**
     * Return repay borrowed asset calldata
     *
     * hparam  _strategy                 Address of the strategy executing it
     * @param  _asset                    Address of the asset to deposit
     * @param  _amount                   Amount of the token to deposit
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getRepayCalldata(
        address, /* _strategy */
        address _asset,
        uint256 _amount
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
        // Encode method data for Garden to invoke
        bytes memory methodData;
        if (_asset == address(0)) {
            methodData = abi.encodeWithSignature('repayBorrow()');
        } else {
            methodData = abi.encodeWithSignature('repayBorrow(uint256)', _amount);
        }
        return (assetToCToken[_asset], _asset == address(0) ? _amount : 0, methodData);
    }

    /* ============ Internal Functions ============ */

    function _getCollateralAsset(
        address _asset,
        uint8 /* _borrowOp */
    ) internal view override returns (address) {
        // TODO: check this
        return assetToCToken[_asset];
    }

    function _getSpender(address _asset) internal view override returns (address) {
        return assetToCToken[_asset];
    }
}
