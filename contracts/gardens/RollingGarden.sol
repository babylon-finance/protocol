/*
    Copyright 2020 Babylon Finance.

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
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IGardenValuer} from '../interfaces/IGardenValuer.sol';
import {IReservePool} from '../interfaces/IReservePool.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {BaseGarden} from './BaseGarden.sol';

/**
 * @title RollingGarden
 * @author Babylon Finance
 *
 * RollingGarden holds the logic to deposit, withdraw and track contributions and fees.
 */
contract RollingGarden is ReentrancyGuard, BaseGarden {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;

    /* ============ State Variables ============ */

    struct ActionInfo {
        uint256 preFeeReserveQuantity; // Reserve value before fees; During issuance, represents raw quantity
        // During withdrawal, represents post-premium value
        uint256 protocolFees; // Total protocol fees (direct + manager revenue share)
        uint256 netFlowQuantity; // When issuing, quantity of reserve asset sent to Garden
        // When withdrawaling, quantity of reserve asset sent to withdrawaler
        uint256 gardenTokenQuantity; // When issuing, quantity of Garden tokens minted to mintee
        // When withdrawaling, quantity of Garden tokens withdrawaled
        uint256 previousGardenTokenSupply; // Garden token supply prior to deposit/withdrawal action
        uint256 newGardenTokenSupply; // Garden token supply after deposit/withdrawal action
        uint256 newReservePositionBalance; // Garden token reserve asset position balance after deposit/withdrawal
    }

    uint256 public depositHardlock; // Window of time after deposits when withdraws are disabled for that user
    uint256 public redemptionWindowAfterInvestmentCompletes; // Window of time after an investment strategy finishes when the capital is available for withdrawals
    uint256 public redemptionsOpenUntil; // Indicates until when the redemptions are open and the ETH is set aside

    /* ============ Constructor ============ */

    /**
     * When a new Garden is created, initializes Investments are set to empty.
     * All parameter validations are on the BabController contract. Validations are performed already on the
     * BabController.
     *
     * @param _integrations           List of integrations to enable. All integrations must be approved by the Controller
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     * @param _creator                Address of the creator
     * @param _name                   Name of the Garden
     * @param _symbol                 Symbol of the Garden
     */

    function initialize(
        address[] memory _integrations,
        address _weth,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol
    ) public {
        super.initialize(_integrations, _weth, _weth, _controller, _creator, _name, _symbol);
        totalContributors = 0;
    }

    /* ============ External Functions ============ */

    /**
     * FUND LEAD ONLY.  Starts the Garden with allowed reserve assets,
     * fees and issuance premium. Only callable by the Garden's creator
     *
     * @param _maxDepositLimit                     Max deposit limit
     * @param _minGardenTokenSupply             Min garden token supply
     * @param _minLiquidityAsset                   Number that represents min amount of liquidity denominated in ETH
     * @param _depositHardlock                     Number that represents the time deposits are locked for an user after he deposits
     * @param _minContribution        Min contribution to the garden
     * @param _strategyCooldownPeriod               How long after the strategy has been activated, will it be ready to be executed
     * @param _strategyCreatorProfitPercentage      What percentage of the profits go to the strategy creator
     * @param _strategyVotersProfitPercentage       What percentage of the profits go to the strategy curators
     * @param _gardenCreatorProfitPercentage What percentage of the profits go to the creator of the garden
     * @param _minVotersQuorum                  Percentage of votes needed to activate an investment strategy (0.01% = 1e14, 1% = 1e16)
     * @param _minIdeaDuration                  Min duration of an investment strategy
     * @param _maxIdeaDuration                  Max duration of an investment strategy
     */
    function start(
        uint256 _maxDepositLimit,
        uint256 _minGardenTokenSupply,
        uint256 _minLiquidityAsset,
        uint256 _depositHardlock,
        uint256 _minContribution,
        uint256 _strategyCooldownPeriod,
        uint256 _strategyCreatorProfitPercentage,
        uint256 _strategyVotersProfitPercentage,
        uint256 _gardenCreatorProfitPercentage,
        uint256 _minVotersQuorum,
        uint256 _minIdeaDuration,
        uint256 _maxIdeaDuration
    ) external payable onlyCreator onlyInactive {
        require(_maxDepositLimit < MAX_DEPOSITS_FUND_V1, 'Max deposit limit needs to be under the limit');

        require(msg.value >= minContribution, 'Creator needs to deposit');
        IBabController ifcontroller = IBabController(controller);
        require(_minGardenTokenSupply > 0, 'Min Garden token supply >= 0');
        require(
            _minLiquidityAsset >= ifcontroller.minRiskyPairLiquidityEth(),
            'Needs to be at least the minimum set by protocol'
        );
        // make initial deposit
        uint256 initialDepositAmount = msg.value;
        uint256 initialTokens = initialDepositAmount.div(initialBuyRate);
        require(initialTokens >= minGardenTokenSupply, 'Initial Garden token supply too low');
        require(_depositHardlock > 1, 'Needs to be at least a couple of seconds to prevent flash loan attacks');
        minGardenTokenSupply = _minGardenTokenSupply;
        maxDepositLimit = _maxDepositLimit;
        gardenInitializedAt = block.timestamp;
        minLiquidityAsset = _minLiquidityAsset;
        depositHardlock = _depositHardlock;
        redemptionWindowAfterInvestmentCompletes = 7 days;
        startCommon(
            _minContribution,
            _strategyCooldownPeriod,
            _strategyCreatorProfitPercentage,
            _strategyVotersProfitPercentage,
            _gardenCreatorProfitPercentage,
            _minVotersQuorum,
            _minIdeaDuration,
            _maxIdeaDuration
        );

        // Deposit
        IWETH(weth).deposit{value: initialDepositAmount}();

        _mint(creator, initialTokens);
        _updateContributorInfo(initialTokens, initialDepositAmount);
        _updatePrincipal(initialDepositAmount);

        require(totalSupply() > 0, 'Garden must receive an initial deposit');

        active = true;
    }

    /**
     * Deposits the Garden's position components into the garden and mints the Garden token of the given quantity
     * to the specified _to address.
     *
     * @param _reserveAssetQuantity  Quantity of the reserve asset that are received
     * @param _minGardenTokenReceiveQuantity   Min quantity of Garden token to receive after issuance
     * @param _to                   Address to mint Garden tokens to
     */
    function deposit(
        uint256 _reserveAssetQuantity,
        uint256 _minGardenTokenReceiveQuantity,
        address _to
    ) public payable nonReentrant onlyActive {
        require(msg.value >= minContribution, '>= minContribution');
        // if deposit limit is 0, then there is no deposit limit
        if (maxDepositLimit > 0) {
            require(principal.add(msg.value) <= maxDepositLimit, 'Max Deposit Limit');
        }
        require(msg.value == _reserveAssetQuantity, 'ETH does not match');
        // Oracle maintenance
        updatePositionTWAPPrices();
        // Always wrap to WETH
        IWETH(weth).deposit{value: msg.value}();
        // Check this here to avoid having relayers
        reenableEthForInvestments();

        _validateReserveAsset(reserveAsset, _reserveAssetQuantity);

        ActionInfo memory depositInfo = _createIssuanceInfo(reserveAsset, _reserveAssetQuantity);

        _validateIssuanceInfo(_minGardenTokenReceiveQuantity, depositInfo);

        // Send Protocol Fee
        payProtocolFeeFromGarden(reserveAsset, depositInfo.protocolFees);

        // Updates Reserve Balance and Mint
        _mint(_to, depositInfo.gardenTokenQuantity);
        _updateContributorInfo(depositInfo.gardenTokenQuantity, msg.value);
        _updatePrincipal(depositInfo.newReservePositionBalance);

        emit GardenTokenDeposited(_to, depositInfo.gardenTokenQuantity, depositInfo.protocolFees);
    }

    /**
     * Withdraws the ETH relative to the token participation in the garden and sends it back to the sender.
     *
     * @param _gardenTokenQuantity             Quantity of the garden token to withdrawal
     * @param _minReserveReceiveQuantity     Min quantity of reserve asset to receive
     * @param _to                            Address to send component assets to
     */
    function withdraw(
        uint256 _gardenTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) external nonReentrant onlyContributor onlyActive {
        require(_gardenTokenQuantity <= balanceOf(msg.sender), 'Withdrawal amount <= to deposited amount');
        // Flashloan protection
        require(
            block.timestamp.sub(contributors[msg.sender].timestamp) >= depositHardlock,
            'Cannot withdraw. Hardlock'
        );
        // Check this here to avoid having relayers
        reenableEthForInvestments();
        ActionInfo memory withdrawalInfo = _createRedemptionInfo(reserveAsset, _gardenTokenQuantity);

        _validateReserveAsset(reserveAsset, withdrawalInfo.netFlowQuantity);

        _validateRedemptionInfo(_minReserveReceiveQuantity, _gardenTokenQuantity, withdrawalInfo);

        _burn(msg.sender, _gardenTokenQuantity);

        emit WithdrawalLog(msg.sender, withdrawalInfo.netFlowQuantity, block.timestamp);
        // Check that the rdemption is possible
        require(canWithdrawEthAmount(withdrawalInfo.netFlowQuantity), 'Not enough liquidity in the fund');
        if (address(this).balance >= withdrawalInfo.netFlowQuantity) {
            // Send eth
            (bool sent, ) = _to.call{value: withdrawalInfo.netFlowQuantity}('');
            require(sent, 'Failed to send Ether');
        } else {
            // Send liquid weth balance
            IWETH(weth).withdraw(withdrawalInfo.netFlowQuantity);
            _to.transfer(withdrawalInfo.netFlowQuantity);
        }

        payProtocolFeeFromGarden(reserveAsset, withdrawalInfo.protocolFees);

        _updatePrincipal(withdrawalInfo.newReservePositionBalance);
        emit GardenTokenWithdrawn(msg.sender, _to, withdrawalInfo.gardenTokenQuantity, withdrawalInfo.protocolFees);
    }

    /**
     * Sender is selling his tokens to the reserve pool at a discount.
     * Reserve pool will receive the tokens.
     *
     * @param _gardenTokenQuantity        Quantity of the garden token to withdrawal
     * @param _minReserveReceiveQuantity     Min quantity of reserve asset to receive
     * @param _to                            Address to send component assets to
     */
    function withdrawToReservePool(
        uint256 _gardenTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) external nonReentrant onlyContributor onlyActive {
        require(_gardenTokenQuantity <= balanceOf(msg.sender), 'Withdrawal amount <= to deposited amount');
        // Flashloan protection
        require(
            block.timestamp.sub(contributors[msg.sender].timestamp) >= depositHardlock,
            'Cannot withdraw. Hardlock'
        );

        IReservePool reservePool = IReservePool(IBabController(controller).getReservePool());
        require(reservePool.isReservePoolAllowedToBuy(address(this), _gardenTokenQuantity), 'Reserve Pool not active');

        ActionInfo memory withdrawalInfo = _createRedemptionInfo(reserveAsset, _gardenTokenQuantity);

        _validateReserveAsset(reserveAsset, withdrawalInfo.netFlowQuantity);
        // If normal redemption is available, don't use the reserve pool
        require(!canWithdrawEthAmount(withdrawalInfo.netFlowQuantity), 'Not enough liquidity in the fund');
        _validateRedemptionInfo(_minReserveReceiveQuantity, _gardenTokenQuantity, withdrawalInfo);

        withdrawalInfo.netFlowQuantity = reservePool.sellTokensToLiquidityPool(address(this), _gardenTokenQuantity);

        emit WithdrawalLog(msg.sender, withdrawalInfo.netFlowQuantity, block.timestamp);

        payProtocolFeeFromGarden(reserveAsset, withdrawalInfo.protocolFees);

        _updatePrincipal(withdrawalInfo.newReservePositionBalance);

        emit GardenTokenWithdrawn(msg.sender, _to, withdrawalInfo.gardenTokenQuantity, withdrawalInfo.protocolFees);
    }

    /**
     * When an investment strategy finishes execution, we want to make that eth available for withdrawals
     * from members of the garden.
     *
     * @param _amount                        Amount of WETH to convert to ETH to set aside
     */
    function startRedemptionWindow(uint256 _amount) external onlyStrategyOrOwner {
        redemptionsOpenUntil = block.timestamp.add(redemptionWindowAfterInvestmentCompletes);
        IWETH(weth).withdraw(_amount);
    }

    /**
     * When the window of redemptions finishes, we need to make the capital available again for investments
     *
     */
    function reenableEthForInvestments() public {
        if (block.timestamp >= redemptionsOpenUntil && address(this).balance > minContribution) {
            // Always wrap to WETH
            IWETH(weth).deposit{value: address(this).balance}();
        }
    }

    /**
     * Burns seller garden tokens and mints them to the reserve pool
     *  @param _contributor           Contributor that is selling the tokens
     *  @param _quantity              Amount of tokens being sold to the reserve pool
     */
    function burnAssetsFromSenderAndMintToReserve(address _contributor, uint256 _quantity) external {
        address reservePool = IBabController(controller).getReservePool();
        require(msg.sender == reservePool, 'Only reserve pool can call this');
        _burn(_contributor, _quantity);
        _mint(reservePool, _quantity);
    }

    /* ============ External Getter Functions ============ */

    /**
     * Check if the fund has ETH amount available for withdrawals
     *
     * @param _amount                        Amount of ETH to withdraw
     */
    function canWithdrawEthAmount(uint256 _amount) public view returns (bool) {
        uint256 ethAsideBalance = address(this).balance;
        uint256 liquidWeth = ERC20(reserveAsset).balanceOf(address(this));
        return (redemptionsOpenUntil <= block.timestamp && ethAsideBalance >= _amount) || liquidWeth >= _amount;
    }

    function getContributor(address _contributor)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        Contributor memory contributor = contributors[_contributor];
        return (contributor.totalDeposit, contributor.tokensReceived, contributor.timestamp);
    }

    /**
     * Get the expected reserve asset to be withdrawaled
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _gardenTokenQuantity             Quantity of Garden tokens to withdrawal
     *
     * @return  uint256                     Expected reserve asset quantity withdrawaled
     */
    function getExpectedReserveWithdrawalQuantity(address _reserveAsset, uint256 _gardenTokenQuantity)
        external
        view
        returns (uint256)
    {
        uint256 preFeeReserveQuantity = _getWithdrawalReserveQuantity(_reserveAsset, _gardenTokenQuantity);

        (, uint256 netReserveFlows) = _getFees(preFeeReserveQuantity, false, _gardenTokenQuantity);

        return netReserveFlows;
    }

    /**
     * Checks if deposit is valid
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _reserveAssetQuantity         Quantity of the reserve asset to deposit with
     *
     * @return  bool                        Returns true if deposit is valid
     */
    function isDepositValid(address _reserveAsset, uint256 _reserveAssetQuantity) external view returns (bool) {
        return
            _reserveAssetQuantity != 0 &&
            IBabController(controller).isValidReserveAsset(_reserveAsset) &&
            totalSupply() >= minGardenTokenSupply;
    }

    /**
     * Checks if withdrawal is valid
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _gardenTokenQuantity             Quantity of garden tokens to withdrawal
     *
     * @return  bool                        Returns true if withdrawal is valid
     */
    function isWithdrawalValid(address _reserveAsset, uint256 _gardenTokenQuantity) external view returns (bool) {
        uint256 setTotalSupply = totalSupply();

        if (
            _gardenTokenQuantity == 0 ||
            !IBabController(controller).isValidReserveAsset(_reserveAsset) ||
            setTotalSupply < minGardenTokenSupply.add(_gardenTokenQuantity)
        ) {
            return false;
        } else {
            uint256 totalWithdrawalValue = _getWithdrawalReserveQuantity(_reserveAsset, _gardenTokenQuantity);

            (, uint256 expectedWithdrawalQuantity) = _getFees(totalWithdrawalValue, false, _gardenTokenQuantity);

            return principal >= expectedWithdrawalQuantity;
        }
    }

    receive() external payable {} // solium-disable-line quotes

    /* ============ Internal Functions ============ */

    function _validateReserveAsset(address _reserveAsset, uint256 _quantity) internal view {
        require(_quantity > 0, 'Quantity > 0');
        require(IBabController(controller).isValidReserveAsset(_reserveAsset), 'Must be reserve asset');
    }

    function _validateIssuanceInfo(uint256 _minGardenTokenReceiveQuantity, ActionInfo memory _depositInfo)
        internal
        view
    {
        // Check that total supply is greater than min supply needed for issuance
        // Note: A min supply amount is needed to avoid division by 0 when Garden token supply is 0
        require(_depositInfo.previousGardenTokenSupply >= minGardenTokenSupply, 'Supply must > than minimum');

        require(_depositInfo.gardenTokenQuantity >= _minGardenTokenReceiveQuantity, 'Must be > min Garden token');
    }

    function _validateRedemptionInfo(
        uint256 _minReserveReceiveQuantity,
        uint256, /* _gardenTokenQuantity */
        ActionInfo memory _withdrawalInfo
    ) internal view {
        // Check that new supply is more than min supply needed for redemption
        // Note: A min supply amount is needed to avoid division by 0 when withdrawaling garden token to 0
        require(_withdrawalInfo.newGardenTokenSupply >= minGardenTokenSupply, 'Supply must be > than minimum');

        require(_withdrawalInfo.netFlowQuantity >= _minReserveReceiveQuantity, 'Must be > than min receive');
    }

    function _createIssuanceInfo(address _reserveAsset, uint256 _reserveAssetQuantity)
        internal
        view
        returns (ActionInfo memory)
    {
        ActionInfo memory depositInfo;
        depositInfo.previousGardenTokenSupply = totalSupply();
        depositInfo.preFeeReserveQuantity = _reserveAssetQuantity;

        (depositInfo.protocolFees, depositInfo.netFlowQuantity) = _getFees(depositInfo.preFeeReserveQuantity, true, 0);

        depositInfo.gardenTokenQuantity = _getGardenTokenMintQuantity(
            _reserveAsset,
            depositInfo.netFlowQuantity,
            depositInfo.previousGardenTokenSupply
        );

        // Calculate inflation and new position multiplier. Note: Round inflation up in order to round position multiplier down
        depositInfo.newGardenTokenSupply = depositInfo.gardenTokenQuantity.add(depositInfo.previousGardenTokenSupply);

        depositInfo.newReservePositionBalance = principal.add(depositInfo.netFlowQuantity);

        return depositInfo;
    }

    function _createRedemptionInfo(address _reserveAsset, uint256 _gardenTokenQuantity)
        internal
        view
        returns (ActionInfo memory)
    {
        ActionInfo memory withdrawalInfo;

        withdrawalInfo.gardenTokenQuantity = _gardenTokenQuantity;

        withdrawalInfo.preFeeReserveQuantity = _getWithdrawalReserveQuantity(_reserveAsset, _gardenTokenQuantity);

        (withdrawalInfo.protocolFees, withdrawalInfo.netFlowQuantity) = _getFees(
            withdrawalInfo.preFeeReserveQuantity,
            false,
            _gardenTokenQuantity
        );

        withdrawalInfo.previousGardenTokenSupply = totalSupply();

        withdrawalInfo.newGardenTokenSupply = withdrawalInfo.previousGardenTokenSupply.sub(_gardenTokenQuantity);

        uint256 outflow = withdrawalInfo.netFlowQuantity.add(withdrawalInfo.protocolFees);

        // Require withdrawable quantity is greater than existing collateral
        require(principal >= outflow, 'Must have enough balance');

        withdrawalInfo.newReservePositionBalance = principal.sub(outflow);

        return withdrawalInfo;
    }

    /**
     * Returns the fees attributed to the manager and the protocol. The fees are calculated as follows:
     *
     * Protocol Fee = (% direct fee %) * reserveAssetQuantity
     *
     * @param _reserveAssetQuantity         Quantity of reserve asset to calculate fees from
     * @param _isDeposit                    Boolean that is true when it is a deposit
     * @param _gardenTokenQuantity            Number of garden tokens involved in the operation
     *
     * @return  uint256                     Fees paid to the protocol in reserve asset
     * @return  uint256                     Net reserve to user net of fees
     */
    function _getFees(
        uint256 _reserveAssetQuantity,
        bool _isDeposit,
        uint256 _gardenTokenQuantity
    ) internal view returns (uint256, uint256) {
        // Get protocol fee percentages
        uint256 protocolFeePercentage =
            _isDeposit
                ? IBabController(controller).getProtocolDepositGardenTokenFee()
                : IBabController(controller).getProtocolWithdrawalGardenTokenFee();

        // Calculate total notional fees
        uint256 protocolFees = protocolFeePercentage.preciseMul(_reserveAssetQuantity);

        uint256 netReserveFlow = _reserveAssetQuantity.sub(protocolFees);

        return (protocolFees, netReserveFlow);
    }

    function _getGardenTokenMintQuantity(
        address _reserveAsset,
        uint256 _netReserveFlows, // Value of reserve asset net of fees
        uint256 _gardenTokenTotalSupply
    ) internal view returns (uint256) {
        // Get valuation of the Garden with the quote asset as the reserve asset.
        // Reverts if price is not found
        uint256 gardenValuationPerToken =
            IGardenValuer(IBabController(controller).getGardenValuer()).calculateGardenValuation(
                address(this),
                _reserveAsset
            );
        gardenValuationPerToken = gardenValuationPerToken.sub(_netReserveFlows.preciseDiv(totalSupply()));

        // Get reserve asset decimals
        uint8 reserveAssetDecimals = ERC20(_reserveAsset).decimals();
        uint256 baseUnits = uint256(10)**reserveAssetDecimals;
        uint256 normalizedTotalReserveQuantityNetFees = _netReserveFlows.preciseDiv(baseUnits);

        uint256 normalizedTotalReserveQuantityNetFeesAndPremium = _netReserveFlows.preciseDiv(baseUnits);

        // Calculate Garden tokens to mint to depositor
        uint256 denominator =
            _gardenTokenTotalSupply.preciseMul(gardenValuationPerToken).add(normalizedTotalReserveQuantityNetFees).sub(
                normalizedTotalReserveQuantityNetFeesAndPremium
            );
        uint256 quantityToMint =
            normalizedTotalReserveQuantityNetFeesAndPremium.preciseMul(_gardenTokenTotalSupply).preciseDiv(denominator);
        return quantityToMint;
    }

    function _getWithdrawalReserveQuantity(address _reserveAsset, uint256 _gardenTokenQuantity)
        internal
        view
        returns (uint256)
    {
        // Get valuation of the Garden with the quote asset as the reserve asset. Returns value in precise units (10e18)
        // Reverts if price is not found
        uint256 gardenValuationPerToken =
            IGardenValuer(IBabController(controller).getGardenValuer()).calculateGardenValuation(
                address(this),
                _reserveAsset
            );

        uint256 totalWithdrawalValueInPreciseUnits = _gardenTokenQuantity.preciseMul(gardenValuationPerToken);
        // Get reserve asset decimals
        uint8 reserveAssetDecimals = ERC20(_reserveAsset).decimals();
        uint256 prePremiumReserveQuantity = totalWithdrawalValueInPreciseUnits.preciseMul(10**reserveAssetDecimals);

        return prePremiumReserveQuantity;
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorInfo(uint256 tokensReceived, uint256 amount) internal {
        Contributor storage contributor = contributors[msg.sender];
        // If new contributor, create one, increment count, and set the current TS
        if (contributor.totalDeposit == 0) {
            totalContributors = totalContributors.add(1);
        }
        contributor.timestamp = block.timestamp;
        contributor.totalDeposit = contributor.totalDeposit.add(amount);
        contributor.tokensReceived = contributor.tokensReceived.add(tokensReceived);

        emit ContributionLog(msg.sender, amount, tokensReceived, block.timestamp);
    }
}
