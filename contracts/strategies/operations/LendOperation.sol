// SPDX-License-Identifier: Apache-2.0



pragma solidity 0.8.9;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {ILendIntegration} from '../../interfaces/ILendIntegration.sol';

import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';

import {Operation} from './Operation.sol';

/**
 * @title LendOperation
 * @author Babylon Finance
 *
 * Executes a lend operation
 */
contract LendOperation is Operation {
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;
    using BytesLib for bytes;

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
     * @param _asset              Asset to receive into this operation
     * @param _capital            Amount of asset received
     * param _assetStatus         Status of the asset amount
     * @param _data               OpData e.g. Address of the asset to lend
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
        address assetToken = BytesLib.decodeOpDataAddress(_data); // We just use the first 20 bytes from the whole opEncodedData
        if (assetToken != _asset) {
            // Trade to WETH if is 0x0 (eth in compound)
            if (assetToken != address(0) || _asset != WETH) {
                IStrategy(msg.sender).trade(_asset, _capital, assetToken == address(0) ? WETH : assetToken);
            }
        }
        uint256 numTokensToSupply;
        if (assetToken == address(0)) {
            // change it to plain eth for compound
            IStrategy(msg.sender).handleWeth(false, IERC20(WETH).balanceOf(msg.sender));
            numTokensToSupply = address(msg.sender).balance;
        } else {
            numTokensToSupply = IERC20(assetToken).balanceOf(msg.sender);
        }
        uint256 exactAmount = ILendIntegration(_integration).getExpectedShares(assetToken, numTokensToSupply);
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(SLIPPAGE_ALLOWED));
        ILendIntegration(_integration).supplyTokens(msg.sender, assetToken, numTokensToSupply, minAmountExpected);
        return (assetToken, numTokensToSupply, 1); // put as collateral
    }

    /**
     * Exits the lend operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        address _borrowToken,
        uint256 _remaining,
        uint8, /* _assetStatus */
        uint256 _percentage,
        bytes memory _data,
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
        address assetToken = BytesLib.decodeOpDataAddressAssembly(_data, 12);
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        _redeemTokens(_borrowToken, _remaining, _percentage, msg.sender, _integration, assetToken);
        _tokenToTrade(_percentage, assetToken, msg.sender, _garden, _integration);
        return (_garden.reserveAsset(), IERC20(_garden.reserveAsset()).balanceOf(msg.sender), 0);
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
        uint256 _remaining,
        uint256 _percentage,
        address _sender,
        address _integration,
        address _assetToken
    ) internal {
        // Normalize to underlying asset if any (ctokens for compound)
        uint256 numTokensToRedeem = ILendIntegration(_integration).getInvestmentTokenAmount(_sender, _assetToken);
        // Apply percentage
        numTokensToRedeem = numTokensToRedeem.preciseMul(_percentage);
        uint256 remainingDebtInCollateralTokens = _getRemainingDebt(_borrowToken, _assetToken, _remaining);
        remainingDebtInCollateralTokens = SafeDecimalMath.normalizeAmountTokens(
            _borrowToken,
            _assetToken,
            remainingDebtInCollateralTokens
        );

        if (_remaining > 0) {
            // Update amount so we can exit if there is debt
            try ILendIntegration(_integration).getCollateralFactor(_assetToken) returns (uint256 collateralPctg) {
                numTokensToRedeem = numTokensToRedeem.sub(
                    remainingDebtInCollateralTokens.preciseDiv(collateralPctg).mul(105).div(100)
                ); // add a bit extra 5% just in case
            } catch {
                numTokensToRedeem = numTokensToRedeem.sub(remainingDebtInCollateralTokens.mul(140).div(100));
            }
        }
        uint256 exchangeRate = ILendIntegration(_integration).getExchangeRatePerToken(_assetToken);
        // replace old aave
        if (_integration == 0x9b468eb07082bE767895eA7A9019619c3Db3BC89) {
            _integration = 0x72e27dA102a67767a7a3858D117159418f93617D;
        }
        ILendIntegration(_integration).redeemTokens(
            msg.sender,
            _assetToken,
            numTokensToRedeem,
            exchangeRate.mul(numTokensToRedeem.sub(numTokensToRedeem.preciseMul(SLIPPAGE_ALLOWED.mul(2))))
        );
    }

    function _tokenToTrade(
        uint256 _percentage,
        address _assetToken,
        address _sender,
        IGarden _garden,
        address _integration
    ) internal {
        address tokenToTradeFrom = _assetToken;
        // if eth, convert it to weth
        if (_assetToken == address(0)) {
            tokenToTradeFrom = WETH;
            IStrategy(_sender).handleWeth(true, _sender.balance);
        }
        if (tokenToTradeFrom != _garden.reserveAsset()) {
            IStrategy(_sender).trade(
                tokenToTradeFrom,
                IERC20(tokenToTradeFrom).balanceOf(_sender),
                _garden.reserveAsset(),
                0
            );
        }
        address rewardsToken = _getRewardToken(_integration);
        // Only sell rewards when the strategy finalizes
        if (rewardsToken != address(0) && _percentage == HUNDRED_PERCENT) {
            uint256 rewardsBalance = IERC20(rewardsToken).balanceOf(_sender);
            // Add rewards
            if (rewardsBalance > 1e16) {
                IStrategy(_sender).trade(rewardsToken, rewardsBalance, _garden.reserveAsset(), 70e15);
            }
        }
    }

    function _getRemainingDebt(
        address _borrowToken,
        address _assetToken,
        uint256 _remaining
    ) private view returns (uint256) {
        if (_remaining == 0) {
            return 0;
        }
        uint256 price = _getPrice(_borrowToken, _assetToken);
        return _remaining.preciseMul(price);
    }

    function _getRewardToken(address _integration) private view returns (address) {
        try ILendIntegration(_integration).getRewardToken() returns (address rewardsToken) {
            return rewardsToken;
        } catch {
            return address(0);
        }
    }
}
