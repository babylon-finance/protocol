// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy, TradeInfo, TradeProtocol} from '../../interfaces/IStrategy.sol';
import {ILendIntegration} from '../../interfaces/ILendIntegration.sol';

import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {UniversalERC20} from '../../lib/UniversalERC20.sol';

import {Operation} from './Operation.sol';

import 'hardhat/console.sol';

/**
 * @title LendOperation
 * @author Babylon Finance
 *
 * Executes a lend operation
 */
contract LendOperation is Operation {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;
    using BytesLib for bytes;
    using UniversalERC20 for IERC20;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _controller) Operation(_name, _controller) {}

    /**
     * Sets operation data for the lend operation
     *
     * @param _data                   Operation data
     */
    function validateOperation(
        bytes calldata _data,
        IGarden _garden,
        address, /* _integration */
        uint256 /* _index */
    ) external view override onlyStrategy {}

    /**
     * Executes the lend operation
     */
    function executeOperation(
        Args memory _args,
        uint256[] memory _prices,
        TradeInfo[] memory _trades
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
        address assetToken = BytesLib.decodeOpDataAddress(_args.data); // We just use the first 20 bytes from the whole opEncodedData
        console.log('lend');
        // Trade _asset to _assetToken
        uint256 numTokensToSupply =
            IStrategy(msg.sender).trade(
                _args.asset,
                _args.capital,
                assetToken,
                0,
                TradeInfo(new TradeProtocol[](0), new address[](0))
            );
        console.log('numTokensToSupply:', numTokensToSupply);
        uint256 exactAmount = ILendIntegration(_args.integration).getExpectedShares(assetToken, numTokensToSupply);
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
        ILendIntegration(_args.integration).supplyTokens(msg.sender, assetToken, numTokensToSupply, minAmountExpected);
        return (assetToken, numTokensToSupply, 1); // put as collateral
    }

    /**
     * Exits the lend operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        address _borrowToken,
        uint256 _debt,
        uint8, /* _assetStatus */
        uint256 _percentage,
        bytes memory _data,
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
        address assetToken = BytesLib.decodeOpDataAddressAssembly(_data, 12);
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        _redeemTokens(_borrowToken, _debt, _percentage, msg.sender, _integration, assetToken);
        // Change to weth if needed
        if (assetToken == address(0)) {
            IStrategy(msg.sender).trade(
                assetToken,
                address(msg.sender).balance,
                WETH,
                0,
                TradeInfo(new TradeProtocol[](0), new address[](0))
            );
            assetToken = WETH;
        }
        address rewardsToken = _getRewardToken(_integration);
        // Only sell rewards when the strategy finalizes
        if (rewardsToken != address(0) && _percentage == HUNDRED_PERCENT) {
            uint256 rewardsBalance = IERC20(rewardsToken).universalBalanceOf(msg.sender);
            // Add rewards
            if (rewardsBalance > 1e16) {
                IStrategy(msg.sender).trade(rewardsToken, rewardsBalance, assetToken, 70e15);
            }
        }
        // Liquidations
        _tradeLiquidationsToAsset(_borrowToken, assetToken);
        return (assetToken, IERC20(assetToken).universalBalanceOf(msg.sender), 0);
    }

    /**
     * Gets the NAV of the lend op in the reserve asset
     *
     * @param _data               OpData e.g. Asset lent
     * @param _garden             Garden the strategy belongs to
     * @param _integration        Status of the asset amount
     * @return _nav               NAV of the strategy
     */
    function getNAV(
        bytes calldata _data,
        IGarden _garden,
        address _integration
    ) external view override returns (uint256, bool) {
        address lendToken = BytesLib.decodeOpDataAddress(_data); // 64 bytes (w/o signature prefix bytes4)
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return (0, true);
        }
        uint256 assetTokenAmount = ILendIntegration(_integration).getInvestmentTokenAmount(msg.sender, lendToken);
        uint256 price = _getPrice(_garden.reserveAsset(), lendToken);
        uint256 NAV =
            SafeDecimalMath.normalizeAmountTokens(lendToken, _garden.reserveAsset(), assetTokenAmount).preciseDiv(
                price
            );
        address rewardsToken = _getRewardToken(_integration);
        if (rewardsToken != address(0)) {
            uint256 rewardsAmount = ILendIntegration(_integration).getRewardsAccrued(msg.sender);
            if (rewardsAmount > 0) {
                uint256 priceRewards = _getPrice(_garden.reserveAsset(), rewardsToken);
                // We add rewards
                if (priceRewards != 0) {
                    NAV = NAV.add(
                        SafeDecimalMath
                            .normalizeAmountTokens(rewardsToken, _garden.reserveAsset(), rewardsAmount)
                            .preciseDiv(priceRewards)
                    );
                }
            }
        }
        require(NAV != 0, 'NAV has to be bigger 0');
        return (NAV, true);
    }

    function _redeemTokens(
        address _borrowToken,
        uint256 _debt,
        uint256 _percentage,
        address _sender,
        address _integration,
        address _assetToken
    ) internal {
        // Normalize to underlying asset if any (ctokens for compound)
        uint256 numTokensToRedeem = ILendIntegration(_integration).getInvestmentTokenAmount(_sender, _assetToken);

        uint256 exchangeRate = ILendIntegration(_integration).getExchangeRatePerToken(_assetToken);
        // backwards compatability
        uint256 healthFactor = 0;
        try ILendIntegration(_integration).getHealthFactor(msg.sender) returns (uint256 factor) {
            healthFactor = factor;
        } catch {}
        if (healthFactor > 0) {
            numTokensToRedeem = healthFactor != type(uint256).max
                ? numTokensToRedeem.preciseMul(healthFactor.sub(1e18).preciseDiv(healthFactor))
                : numTokensToRedeem;
        } else {
            // Compound does not support health factor which makes things
            // complicated. Do not create strategies which have the last
            // operation CompoundLend and debt. Such strategies would fail to
            // finalize due to _debt being zero and no health factor.
            if (_debt > 0) {
                uint256 debtInCollateral =
                    SafeDecimalMath.normalizeAmountTokens(
                        _borrowToken,
                        _assetToken,
                        _debt.preciseMul(_getPrice(_borrowToken, _assetToken))
                    );
                // Update amount so we can exit if there is debt
                try ILendIntegration(_integration).getCollateralFactor(_assetToken) returns (uint256 collateralPctg) {
                    numTokensToRedeem = numTokensToRedeem.sub(
                        debtInCollateral.preciseDiv(collateralPctg).mul(105).div(100)
                    ); // add a bit extra 5% just in case
                } catch {
                    numTokensToRedeem = numTokensToRedeem.sub(debtInCollateral.mul(140).div(100));
                }
            }
        }
        // Apply percentage
        numTokensToRedeem = numTokensToRedeem.preciseMul(_percentage);
        // sometimes dust is left
        if (numTokensToRedeem > 1000) {
            ILendIntegration(_integration).redeemTokens(
                msg.sender,
                _assetToken,
                numTokensToRedeem,
                exchangeRate.mul(numTokensToRedeem.sub(numTokensToRedeem.preciseMul(SLIPPAGE_ALLOWED.mul(2))))
            );
        }
    }

    function _tradeLiquidationsToAsset(address _borrowToken, address _assetToken) private {
        // Trade borrow token (from liquidations)
        uint256 borrowBalance = IERC20(_borrowToken).universalBalanceOf(msg.sender);
        if (borrowBalance > 1e6) {
            IStrategy(msg.sender).trade(
                _borrowToken,
                borrowBalance,
                _assetToken,
                0,
                TradeInfo(new TradeProtocol[](0), new address[](0))
            );
        }
    }

    function _getRewardToken(address _integration) private view returns (address) {
        try ILendIntegration(_integration).getRewardToken() returns (address rewardsToken) {
            return rewardsToken;
        } catch {
            return address(0);
        }
    }
}
