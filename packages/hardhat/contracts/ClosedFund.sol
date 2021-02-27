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

// import "hardhat/console.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { IWETH } from "./interfaces/external/weth/IWETH.sol";
import { IFundIdeas } from "./interfaces/IFundIdeas.sol";
import { IBabController } from "./interfaces/IBabController.sol";
import { IFundValuer } from "./interfaces/IFundValuer.sol";
import { BaseFund } from "./BaseFund.sol";


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
    uint256 public fundActiveWindow;          // Duration of the fund active window
    uint256 public fundWithdrawalWindow;      // Duration of the fund withdrawal window
    uint256 public fundInitializedAt;         // Fund Initialized at timestamp
    uint256 public fundCurrentActiveWindowStartedAt;   // Fund Initialized at timestamp

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
     * @param _creator                Address of the creator
     * @param _name                   Name of the Fund
     * @param _symbol                 Symbol of the Fund
     * @param _minContribution        Min contribution to the fund
     */

    constructor(
        address[] memory _integrations,
        address _weth,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol,
        uint256 _minContribution
    )
        BaseFund(
            _integrations,
            _weth,
            _weth,
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
     * @param _fundActiveWindow               Fund active window
     * @param _fundWithdrawalWindow           Fund withdrawal window
     * @param _fundIdeas                      Address of the instance with the investment ideas
     */
    function initialize(
        uint256 _maxDepositLimit,
        uint256 _premiumPercentage,
        uint256 _minFundTokenSupply,
        uint256 _fundActiveWindow,
        uint256 _fundWithdrawalWindow,
        address _fundIdeas
    ) external onlyCreator onlyInactive payable {
        require(_maxDepositLimit >= 1**19, "Max deposit limit needs >= 10");

        require(msg.value > minContribution && msg.value < _maxDepositLimit.div(20), "Creator needs to deposit, up to 20% of the max fund");
        IBabController ifcontroller = IBabController(controller);
        require(
            _premiumPercentage <= ifcontroller.getMaxFundPremiumPercentage(),
            "Premium must < max"
        );
        require(
            _fundActiveWindow <= ifcontroller.getMaxFundActiveWindow() && _fundActiveWindow >= ifcontroller.getMinFundActiveWindow() ,
            "Fund active window must be within range"
        );
        require(
            _fundWithdrawalWindow <= ifcontroller.getMaxWithdrawalWindow() && _fundWithdrawalWindow >= ifcontroller.getMinWithdrawalWindow() ,
            "Fund active window must be within range"
        );
        require(
            _minFundTokenSupply > 0,
            "Min Fund token supply >= 0"
        );
        minFundTokenSupply = _minFundTokenSupply;
        premiumPercentage = _premiumPercentage;
        maxDepositLimit = _maxDepositLimit;
        fundActiveWindow = _fundActiveWindow;
        fundWithdrawalWindow = _fundWithdrawalWindow;
        fundInitializedAt = block.timestamp;
        fundCurrentActiveWindowStartedAt = block.timestamp;

        IFundIdeas fundIdeasC = IFundIdeas(_fundIdeas);
        require(fundIdeasC.controller() == controller, "Controller must be the same");
        require(fundIdeasC.fund() == address(this), "Fund must be this contract");
        fundIdeas = _fundIdeas;

        uint256 initialDepositAmount = msg.value;

        // make initial deposit
        uint256 initialTokens = initialDepositAmount.div(initialBuyRate);

        IWETH(weth).deposit{value: initialDepositAmount}();

        _mint(creator, initialTokens);
        _udpateContributorInfo(initialTokens, initialDepositAmount);

        _calculateAndEditPosition(
          weth,
          initialDepositAmount,
          initialDepositAmount,
          0
        );

        require(totalSupply() > 0, "Fund must receive an initial deposit");

        active = true;
    }

    /**
      * Restarts the current deposit window if needed
      *
    */
    function restartWindow() public {
      if (block.timestamp >= fundCurrentActiveWindowStartedAt.add(fundActiveWindow.add(fundWithdrawalWindow))) {
        if (active) {
          fundCurrentActiveWindowStartedAt = block.timestamp;
        }
      }
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
        restartWindow();
        require(
            msg.value >= minContribution,
            ">= minContribution"
        );
        require(block.timestamp >= fundCurrentActiveWindowStartedAt &&
          block.timestamp < fundCurrentActiveWindowStartedAt.add(fundActiveWindow),
          "Fund is not in the withdrawal window"
        );
        // if deposit limit is 0, then there is no deposit limit
        if(maxDepositLimit > 0) {
          require(totalFundsDeposited.add(msg.value) <= maxDepositLimit, "Max Deposit Limit");
        }

        // Always wrap to WETH
        IWETH(weth).deposit{value: msg.value}();

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
        require(block.timestamp >= fundCurrentActiveWindowStartedAt.add(fundActiveWindow) &&
          block.timestamp < fundCurrentActiveWindowStartedAt.add(fundActiveWindow).add(fundWithdrawalWindow),
          "Fund is not in the withdrawal window"
        );
        // require(block.timestamp > fundEndsBy, "Withdrawals are disabled until fund ends");
        require(
            _fundTokenQuantity <= balanceOf(msg.sender),
            "Withdrawal amount <= to deposited amount"
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
        totalFunds = totalFunds.sub(withdrawalInfo.netFlowQuantity).sub(withdrawalInfo.protocolFees);

        IWETH(weth).withdraw(withdrawalInfo.netFlowQuantity);
        _to.transfer(withdrawalInfo.netFlowQuantity);

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
            "Premium < maximum allowed"
        );

        premiumPercentage = _premiumPercentage;

        emit PremiumEdited(_premiumPercentage);
    }

    // if limit == 0 then there is no deposit limit
    function setDepositLimit(uint limit) external onlyGovernanceFund {
      maxDepositLimit = limit;
    }

    // Any tokens (other than the target) that are sent here by mistake are recoverable by the owner
    // TODO: If it is not whitelisted, trade it for weth
    function sweep(address _token) external onlyContributor(msg.sender) {
       require(!_hasPosition(_token), "Token is one of the fund positions");
       uint256 balance = ERC20(_token).balanceOf(address(this));
       require(balance > 0, "Token balance > 0");
       _calculateAndEditPosition(_token, balance, ERC20(_token).balanceOf(address(this)), 0);
    }

    /* ============ External Getter Functions ============ */

    function getContributor(address _contributor) public view returns (uint256, uint256, uint256) {
        Contributor memory contributor = contributors[_contributor];
        return (contributor.totalDeposit, contributor.tokensReceived, contributor.timestamp);
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
        (, uint256 netReserveFlow) = _getFees(_reserveAssetQuantity, true, 0);

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

        (, uint256 netReserveFlows) = _getFees(preFeeReserveQuantity, false, _fundTokenQuantity);

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
                _getFees(totalWithdrawalValue, false, _fundTokenQuantity);

            uint256 existingBalance =
                _getPositionBalance(_reserveAsset).toUint256();

            return existingBalance >= expectedWithdrawalQuantity;
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
        uint256 _minFundTokenReceiveQuantity,
        ActionInfo memory _depositInfo
    ) internal view {
        // Check that total supply is greater than min supply needed for issuance
        // Note: A min supply amount is needed to avoid division by 0 when Fund token supply is 0
        require(
            _depositInfo.previousFundTokenSupply >= minFundTokenSupply,
            "Supply must > than minimum"
        );

        require(
            _depositInfo.fundTokenQuantity >= _minFundTokenReceiveQuantity,
            "Must be > min Fund token"
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
        depositInfo.previousFundTokenSupply = totalSupply();
        depositInfo.preFeeReserveQuantity = _reserveAssetQuantity;

        (
            depositInfo.protocolFees,
            depositInfo.netFlowQuantity
        ) = _getFees(depositInfo.preFeeReserveQuantity, true, 0);

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
        ) = _getFees(withdrawalInfo.preFeeReserveQuantity, false, _fundTokenQuantity);

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
        if (_depositInfo.protocolFees > 0) {
            ERC20(_reserveAsset).transferFrom(
                address(this),
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
     * Returns the fees attributed to the manager and the protocol. The fees are calculated as follows:
     *
     * Protocol Fee = (% direct fee %) * reserveAssetQuantity
     *
     * @param _reserveAssetQuantity         Quantity of reserve asset to calculate fees from
     * @param _isDeposit                    Boolean that is true when it is a deposit
     * @param _fundTokenQuantity            Number of fund tokens involved in the operation
     *
     * @return  uint256                     Fees paid to the protocol in reserve asset
     * @return  uint256                     Net reserve to user net of fees
     */
    function _getFees(uint256 _reserveAssetQuantity, bool _isDeposit, uint256 _fundTokenQuantity)
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
        uint perfFee = 0;
        if (!_isDeposit) {
          uint percentage = balanceOf(msg.sender).div(_fundTokenQuantity); // Divide by the % tokens being withdrawn
          uint profits = contributors[msg.sender].totalDeposit.div(percentage).sub(_reserveAssetQuantity);
          if (profits > 0) {
            perfFee = IBabController(controller)
            .getProtocolPerformanceFee().preciseMul(profits);
          }
        }

        // Calculate total notional fees
        uint256 protocolFees =
            protocolFeePercentage.preciseMul(_reserveAssetQuantity).add(perfFee);

        uint256 netReserveFlow =
            _reserveAssetQuantity.sub(protocolFees);

        return (protocolFees, netReserveFlow);
    }

    function _getFundTokenMintQuantity(
        address _reserveAsset,
        uint256 _netReserveFlows, // Value of reserve asset net of fees
        uint256 _fundTokenTotalSupply
    ) internal view returns (uint256) {
        uint256 premiumPercentageToApply = premiumPercentage;
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

        uint256 premiumPercentageToApply = premiumPercentage;
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
            "Must have enough balance"
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
            balanceOf(_caller) > 0,
            "Only participant can withdraw"
        );
    }
}
