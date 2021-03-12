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

import "hardhat/console.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { PreciseUnitMath } from "../lib/PreciseUnitMath.sol";
import { IWETH } from "../interfaces/external/weth/IWETH.sol";
import { IBabController } from "../interfaces/IBabController.sol";
import { ICommunityValuer } from "../interfaces/ICommunityValuer.sol";
import { IReservePool } from "../interfaces/IReservePool.sol";
import { IPriceOracle } from "../interfaces/IPriceOracle.sol";
import { BaseCommunity } from "./BaseCommunity.sol";


/**
 * @title RollingCommunity
 * @author Babylon Finance
 *
 * RollingCommunity holds the logic to deposit, withdraw and track contributions and fees.
 */
contract RollingCommunity is BaseCommunity, ReentrancyGuard {
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
      uint256 netFlowQuantity; // When issuing, quantity of reserve asset sent to Community
      // When withdrawaling, quantity of reserve asset sent to withdrawaler
      uint256 communityTokenQuantity; // When issuing, quantity of Community tokens minted to mintee
      // When withdrawaling, quantity of Community tokens withdrawaled
      uint256 previousCommunityTokenSupply; // Community token supply prior to deposit/withdrawal action
      uint256 newCommunityTokenSupply; // Community token supply after deposit/withdrawal action
      uint256 newReservePositionBalance; // Community token reserve asset position balance after deposit/withdrawal
    }

    uint256 public depositHardlock;                // Window of time after deposits when withdraws are disabled for that user
    uint256 public redemptionWindowAfterInvestmentCompletes; // Window of time after an investment idea finishes when the capital is available for withdrawals
    uint256 public redemptionsOpenUntil;           // Indicates until when the redemptions are open and the ETH is set aside


    /* ============ Constructor ============ */

    /**
     * When a new Community is created, initializes Investments are set to empty.
     * All parameter validations are on the BabController contract. Validations are performed already on the
     * BabController.
     *
     * @param _integrations           List of integrations to enable. All integrations must be approved by the Controller
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     * @param _creator                Address of the creator
     * @param _name                   Name of the Community
     * @param _symbol                 Symbol of the Community
     */

    function initialize(
        address[] memory _integrations,
        address _weth,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol
    ) public override
    {
      super.initialize(
          _integrations,
          _weth,
          _weth,
          _controller,
          _creator,
          _name,
          _symbol
      );
      totalContributors = 0;
      totalFundsDeposited = 0;
      totalFunds = 0;
    }

    /* ============ External Functions ============ */

    /**
     * FUND LEAD ONLY.  Starts the Community with allowed reserve assets,
     * fees and issuance premium. Only callable by the Community's creator
     *
     * @param _maxDepositLimit                     Max deposit limit
     * @param _minCommunityTokenSupply             Min community token supply
     * @param _minLiquidityAsset                   Number that represents min amount of liquidity denominated in ETH
     * @param _depositHardlock                     Number that represents the time deposits are locked for an user after he deposits
     * @param _minContribution        Min contribution to the community
     * @param _ideaCooldownPeriod               How long after the idea has been activated, will it be ready to be executed
     * @param _ideaCreatorProfitPercentage      What percentage of the profits go to the idea creator
     * @param _ideaVotersProfitPercentage       What percentage of the profits go to the idea curators
     * @param _communityCreatorProfitPercentage What percentage of the profits go to the creator of the community
     * @param _minVotersQuorum                  Percentage of votes needed to activate an investment idea (0.01% = 1e14, 1% = 1e16)
     * @param _minIdeaDuration                  Min duration of an investment idea
     * @param _maxIdeaDuration                  Max duration of an investment idea
     */
    function start(
        uint256 _maxDepositLimit,
        uint256 _minCommunityTokenSupply,
        uint256 _minLiquidityAsset,
        uint256 _depositHardlock,
        uint256 _minContribution,
        uint256 _ideaCooldownPeriod,
        uint256 _ideaCreatorProfitPercentage,
        uint256 _ideaVotersProfitPercentage,
        uint256 _communityCreatorProfitPercentage,
        uint256 _minVotersQuorum,
        uint256 _minIdeaDuration,
        uint256 _maxIdeaDuration
    ) external onlyCreator onlyInactive payable {
        require(_maxDepositLimit < MAX_DEPOSITS_FUND_V1, "Max deposit limit needs to be under the limit");

        require(msg.value >= minContribution, "Creator needs to deposit");
        IBabController ifcontroller = IBabController(controller);
        require(
            _minCommunityTokenSupply > 0,
            "Min Community token supply >= 0"
        );
        require(_minLiquidityAsset >= ifcontroller.minRiskyPairLiquidityEth(),
          "Needs to be at least the minimum set by protocol");
        // make initial deposit
        uint256 initialDepositAmount = msg.value;
        uint256 initialTokens = initialDepositAmount.div(initialBuyRate);
        require(initialTokens >= minCommunityTokenSupply,
          "Initial Community token supply too low");
        require(_depositHardlock > 1, "Needs to be at least a couple of seconds to prevent flash loan attacks");
        minCommunityTokenSupply = _minCommunityTokenSupply;
        maxDepositLimit = _maxDepositLimit;
        communityInitializedAt = block.timestamp;
        minLiquidityAsset = _minLiquidityAsset;
        depositHardlock = _depositHardlock;
        redemptionWindowAfterInvestmentCompletes = 7 days;
        startCommon(
            _minContribution,
            _ideaCooldownPeriod,
            _ideaCreatorProfitPercentage,
            _ideaVotersProfitPercentage,
            _communityCreatorProfitPercentage,
            _minVotersQuorum,
            _minIdeaDuration,
            _maxIdeaDuration);


        // Deposit
        IWETH(weth).deposit{value: initialDepositAmount}();

        _mint(creator, initialTokens);
        _updateContributorInfo(initialTokens, initialDepositAmount);
        _updateReserveBalance(initialDepositAmount);

        require(totalSupply() > 0, "Community must receive an initial deposit");

        active = true;
    }

    /**
     * Deposits the Community's position components into the community and mints the Community token of the given quantity
     * to the specified _to address.
     *
     * @param _reserveAssetQuantity  Quantity of the reserve asset that are received
     * @param _minCommunityTokenReceiveQuantity   Min quantity of Community token to receive after issuance
     * @param _to                   Address to mint Community tokens to
     */
    function deposit(
        uint256 _reserveAssetQuantity,
        uint256 _minCommunityTokenReceiveQuantity,
        address _to
    ) public payable nonReentrant onlyActive {
        require(
            msg.value >= minContribution,
            ">= minContribution"
        );
        // if deposit limit is 0, then there is no deposit limit
        if(maxDepositLimit > 0) {
          require(totalFundsDeposited.add(msg.value) <= maxDepositLimit, "Max Deposit Limit");
        }
        require(msg.value == _reserveAssetQuantity, "ETH does not match");
        // Always wrap to WETH
        IWETH(weth).deposit{value: msg.value}();
        // Check this here to avoid having relayers
        reenableEthForInvestments();

        _validateReserveAsset(reserveAsset, _reserveAssetQuantity);

        ActionInfo memory depositInfo =
            _createIssuanceInfo(reserveAsset, _reserveAssetQuantity);

        _validateIssuanceInfo(_minCommunityTokenReceiveQuantity, depositInfo);

        // Send Protocol Fee
        payProtocolFeeFromCommunity(reserveAsset, depositInfo.protocolFees);

        // Updates Reserve Balance and Mint
        _mint(_to, depositInfo.communityTokenQuantity);
        _updateContributorInfo(depositInfo.communityTokenQuantity, msg.value);
        _updateReserveBalance(depositInfo.newReservePositionBalance);

        emit CommunityTokenDeposited(
            _to,
            depositInfo.communityTokenQuantity,
            depositInfo.protocolFees
        );
    }

    /**
     * Withdraws the ETH relative to the token participation in the community and sends it back to the sender.
     *
     * @param _communityTokenQuantity             Quantity of the community token to withdrawal
     * @param _minReserveReceiveQuantity     Min quantity of reserve asset to receive
     * @param _to                            Address to send component assets to
     */
    function withdraw(
        uint256 _communityTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) external nonReentrant onlyContributor onlyActive {
        require(
            _communityTokenQuantity <= balanceOf(msg.sender),
            "Withdrawal amount <= to deposited amount"
        );
        // Flashloan protection
        require(block.timestamp.sub(contributors[msg.sender].timestamp) >= depositHardlock, "Cannot withdraw. Hardlock");
        // Check this here to avoid having relayers
        reenableEthForInvestments();
        ActionInfo memory withdrawalInfo =
            _createRedemptionInfo(reserveAsset, _communityTokenQuantity);

        _validateReserveAsset(reserveAsset, withdrawalInfo.netFlowQuantity);

        _validateRedemptionInfo(
            _minReserveReceiveQuantity,
            _communityTokenQuantity,
            withdrawalInfo
        );

        _burn(msg.sender, _communityTokenQuantity);

        emit WithdrawalLog(
            msg.sender,
            withdrawalInfo.netFlowQuantity,
            block.timestamp
        );
        totalFunds = totalFunds.sub(withdrawalInfo.netFlowQuantity).sub(withdrawalInfo.protocolFees);
        // Check that the rdemption is possible
        require(canWithdrawEthAmount(withdrawalInfo.netFlowQuantity), "Not enough liquidity in the fund");
        if (address(this).balance >= withdrawalInfo.netFlowQuantity) {
          // Send eth
          (bool sent,) = _to.call{value: withdrawalInfo.netFlowQuantity}("");
          require(sent, "Failed to send Ether");
        } else {
          // Send liquid weth balance
          IWETH(weth).withdraw(withdrawalInfo.netFlowQuantity);
          _to.transfer(withdrawalInfo.netFlowQuantity);
        }

        payProtocolFeeFromCommunity(reserveAsset, withdrawalInfo.protocolFees);

        _updateReserveBalance(withdrawalInfo.newReservePositionBalance);
        console.log(withdrawalInfo.newReservePositionBalance);
        console.log(withdrawalInfo.netFlowQuantity);
        emit CommunityTokenWithdrawn(
            msg.sender,
            _to,
            withdrawalInfo.communityTokenQuantity,
            withdrawalInfo.protocolFees
        );
    }

    /**
     * Sender is selling his tokens to the reserve pool at a discount.
     * Reserve pool will receive the tokens.
     *
     * @param _communityTokenQuantity        Quantity of the community token to withdrawal
     * @param _minReserveReceiveQuantity     Min quantity of reserve asset to receive
     * @param _to                            Address to send component assets to
     */
    function withdrawToReservePool(
      uint256 _communityTokenQuantity,
      uint256 _minReserveReceiveQuantity,
      address payable _to
    ) external nonReentrant onlyContributor onlyActive {
      require(
          _communityTokenQuantity <= balanceOf(msg.sender),
          "Withdrawal amount <= to deposited amount"
      );
      // Flashloan protection
      require(block.timestamp.sub(contributors[msg.sender].timestamp) >= depositHardlock, "Cannot withdraw. Hardlock");

      IReservePool reservePool = IReservePool(IBabController(controller).getReservePool());
      require(reservePool.isReservePoolAllowedToBuy(address(this), _communityTokenQuantity), "Reserve Pool not active");

      ActionInfo memory withdrawalInfo =
          _createRedemptionInfo(reserveAsset, _communityTokenQuantity);

      _validateReserveAsset(reserveAsset, withdrawalInfo.netFlowQuantity);
      // If normal redemption is available, don't use the reserve pool
      require(!canWithdrawEthAmount(withdrawalInfo.netFlowQuantity), "Not enough liquidity in the fund");
      _validateRedemptionInfo(
          _minReserveReceiveQuantity,
          _communityTokenQuantity,
          withdrawalInfo
      );

      withdrawalInfo.netFlowQuantity = reservePool.sellTokensToLiquidityPool(address(this), _communityTokenQuantity);

      emit WithdrawalLog(
          msg.sender,
          withdrawalInfo.netFlowQuantity,
          block.timestamp
      );
      totalFunds = totalFunds.sub(withdrawalInfo.netFlowQuantity).sub(withdrawalInfo.protocolFees);

      payProtocolFeeFromCommunity(reserveAsset, withdrawalInfo.protocolFees);

      _updateReserveBalance(withdrawalInfo.newReservePositionBalance);

      emit CommunityTokenWithdrawn(
          msg.sender,
          _to,
          withdrawalInfo.communityTokenQuantity,
          withdrawalInfo.protocolFees
      );
    }

    // if limit == 0 then there is no deposit limit
    function setDepositLimit(uint limit) external onlyGovernanceCommunity {
      maxDepositLimit = limit;
    }

    // Any tokens (other than the target) that are sent here by mistake are recoverable by contributors
    // Exchange for WETH
    function sweep(address _token) external onlyContributor {
       require(_token != reserveAsset, "Token is not the reserve asset");
       uint256 balance = ERC20(_token).balanceOf(address(this));
       require(balance > 0, "Token balance > 0");
       bytes memory _emptyTradeData;
       // TODO: probably use uniswap or 1inch
       _trade("_kyber", _token, balance, reserveAsset, 0, _emptyTradeData);
    }

    /**
     * When an investment idea finishes execution, we want to make that eth available for withdrawals
     * from members of the community.
     *
     * @param _amount                        Amount of WETH to convert to ETH to set aside
     */
    function startRedemptionWindow(uint256 _amount) external onlyInvestmentIdeaOrOwner {
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
     * Burns seller community tokens and mints them to the reserve pool
     *  @param _contributor           Contributor that is selling the tokens
     *  @param _quantity              Amount of tokens being sold to the reserve pool
     */
    function burnAssetsFromSenderAndMintToReserve(address _contributor, uint256 _quantity) external {
      address reservePool = IBabController(controller).getReservePool();
      require(msg.sender == reservePool, "Only reserve pool can call this");
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
      return
        (redemptionsOpenUntil <= block.timestamp && ethAsideBalance >= _amount) ||
        liquidWeth >= _amount;
    }

    function getContributor(address _contributor) public view returns (uint256, uint256, uint256) {
        Contributor memory contributor = contributors[_contributor];
        return (contributor.totalDeposit, contributor.tokensReceived, contributor.timestamp);
    }

    /**
     * Get the expected reserve asset to be withdrawaled
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _communityTokenQuantity             Quantity of Community tokens to withdrawal
     *
     * @return  uint256                     Expected reserve asset quantity withdrawaled
     */
    function getExpectedReserveWithdrawalQuantity(
        address _reserveAsset,
        uint256 _communityTokenQuantity
    ) external view returns (uint256) {
        uint256 preFeeReserveQuantity =
            _getWithdrawalReserveQuantity(_reserveAsset, _communityTokenQuantity);

        (, uint256 netReserveFlows) = _getFees(preFeeReserveQuantity, false, _communityTokenQuantity);

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
    function isDepositValid(
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    ) external view returns (bool) {
        return
            _reserveAssetQuantity != 0 &&
            IBabController(controller).isValidReserveAsset(_reserveAsset) &&
            totalSupply() >= minCommunityTokenSupply;
    }

    /**
     * Checks if withdrawal is valid
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _communityTokenQuantity             Quantity of community tokens to withdrawal
     *
     * @return  bool                        Returns true if withdrawal is valid
     */
    function isWithdrawalValid(
        address _reserveAsset,
        uint256 _communityTokenQuantity
    ) external view returns (bool) {
        uint256 setTotalSupply = totalSupply();

        if (
            _communityTokenQuantity == 0 ||
            !IBabController(controller).isValidReserveAsset(_reserveAsset) ||
            setTotalSupply < minCommunityTokenSupply.add(_communityTokenQuantity)
        ) {
            return false;
        } else {
            uint256 totalWithdrawalValue =
                _getWithdrawalReserveQuantity(
                    _reserveAsset,
                    _communityTokenQuantity
                );

            (, uint256 expectedWithdrawalQuantity) =
                _getFees(totalWithdrawalValue, false, _communityTokenQuantity);

            return reserveBalance >= expectedWithdrawalQuantity;
        }
    }

    receive() external payable {} // solium-disable-line quotes

    /* ============ Internal Functions ============ */

    function _validateReserveAsset(address _reserveAsset, uint256 _quantity)
        internal
        view
    {
        require(_quantity > 0, "Quantity > 0");
        require(
            IBabController(controller).isValidReserveAsset(_reserveAsset),
            "Must be reserve asset"
        );
    }

    function _validateIssuanceInfo(
        uint256 _minCommunityTokenReceiveQuantity,
        ActionInfo memory _depositInfo
    ) internal view {
        // Check that total supply is greater than min supply needed for issuance
        // Note: A min supply amount is needed to avoid division by 0 when Community token supply is 0
        require(
            _depositInfo.previousCommunityTokenSupply >= minCommunityTokenSupply,
            "Supply must > than minimum"
        );

        require(
            _depositInfo.communityTokenQuantity >= _minCommunityTokenReceiveQuantity,
            "Must be > min Community token"
        );
    }

    function _validateRedemptionInfo(
        uint256 _minReserveReceiveQuantity,
        uint256 /* _communityTokenQuantity */,
        ActionInfo memory _withdrawalInfo
    ) internal view {
        // Check that new supply is more than min supply needed for redemption
        // Note: A min supply amount is needed to avoid division by 0 when withdrawaling community token to 0
        require(
            _withdrawalInfo.newCommunityTokenSupply >= minCommunityTokenSupply,
            "Supply must be > than minimum"
        );

        require(
            _withdrawalInfo.netFlowQuantity >= _minReserveReceiveQuantity,
            "Must be > than min receive"
        );
    }

    function _createIssuanceInfo(
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    ) internal view returns (ActionInfo memory) {
        ActionInfo memory depositInfo;
        depositInfo.previousCommunityTokenSupply = totalSupply();
        depositInfo.preFeeReserveQuantity = _reserveAssetQuantity;

        (
            depositInfo.protocolFees,
            depositInfo.netFlowQuantity
        ) = _getFees(depositInfo.preFeeReserveQuantity, true, 0);

        depositInfo.communityTokenQuantity = _getCommunityTokenMintQuantity(
            _reserveAsset,
            depositInfo.netFlowQuantity,
            depositInfo.previousCommunityTokenSupply
        );

        // Calculate inflation and new position multiplier. Note: Round inflation up in order to round position multiplier down
        depositInfo.newCommunityTokenSupply =
            depositInfo.communityTokenQuantity.add(
              depositInfo.previousCommunityTokenSupply
            );

        depositInfo.newReservePositionBalance = reserveBalance.add(depositInfo.netFlowQuantity);

        return depositInfo;
    }

    function _createRedemptionInfo(
        address _reserveAsset,
        uint256 _communityTokenQuantity
    ) internal view returns (ActionInfo memory) {
        ActionInfo memory withdrawalInfo;

        withdrawalInfo.communityTokenQuantity = _communityTokenQuantity;

        withdrawalInfo.preFeeReserveQuantity = _getWithdrawalReserveQuantity(
            _reserveAsset,
            _communityTokenQuantity
        );

        (
            withdrawalInfo.protocolFees,
            withdrawalInfo.netFlowQuantity
        ) = _getFees(withdrawalInfo.preFeeReserveQuantity, false, _communityTokenQuantity);

        withdrawalInfo.previousCommunityTokenSupply = totalSupply();

        withdrawalInfo.newCommunityTokenSupply =
            withdrawalInfo.previousCommunityTokenSupply.sub(_communityTokenQuantity);

        withdrawalInfo.newReservePositionBalance = _getWithdrawalPositionBalance(
            _reserveAsset,
            withdrawalInfo
        );

        return withdrawalInfo;
    }

    /**
     * Returns the fees attributed to the manager and the protocol. The fees are calculated as follows:
     *
     * Protocol Fee = (% direct fee %) * reserveAssetQuantity
     *
     * @param _reserveAssetQuantity         Quantity of reserve asset to calculate fees from
     * @param _isDeposit                    Boolean that is true when it is a deposit
     * @param _communityTokenQuantity            Number of community tokens involved in the operation
     *
     * @return  uint256                     Fees paid to the protocol in reserve asset
     * @return  uint256                     Net reserve to user net of fees
     */
    function _getFees(uint256 _reserveAssetQuantity, bool _isDeposit, uint256 _communityTokenQuantity)
        internal
        view
        returns (
            uint256,
            uint256
        )
    {
        // Get protocol fee percentages
        uint256 protocolFeePercentage =
            _isDeposit
                ? IBabController(controller).getProtocolDepositCommunityTokenFee()
                : IBabController(controller)
                    .getProtocolWithdrawalCommunityTokenFee();

        // Calculate total notional fees
        uint256 protocolFees =
            protocolFeePercentage.preciseMul(_reserveAssetQuantity);

        uint256 netReserveFlow =
            _reserveAssetQuantity.sub(protocolFees);

        return (protocolFees, netReserveFlow);
    }

    function _getCommunityTokenMintQuantity(
        address _reserveAsset,
        uint256 _netReserveFlows, // Value of reserve asset net of fees
        uint256 _communityTokenTotalSupply
    ) internal view returns (uint256) {
        // Get valuation of the Community with the quote asset as the reserve asset.
        // Reverts if price is not found
        uint256 communityValuation = ICommunityValuer(IBabController(controller).getCommunityValuer()).calculateCommunityValuation(address(this), _reserveAsset);
        // Get reserve asset decimals
        uint8 reserveAssetDecimals = ERC20(_reserveAsset).decimals();
        uint256 baseUnits = uint256(10) ** reserveAssetDecimals;
        uint256 normalizedTotalReserveQuantityNetFees = _netReserveFlows.preciseDiv(baseUnits);

        uint256 normalizedTotalReserveQuantityNetFeesAndPremium =
            _netReserveFlows.preciseDiv(baseUnits);

        // Calculate Community tokens to mint to depositor
        uint256 denominator =
            _communityTokenTotalSupply
                .preciseMul(communityValuation)
                .add(normalizedTotalReserveQuantityNetFees)
                .sub(normalizedTotalReserveQuantityNetFeesAndPremium);
        uint256 quantityToMint =
            normalizedTotalReserveQuantityNetFeesAndPremium
                .preciseMul(_communityTokenTotalSupply)
                .preciseDiv(denominator);
        return quantityToMint;
    }

    function _getWithdrawalReserveQuantity(
        address _reserveAsset,
        uint256 _communityTokenQuantity
    ) internal view returns (uint256) {
        // Get valuation of the Community with the quote asset as the reserve asset. Returns value in precise units (10e18)
        // Reverts if price is not found
        uint256 communityValuation =
            ICommunityValuer(IBabController(controller).getCommunityValuer())
                .calculateCommunityValuation(address(this), _reserveAsset);

        uint256 totalWithdrawalValueInPreciseUnits =
            _communityTokenQuantity.preciseMul(communityValuation);
        // Get reserve asset decimals
        uint8 reserveAssetDecimals = ERC20(_reserveAsset).decimals();
        uint256 prePremiumReserveQuantity =
            totalWithdrawalValueInPreciseUnits.preciseMul(
                10**reserveAssetDecimals
            );

        return prePremiumReserveQuantity;
    }

    /**
     * The new position reserve asset balance is calculated as follows:
     * totalReserve = oldBalance - reserveQuantityToSendOut
     * newBalance = totalReserve / newCommunityTokenSupply
     */
    function _getWithdrawalPositionBalance(
        address _reserveAsset,
        ActionInfo memory _withdrawalInfo
    ) internal view returns (uint256) {
        uint256 totalExistingBalance = reserveBalance;


        uint256 outflow =
            _withdrawalInfo
                .netFlowQuantity
                .add(_withdrawalInfo.protocolFees);

        // Require withdrawable quantity is greater than existing collateral
        require(
            totalExistingBalance >= outflow,
            "Must have enough balance"
        );

        return
            totalExistingBalance.sub(outflow);
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

      totalFunds = totalFunds.add(amount);
      totalFundsDeposited = totalFundsDeposited.add(amount);
      contributor.totalDeposit = contributor.totalDeposit.add(amount);
      contributor.tokensReceived = contributor.tokensReceived.add(
          tokensReceived
      );

      emit ContributionLog(
        msg.sender,
        amount,
        tokensReceived,
        block.timestamp
      );
    }
}
