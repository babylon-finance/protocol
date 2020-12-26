/*
    Copyright 2020 DFolio.

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
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";
import { AddressArrayUtils } from "./lib/AddressArrayUtils.sol";

import { Investment } from "./investments/Investment.sol"
import { IFolioController } from "./interfaces/IFolioController.sol";
import { IFundIssuanceHook } from "./interfaces/IFundIssuanceHook.sol";
import { IFund } from "./interfaces/IFund.sol";


/**
 * @title ClosedFund
 * @author DFolio
 *
 * OpenFund holds the logic to deposit, witthdraw and track contributions and fees.
 */
contract OpenFund is BaseFund, ReentrancyGuard {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using Address for address;
    using AddressArrayUtils for address[];

    /* ============ Events ============ */
    event FundTokenIssued(
        address indexed _fund,
        address indexed _to,
        address _hookContract,
        uint256 _quantity
    );
    event FundTokenRedeemed(
        address indexed _fund,
        address indexed _redeemer,
        address indexed _to,
        uint256 _quantity
    );

    event ContributionLog(address indexed contributor,uint256 amount,uint256 timestamp);
    event WithdrawalLog(address indexed sender, uint amount, uint timestamp);

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    struct ActionInfo {
      uint256 preFeeReserveQuantity;                 // Reserve value before fees; During issuance, represents raw quantity
                                                     // During redeem, represents post-premium value
      uint256 protocolFees;                          // Total protocol fees (direct + manager revenue share)
      uint256 managerFee;                            // Total manager fee paid in reserve asset
      uint256 netFlowQuantity;                       // When issuing, quantity of reserve asset sent to Fund
                                                     // When redeeming, quantity of reserve asset sent to redeemer
      uint256 fundTokenQuantity;                      // When issuing, quantity of Fund tokens minted to mintee
                                                     // When redeeming, quantity of Fund tokens redeemed
      uint256 previousFundTokenSupply;                // Fund token supply prior to issue/redeem action
      uint256 newFundTokenSupply;                     // Fund token supply after issue/redeem action
      int256 newPositionMultiplier;                  // Fund token position multiplier after issue/redeem
      uint256 newReservePositionUnit;                // Fund token reserve asset position unit after issue/redeem
    }

    IFundIssuanceHook managerIssuanceHook;      // Issuance hook configurations
    IFundIssuanceHook managerRedemptionHook;    // Redemption hook configurations

    uint256 managerIssueFee;  // % of the issuance denominated in the reserve asset
    uint256 managerWithdrawalFee; // % of the redemption denominated in the reserve asset,  charged in withdrawal
    uint256 managerPerformanceFee; // % of the profits denominated in the reserve asset, charged in withdrawal
    uint256 premiumPercentage; // Premium percentage (0.01% = 1e14, 1% = 1e16). This premium is a buffer around oracle
                                // prices paid by user to the Fund Token, which prevents arbitrage and oracle front running

    // Wrapped ETH address
    IWETH public immutable weth;

    // List of contributors
    struct Contributor {
      uint256 amount; //wei
      uint256 timestamp;
      bool claimed;
    }
    mapping(address => Contributor) public contributors;
    uint256 public totalContributors;
    uint256 public totalFundsDeposited;
    // Min contribution in the fund
    uint256 public minContribution = 1000000000000; //wei
    uint256 public buyRate =  10 ** 9;
    uint256 public minFundTokenSupply;


    /* ============ Constructor ============ */

    /**
     * When a new Fund is created, initializes Investments are set to empty.
     * All parameter validations are on the FolioController contract. Validations are performed already on the
     * FolioController. Initiates the positionMultiplier as 1e18 (no adjustments).
     *
     * @param _integrations           List of integrations to enable. All integrations must be approved by the Controller
     * @param _weth                   Address of the WETH ERC20
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _controller             Address of the controller
     * @param _manager                Address of the manager
     * @param _managerFeeRecipient    Address where the manager will receive the fees
     * @param _name                   Name of the Fund
     * @param _symbol                 Symbol of the Fund
     */

    constructor(
        address[] memory _integrations,
        IWETH _weth,
        IController _controller,
        address _manager,
        address _managerFeeRecipient,
        address _reserveAsset,
        string memory _name,
        string memory _symbol,
        uint256 _minContribution,
        uint 256 _buyRate
    ) public BaseFund(
        _integrations,
        _weth,
        _controller,
        _manager,
        _reserveAsset,
        _name,
        _symbol
      ){
        minContribution = _minContribution;
        buyRate = _buyRate;
        totalContributors = 0;
        totalFundsDeposited = 0;
    }

    /* ============ External Functions ============ */

    /**
     * SET MANAGER ONLY. Initializes this module to the Fund with hooks, allowed reserve assets,
     * fees and issuance premium. Only callable by the Fund's manager. Hook addresses are optional.
     * Address(0) means that no hook will be called.
     *
     * @param _managerIssueFee
     * @param _managerWithdrawalFee
     * @param _managerPerformanceFee
     * @param _premiumPercentage
     */
    function initialize(
        uint256 _managerIssueFee,
        uint256 _managerWithdrawalFee,
        uint256 _managerPerformanceFee,
        uint256 _premiumPercentage,
        uint256 _minFundTokenSupply,
        IFundIssuanceHook _managerIssuanceHook,
        IFundIssuanceHook _managerRedeemHook,
    )
        external
        onlyManager
        onlyInactive
    {
        require(_managerIssueFee <= IFolioController(controller).maxManagerIssueFee, "Manager issue fee must be less than max");
        require(_managerRedeemFee <= IFolioController(controller).maxManagerRedeemFee, "Manager redeem fee must be less than max");
        require(_managerPerformanceFee <= IFolioController(controller).maxManagerPerformanceFee, "Manager performance fee must be less than max");
        require(_premiumPercentage <= IFolioController(controller).maxFundPremiumPercentage, "Premium must be less than max");
        require(_minFundTokenSupply > 0, "Min Fund token supply must be greater than 0");

        managerIssueFee = _managerIssueFee;
        minFundTokenSupply = _minFundTokenSupply;
        managerWithdrawalFee = _managerWithdrawalFee;
        managerPerformanceFee = _managerPerformanceFee;
        premiumPercentage = _premiumPercentage;
        managerIssuanceHook = _managerIssuanceHook;
        maangerRedeemHook = _managerRedeemHook;
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
    )
        external
        payable
        nonReentrant
        onlyActive
    {
        require(
            msg.value >= minContribution,
            "Send at least 1000000000000 wei"
        );
        // Always wrap to WETH
        weth.deposit{ value: msg.value }();

        if (_reserveAsset != weth) {
          // TODO: trade from weth into reserve asset
        }

        _validateReserveAsset( _reserveAsset, _reserveAssetQuantity);

        _callPreIssueHooks(_reserveAsset, _reserveAssetQuantity, msg.sender, _to);

        ActionInfo memory issueInfo = _createIssuanceInfo(_reserveAsset, _reserveAssetQuantity);

        _validateIssuanceInfo(_minFundTokenReceiveQuantity, issueInfo);

        _transferCollateralAndHandleFees(IERC20(_reserveAsset), issueInfo);

        Contributor storage contributor = contributors[msg.sender];

        // If new contributor, create one, increment count, and set the current TS
        if (contributor.amount == 0) {
          totalContributors = totalContributors.add(1);
          contributor.timestamp = block.timestamp;
        }

        totalFunds = totalFunds.add(msg.value);
        contributor.amount = contributor.amount.add(msg.value);
        emit ContributionLog(msg.sender, msg.value, block.timestamp);

        _handleIssueStateUpdates(_reserveAsset, _to, issueInfo);
    }

    /**
     * Redeems the Fund's positions and sends the components of the given
     * quantity to the caller. This function only handles Default Positions (positionState = 0).
     *
     * @param _quantity             Quantity of the fund token to redeem
     * @param _minReserveReceiveQuantity    Min quantity of reserve asset to receive
     * @param _to                   Address to send component assets to
     */
    function withdraw(
        uint256 _fundTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address _to
    )
        external
        nonReentrant
        onlyContributor(msg.sender)
    {
      Contributor storage contributor = contributors[msg.sender];
      require(_amount <= contributor.amount, 'Withdrawal amount must be less than or equal to deposited amount');

      _validateReserveAsset( _reserveAsset, _fundTokenQuantity);

      _callPreRedeemHooks(_fundTokenQuantity, msg.sender, _to);

      ActionInfo memory redeemInfo = _createRedemptionInfo(_reserveAsset, _fundTokenQuantity);

      _validateRedemptionInfo(_minReserveReceiveQuantity, _fundTokenQuantity, redeemInfo);

      contributor.amount = contributor.amount.sub(_amount);
      totalFunds = totalFunds.sub(_amount);
      if (contributor.amount == 0) {
        totalContributors = totalContributors.sub(1);
      }


      _burn(msg.sender, _fundTokenQuantity);

      emit WithdrawalLog(msg.sender, _amount, block.timestamp);

      // Instruct the Fund to transfer the reserve asset back to the user
      IERC20(_reserveAsset).transfer(_to, redeemInfo.netFlowQuantity);

      weth.withdraw(redeemInfo.netFlowQuantity);

      _to.transfer(redeemInfo.netFlowQuantity);

      _handleRedemptionFees(_reserveAsset, redeemInfo);

      _handleRedeemStateUpdates(_reserveAsset, _to, redeemInfo);
    }


    /* ============ External Getter Functions ============ */

    function getPremiumPercentage() external view returns (uint256) {
      return premiumPercentage;
    }

    function getIssueManagerFee() external view returns (uint256) {
      return managerIssueFee;
    }

    function getRedeemManagerFee() external view returns (uint256) {
      return managerRedeemFee;
    }

    function getManagerPerformanceFee() external view returns (uint256) {
      return managerPerformanceFee;
    }

    /**
     * Get the expected fund tokens minted to recipient on issuance
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _reserveAssetQuantity         Quantity of the reserve asset to issue with
     *
     * @return  uint256                     Expected Fund tokens to be minted to recipient
     */
    function getExpectedFundTokensIssuedQuantity(
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    )
        external
        view
        returns (uint256)
    {
        (,, uint256 netReserveFlow) = _getFees(
            _reserveAssetQuantity,
        );

        uint256 setTotalSupply = totalSupply();

        return _getFundTokenMintQuantity(
            _reserveAsset,
            netReserveFlow,
            setTotalSupply
        );
    }

    /**
     * Get the expected reserve asset to be redeemed
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _fundTokenQuantity             Quantity of Fund tokens to redeem
     *
     * @return  uint256                     Expected reserve asset quantity redeemed
     */
    function getExpectedReserveRedeemQuantity(
        address _reserveAsset,
        uint256 _fundTokenQuantity
    )
        external
        view
        returns (uint256)
    {
        uint256 preFeeReserveQuantity = _getRedeemReserveQuantity(_reserveAsset, _fundTokenQuantity);

        (,, uint256 netReserveFlows) = _getFees(
            preFeeReserveQuantity,
        );

        return netReserveFlows;
    }

    /**
     * Checks if issue is valid
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _reserveAssetQuantity         Quantity of the reserve asset to issue with
     *
     * @return  bool                        Returns true if issue is valid
     */
    function isIssueValid(
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    )
        external
        view
        returns (bool)
    {
        uint256 setTotalSupply = totalSupply();

    return _reserveAssetQuantity != 0
            && IController(controller).isValidReserveAsset(_reserveAsset)
            && setTotalSupply >= minFundTokenSupply
    }

    /**
     * Checks if redeem is valid
     *
     * @param _reserveAsset                 Address of the reserve asset
     * @param _fundTokenQuantity             Quantity of fund tokens to redeem
     *
     * @return  bool                        Returns true if redeem is valid
     */
    function isRedeemValid(
        address _reserveAsset,
        uint256 _fundTokenQuantity
    )
        external
        view
        returns (bool)
    {
        uint256 setTotalSupply = totalSupply();

        if (
            _fundTokenQuantity == 0
            || !IController(controller).isValidReserveAsset(_reserveAsset)
            || setTotalSupply <  minFundTokenSupply.add(_fundTokenQuantity)
        ) {
            return false;
        } else {
            uint256 totalRedeemValue =_getRedeemReserveQuantity(_reserveAsset, _fundTokenQuantity);

            (,, uint256 expectedRedeemQuantity) = _getFees(
                totalRedeemValue,
            );

            uint256 existingUnit = getPositionRealUnit(_reserveAsset).toUint256();

            return existingUnit.preciseMul(setTotalSupply) >= expectedRedeemQuantity;
        }
    }

    receive() external payable {} // solium-disable-line quotes

    /* ============ Internal Functions ============ */

    function _validateReserveAsset(address _reserveAsset, uint256 _quantity) internal view {
        require(_quantity > 0, "Quantity must be > 0");
        require(IFolioController(controller).isValidReserveAsset(_reserveAsset), "Must be valid reserve asset");
    }

    function _validateIssuanceInfo(uint256 _minFundTokenReceiveQuantity, ActionInfo memory _issueInfo) internal view {
        // Check that total supply is greater than min supply needed for issuance
        // Note: A min supply amount is needed to avoid division by 0 when Fund token supply is 0
        require(
            _issueInfo.previousFundTokenSupply >= minFundTokenSupply,
            "Supply must be greater than minimum to enable issuance"
        );

        require(_issueInfo.setFundTokenQuantity >= _minFundTokenReceiveQuantity, "Must be greater than min Fund token");
    }

    function _validateRedemptionInfo(
        uint256 _minReserveReceiveQuantity,
        uint256 _fundTokenQuantity,
        ActionInfo memory _redeemInfo
    )
        internal
        view
    {
        // Check that new supply is more than min supply needed for redemption
        // Note: A min supply amount is needed to avoid division by 0 when redeeming fund token to 0
        require(
            _redeemInfo.newFundTokenSupply >= minFundTokenSupply,
            "Supply must be greater than minimum to enable redemption"
        );

        require(_redeemInfo.netFlowQuantity >= _minReserveReceiveQuantity, "Must be greater than min receive reserve quantity");
    }

    function _createIssuanceInfo(
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    )
        internal
        view
        returns (ActionInfo memory)
    {
        ActionInfo memory issueInfo;

        issueInfo.previousFundTokenSupply = totalSupply();

        issueInfo.preFeeReserveQuantity = _reserveAssetQuantity;

        (issueInfo.protocolFees, issueInfo.managerFee, issueInfo.netFlowQuantity) = _getFees(
            issueInfo.preFeeReserveQuantity
        );

        issueInfo.fundTokenQuantity = _getFundTokenMintQuantity(
            _reserveAsset,
            issueInfo.netFlowQuantity,
            issueInfo.previousFundTokenSupply
        );

        (issueInfo.newFundTokenSupply, issueInfo.newPositionMultiplier) = _getIssuePositionMultiplier(issueInfo);

        issueInfo.newReservePositionUnit = _getIssuePositionUnit(_reserveAsset, issueInfo);

        return issueInfo;
    }

    function _createRedemptionInfo(
        address _reserveAsset,
        uint256 _fundTokenQuantity
    )
        internal
        view
        returns (ActionInfo memory)
    {
        ActionInfo memory redeemInfo;

        redeemInfo.fundTokenQuantity = _fundTokenQuantity;

        redeemInfo.preFeeReserveQuantity =_getRedeemReserveQuantity(_reserveAsset, _fundTokenQuantity);

        (redeemInfo.protocolFees, redeemInfo.managerFee, redeemInfo.netFlowQuantity) = _getFees(
            redeemInfo.preFeeReserveQuantity,
        );

        redeemInfo.previousFundTokenSupply = totalSupply();

        (redeemInfo.newFundTokenSupply, redeemInfo.newPositionMultiplier) = _getRedeemPositionMultiplier(_fundTokenQuantity, redeemInfo);

        redeemInfo.newReservePositionUnit = _getRedeemPositionUnit(_reserveAsset, redeemInfo);

        return redeemInfo;
    }

    /**
     * Transfer reserve asset from user to Fund and fees from user to appropriate fee recipients
     */
    function _transferCollateralAndHandleFees(IERC20 _reserveAsset, ActionInfo memory _issueInfo) internal {
        transferFrom(_reserveAsset, msg.sender, address(this), _issueInfo.netFlowQuantity);

        if (_issueInfo.protocolFees > 0) {
            transferFrom(_reserveAsset, msg.sender, controller.feeRecipient(), _issueInfo.protocolFees);
        }

        if (_issueInfo.managerFee > 0) {
            transferFrom(_reserveAsset, msg.sender, managerFeeRecipient, _issueInfo.managerFee);
        }
    }

    function _handleIssueStateUpdates(
        address _reserveAsset,
        address _to,
        ActionInfo memory _issueInfo
    )
        internal
    {
        editPositionMultiplier(_issueInfo.newPositionMultiplier);

        editPosition(_reserveAsset, _issueInfo.newReservePositionUnit, address(0));

        _mint(_to, _issueInfo.fundTokenQuantity);

        emit FundTokenTokenIssued(
            address(this),
            msg.sender,
            _to,
            _reserveAsset,
            address(managerIssuanceHook),
            _issueInfo._fundTokenQuantity,
            _issueInfo.managerFee,
            _issueInfo.protocolFees
        );
    }

    function _handleRedeemStateUpdates(
        address _reserveAsset,
        address _to,
        ActionInfo memory _redeemInfo
    )
        internal
    {
        editPositionMultiplier(_redeemInfo.newPositionMultiplier);

        editPosition(_reserveAsset, _redeemInfo.newReservePositionUnit, address(0));

        emit FundTokenRedeemed(
            address(this),
            msg.sender,
            _to,
            _reserveAsset,
            address(managerRedemptionHook),
            _redeemInfo._fundTokenQuantity,
            _redeemInfo.managerFee,
            _redeemInfo.protocolFees
        );
    }

    function _handleRedemptionFees(address _reserveAsset, ActionInfo memory _redeemInfo) internal {
        // Instruct the Fund to transfer protocol fee to fee recipient if there is a fee
        payProtocolFeeFromFund(_reserveAsset, _redeemInfo.protocolFees);

        // Instruct the Fund to transfer manager fee to manager fee recipient if there is a fee
        if (_redeemInfo.managerFee > 0) {
            payManagerFeeFromFund(_reserveAsset, _redeemInfo.managerFee);
        }
    }

    /**
     * Returns the issue premium percentage. Virtual function that can be overridden in future versions of the module
     * and can contain arbitrary logic to calculate the issuance premium.
     */
    function _getIssuePremium(
    )
        virtual
        internal
        view
        returns (uint256)
    {
        return premiumPercentage;
    }

    /**
     * Returns the redeem premium percentage. Virtual function that can be overridden in future versions of the module
     * and can contain arbitrary logic to calculate the redemption premium.
     */
    function _getRedeemPremium(
    )
        virtual
        internal
        view
        returns (uint256)
    {
        return premiumPercentage;
    }

    /**
     * Returns the fees attributed to the manager and the protocol. The fees are calculated as follows:
     *
     * ManagerFee = (manager fee % - % to protocol) * reserveAssetQuantity
     * Protocol Fee = (% manager fee share + direct fee %) * reserveAssetQuantity
     *
     * @param _reserveAssetQuantity         Quantity of reserve asset to calculate fees from
     * @param _isIssue
     *
     * @return  uint256                     Fees paid to the protocol in reserve asset
     * @return  uint256                     Fees paid to the manager in reserve asset
     * @return  uint256                     Net reserve to user net of fees
     */
    function _getFees(
        uint256 _reserveAssetQuantity,
        bool isIssue
    )
        internal
        view
        returns (uint256, uint256, uint256)
    {
        // Get protocol fee percentages
        uint256 protocolFeePercentage = isIssue : controller.protocolIssueFundTokenFee : protocolRedeemFundTokenFee;
        uint256 managerFeePercentage = isIssue: managerIssueFee : managerRedeemFee;

        // Calculate total notional fees
        uint256 protocolFees = protocolFeePercentage.preciseMul(_reserveAssetQuantity);
        uint256 managerFee = managerFeePercentage.preciseMul(_reserveAssetQuantity);

        uint256 netReserveFlow = _reserveAssetQuantity.sub(protocolFees).sub(managerFee);

        return (protocolFees, managerFee, netReserveFlow);
    }

    function _getFundTokenMintQuantity(
        address _reserveAsset,
        uint256 _netReserveFlows,            // Value of reserve asset net of fees
        uint256 _fundTokenTotalSupply
    )
        internal
        view
        returns (uint256)
    {
        uint256 premiumPercentage = _getIssuePremium(_reserveAsset, _netReserveFlows);
        uint256 premiumValue = _netReserveFlows.preciseMul(premiumPercentage);

        // Get valuation of the Fund with the quote asset as the reserve asset. Returns value in precise units (1e18)
        // Reverts if price is not found
        uint256 fundValuation = controller.getFundValuer().calculateFundValuation(address(this), _reserveAsset);

        // Get reserve asset decimals
        uint256 reserveAssetDecimals = ERC20(_reserveAsset).decimals();
        uint256 normalizedTotalReserveQuantityNetFees = _netReserveFlows.preciseDiv(10 ** reserveAssetDecimals);
        uint256 normalizedTotalReserveQuantityNetFeesAndPremium = _netReserveFlows.sub(premiumValue).preciseDiv(10 ** reserveAssetDecimals);

        // Calculate Fund tokens to mint to issuer
        uint256 denominator = _fundTokenTotalSupply.preciseMul(fundValuation).add(normalizedTotalReserveQuantityNetFees).sub(normalizedTotalReserveQuantityNetFeesAndPremium);
        return normalizedTotalReserveQuantityNetFeesAndPremium.preciseMul(_fundTokenTotalSupply).preciseDiv(denominator);
    }

    function _getRedeemReserveQuantity(
        address _reserveAsset,
        uint256 _fundTokenQuantity
    )
        internal
        view
        returns (uint256)
    {
        // Get valuation of the Fund with the quote asset as the reserve asset. Returns value in precise units (10e18)
        // Reverts if price is not found
        uint256 fundValuation = controller.getFundValuer().calculateFundValuation(address(this), _reserveAsset);

        uint256 totalRedeemValueInPreciseUnits = _fundTokenQuantity.preciseMul(fundValuation);
        // Get reserve asset decimals
        uint256 reserveAssetDecimals = ERC20(_reserveAsset).decimals();
        uint256 prePremiumReserveQuantity = totalRedeemValueInPreciseUnits.preciseMul(10 ** reserveAssetDecimals);

        uint256 premiumPercentage = _getRedeemPremium(_reserveAsset, _fundTokenQuantity);
        uint256 premiumQuantity = prePremiumReserveQuantity.preciseMulCeil(premiumPercentage);

        return prePremiumReserveQuantity.sub(premiumQuantity);
    }

    /**
     * The new position multiplier is calculated as follows:
     * inflationPercentage = (newSupply - oldSupply) / newSupply
     * newMultiplier = (1 - inflationPercentage) * positionMultiplier
     */
    function _getIssuePositionMultiplier(
        ActionInfo memory _issueInfo
    )
        internal
        view
        returns (uint256, int256)
    {
        // Calculate inflation and new position multiplier. Note: Round inflation up in order to round position multiplier down
        uint256 newTotalSupply = _issueInfo.fundTokenQuantity.add(_issueInfo.previousFundTokenSupply);
        int256 newPositionMultiplier = positionMultiplier().mul(_issueInfo.previousFundTokenSupply.toInt256()).div(newTotalSupply.toInt256());

        return (newTotalSupply, newPositionMultiplier);
    }

    /**
     * Calculate deflation and new position multiplier. Note: Round deflation down in order to round position multiplier down
     *
     * The new position multiplier is calculated as follows:
     * deflationPercentage = (oldSupply - newSupply) / newSupply
     * newMultiplier = (1 + deflationPercentage) * positionMultiplier
     */
    function _getRedeemPositionMultiplier(
        uint256 _fundTokenQuantity,
        ActionInfo memory _redeemInfo
    )
        internal
        view
        returns (uint256, int256)
    {
        uint256 newTotalSupply = _redeemInfo.previousFundTokenSupply.sub(_fundTokenQuantity);
        int256 newPositionMultiplier = positionMultiplier()
            .mul(_redeemInfo.previousFundTokenSupply.toInt256())
            .div(newTotalSupply.toInt256());

        return (newTotalSupply, newPositionMultiplier);
    }

    /**
     * The new position reserve asset unit is calculated as follows:
     * totalReserve = (oldUnit * oldFundTokenSupply) + reserveQuantity
     * newUnit = totalReserve / newFundTokenSupply
     */
    function _getIssuePositionUnit(
        address _reserveAsset,
        ActionInfo memory _issueInfo
    )
        internal
        view
        returns (uint256)
    {
        uint256 existingUnit = getPositionRealUnit(_reserveAsset).toUint256();
        uint256 totalReserve = existingUnit
            .preciseMul(_issueInfo.previousFundTokenSupply)
            .add(_issueInfo.netFlowQuantity);

        return totalReserve.preciseDiv(_issueInfo.newFundTokenSupply);
    }

    /**
     * The new position reserve asset unit is calculated as follows:
     * totalReserve = (oldUnit * oldFundTokenSupply) - reserveQuantityToSendOut
     * newUnit = totalReserve / newFundTokenSupply
     */
    function _getRedeemPositionUnit(
        address _reserveAsset,
        ActionInfo memory _redeemInfo
    )
        internal
        view
        returns (uint256)
    {
        uint256 existingUnit = getPositionRealUnit(_reserveAsset).toUint256();
        uint256 totalExistingUnits = existingUnit.preciseMul(_redeemInfo.previousFundTokenSupply);

        uint256 outflow = _redeemInfo.netFlowQuantity.add(_redeemInfo.protocolFees).add(_redeemInfo.managerFee);

        // Require withdrawable quantity is greater than existing collateral
        require(totalExistingUnits >= outflow, "Must be greater than total available collateral");

        return totalExistingUnits.sub(outflow).preciseDiv(_redeemInfo.newFundTokenSupply);
    }


    /**
     * If a pre-issue hook has been configured, call the external-protocol contract. Pre-issue hook logic
     * can contain arbitrary logic including validations, external function calls, etc.
     */
    function _callPreIssueHooks(
        uint256 _reserveAssetQuantity,
        address _caller,
        address _to
    )
        internal
    {
        if (address(managerIssuanceHook) != address(0)) {
            managerIssuanceHook.invokePreIssueHook(address(this), reserveAsset, _reserveAssetQuantity, _caller, _to);
        }
    }

    /**
     * If a pre-redeem hook has been configured, call the external-protocol contract.
     */
    function _callPreRedeemHooks(uint256 _fundTokenQuantity, address _caller, address _to) internal {
        if (address(managerRedemptionHook) != address(0)) {
            managerRedemptionHook.invokePreRedeemHook(address(this), _fundTokenQuantity, _caller, _to);
        }
    }

}
