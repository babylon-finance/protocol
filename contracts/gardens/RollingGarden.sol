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

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';

import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {Safe3296} from '../lib/Safe3296.sol';
import {Errors, _require} from '../lib/BabylonErrors.sol';

import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {BaseGarden} from './BaseGarden.sol';

/* solhint-disable private-vars-leading-underscore */

/**
 * @title RollingGarden
 * @author Babylon Finance
 *
 * RollingGarden holds the logic to deposit, withdraw and track contributions and fees.
 */
contract RollingGarden is ReentrancyGuard, BaseGarden {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for int256;
    using SafeDecimalMath for uint256;
    using Address for address;

    /* ============ Events ============ */
    event ProfitsForContributor(address indexed _contributor, uint256 indexed _amount);

    event BABLRewardsForContributor(address indexed _contributor, uint96 _rewards);

    /* ============ State Variables ============ */

    struct ActionInfo {
        // During withdrawal, represents post-premium value
        uint256 protocolFees; // Total protocol fees (direct + manager revenue share)
        uint256 netFlowQuantity; // When issuing, quantity of reserve asset sent to Garden
        // When withdrawaling, quantity of reserve asset sent to withdrawaler
        uint256 gardenTokenQuantity; // When issuing, quantity of Garden tokens minted to mintee
        // When withdrawaling, quantity of Garden tokens withdrawaled
        uint256 newGardenTokenSupply; // Garden token supply after deposit/withdrawal action
    }

    uint256 public depositHardlock; // Window of time after deposits when withdraws are disabled for that user
    // Window of time after an investment strategy finishes when the capital is available for withdrawals
    uint256 public withdrawalWindowAfterStrategyCompletes;
    uint256 public withdrawalsOpenUntil; // Indicates until when the withdrawals are open and the ETH is set aside

    uint256 public constant EARLY_WITHDRAWAL_PENALTY = 15e16;

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
     * When a new Garden is created, initializes strategies are set to empty.
     * All parameter validations are on the BabController contract. Validations are performed already on the
     * BabController.
     *
     * @param _reserveAsset           Address of the reserve asset. Initially WETH ERC20
     * @param _controller             Address of the controller
     * @param _creator                Address of the creator
     * @param _name                   Name of the Garden
     * @param _symbol                 Symbol of the Garden
     */

    function initialize(
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol
    ) public override {
        super.initialize(_reserveAsset, _controller, _creator, _name, _symbol);
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
     * @param _minVotersQuorum                  Percentage of votes needed to activate an strategy (0.01% = 1e14, 1% = 1e16)
     * @param _minStrategyDuration                  Min duration of an strategy
     * @param _maxStrategyDuration                  Max duration of an strategy
     */
    function start(
        uint256 _maxDepositLimit,
        uint256 _minGardenTokenSupply,
        uint256 _minLiquidityAsset,
        uint256 _depositHardlock,
        uint256 _minContribution,
        uint256 _strategyCooldownPeriod,
        uint256 _minVotersQuorum,
        uint256 _minStrategyDuration,
        uint256 _maxStrategyDuration
    ) external payable onlyCreator onlyInactive {
        _require(_maxDepositLimit <= MAX_DEPOSITS_FUND_V1, Errors.MAX_DEPOSIT_LIMIT);

        _require(msg.value >= minContribution, Errors.MIN_CONTRIBUTION);
        IBabController babController = IBabController(controller);
        _require(_minGardenTokenSupply > 0, Errors.MIN_TOKEN_SUPPLY);
        _require(_depositHardlock > 0, Errors.DEPOSIT_HARDLOCK);
        _require(_minLiquidityAsset >= babController.minRiskyPairLiquidityEth(), Errors.MIN_LIQUIDITY);
        // make initial deposit
        _require(msg.value >= _minGardenTokenSupply, Errors.MIN_LIQUIDITY);
        _require(msg.value <= _maxDepositLimit, Errors.MAX_DEPOSIT_LIMIT);
        minGardenTokenSupply = _minGardenTokenSupply;
        maxDepositLimit = _maxDepositLimit;
        gardenInitializedAt = block.timestamp;
        minLiquidityAsset = _minLiquidityAsset;
        depositHardlock = _depositHardlock;
        withdrawalWindowAfterStrategyCompletes = 7 days;
        startCommon(
            _minContribution,
            _strategyCooldownPeriod,
            _minVotersQuorum,
            _minStrategyDuration,
            _maxStrategyDuration
        );

        // Deposit
        IWETH(WETH).deposit{value: msg.value}();

        uint256 previousBalance = balanceOf(msg.sender);
        _mint(creator, msg.value);
        _updateContributorDepositInfo(previousBalance);
        _updatePrincipal(msg.value);

        _require(totalSupply() > 0, Errors.MIN_LIQUIDITY);
        active = true;
        emit GardenDeposit(msg.sender, msg.value, msg.value, 0, block.timestamp);
    }

    /**
     * Deposits the reserve asset into the garden and mints the Garden token of the given quantity
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
        _require(msg.value >= minContribution, Errors.MIN_CONTRIBUTION);
        // if deposit limit is 0, then there is no deposit limit
        if (maxDepositLimit > 0) {
            _require(principal.add(msg.value) <= maxDepositLimit, Errors.MAX_DEPOSIT_LIMIT);
        }
        _require(msg.value == _reserveAssetQuantity, Errors.MSG_VALUE_DO_NOT_MATCH);
        // Always wrap to WETH
        IWETH(WETH).deposit{value: msg.value}();
        // Check this here to avoid having relayers
        reenableEthForStrategies();

        _validateReserveAsset(reserveAsset, _reserveAssetQuantity);

        ActionInfo memory depositInfo = _createIssuanceInfo(_reserveAssetQuantity);

        // Check that total supply is greater than min supply needed for issuance
        // TODO: A min supply amount is needed to avoid division by 0 when Garden token supply is 0
        _require(totalSupply() >= minGardenTokenSupply, Errors.MIN_TOKEN_SUPPLY);

        // gardenTokenQuantity has to be at least _minGardenTokenReceiveQuantity
        _require(depositInfo.gardenTokenQuantity >= _minGardenTokenReceiveQuantity, Errors.MIN_TOKEN_SUPPLY);

        // Send Protocol Fee
        payProtocolFeeFromGarden(reserveAsset, depositInfo.protocolFees);

        // Updates Reserve Balance and Mint
        uint256 previousBalance = balanceOf(msg.sender);
        _mint(_to, depositInfo.gardenTokenQuantity);
        _updateContributorDepositInfo(previousBalance);
        _updatePrincipal(principal.add(depositInfo.netFlowQuantity));
        emit GardenDeposit(_to, msg.value, depositInfo.gardenTokenQuantity, depositInfo.protocolFees, block.timestamp);
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
        _withdraw(_gardenTokenQuantity, _minReserveReceiveQuantity, _to);
    }

    /**
     * Requests an immediate withdrawal taking the EARLY_WITHDRAWAL_PENALTY that stays invested.
     *
     * @param _gardenTokenQuantity              Quantity of the garden token to withdrawal
     * @param _to                               Address to send component assets to
     */
    function withdrawWithPenalty(uint256 _gardenTokenQuantity, address payable _to)
        external
        nonReentrant
        onlyContributor
    {
        // Check that cannot do a normal withdrawal
        _require(!canWithdrawEthAmount(msg.sender, _gardenTokenQuantity), Errors.NORMAL_WITHDRAWAL_POSSIBLE);
        uint256 netReserveFlows = _gardenTokenQuantity.sub(_gardenTokenQuantity.preciseMul(EARLY_WITHDRAWAL_PENALTY));
        (uint256 totalActive, uint256 largestCapital, address maxStrategy) = getActiveCapital();
        // Check that strategy has enough capital to support the withdrawal
        require(IStrategy(maxStrategy).minRebalanceCapital() <= largestCapital.sub(netReserveFlows));
        IStrategy(maxStrategy).unwindStrategy(netReserveFlows);
        // We burn their penalty
        _burn(msg.sender, _gardenTokenQuantity.preciseMul(EARLY_WITHDRAWAL_PENALTY));
        _withdraw(_gardenTokenQuantity, netReserveFlows, _to);
    }

    /**
     * User can claim the profits from the strategies that his principal
     * was invested in.
     */
    function claimReturns(address[] calldata _finalizedStrategies) external nonReentrant onlyContributor {
        Contributor storage contributor = contributors[msg.sender];
        _require(block.timestamp > contributor.claimedAt, Errors.ALREADY_CLAIMED); // race condition check

        (uint256 totalProfits, uint256 bablRewards) = _getProfitsAndBabl(_finalizedStrategies);

        if (totalProfits > 0 && address(this).balance > 0) {
            contributor.claimedProfits = contributor.claimedProfits.add(totalProfits); // Profits claimed properly
            // Send ETH
            Address.sendValue(msg.sender, totalProfits);
            emit ProfitsForContributor(msg.sender, totalProfits);
        }
        if (bablRewards > 0) {
            contributor.claimedBABL = contributor.claimedBABL.add(bablRewards); // BABL Rewards claimed properly
            contributor.claimedAt = block.timestamp; // Checkpoint of this claim
            // Send BABL rewards
            IRewardsDistributor rewardsDistributor =
                IRewardsDistributor(IBabController(controller).rewardsDistributor());
            rewardsDistributor.sendTokensToContributor(msg.sender, uint96(bablRewards));
            emit BABLRewardsForContributor(msg.sender, uint96(bablRewards));
        }
    }

    /**
     * When an strategy finishes execution, contributors might want
     * to know the profits and BABL rewards for their participation in the different strategies
     *
     * @param _finalizedStrategies       Array of the finalized strategies
     */

    function getProfitsAndBabl(address[] calldata _finalizedStrategies)
        public
        view
        onlyContributor
        returns (uint256, uint96)
    {
        return _getProfitsAndBabl(_finalizedStrategies);
    }

    /**
     * When an strategy finishes execution, we want to make that eth available for withdrawals
     * from members of the garden.
     *
     * @param _amount                        Amount of WETH to convert to ETH to set aside
     */
    function startWithdrawalWindow(uint256 _amount) external onlyStrategyOrProtocol {
        if (withdrawalsOpenUntil > block.timestamp) {
            withdrawalsOpenUntil = block.timestamp.add(
                withdrawalWindowAfterStrategyCompletes.sub(withdrawalsOpenUntil.sub(block.timestamp))
            );
        } else {
            withdrawalsOpenUntil = block.timestamp.add(withdrawalWindowAfterStrategyCompletes);
        }
        IWETH(WETH).withdraw(_amount);
    }

    /**
     * When the window of withdrawals finishes, we need to make the capital available again for investments
     *
     */
    function reenableEthForStrategies() public {
        if (block.timestamp >= withdrawalsOpenUntil && address(this).balance > minContribution) {
            withdrawalsOpenUntil = 0;
            IWETH(WETH).deposit{value: address(this).balance}();
        }
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

        // Withdrawal open
        if (block.timestamp <= withdrawalsOpenUntil) {
            // Pro rata withdrawals
            return ethAsideBalance.preciseMul(contributors[msg.sender].gardenAverageOwnership) >= _amount;
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

    /**
     * Checks balance locked for strategists and voters in active strategies
     *
     * @param _contributor                 Address of the account
     *
     * @return  uint256                    Returns the amount of locked garden tokens for the account
     */
    function getLockedBalance(address _contributor) external view returns (uint256) {
        uint256 lockedAmount;
        for (uint256 i = 0; i <= strategies.length - 1; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            uint256 votes = uint256(_abs(strategy.getUserVotes(_contributor)));
            if (votes > 0) {
                lockedAmount += votes;
            }
            if (_contributor == strategy.strategist()) {
                lockedAmount += strategy.stake();
            }
        }
        if (balanceOf(_contributor) < lockedAmount) lockedAmount = balanceOf(_contributor); // TODO Remove when implementing locked stake in voting and strategy creation - Now this avoid overflows
        return lockedAmount;
    }

    /**
     * Gets the total active capital currently invested in strategies
     *
     * @return uint256       Total amount active
     * @return uint256       Total amount active in the largest strategy
     * @return address       Address of the largest strategy
     */
    function getActiveCapital()
        public
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        uint256 totalActiveCapital = 0;
        uint256 maxAllocation = 0;
        address maxStrategy = address(0);
        for (uint8 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            if (strategy.isStrategyActive()) {
                uint256 allocation = strategy.capitalAllocated();
                totalActiveCapital = totalActiveCapital.add(allocation);
                if (allocation > maxAllocation) {
                    maxAllocation = allocation;
                    maxStrategy = strategies[i];
                }
            }
        }
        return (totalActiveCapital, maxAllocation, maxStrategy);
    }

    // solhint-disable-next-line
    receive() external payable {}

    /* ============ Internal Functions ============ */

    /**
     * Aux function to withdraw from a garden
     */
    function _withdraw(
        uint256 _gardenTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) private {
        // Withdrawal amount has to be equal or less than msg.sender balance
        _require(_gardenTokenQuantity <= balanceOf(msg.sender), Errors.MSG_SENDER_TOKENS_DO_NOT_MATCH);
        // Flashloan protection
        _require(
            block.timestamp.sub(contributors[msg.sender].lastDepositAt) >= depositHardlock,
            Errors.TOKENS_TIMELOCKED
        );
        _require(
            _gardenTokenQuantity <= balanceOf(msg.sender).sub(this.getLockedBalance(msg.sender)),
            Errors.TOKENS_TIMELOCKED
        ); // Strategists and Voters cannot withdraw locked stake while in active strategies

        // Check this here to avoid having relayers
        reenableEthForStrategies();
        ActionInfo memory withdrawalInfo = _createRedemptionInfo(_gardenTokenQuantity);
        _require(canWithdrawEthAmount(msg.sender, withdrawalInfo.netFlowQuantity), Errors.MIN_LIQUIDITY);

        _validateReserveAsset(reserveAsset, withdrawalInfo.netFlowQuantity);

        _validateRedemptionInfo(_minReserveReceiveQuantity, _gardenTokenQuantity, withdrawalInfo);

        _burn(msg.sender, _gardenTokenQuantity);
        _updateContributorWithdrawalInfo(withdrawalInfo.netFlowQuantity);

        // Check that the withdrawal is possible
        // Unwrap WETH if ETH balance lower than netFlowQuantity
        if (address(this).balance < withdrawalInfo.netFlowQuantity) {
            IWETH(WETH).withdraw(withdrawalInfo.netFlowQuantity);
        }
        // Send ETH
        Address.sendValue(_to, withdrawalInfo.netFlowQuantity);
        payProtocolFeeFromGarden(reserveAsset, withdrawalInfo.protocolFees);

        uint256 outflow = withdrawalInfo.netFlowQuantity.add(withdrawalInfo.protocolFees);

        // Required withdrawable quantity is greater than existing collateral
        _require(principal >= outflow, Errors.BALANCE_TOO_LOW);
        _updatePrincipal(principal.sub(outflow));

        emit GardenWithdrawal(
            msg.sender,
            _to,
            withdrawalInfo.netFlowQuantity,
            withdrawalInfo.gardenTokenQuantity,
            withdrawalInfo.protocolFees,
            block.timestamp
        );
    }

    function _getProfitsAndBabl(address[] calldata _finalizedStrategies) internal view returns (uint256, uint96) {
        uint256 contributorTotalProfits = 0;
        uint256 bablTotalRewards = 0;
        for (uint256 i = 0; i < _finalizedStrategies.length; i++) {
            IStrategy strategy = IStrategy(_finalizedStrategies[i]);
            uint256 totalProfits = 0; // Total Profits of each finalized strategy
            // Positive strategies not yet claimed
            if (
                strategy.exitedAt() > contributors[msg.sender].claimedAt &&
                strategy.executedAt() >= contributors[msg.sender].initialDepositAt
            ) {
                // If strategy returned money we give out the profits
                if (strategy.capitalReturned() > strategy.capitalAllocated()) {
                    // (User percentage * strategy profits) / (strategy capital)
                    totalProfits = totalProfits.add(strategy.capitalReturned().sub(strategy.capitalAllocated()));
                    // We reserve 5% of profits for performance fees

                    totalProfits = totalProfits.sub(totalProfits.multiplyDecimal(PROFIT_PROTOCOL_FEE));
                }

                // Give out BABL
                uint256 creatorBonus = msg.sender == creator ? CREATOR_BONUS : 0;
                bool isStrategist = msg.sender == strategy.strategist();
                bool isVoter = strategy.getUserVotes(msg.sender) != 0;
                // pending userPrincipal improvement to have more accurate calculations
                uint256 strategyRewards = strategy.strategyRewards();
                uint256 contributorProfits = 0;
                uint256 bablRewards = 0;
                uint256 tempForEvents = 0;

                // Get strategist rewards in case the contributor is also the strategist of the strategy
                if (isStrategist) {
                    bablRewards = bablRewards.add(strategyRewards.multiplyDecimal(BABL_STRATEGIST_SHARE));

                    contributorProfits = contributorProfits.add(totalProfits.multiplyDecimal(PROFIT_STRATEGIST_SHARE));
                }

                // Get proportional voter (stewards) rewards in case the contributor was also a steward of the strategy
                if (isVoter) {
                    tempForEvents = bablRewards;
                    bablRewards = bablRewards.add(
                        strategyRewards.multiplyDecimal(BABL_STEWARD_SHARE).preciseMul(
                            uint256(strategy.getUserVotes(msg.sender)).preciseDiv(strategy.absoluteTotalVotes())
                        )
                    );

                    tempForEvents = contributorProfits;

                    contributorProfits = contributorProfits.add(
                        totalProfits
                            .multiplyDecimal(PROFIT_STEWARD_SHARE)
                            .preciseMul(uint256(strategy.getUserVotes(msg.sender)))
                            .preciseDiv(strategy.absoluteTotalVotes())
                    );
                }

                // Get proportional LP rewards as every active contributor of the garden is a LP of their strategies
                tempForEvents = bablRewards;
                bablRewards = bablRewards.add(
                    strategyRewards.multiplyDecimal(BABL_LP_SHARE).preciseMul(
                        contributors[msg.sender].gardenAverageOwnership.preciseDiv(strategy.capitalAllocated())
                    )
                );

                tempForEvents = contributorProfits;

                contributorProfits = contributorProfits.add(
                    contributors[msg.sender].gardenAverageOwnership.preciseMul(totalProfits).multiplyDecimal(
                        PROFIT_LP_SHARE
                    )
                );

                // Get a multiplier bonus in case the contributor is the garden creator
                if (creatorBonus > 0) {
                    tempForEvents = bablRewards;
                    bablRewards = bablRewards.add(bablRewards.multiplyDecimal(creatorBonus));
                }

                bablTotalRewards = bablTotalRewards.add(bablRewards);
                contributorTotalProfits = contributorTotalProfits.add(contributorProfits);
            }
        }

        return (contributorTotalProfits, Safe3296.safe96(bablTotalRewards, 'R28'));
    }

    /**
     * Returns the losses of a garden since a timestamp
     *
     * @param _since                        Timestamp since when we should calculate the losses
     * @return  uint256                     Losses of a garden since a timestamp
     */
    function _getLossesGarden(uint256 _since) private view returns (uint256) {
        uint256 totalLosses = 0;
        for (uint256 i = 0; i < finalizedStrategies.length; i++) {
            if (IStrategy(finalizedStrategies[i]).executedAt() >= _since) {
                totalLosses = totalLosses.add(IStrategy(finalizedStrategies[i]).getLossesStrategy());
            }
        }
        for (uint256 i = 0; i < strategies.length; i++) {
            if (IStrategy(strategies[i]).executedAt() >= _since) {
                totalLosses = totalLosses.add(IStrategy(strategies[i]).getLossesStrategy());
            }
        }

        return totalLosses;
    }

    function _validateReserveAsset(address _reserveAsset, uint256 _quantity) internal view {
        _require(_quantity > 0, Errors.GREATER_THAN_ZERO);
        _require(IBabController(controller).isValidReserveAsset(_reserveAsset), Errors.MUST_BE_RESERVE_ASSET);
    }

    function _validateRedemptionInfo(
        uint256 _minReserveReceiveQuantity,
        uint256, /* _gardenTokenQuantity */
        ActionInfo memory _withdrawalInfo
    ) internal view {
        // Check that new supply is more than min supply needed for withdrawal
        // Note: A min supply amount is needed to avoid division by 0 when withdrawaling garden token to 0
        _require(_withdrawalInfo.newGardenTokenSupply >= minGardenTokenSupply, Errors.MIN_TOKEN_SUPPLY);

        _require(_withdrawalInfo.netFlowQuantity >= _minReserveReceiveQuantity, Errors.MIN_TOKEN_SUPPLY);
    }

    function _createIssuanceInfo(uint256 _reserveAssetQuantity) internal view returns (ActionInfo memory) {
        ActionInfo memory depositInfo;

        (depositInfo.protocolFees, depositInfo.netFlowQuantity) = _getFees(_reserveAssetQuantity, true);

        depositInfo.gardenTokenQuantity = depositInfo.netFlowQuantity;

        depositInfo.newGardenTokenSupply = depositInfo.gardenTokenQuantity.add(totalSupply());

        return depositInfo;
    }

    function _createRedemptionInfo(uint256 _gardenTokenQuantity) internal view returns (ActionInfo memory) {
        ActionInfo memory withdrawalInfo;

        withdrawalInfo.gardenTokenQuantity = _gardenTokenQuantity;

        (withdrawalInfo.protocolFees, withdrawalInfo.netFlowQuantity) = _getFees(_gardenTokenQuantity, false);

        withdrawalInfo.newGardenTokenSupply = totalSupply().sub(_gardenTokenQuantity);

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
                ? IBabController(controller).protocolDepositGardenTokenFee()
                : IBabController(controller).protocolWithdrawalGardenTokenFee();

        uint256 reserveAssetReal = _reserveAssetQuantity;
        // If there is a withdrawal, we adjust for losses
        if (!_isDeposit) {
            uint256 losses = _getLossesGarden(contributors[msg.sender].initialDepositAt);
            // // If there are losses we need to adjust them down
            if (losses > 0) {
                reserveAssetReal = reserveAssetReal.sub(
                    losses.preciseMul(contributors[msg.sender].gardenAverageOwnership)
                );
            }
        }
        // Calculate total notional fees
        uint256 protocolFees = protocolFeePercentage.preciseMul(reserveAssetReal);

        uint256 netReserveFlow = reserveAssetReal.sub(protocolFees);

        return (protocolFees, netReserveFlow);
    }

    /**
     * Updates the contributor info in the array
     */
    function _updateContributorDepositInfo(uint256 previousBalance) internal {
        Contributor storage contributor = contributors[msg.sender];
        // If new contributor, create one, increment count, and set the current TS
        if (previousBalance == 0) {
            totalContributors = totalContributors.add(1);
            contributor.gardenAverageOwnership = balanceOf(msg.sender).preciseDiv(totalSupply());
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

    function _abs(int256 x) private pure returns (int256) {
        return x >= 0 ? x : -x;
    }
}
