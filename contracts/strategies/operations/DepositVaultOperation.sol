// SPDX-License-Identifier: Apache-2.0

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
        address, /* _integration */
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

        return _enterVault(
            _asset,
            _capital,
            _integration,
            yieldVault,
            vaultAsset
        );
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
        if (amountVault > 0) {
            uint256 minAmount =
                amountVault.sub(amountVault.preciseMul(SLIPPAGE_ALLOWED)).preciseDiv(
                    IPassiveIntegration(_integration).getPricePerShare(yieldVault).mul(
                        10**PreciseUnitMath.decimals().sub(vaultAsset == address(0) ? 18 : ERC20(vaultAsset).decimals())
                    )
                );
            IPassiveIntegration(_integration).exitInvestment(
                msg.sender,
                yieldVault,
                amountVault,
                vaultAsset,
                minAmount
            );
        }
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
        // try to get price of an investment token from Oracle
        // markets sometimes price assets differently than
        // their underlying protocols, e.g., stETH/Lido
        uint256 price = _getPrice(_garden.reserveAsset(), vaultAsset);
        // If vault asset cannot be priced
        require(price != 0, 'Vault asset cannot be priced');
        uint256 pricePerShare = _getPrice(vault, vaultAsset);
        // if failed to fetch price from Oracle get it from the underlying protocol
        if (pricePerShare == 0) {
            pricePerShare = IPassiveIntegration(_integration).getPricePerShare(vault);
            // Normalization of pricePerShare
            pricePerShare = pricePerShare.mul(
                10**PreciseUnitMath.decimals().sub(vaultAsset == address(0) ? 18 : ERC20(vaultAsset).decimals())
            );
        }
        uint256 NAV;
        //Balance normalization
        balance = SafeDecimalMath.normalizeAmountTokens(vaultAsset, _garden.reserveAsset(), balance);
        NAV = pricePerShare.preciseMul(balance).preciseDiv(price);
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

    function _enterVault(
        address _asset,
        uint256 _capital,
        address _integration,
        address _yieldVault,
        address _vaultAsset
    )
        internal
        returns (
            address,
            uint256,
            uint8
        )
    {
        uint256 vaultAssetQuantity = _vaultAsset != _asset ?
            IStrategy(msg.sender).trade(_asset, _capital, _vaultAsset) :
            IERC20(_vaultAsset).balanceOf(msg.sender);

        uint256 minAmountExpected =
            IPassiveIntegration(_integration).getExpectedShares(_yieldVault, _capital).preciseMul(uint256(1e18).sub(SLIPPAGE_ALLOWED));

        IPassiveIntegration(_integration).enterInvestment(
            msg.sender,
            _yieldVault,
            minAmountExpected,
            _vaultAsset,
            vaultAssetQuantity
        );

        return (_getResultAsset(_integration, _yieldVault), IERC20(_vaultAsset).balanceOf(msg.sender), 0);
    }

    function _getRewardsNAV(
        address _integration,
        address _yieldVault,
        address _reserveAsset
    ) private view returns (uint256) {
        try IPassiveIntegration(_integration).getRewards(msg.sender, _yieldVault) returns (
            address rewardToken,
            uint256 amount
        ) {
            if (rewardToken != address(0) && amount > 0) {
                uint256 normalizedBalance = SafeDecimalMath.normalizeAmountTokens(rewardToken, _reserveAsset, amount);
                uint256 price = _getPrice(rewardToken, _reserveAsset);
                return
                    price != 0
                        ? price.preciseMul(normalizedBalance)
                        : _getPrice(rewardToken, _yieldVault)
                            .preciseMul(_getPrice(_yieldVault, _reserveAsset))
                            .preciseMul(normalizedBalance);
            }
            return 0;
        } catch {
            return 0;
        }
    }
}
