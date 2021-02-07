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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {IWETH} from "./interfaces/external/weth/IWETH.sol";
import {IBabController} from "./interfaces/IBabController.sol";
import {IFundValuer} from "./interfaces/IFundValuer.sol";
import {IFundIssuanceHook} from "./interfaces/IFundIssuanceHook.sol";
import {BaseFund} from "./BaseFund.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";


/**
 * @title ClosedFund
 * @author Babylon Finance
 *
 * ClosedFund holds the logic to deposit, withdraw and track contributions and fees.
 */
contract ClosedFund is BaseFund, ReentrancyGuard {
  using SafeCast for uint256;
  using SafeCast for int256;
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using PreciseUnitMath for int256;
  using PreciseUnitMath for uint256;

    /* ============ Events ============ */
    event FundTokenDeposited(
        address indexed _to,
        uint256 fundTokenQuantity,
        uint256 protocolFees
    );
    event FundTokenwithdrawed(
        address indexed _from,
        address indexed _to,
        uint256 fundTokenQuantity,
        uint256 protocolFees
    );

    event PremiumEdited(uint256 amount);
    event ContributionLog(
        address indexed contributor,
        uint256 amount,
        uint256 tokensReceived,
        uint256 timestamp
    );
    event WithdrawalLog(
        address indexed sender,
        uint256 amount,
        uint256 timestamp
    );

    /* ============ Modifiers ============ */

    modifier onlyContributor(address payable _caller) {
        _validateOnlyContributor(_caller);
        _;
    }

    /* ============ State Variables ============ */
    uint256 constant public initialBuyRate = 1000000000000; // Initial buy rate for the manager

    struct ActionInfo {
        uint256 preFeeReserveQuantity; // Reserve value before fees; During issuance, represents raw quantity
        // During withdrawal, represents post-premium value
        uint256 protocolFees; // Total protocol fees (direct + manager revenue share)
        uint256 netFlowQuantity; // When issuing, quantity of reserve asset sent to Fund
        // When withdrawaling, quantity of reserve asset sent to withdrawaler
        uint256 fundTokenQuantity; // When issuing, quantity of Fund tokens minted to mintee
        // When withdrawaling, quantity of Fund tokens withdrawaled
        uint256 previousFundTokenSupply; // Fund token supply prior to deposit/withdrawal action
        uint256 newFundTokenSupply; // Fund token supply after deposit/withdrawal action
        uint256 newReservePositionBalance; // Fund token reserve asset position balance after deposit/withdrawal
    }


    uint256 public maxDepositLimit; // Limits the amount of deposits
    uint256 public fundDuration; // Initial duration of the fund
    uint256 public fundEpoch; // Set window of time to decide the next investment idea
    uint256 public fundEndsBy; // Timestamp when the fund ends and withdrawals are allowed
    uint256 public fundDeliberationDuration; // Window for endorsing / downvoting an idea

    // ======= Investment ideas =========
    uint8 public constant maxIdeasPerEpoch = 3;
    uint256 public currentInvestmentsIndex = 1;

    struct InvestmentIdea {
      uint256 index;                     // Investment index (used for votes)
      address participant;               // Address of the participant that submitted the bet
      uint256 enteredAt;                 // Timestamp when the idea was submitted
      uint256 executedAt;                // Timestamp when the idea was executed
      uint256 exitedAt;                  // Timestamp when the idea was submitted
      uint256 stake;                     // Amount of stake (in reserve asset)
      uint256 capitalRequested;          // Amount of capital requested (in reserve asset)
      uint256 duration;                  // Duration of the bet
      int256 totalVotes;                 // Total votes
      uint256 totalVoters;               // Total amount of participants that voted
      bytes enterPayload;                // Calldata to execute when entering
      bytes exitPayload;                 // Calldata to execute when exiting the trade
      bool finalized;                    // Flag that indicates whether we exited the idea
    }

    mapping(uint256 => mapping(address => int256)) internal votes;  // Investment idea votes from participants (can be negative if downvoting)

    uint256 currentMinStakeEpoch;        // Used to keep track of the min staked amount. An idea can only be submitted if there are less than 3 or above the limit
    uint256 currentMinStakeIndex;        // Index position of the investment idea with the lowest stake
    InvestmentIdea[maxIdeasPerEpoch] investmentIdeasCurrentEpoch;
    InvestmentIdea[] investmentsExecuted;

    uint256 public lastInvestmentExecutedAt; // Timestamp when the last investment was executed

    // Fees
    uint256 public premiumPercentage; // Premium percentage (0.01% = 1e14, 1% = 1e16). This premium is a buffer around oracle
    // prices paid by user to the Fund Token, which prevents arbitrage and oracle front running

    // List of contributors
    struct Contributor {
        uint256 totalDeposit; //wei
        uint256 tokensReceived;
        uint256 timestamp;
    }

    mapping(address => Contributor) public contributors;
    uint256 public totalContributors;
    uint256 public totalFundsDeposited;
    uint256 public totalFunds;
    // Min contribution in the fund
    uint256 public minContribution = initialBuyRate; //wei
    uint256 public minFundTokenSupply;

    /* ============ Constructor ============ */

    /**
     * When a new Fund is created, initializes Investments are set to empty.
     * All parameter validations are on the BabController contract. Validations are performed already on the
     * BabController.
     *
     * @param _integrations           List of integrations to enable. All integrations must be approved by the Controller
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _creator                Address of the creator
     * @param _name                   Name of the Fund
     * @param _symbol                 Symbol of the Fund
     * @param _minContribution        Min contribution to the fund
     */

    constructor(
        address[] memory _integrations,
        address _weth,
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol,
        uint256 _minContribution
    )
        BaseFund(
            _integrations,
            _weth,
            _reserveAsset,
            _controller,
            _creator,
            _name,
            _symbol
        )
    {
        minContribution = _minContribution;
        totalContributors = 0;
        totalFundsDeposited = 0;
        totalFunds = 0;
    }

    /* ============ External Functions ============ */

    /**
     * FUND MANAGER ONLY. Initializes this module to the Fund with hooks, allowed reserve assets,
     * fees and issuance premium. Only callable by the Fund's manager. Hook addresses are optional.
     * Address(0) means that no hook will be called.
     *
     * @param _maxDepositLimit                Max deposit limit
     * @param _premiumPercentage              Premium percentage to avoid arbitrage
     * @param _minFundTokenSupply             Min fund token supply
     * @param _fundDuration                   Fund duration
     * @param _fundEpoch                      Controls how often an investment idea can be executed
     * @param _fundDeliberationDuration       How long after the epoch has completed, people can curate before the top idea being executed
     */
    function initialize(
        uint256 _maxDepositLimit,
        uint256 _premiumPercentage,
        uint256 _minFundTokenSupply,
        uint256 _fundDuration,
        uint256 _fundEpoch,
        uint256 _fundDeliberationDuration
    ) external onlyCreator onlyInactive payable {
        require(_maxDepositLimit >= 1**19, "Max deposit limit needs to be greater than ten eth");

        require(msg.value > minContribution && msg.value < _maxDepositLimit.div(10), "Creator needs to deposit, up to 10% of the max fund eth");
        IBabController ifcontroller = IBabController(controller);
        require(
            _premiumPercentage <= ifcontroller.getMaxFundPremiumPercentage(),
            "Premium must be less than max"
        );
        require(
            _fundDuration <= ifcontroller.getMaxFundDuration() && _fundDuration >= ifcontroller.getMinFundDuration() ,
            "Fund duration must be within the range allowed by the protocol"
        );
        require(
            _fundEpoch <= ifcontroller.getMaxFundEpoch() && _fundEpoch >= ifcontroller.getMinFundEpoch() ,
            "Fund epoch must be within the range allowed by the protocol"
        );
        require(
            _fundDeliberationDuration <= ifcontroller.getMaxDeliberationPeriod() && _fundDeliberationDuration >= ifcontroller.getMinDeliberationPeriod() ,
            "Fund deliberation must be within the range allowed by the protocol"
        );
        require(
            _minFundTokenSupply > 0,
            "Min Fund token supply must be greater than 0"
        );
        minFundTokenSupply = _minFundTokenSupply;
        premiumPercentage = _premiumPercentage;
        maxDepositLimit = _maxDepositLimit;
        fundDuration = _fundDuration;
        fundEpoch = _fundEpoch;
        fundEndsBy = block.timestamp + _fundDuration;
        fundDeliberationDuration = _fundDeliberationDuration;
        lastInvestmentExecutedAt = block.timestamp; // Start the counter for first epoch

        uint256 initialDepositAmount = msg.value;

        // make initial deposit
        uint256 initialTokens = initialDepositAmount.div(initialBuyRate);

        IWETH(weth).deposit{value: initialDepositAmount}();

        // TODO: Trade to reserve asset if different than WETH

        _mint(creator, initialTokens);
        _udpateContributorInfo(initialTokens, initialDepositAmount);

        _calculateAndEditPosition(
          weth,
          initialDepositAmount,
          initialDepositAmount,
          0
        );

        require(totalSupply() > 0, "The fund must receive an initial deposit by the manager");

        active = true;
    }

    /**
     * Deposits the Fund's position components into the fund and mints the Fund token of the given quantity
     * to the specified _to address. This function only handles default Positions (positionState = 0).
     *
     * @param _reserveAssetQuantity  Quantity of the reserve asset that are received
     * @param _minFundTokenReceiveQuantity   Min quantity of Fund token to receive after issuance
     * @param _to                   Address to mint Fund tokens to
     */
    function deposit(
        uint256 _reserveAssetQuantity,
        uint256 _minFundTokenReceiveQuantity,
        address _to
    ) public payable nonReentrant onlyActive {
        require(
            msg.value >= minContribution,
            "Send at least 1000000000000 wei"
        );
        require(block.timestamp < fundEndsBy, "Fund is already closed");
        // if deposit limit is 0, then there is no deposit limit
        if(maxDepositLimit > 0) {
          require(totalFundsDeposited.add(msg.value) <= maxDepositLimit, "Max Deposit Limit reached");
        }

        // Always wrap to WETH
        IWETH(weth).deposit{value: msg.value}();

        if (reserveAsset != weth) {
            // TODO: trade from weth into reserve asset
        }

        _validateReserveAsset(reserveAsset, _reserveAssetQuantity);

        ActionInfo memory depositInfo =
            _createIssuanceInfo(reserveAsset, _reserveAssetQuantity);

        _validateIssuanceInfo(_minFundTokenReceiveQuantity, depositInfo);

        _transferCollateralAndHandleFees(reserveAsset, depositInfo);

        _udpateContributorInfo(depositInfo.fundTokenQuantity, msg.value);

        _handleDepositStateUpdates(reserveAsset, _to, depositInfo);
    }

    /**
     * Withdrawals the Fund's positions and sends the components of the given
     * quantity to the caller. This function only handles Default Positions (positionState = 0).
     *
     * @param _fundTokenQuantity             Quantity of the fund token to withdrawal
     * @param _minReserveReceiveQuantity     Min quantity of reserve asset to receive
     * @param _to                            Address to send component assets to
     */
    function withdraw(
        uint256 _fundTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) external nonReentrant onlyContributor(msg.sender) onlyActive {
        require(block.timestamp > fundEndsBy, "Withdrawals are disabled until the fund ends");
        require(
            _fundTokenQuantity <= IERC20(address(this)).balanceOf(msg.sender),
            "Withdrawal amount must be less than or equal to deposited amount"
        );
        _validateReserveAsset(reserveAsset, _fundTokenQuantity);

        ActionInfo memory withdrawalInfo =
            _createRedemptionInfo(reserveAsset, _fundTokenQuantity);

        _validateRedemptionInfo(
            _minReserveReceiveQuantity,
            _fundTokenQuantity,
            withdrawalInfo
        );

        _burn(msg.sender, _fundTokenQuantity);

        emit WithdrawalLog(
            msg.sender,
            withdrawalInfo.netFlowQuantity,
            block.timestamp
        );

        totalFunds = totalFunds.sub(withdrawalInfo.netFlowQuantity);

        if (reserveAsset != weth) {
            // Instruct the Fund to transfer the reserve asset back to the user
            IERC20(reserveAsset).transfer(_to, withdrawalInfo.netFlowQuantity);
        } else {
            IWETH(weth).withdraw(withdrawalInfo.netFlowQuantity);
            _to.transfer(withdrawalInfo.netFlowQuantity);
        }

        _handleRedemptionFees(reserveAsset, withdrawalInfo);

        _handleWithdrawalStateUpdates(reserveAsset, _to, withdrawalInfo);
    }

    /**
     * FUND MANAGER ONLY. Edit the premium percentage
     *
     * @param _premiumPercentage            Premium percentage in 10e16 (e.g. 10e16 = 1%)
     */
    function editPremium(uint256 _premiumPercentage) external onlyGovernanceFund {
        require(
            _premiumPercentage <=
                IBabController(controller).getMaxFundPremiumPercentage(),
            "Premium must be less than maximum allowed"
        );

        premiumPercentage = _premiumPercentage;

        emit PremiumEdited(_premiumPercentage);
    }

    // if limit == 0 then there is no deposit limit
    function setDepositLimit(uint limit) external onlyGovernanceFund {
      maxDepositLimit = limit;
    }

    function setFundEndDate(uint256 _endsTimestamp) external onlyGovernanceFund {
      fundEndsBy = _endsTimestamp;
    }

    // Any tokens (other than the target) that are sent here by mistake are recoverable by the owner
    // TODO: If it is not whitelisted, trade it for weth
    function sweep(address _token) external onlyParticipant {
       require(!_hasPosition(_token), "This token is one of the fund positions");
       uint256 balance = IERC20(_token).balanceOf(address(this));
       require(balance > 0, "The token needs to have a positive balance");
       _calculateAndEditPosition(_token, balance, IERC20(_token).balanceOf(address(this)), 0);
    }

    /* ============ External Getter Functions ============ */

    function getContributor(address _contributor) public view returns (uint256, uint256, uint256) {
        Contributor memory contributor = contributors[_contributor];
        return (contributor.totalDeposit, contributor.tokensReceived, contributor.timestamp);
    }

    function getPremiumPercentage() external view returns (uint256) {
        return premiumPercentage;
    }

    /**
     * Get the expected fund tokens minted to recipient on issuance
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _reserveAssetQuantity         Quantity of the reserve asset to deposit with
     *
     * @return  uint256                     Expected Fund tokens to be minted to recipient
     */
    function getExpectedFundTokensDepositdQuantity(
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    ) external view returns (uint256) {
        (, uint256 netReserveFlow) = _getFees(_reserveAssetQuantity, true);

        uint256 setTotalSupply = totalSupply();

        return
            _getFundTokenMintQuantity(
                _reserveAsset,
                netReserveFlow,
                setTotalSupply
            );
    }

    /**
     * Get the expected reserve asset to be withdrawaled
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _fundTokenQuantity             Quantity of Fund tokens to withdrawal
     *
     * @return  uint256                     Expected reserve asset quantity withdrawaled
     */
    function getExpectedReserveWithdrawalQuantity(
        address _reserveAsset,
        uint256 _fundTokenQuantity
    ) external view returns (uint256) {
        uint256 preFeeReserveQuantity =
            _getWithdrawalReserveQuantity(_reserveAsset, _fundTokenQuantity);

        (, uint256 netReserveFlows) = _getFees(preFeeReserveQuantity, false);

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
        uint256 setTotalSupply = totalSupply();

        return
            _reserveAssetQuantity != 0 &&
            IBabController(controller).isValidReserveAsset(_reserveAsset) &&
            setTotalSupply >= minFundTokenSupply;
    }

    /**
     * Checks if withdrawal is valid
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _fundTokenQuantity             Quantity of fund tokens to withdrawal
     *
     * @return  bool                        Returns true if withdrawal is valid
     */
    function isWithdrawalValid(
        address _reserveAsset,
        uint256 _fundTokenQuantity
    ) external view returns (bool) {
        uint256 setTotalSupply = totalSupply();

        if (
            _fundTokenQuantity == 0 ||
            !IBabController(controller).isValidReserveAsset(_reserveAsset) ||
            setTotalSupply < minFundTokenSupply.add(_fundTokenQuantity)
        ) {
            return false;
        } else {
            uint256 totalWithdrawalValue =
                _getWithdrawalReserveQuantity(
                    _reserveAsset,
                    _fundTokenQuantity
                );

            (, uint256 expectedWithdrawalQuantity) =
                _getFees(totalWithdrawalValue, false);

            uint256 existingBalance =
                _getPositionBalance(_reserveAsset).toUint256();

            return existingBalance >= expectedWithdrawalQuantity;
        }
    }

    /**
     * Adds an investment idea to the contenders array for this epoch.
     * Investment stake is stored in the contract. (not converted to reserve asset).
     * If the array is already at the limit, replace the one with the lowest stake.
     * @param _capitalRequested              Capital requested denominated in the reserve asset
     * @param _stake                         Stake denominated in the reserve asset
     * @param _investmentDuration            Investment duration in seconds
     * @param _enterData                     Operation to perform to enter the investment
     * @param _exitData                      Operation to perform to exit the investment
     * TODO: Meta Transaction
     */
    function addInvestmentIdea(uint256 _capitalRequested, uint256 _stake, uint256 _investmentDuration, bytes memory _enterData, bytes memory _exitData) external onlyParticipant payable {
      require(block.timestamp < lastInvestmentExecutedAt.add(fundEpoch), "Idea can only be suggested before the deliberation period");
      require(_stake > 0, "Stake amount must be greater than 0");
      require(_investmentDuration > 1 hours, "Investment duration must be greater than an hour");
      require(_capitalRequested < _getPositionBalance(reserveAsset).toUint256(), "The capital requested is greater than the capital available");
      require(investmentIdeasCurrentEpoch.length < maxIdeasPerEpoch || _stake > currentMinStakeEpoch, "Not enough stake to add the idea");
      uint ideaIndex = investmentIdeasCurrentEpoch.length;
      if (ideaIndex >= maxIdeasPerEpoch) {
        ideaIndex = currentMinStakeIndex;
      }
      // Check than enter and exit data call callIntegration
      InvestmentIdea storage idea = investmentIdeasCurrentEpoch[ideaIndex];
      idea.index = currentInvestmentsIndex;
      idea.participant = msg.sender;
      idea.capitalRequested = _capitalRequested;
      idea.enteredAt = block.timestamp;
      idea.stake = _stake;
      idea.duration = _investmentDuration;
      idea.enterPayload = _enterData;
      idea.exitPayload = _exitData;
      currentInvestmentsIndex ++;
    }

    /**
     * Curates an investment idea fromt the contenders array for this epoch.
     * This can happen at any time. As long as there are investment ideas.
     * @param _ideaIndex                The position of the idea index in the array for the current epoch
     * @param _amount                   Amount to curate, positive to endorse, negative to downvote
     * TODO: Meta Transaction
     */
    function curateInvestmentIdea(uint8 _ideaIndex, int256 _amount) external onlyParticipant {
      require(investmentIdeasCurrentEpoch.length > _ideaIndex, "The idea index does not exist");
      require(_amount.toUint256() < balanceOf(msg.sender), "Participant does not have enough balance");
      InvestmentIdea storage idea = investmentIdeasCurrentEpoch[_ideaIndex];
      // TODO: Check that the curator has not used all his fund tokens during this epoch already
      if (votes[idea.index][msg.sender] == 0) {
        idea.totalVoters++;
      }
      votes[idea.index][msg.sender] = _amount;
      idea.totalVotes.add(_amount);
    }

    function executeTopTrade() external onlyKeeper {
      require(block.timestamp > lastInvestmentExecutedAt.add(fundEpoch).add(fundDeliberationDuration), "Idea can only be executed after the minimum period has elapsed");
      require(investmentIdeasCurrentEpoch.length > 0, "There must be an investment idea ready to execute");
      // check that the keeper is registered and healthy
      uint8 topIdeaIndex = 0;
      InvestmentIdea storage idea = investmentIdeasCurrentEpoch[topIdeaIndex];
      // Execute enter trade
      // _invoke(_integration, _value, _data);
      // Push the trade to the investments executed
      investmentsExecuted[investmentsExecuted.length] = idea;

      // Clear investment ideas
      delete investmentIdeasCurrentEpoch;
      // Restarts the epoc counter
      lastInvestmentExecutedAt = block.timestamp;
      idea.executedAt = block.timestamp;
      // Sends fee to the keeper
    }

    function finalizeTrade(uint _ideaIndex) external onlyKeeper {
      require(investmentsExecuted.length > _ideaIndex, "This idea index does not exist");
      InvestmentIdea storage idea = investmentsExecuted[_ideaIndex];
      require(!idea.finalized, "This investment was already exited");
      // check that the keeper is registered and healthy
      // Execute exit trade
      //_invoke(_integration, _value, _data);
      // Mark as finalized
      idea.finalized = true;
      idea.exitedAt = block.timestamp;
      // Reward contributors accordingly with reserve asset & update position of the reserve asset

      // Sends fee to the keeper
    }

    receive() external payable {} // solium-disable-line quotes

    /* ============ Internal Functions ============ */

    function _validateReserveAsset(address _reserveAsset, uint256 _quantity)
        internal
        view
    {
        require(_quantity > 0, "Quantity must be > 0");
        require(
            IBabController(controller).isValidReserveAsset(_reserveAsset),
            "Must be valid reserve asset"
        );
    }

    function _validateIssuanceInfo(
        uint256 _minFundTokenReceiveQuantity,
        ActionInfo memory _depositInfo
    ) internal view {
        // Check that total supply is greater than min supply needed for issuance
        // Note: A min supply amount is needed to avoid division by 0 when Fund token supply is 0
        require(
            _depositInfo.previousFundTokenSupply >= minFundTokenSupply,
            "Supply must be greater than minimum to enable issuance"
        );

        require(
            _depositInfo.fundTokenQuantity >= _minFundTokenReceiveQuantity,
            "Must be greater than min Fund token"
        );
    }

    function _validateRedemptionInfo(
        uint256 _minReserveReceiveQuantity,
        uint256 /* _fundTokenQuantity */,
        ActionInfo memory _withdrawalInfo
    ) internal view {
        // Check that new supply is more than min supply needed for redemption
        // Note: A min supply amount is needed to avoid division by 0 when withdrawaling fund token to 0
        require(
            _withdrawalInfo.newFundTokenSupply >= minFundTokenSupply,
            "Supply must be greater than minimum to enable redemption"
        );

        require(
            _withdrawalInfo.netFlowQuantity >= _minReserveReceiveQuantity,
            "Must be greater than min receive reserve quantity"
        );
    }

    function _createIssuanceInfo(
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    ) internal view returns (ActionInfo memory) {
        ActionInfo memory depositInfo;
        depositInfo.previousFundTokenSupply = totalSupply();
        depositInfo.preFeeReserveQuantity = _reserveAssetQuantity;

        (
            depositInfo.protocolFees,
            depositInfo.netFlowQuantity
        ) = _getFees(depositInfo.preFeeReserveQuantity, true);

        depositInfo.fundTokenQuantity = _getFundTokenMintQuantity(
            _reserveAsset,
            depositInfo.netFlowQuantity,
            depositInfo.previousFundTokenSupply
        );

        // Calculate inflation and new position multiplier. Note: Round inflation up in order to round position multiplier down
        depositInfo.newFundTokenSupply =
            depositInfo.fundTokenQuantity.add(
              depositInfo.previousFundTokenSupply
            );

        uint256 existingBalance = _getPositionBalance(_reserveAsset).toUint256();

        depositInfo.newReservePositionBalance = existingBalance.add(depositInfo.netFlowQuantity);

        return depositInfo;
    }

    function _createRedemptionInfo(
        address _reserveAsset,
        uint256 _fundTokenQuantity
    ) internal view returns (ActionInfo memory) {
        ActionInfo memory withdrawalInfo;

        withdrawalInfo.fundTokenQuantity = _fundTokenQuantity;

        withdrawalInfo.preFeeReserveQuantity = _getWithdrawalReserveQuantity(
            _reserveAsset,
            _fundTokenQuantity
        );

        (
            withdrawalInfo.protocolFees,
            withdrawalInfo.netFlowQuantity
        ) = _getFees(withdrawalInfo.preFeeReserveQuantity, false);

        withdrawalInfo.previousFundTokenSupply = totalSupply();

        withdrawalInfo.newFundTokenSupply =
            withdrawalInfo.previousFundTokenSupply.sub(_fundTokenQuantity);

        withdrawalInfo.newReservePositionBalance = _getWithdrawalPositionBalance(
            _reserveAsset,
            withdrawalInfo
        );

        return withdrawalInfo;
    }

    /**
     * Transfer reserve asset from user to Fund and fees from user to appropriate fee recipients
     */
    function _transferCollateralAndHandleFees(
        address _reserveAsset,
        ActionInfo memory _depositInfo
    ) internal {
        // Only need to transfer the collateral if different than WETH
        if (_reserveAsset != weth) {
          IERC20(_reserveAsset).transferFrom(
              msg.sender,
              address(this),
              _depositInfo.netFlowQuantity
          );
        }
        if (_depositInfo.protocolFees > 0) {
            IERC20(_reserveAsset).transferFrom(
                msg.sender,
                IBabController(controller).getFeeRecipient(),
                _depositInfo.protocolFees
            );
        }
    }

    function _handleDepositStateUpdates(
        address _reserveAsset,
        address _to,
        ActionInfo memory _depositInfo
    ) internal {

        editPosition(
            _reserveAsset,
            _depositInfo.newReservePositionBalance,
            address(0),
            msg.value,
            0
        );

        _mint(_to, _depositInfo.fundTokenQuantity);

        emit FundTokenDeposited(
            _to,
            _depositInfo.fundTokenQuantity,
            _depositInfo.protocolFees
        );
    }

    function _handleWithdrawalStateUpdates(
        address _reserveAsset,
        address _to,
        ActionInfo memory _withdrawalInfo
    ) internal {
        editPosition(
            _reserveAsset,
            _withdrawalInfo.newReservePositionBalance,
            address(0),
            uint256(-_withdrawalInfo.netFlowQuantity),
            0
        );

        emit FundTokenwithdrawed(
            msg.sender,
            _to,
            _withdrawalInfo.fundTokenQuantity,
            _withdrawalInfo.protocolFees
        );
    }

    function _handleRedemptionFees(
        address _reserveAsset,
        ActionInfo memory _withdrawalInfo
    ) internal {
        // Instruct the Fund to transfer protocol fee to fee recipient if there is a fee
        payProtocolFeeFromFund(_reserveAsset, _withdrawalInfo.protocolFees);
    }

    /**
     * Returns the deposit premium percentage. Virtual function that can be overridden in future versions of the module
     * and can contain arbitrary logic to calculate the issuance premium.
     */
    function _getDepositPremium() internal view virtual returns (uint256) {
        return premiumPercentage;
    }

    /**
     * Returns the withdrawal premium percentage. Virtual function that can be overridden in future versions of the module
     * and can contain arbitrary logic to calculate the redemption premium.
     */
    function _getWithdrawalPremium() internal view virtual returns (uint256) {
        return premiumPercentage;
    }

    /**
     * Returns the fees attributed to the manager and the protocol. The fees are calculated as follows:
     *
     * Protocol Fee = (% direct fee %) * reserveAssetQuantity
     *
     * @param _reserveAssetQuantity         Quantity of reserve asset to calculate fees from
     * @param _isDeposit ad
     *
     * @return  uint256                     Fees paid to the protocol in reserve asset
     * @return  uint256                     Net reserve to user net of fees
     */
    function _getFees(uint256 _reserveAssetQuantity, bool _isDeposit)
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
                ? IBabController(controller).getProtocolDepositFundTokenFee()
                : IBabController(controller)
                    .getProtocolWithdrawalFundTokenFee();
        // Get performance if withdrawal and there are profits
        if (!_isDeposit) {
          uint profits = _reserveAssetQuantity.sub(contributors[msg.sender].totalDeposit);
          if (profits > 0) {
            uint perfFee = IBabController(controller)
            .getProtocolPerformanceFee().preciseMul(profits);
            protocolFeePercentage = protocolFeePercentage.add(perfFee);
          }
        }

        // Calculate total notional fees
        uint256 protocolFees =
            protocolFeePercentage.preciseMul(_reserveAssetQuantity);

        uint256 netReserveFlow =
            _reserveAssetQuantity.sub(protocolFees);

        return (protocolFees, netReserveFlow);
    }

    function _getFundTokenMintQuantity(
        address _reserveAsset,
        uint256 _netReserveFlows, // Value of reserve asset net of fees
        uint256 _fundTokenTotalSupply
    ) internal view returns (uint256) {
        uint256 premiumPercentageToApply = _getDepositPremium();
        uint256 premiumValue =
            _netReserveFlows.preciseMul(premiumPercentageToApply);

        // Get valuation of the Fund with the quote asset as the reserve asset.
        // Reverts if price is not found
        uint256 fundValuation = IFundValuer(IBabController(controller).getFundValuer()).calculateFundValuation(address(this), _reserveAsset);

        // Get reserve asset decimals
        uint256 reserveAssetDecimals = ERC20(_reserveAsset).decimals();
        uint256 baseUnits = uint256(10) ** reserveAssetDecimals;
        uint256 normalizedTotalReserveQuantityNetFees = _netReserveFlows.preciseDiv(baseUnits);

        uint256 normalizedTotalReserveQuantityNetFeesAndPremium =
            _netReserveFlows.sub(premiumValue).preciseDiv(baseUnits);

        // Calculate Fund tokens to mint to depositor
        uint256 denominator =
            _fundTokenTotalSupply
                .preciseMul(fundValuation)
                .add(normalizedTotalReserveQuantityNetFees)
                .sub(normalizedTotalReserveQuantityNetFeesAndPremium);
        uint256 quantityToMint =
            normalizedTotalReserveQuantityNetFeesAndPremium
                .preciseMul(_fundTokenTotalSupply)
                .preciseDiv(denominator);
        return quantityToMint;
    }

    function _getWithdrawalReserveQuantity(
        address _reserveAsset,
        uint256 _fundTokenQuantity
    ) internal view returns (uint256) {
        // Get valuation of the Fund with the quote asset as the reserve asset. Returns value in precise units (10e18)
        // Reverts if price is not found
        uint256 fundValuation =
            IFundValuer(IBabController(controller).getFundValuer())
                .calculateFundValuation(address(this), _reserveAsset);

        uint256 totalWithdrawalValueInPreciseUnits =
            _fundTokenQuantity.preciseMul(fundValuation);
        // Get reserve asset decimals
        uint256 reserveAssetDecimals = ERC20(_reserveAsset).decimals();
        uint256 prePremiumReserveQuantity =
            totalWithdrawalValueInPreciseUnits.preciseMul(
                10**reserveAssetDecimals
            );

        uint256 premiumPercentageToApply = _getWithdrawalPremium();
        uint256 premiumQuantity =
            prePremiumReserveQuantity.preciseMulCeil(premiumPercentageToApply);

        return prePremiumReserveQuantity.sub(premiumQuantity);
    }

    /**
     * The new position reserve asset balance is calculated as follows:
     * totalReserve = oldBalance - reserveQuantityToSendOut
     * newBalance = totalReserve / newFundTokenSupply
     */
    function _getWithdrawalPositionBalance(
        address _reserveAsset,
        ActionInfo memory _withdrawalInfo
    ) internal view returns (uint256) {
        uint256 totalExistingBalance = _getPositionBalance(_reserveAsset).toUint256();


        uint256 outflow =
            _withdrawalInfo
                .netFlowQuantity
                .add(_withdrawalInfo.protocolFees);

        // Require withdrawable quantity is greater than existing collateral
        require(
            totalExistingBalance >= outflow,
            "Must be greater than total available collateral"
        );

        return
            totalExistingBalance.sub(outflow);
    }

    /**
     * Updates the contributor info in the array
     */
    function _udpateContributorInfo(uint256 tokensReceived, uint256 amount) internal {
      Contributor storage contributor = contributors[msg.sender];
      // If new contributor, create one, increment count, and set the current TS
      if (contributor.totalDeposit == 0) {
        totalContributors = totalContributors.add(1);
        contributor.timestamp = block.timestamp;
      }

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

    function _validateOnlyContributor(address _caller) internal view {
        require(
            IERC20(address(this)).balanceOf(_caller) > 0,
            "Only someone with the fund token can withdraw"
        );
    }
}
