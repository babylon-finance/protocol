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

pragma solidity 0.7.6;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IPassiveIntegration} from '../../interfaces/IPassiveIntegration.sol';
import {ConvexStakeIntegration} from '../../integrations/passive/ConvexStakeIntegration.sol';
import {IBooster} from '../../interfaces/external/convex/IBooster.sol';
import {IBasicRewards} from '../../interfaces/external/convex/IBasicRewards.sol';

import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';

import {Operation} from './Operation.sol';

/**
 * @title DepositVaultOperation/Stake Operation
 * @author Babylon Finance
 *
 * Executes a stake (deposit vault) operation
 */
contract DepositVaultOperation is Operation {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using BytesLib for bytes;

    /* ============ Constructor ============ */

    IBooster private constant booster = IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address private constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52; // crv
    address private constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32; // lDO

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _controller) Operation(_name, _controller) {}

    /**
     * Sets operation data for the deposit vault operation
     *
     * @param _data                   Operation data
     */
    function validateOperation(
        bytes calldata _data,
        IGarden, /* _garden */
        address _integration,
        uint256 /* _index */
    ) external view override onlyStrategy {
        require(BytesLib.decodeOpDataAddress(_data) != address(0), 'Incorrect vault address!');
    }

    /**
     * Executes the deposit vault operation
     * @param _asset              Asset to receive into this operation
     * @param _capital            Amount of asset received
     * param _assetStatus         Status of the asset amount
     * @param _data               OpData e.g. Address of the vault to enter
     * param _garden              Garden of the strategy
     * @param _integration        Address of the integration to execute
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8, /* _assetStatus */
        bytes calldata _data,
        IGarden, /* _garden */
        address _integration
    )
        external
        override
        onlyStrategy
        returns (
            address,
            uint256,
            uint8
        )
    {
        address yieldVault = BytesLib.decodeOpDataAddress(_data);
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(yieldVault);
        if (vaultAsset != _asset) {
            // get ETH if it's needed
            if (vaultAsset == address(0)) {
                if (_asset != WETH) {
                    IStrategy(msg.sender).trade(_asset, _capital, WETH);
                }
                IStrategy(msg.sender).handleWeth(false, IERC20(WETH).balanceOf(msg.sender));
            } else {
                IStrategy(msg.sender).trade(_asset, _capital, vaultAsset);
            }
        }
        uint256 minAmountExpected = _getMinAmountExpected(yieldVault, _capital, _integration);
        IPassiveIntegration(_integration).enterInvestment(
            msg.sender,
            yieldVault,
            minAmountExpected,
            vaultAsset,
            vaultAsset == address(0) ? address(msg.sender).balance : IERC20(vaultAsset).balanceOf(msg.sender)
        );
        vaultAsset = _getResultAsset(_integration, yieldVault);
        return (vaultAsset, IERC20(vaultAsset).balanceOf(msg.sender), 0); // liquid
    }

    function _getMinAmountExpected(
        address _yieldVault,
        uint256 _capital,
        address _integration
    ) internal view returns (uint256) {
        uint256 exactAmount = IPassiveIntegration(_integration).getExpectedShares(_yieldVault, _capital);
        return exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
    }

    /**
     * Exits the deposit vault operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        address, /* _asset */
        uint256, /* _remaining */
        uint8, /* _assetStatus */
        uint256 _percentage,
        bytes calldata _data,
        IGarden, /* _garden */
        address _integration
    )
        external
        override
        onlyStrategy
        returns (
            address,
            uint256,
            uint8
        )
    {
        address yieldVault = BytesLib.decodeOpDataAddress(_data);
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(yieldVault);
        uint256 amountVault =
            IERC20(_getResultAsset(_integration, yieldVault)).balanceOf(msg.sender).preciseMul(_percentage);
        uint256 minAmount =
            amountVault.sub(amountVault.preciseMul(SLIPPAGE_ALLOWED)).preciseDiv(
                IPassiveIntegration(_integration).getPricePerShare(yieldVault).mul(
                    10**PreciseUnitMath.decimals().sub(vaultAsset == address(0) ? 18 : ERC20(vaultAsset).decimals())
                )
            );
        IPassiveIntegration(_integration).exitInvestment(msg.sender, yieldVault, amountVault, vaultAsset, minAmount);
        return (
            vaultAsset,
            vaultAsset != address(0) ? IERC20(vaultAsset).balanceOf(msg.sender) : address(msg.sender).balance,
            0
        );
    }

    /**
     * Gets the NAV of the deposit vault op in the reserve asset
     *
     * @param _data               OpData e.g. Vault
     * @param _garden             Garden the strategy belongs to
     * @param _integration        Status of the asset amount
     * @return _nav               NAV of the strategy
     */
    function getNAV(
        bytes calldata _data,
        IGarden _garden,
        address _integration
    ) external view override returns (uint256, bool) {
        address vault = BytesLib.decodeOpDataAddress(_data); // 64 bytes (w/o signature prefix bytes4)
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return (0, true);
        }
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(vault); // USDC, DAI, WETH
        uint256 balance = IERC20(_getResultAsset(_integration, vault)).balanceOf(msg.sender);
        uint256 price = _getPrice(_garden.reserveAsset(), vaultAsset);
        // try to get price of an investment token from Oracle
        // markets sometimes price assets differently than
        // their underlying protocols, e.g., stETH/Lido
        uint256 pricePerShare = _getPrice(vault, vaultAsset);
        // if failed to fetch price from Oracle get it from the underlying protocol
        if (pricePerShare == 0) {
            pricePerShare = IPassiveIntegration(_integration).getPricePerShare(vault);
            // Normalization of pricePerShare
            pricePerShare = pricePerShare.mul(
                10**PreciseUnitMath.decimals().sub(vaultAsset == address(0) ? 18 : ERC20(vaultAsset).decimals())
            );
        }
        //Balance normalization
        balance = SafeDecimalMath.normalizeAmountTokens(vaultAsset, _garden.reserveAsset(), balance);
        uint256 NAV = pricePerShare.preciseMul(balance).preciseDiv(price);
        // Get value of pending rewards
        NAV = NAV.add(_getRewardsNAV(_integration, vault, _garden.reserveAsset()));
        require(NAV != 0, 'NAV has to be bigger 0');
        return (NAV, true);
    }

    // Function to provide backward compatibility
    function _getResultAsset(address _integration, address _yieldVault) private view returns (address) {
        try IPassiveIntegration(_integration).getResultAsset(_yieldVault) returns (address _resultAsset) {
            return _resultAsset;
        } catch {
            return _yieldVault;
        }
    }

    function _getRewardsNAV(
        address _integration,
        address _yieldVault,
        address _reserveAsset
    ) private view returns (uint256) {
        // Patching old convex stETH.
        if (
            address(msg.sender) == 0x3FeaD42999D537477CE39335aA7b4951e8e78233 ||
            address(msg.sender) == 0x4f85dD417d19058cA81564f41572fb90D2F7e935
        ) {
            uint256 nav =
                _getPrice(CRV, _reserveAsset).preciseMul(
                    IBasicRewards(0x0A760466E1B4621579a82a39CB56Dda2F4E70f03).earned(msg.sender) * 2
                );
            nav = nav.add(
                _getPrice(LDO, _reserveAsset).preciseMul(
                    IBasicRewards(0x008aEa5036b819B4FEAEd10b2190FBb3954981E8).earned(msg.sender)
                )
            );
            return nav;
        }
        // Patching 3Pool
        if (address(msg.sender) == 0x9D78319EDA31663B487204F0CA88A046e742eE16) {
            return
                _getPrice(CRV, _reserveAsset).preciseMul(
                    IBasicRewards(0x689440f2Ff927E1f24c72F1087E1FAF471eCe1c8).earned(msg.sender) * 2
                );
        }
        // Patching IB
        if (_yieldVault == 0x912EC00eaEbf3820a9B0AC7a5E15F381A1C91f22) {
            return
                _getPrice(CRV, _reserveAsset).preciseMul(
                    IBasicRewards(0x3E03fFF82F77073cc590b656D42FceB12E4910A8).earned(msg.sender) * 2
                );
        }
        try IPassiveIntegration(_integration).getRewards(msg.sender, _yieldVault) returns (
            address rewardToken,
            uint256 amount
        ) {
            if (rewardToken != address(0) && amount > 0) {
                return _getPrice(rewardToken, _reserveAsset).preciseMul(amount);
            }
            return 0;
        } catch {
            return 0;
        }
    }
}
