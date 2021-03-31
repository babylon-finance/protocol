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
import {IReservePool} from '../interfaces/IReservePool.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {BaseGarden} from './BaseGarden.sol';
import {Safe3296} from '../lib/Safe3296.sol';

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

    mapping(address => uint256) public redemptionRequests; // Current redemption requests for this window
    uint256 public totalRequestsAmountInWindow; // Total Redemption Request Amount
    uint256 public reserveAvailableForRedemptionsInWindow; // Total available for redemptions in this window

    uint256 public constant BABL_STRATEGIST_SHARE = 8e16;
    uint256 public constant BABL_STEWARD_SHARE = 17e16;
    uint256 public constant BABL_LP_SHARE = 75e16;

    uint256 public constant PROFIT_STRATEGIST_SHARE = 10e16;
    uint256 public constant PROFIT_STEWARD_SHARE = 5e16;
    uint256 public constant PROFIT_LP_SHARE = 80e16;
    uint256 public constant PROFIT_PROTOCOL_FEE = 5e16;

    uint256 public constant CREATOR_BONUS = 15e16;

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
        require(_depositHardlock > 0, 'Deposit hardlock needs to be at least 1 block');
        require(
            _minLiquidityAsset >= ifcontroller.minRiskyPairLiquidityEth(),
            'Needs to be at least the minimum set by protocol'
        );
        // make initial deposit
        uint256 initialDepositAmount = msg.value;
        uint256 initialTokens = initialDepositAmount;
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

        uint256 previousBalance = balanceOf(msg.sender);
        _mint(creator, initialTokens);
        _updateContributorDepositInfo(previousBalance, initialDepositAmount);
        _updatePrincipal(initialDepositAmount);

        require(totalSupply() > 0, 'Garden must receive an initial deposit');
        active = true;
        emit GardenTokenDeposited(msg.sender, msg.value, initialTokens, 0, block.timestamp);
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
        // Always wrap to WETH
        IWETH(weth).deposit{value: msg.value}();
        // Check this here to avoid having relayers
        reenableEthForInvestments();

        _validateReserveAsset(reserveAsset, _reserveAssetQuantity);

        ActionInfo memory depositInfo = _createIssuanceInfo(_reserveAssetQuantity);

        // Check that total supply is greater than min supply needed for issuance
        // Note: A min supply amount is needed to avoid division by 0 when Garden token supply is 0
        require(depositInfo.previousGardenTokenSupply >= minGardenTokenSupply, 'Supply must > than minimum');

        require(depositInfo.gardenTokenQuantity >= _minGardenTokenReceiveQuantity, 'Must be > min Garden token');

        // Send Protocol Fee
        payProtocolFeeFromGarden(reserveAsset, depositInfo.protocolFees);

        // Updates Reserve Balance and Mint
        uint256 previousBalance = balanceOf(msg.sender);
        _mint(_to, depositInfo.gardenTokenQuantity);
        _updateContributorDepositInfo(previousBalance, msg.value);
        _updatePrincipal(depositInfo.newReservePositionBalance);
        emit GardenTokenDeposited(
            _to,
            msg.value,
            depositInfo.gardenTokenQuantity,
            depositInfo.protocolFees,
            block.timestamp
        );
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
    ) external nonReentrant onlyContributor {
        require(_gardenTokenQuantity <= balanceOf(msg.sender), 'Withdrawal amount <= to deposited amount');
        // Flashloan protection
        require(
            block.timestamp.sub(contributors[msg.sender].lastDepositAt) >= depositHardlock,
            'Cannot withdraw. Hardlock'
        );
        // Check this here to avoid having relayers
        reenableEthForInvestments();
        ActionInfo memory withdrawalInfo = _createRedemptionInfo(_gardenTokenQuantity);

        _validateReserveAsset(reserveAsset, withdrawalInfo.netFlowQuantity);

        _validateRedemptionInfo(_minReserveReceiveQuantity, _gardenTokenQuantity, withdrawalInfo);

        _burn(msg.sender, _gardenTokenQuantity);
        _updateContributorWithdrawalInfo(withdrawalInfo.netFlowQuantity);

        // Check that the redemption is possible
        require(canWithdrawEthAmount(msg.sender, withdrawalInfo.netFlowQuantity), 'Not enough liquidity in the fund');
        if (address(this).balance >= withdrawalInfo.netFlowQuantity) {
            // Send eth
            (bool sent, ) = _to.call{value: withdrawalInfo.netFlowQuantity}('');
            require(sent, 'Failed to send Ether');
        } else {
            // Send liquid weth balance
            IWETH(weth).withdraw(withdrawalInfo.netFlowQuantity);
            _to.transfer(withdrawalInfo.netFlowQuantity);
        }
        redemptionRequests[msg.sender] = 0;
        payProtocolFeeFromGarden(reserveAsset, withdrawalInfo.protocolFees);

        _updatePrincipal(withdrawalInfo.newReservePositionBalance);

        emit GardenTokenWithdrawn(
            msg.sender,
            _to,
            withdrawalInfo.netFlowQuantity,
            withdrawalInfo.gardenTokenQuantity,
            withdrawalInfo.protocolFees,
            block.timestamp
        );
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
            block.timestamp.sub(contributors[msg.sender].lastDepositAt) >= depositHardlock,
            'Cannot withdraw. Hardlock'
        );

        IReservePool reservePool = IReservePool(IBabController(controller).getReservePool());
        require(reservePool.isReservePoolAllowedToBuy(address(this), _gardenTokenQuantity), 'Reserve Pool not active');

        ActionInfo memory withdrawalInfo = _createRedemptionInfo(_gardenTokenQuantity);

        _validateReserveAsset(reserveAsset, withdrawalInfo.netFlowQuantity);
        // If normal redemption is available, don't use the reserve pool
        require(!canWithdrawEthAmount(msg.sender, withdrawalInfo.netFlowQuantity), 'Not enough liquidity in the fund');
        _validateRedemptionInfo(_minReserveReceiveQuantity, _gardenTokenQuantity, withdrawalInfo);

        withdrawalInfo.netFlowQuantity = reservePool.sellTokensToLiquidityPool(address(this), _gardenTokenQuantity);
        _updateContributorWithdrawalInfo(withdrawalInfo.netFlowQuantity);

        payProtocolFeeFromGarden(reserveAsset, withdrawalInfo.protocolFees);

        _updatePrincipal(withdrawalInfo.newReservePositionBalance);

        emit GardenTokenWithdrawn(
            msg.sender,
            _to,
            withdrawalInfo.netFlowQuantity,
            withdrawalInfo.gardenTokenQuantity,
            withdrawalInfo.protocolFees,
            block.timestamp
        );
    }

    /**
     * User can claim the profits from the strategies that his principal
     * was invested in.
     */
    // Raul Review
    function claimReturns(address[] calldata _finalizedStrategies) external nonReentrant onlyContributor {
        Contributor memory contributor = contributors[msg.sender];
        (uint256 totalProfits, uint256 bablRewards) = this._getProfitsAndBabl(_finalizedStrategies);
        if (totalProfits > 0 && address(this).balance > 0) {
            // Send eth
            (bool sent, ) = msg.sender.call{value: totalProfits}('');
            require(sent, 'Failed to send Ether');
            contributor.claimedAt = block.timestamp;
        }
        if (bablRewards > 0) {
            // Send BABL rewards
            contributors[msg.sender].claimedBABL = contributors[msg.sender].claimedBABL.add(bablRewards);
            IRewardsDistributor rewardsDistributor =
                IRewardsDistributor(IBabController(controller).getRewardsDistributor());
            rewardsDistributor.sendTokensToContributor(msg.sender, bablRewards);
        }
    }

    // Raul Review
    function _getProfitsAndBabl(address[] calldata _finalizedStrategies)
        external
        view
        onlyContributor
        returns (uint256, uint256)
    {
        require(contributors[msg.sender].lastDepositAt > contributors[msg.sender].claimedAt, 'Nothing new to claim');
        uint256 contributorProfits = 0;
        uint256 bablTotalRewards = 0;
        for (uint256 i = 0; i < _finalizedStrategies.length; i++) {
            IStrategy strategy = IStrategy(_finalizedStrategies[i]);
            uint256 totalProfits = 0; // Total Profits of each finalized strategy
            // Positive strategies not yet claimed
            if (
                strategy.exitedAt() > contributors[msg.sender].claimedAt &&
                strategy.enteredAt() >= contributors[msg.sender].initialDepositAt // TODO: may need to remove because of rebalance
            ) {
                // If strategy returned money we give out the profits
                if (strategy.capitalReturned() > strategy.capitalAllocated()) {
                    // (User percentage * strategy profits) / (strategy capital)
                    totalProfits = totalProfits.add(strategy.capitalReturned().sub(strategy.capitalAllocated()));
                }
                // Give out BABL
                uint256 creatorBonus = msg.sender == creator ? CREATOR_BONUS : 0;
                bool isStrategist = msg.sender == strategy.strategist();
                bool isVoter = strategy.getUserVotes(msg.sender) != 0;
                // pending userPrincipal improvement to have more accurate calculations
                uint256 strategyRewards = strategy.strategyRewards();
                uint256 bablRewards = 0;

                // Get strategist rewards in case the contributor is also the strategist of the strategy
                if (isStrategist) {
                    bablRewards = bablRewards.add(strategyRewards.preciseMul(BABL_STRATEGIST_SHARE));
                    contributorProfits = contributorProfits.add(totalProfits.preciseMul(PROFIT_STRATEGIST_SHARE));
                }

                // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
                if (isVoter) {
                    bablRewards = bablRewards.add(
                        strategyRewards
                            .preciseMul(BABL_STEWARD_SHARE)
                            .mul(uint256(strategy.getUserVotes(msg.sender)))
                            .div(strategy.absoluteTotalVotes())
                    );
                    contributorProfits = contributorProfits.add(
                        totalProfits
                            .preciseMul(PROFIT_STEWARD_SHARE)
                            .mul(uint256(strategy.getUserVotes(msg.sender)))
                            .div(strategy.absoluteTotalVotes())
                    );
                }

                // Get proportional LP rewards as every active contributor of the garden is a LP of their strategies
                bablRewards = bablRewards.add(
                    strategyRewards.preciseMul(BABL_LP_SHARE).mul(contributors[msg.sender].gardenAverageOwnership)
                );
                contributorProfits = contributorProfits.add(
                    contributors[msg.sender].gardenAverageOwnership.mul(totalProfits).preciseMul(PROFIT_LP_SHARE)
                );

                // Get a multiplier bonus in case the contributor is the garden creator
                if (creatorBonus > 0) {
                    bablRewards = bablRewards.add(bablRewards.preciseMul(creatorBonus));
                }

                bablTotalRewards = bablTotalRewards.add(bablRewards);
            }
        }
        return (contributorProfits, Safe3296.safe96(bablTotalRewards, 'overflow 96 bits'));
    }

    /**
     * When an investment strategy finishes execution, we want to make that eth available for withdrawals
     * from members of the garden.
     *
     * @param _amount                        Amount of WETH to convert to ETH to set aside
     */
    function startRedemptionWindow(uint256 _amount) external onlyStrategyOrOwner {
        redemptionsOpenUntil = block.timestamp.add(redemptionWindowAfterInvestmentCompletes);
        reserveAvailableForRedemptionsInWindow.add(_amount);
        IWETH(weth).withdraw(_amount);
    }

    /**
     * When the window of redemptions finishes, we need to make the capital available again for investments
     *
     */
    function reenableEthForInvestments() public {
        if (block.timestamp >= redemptionsOpenUntil && address(this).balance > minContribution) {
            // Always wrap to WETH
            totalRequestsAmountInWindow = 0;
            reserveAvailableForRedemptionsInWindow = 0;
            redemptionsOpenUntil = 0;
            IWETH(weth).deposit{value: address(this).balance}();
        }
    }

    /**
     * When the window of redemptions is open, signal your intention to redeem.
     *
     * @param _amount Amount to request a redemption in next window
     */
    function requestRedemptionAmount(uint256 _amount) public {
        require(_amount <= balanceOf(msg.sender), 'Withdrawal amount <= to deposited amount');
        // Flashloan protection
        require(
            block.timestamp.sub(contributors[msg.sender].lastDepositAt) >= depositHardlock,
            'Cannot withdraw. Hardlock'
        );
        require(redemptionsOpenUntil == 0, 'There is an open redemption window already');
        require(redemptionRequests[msg.sender] == 0, 'Cannot request twice in the same window');
        redemptionRequests[msg.sender] = _amount;
        totalRequestsAmountInWindow.add(_amount);
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
     * Check if the fund has ETH amount available for withdrawals.
     * If it returns false, reserve pool would be available.
     * @param _contributor                   Address of the contributors
     * @param _amount                        Amount of ETH to withdraw
     */
    function canWithdrawEthAmount(address _contributor, uint256 _amount) public view returns (bool) {
        uint256 ethAsideBalance = address(this).balance;
        uint256 liquidWeth = ERC20(reserveAsset).balanceOf(address(this));

        // Weth already available
        if (liquidWeth >= _amount) {
            return true;
        }

        // Redemptions open
        if (block.timestamp <= redemptionsOpenUntil) {
            // Requested a redemption
            if (redemptionRequests[_contributor] > 0) {
                return
                    redemptionRequests[_contributor].div(totalRequestsAmountInWindow).mul(
                        reserveAvailableForRedemptionsInWindow
                    ) >= _amount;
            }
            // Didn't request a redemption
            return ethAsideBalance.sub(reserveAvailableForRedemptionsInWindow) >= _amount;
        }
        return false;
    }

    /**
     * Get the expected reserve asset to be withdrawaled
     *
     * @param _gardenTokenQuantity             Quantity of Garden tokens to withdrawal
     *
     * @return  uint256                     Expected reserve asset quantity withdrawaled
     */
    function getExpectedReserveWithdrawalQuantity(uint256 _gardenTokenQuantity) external view returns (uint256) {
        (, uint256 netReserveFlows) = _getFees(_gardenTokenQuantity, false);

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
        if (
            _gardenTokenQuantity == 0 ||
            !IBabController(controller).isValidReserveAsset(_reserveAsset) ||
            totalSupply() < minGardenTokenSupply.add(_gardenTokenQuantity)
        ) {
            return false;
        } else {
            uint256 totalWithdrawalValue = _gardenTokenQuantity;

            (, uint256 expectedWithdrawalQuantity) = _getFees(totalWithdrawalValue, false);

            return principal >= expectedWithdrawalQuantity;
        }
    }

    receive() external payable {} // solium-disable-line quotes

    /* ============ Internal Functions ============ */

    function _validateReserveAsset(address _reserveAsset, uint256 _quantity) internal view {
        require(_quantity > 0, 'Quantity > 0');
        require(IBabController(controller).isValidReserveAsset(_reserveAsset), 'Must be reserve asset');
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

    function _createIssuanceInfo(uint256 _reserveAssetQuantity) internal view returns (ActionInfo memory) {
        ActionInfo memory depositInfo;
        depositInfo.previousGardenTokenSupply = totalSupply();
        depositInfo.preFeeReserveQuantity = _reserveAssetQuantity;

        (depositInfo.protocolFees, depositInfo.netFlowQuantity) = _getFees(depositInfo.preFeeReserveQuantity, true);

        depositInfo.gardenTokenQuantity = depositInfo.netFlowQuantity;

        // Calculate inflation and new position multiplier. Note: Round inflation up in order to round position multiplier down
        depositInfo.newGardenTokenSupply = depositInfo.gardenTokenQuantity.add(depositInfo.previousGardenTokenSupply);

        depositInfo.newReservePositionBalance = principal.add(depositInfo.netFlowQuantity);

        return depositInfo;
    }

    function _createRedemptionInfo(uint256 _gardenTokenQuantity) internal view returns (ActionInfo memory) {
        ActionInfo memory withdrawalInfo;

        withdrawalInfo.gardenTokenQuantity = _gardenTokenQuantity;

        withdrawalInfo.preFeeReserveQuantity = _gardenTokenQuantity;

        (withdrawalInfo.protocolFees, withdrawalInfo.netFlowQuantity) = _getFees(
            withdrawalInfo.preFeeReserveQuantity,
            false
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
     *
     * @return  uint256                     Fees paid to the protocol in reserve asset
     * @return  uint256                     Net reserve to user net of fees
     */
    function _getFees(uint256 _reserveAssetQuantity, bool _isDeposit) internal view returns (uint256, uint256) {
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

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorDepositInfo(uint256 previousBalance, uint256 amount) internal {
        Contributor storage contributor = contributors[msg.sender];
        // If new contributor, create one, increment count, and set the current TS
        if (previousBalance == 0) {
            totalContributors = totalContributors.add(1);
            contributor.gardenAverageOwnership = amount.preciseDiv(totalSupply());
            contributor.initialDepositAt = block.timestamp;
        } else {
            // Cumulative moving average
            // CMAn+1 = New value + (CMAn * operations) / (operations + 1)
            contributor.gardenAverageOwnership = contributor
                .gardenAverageOwnership
                .mul(contributor.numberOfOps)
                .add(balanceOf(msg.sender).preciseDiv(totalSupply()))
                .div(contributor.numberOfOps.add(1));
        }
        contributor.lastDepositAt = block.timestamp;
        contributor.numberOfOps = contributor.numberOfOps.add(1);
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorWithdrawalInfo(
        uint256 /*amount*/
    ) internal {
        Contributor storage contributor = contributors[msg.sender];
        // If sold everything
        if (balanceOf(msg.sender) == 0) {
            contributor.lastDepositAt = 0;
            contributor.initialDepositAt = 0;
            contributor.gardenAverageOwnership = 0;
            contributor.numberOfOps = 0;
            totalContributors = totalContributors.sub(1);
        } else {
            contributor.gardenAverageOwnership = contributor
                .gardenAverageOwnership
                .mul(contributor.numberOfOps)
                .add(balanceOf(msg.sender).preciseDiv(totalSupply()))
                .div(contributor.numberOfOps.add(1));
            contributor.numberOfOps = contributor.numberOfOps.add(1);
        }
    }
}
