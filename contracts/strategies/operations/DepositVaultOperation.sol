// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import {TradesIterator, NumbersIterator} from '../../interfaces/IOperation.sol';
import {IStrategy, TradeInfo, TradeProtocol} from '../../interfaces/IStrategy.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy, TradeInfo, TradeProtocol} from '../../interfaces/IStrategy.sol';
import {IPassiveIntegration} from '../../interfaces/IPassiveIntegration.sol';
import {ConvexStakeIntegration} from '../../integrations/passive/ConvexStakeIntegration.sol';
import {IJarUniV3} from '../../interfaces/external/pickle/IJarUniV3.sol';
import {IBasicRewards} from '../../interfaces/external/convex/IBasicRewards.sol';

import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {UniversalERC20} from '../../lib/UniversalERC20.sol';
import {TradeIteratorLib} from '../../lib/TradeIteratorLib.sol';
import {NumberIteratorLib} from '../../lib/NumberIteratorLib.sol';

import {Operation} from './Operation.sol';

import 'hardhat/console.sol';

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
    using UniversalERC20 for IERC20;
    using TradeIteratorLib for TradesIterator;
    using NumberIteratorLib for NumbersIterator;

    /* ============ Constructor ============ */

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
     */
    function executeOperation(
        Args memory _args,
        NumbersIterator memory _pricesIterator,
        TradesIterator memory _tradesIterator
    )
        external
        override
        onlyStrategy
        returns (ExecRet memory ret)
    {
        address yieldVault = BytesLib.decodeOpDataAddress(_args.data);
        address vaultAsset = IPassiveIntegration(_args.integration).getInvestmentAsset(yieldVault);

        uint256 vaultAssetQuantity =
            vaultAsset != _args.asset
                ? IStrategy(msg.sender).trade(
                    _args.asset,
                    _args.capital,
                    vaultAsset,
                    0,
                    TradeIteratorLib.none()
                )
                : IERC20(vaultAsset).universalBalanceOf(msg.sender);

        //uint256 minAmountExpected =
        //    IPassiveIntegration(_integration).getExpectedShares(_yieldVault, _capital).preciseMul(
        //        uint256(1e18).sub(SLIPPAGE_ALLOWED)
        //    );

        IPassiveIntegration(_args.integration).enterInvestment(
            msg.sender,
            yieldVault,
            1, // TODO: change from priceOracle
            vaultAsset,
            vaultAssetQuantity
        );

        vaultAsset = _getResultAsset(_args.integration, yieldVault);
        console.log('after enter');
        return ExecRet(vaultAsset, IERC20(vaultAsset).universalBalanceOf(msg.sender), 0, _pricesIterator.counter, _tradesIterator.counter);
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
        IGarden _garden,
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
            IERC20(_getResultAsset(_integration, yieldVault)).universalBalanceOf(msg.sender).preciseMul(_percentage);
        if (amountVault > 0) {
            uint256 minAmount =
                amountVault.sub(amountVault.preciseMul(SLIPPAGE_ALLOWED)).preciseDiv(
                    _getPrice(yieldVault, vaultAsset).mul(
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
            // Only claim and sell rewards on final exit
            if (_percentage == HUNDRED_PERCENT) {
                try IPassiveIntegration(_integration).getRewards(msg.sender, yieldVault) returns (
                    address rewardToken,
                    uint256 amount
                ) {
                    if (rewardToken != address(0)) {
                        amount = IERC20(rewardToken).universalBalanceOf(msg.sender);
                        if (amount > MIN_TRADE_AMOUNT) {
                            address rasset = _garden.reserveAsset();
                            IStrategy(msg.sender).trade(
                                rewardToken,
                                amount,
                                rasset,
                                0,
                                TradeIteratorLib.none()
                            );
                        }
                    }
                } catch {}
            }
        }
        return (
            vaultAsset,
            vaultAsset != address(0) ? IERC20(vaultAsset).universalBalanceOf(msg.sender) : address(msg.sender).balance,
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
        uint256 NAV = _getCoreNAV(_integration, vault, _garden);
        // Get value of pending rewards
        NAV = NAV.add(_getRewardsNAV(_integration, vault, _garden.reserveAsset()));
        require(NAV != 0, 'NAV has to be bigger v 0');
        return (NAV, true);
    }

    function _getCoreNAV(
        address _integration,
        address _vault,
        IGarden _garden
    ) internal view returns (uint256) {
        address resultAsset = _getResultAsset(_integration, _vault);
        uint256 balance = IERC20(resultAsset).universalBalanceOf(msg.sender);
        // Get price through oracle
        uint256 price = _getPrice(resultAsset, _garden.reserveAsset());
        uint256 NAV =
            SafeDecimalMath.normalizeAmountTokens(resultAsset, _garden.reserveAsset(), balance.preciseMul(price));
        // Get remaining investment asset
        address vaultAsset = IPassiveIntegration(_integration).getInvestmentAsset(_vault);
        balance = IERC20(vaultAsset).universalBalanceOf(msg.sender);
        price = _getPrice(vaultAsset, _garden.reserveAsset());
        if (balance > 0) {
            NAV = NAV.add(
                SafeDecimalMath.normalizeAmountTokens(vaultAsset, _garden.reserveAsset(), balance.preciseMul(price))
            );
        }
        return NAV;
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
