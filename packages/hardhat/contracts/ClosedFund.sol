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
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {PreciseUnitMath} from "./lib/PreciseUnitMath.sol";
import {AddressArrayUtils} from "./lib/AddressArrayUtils.sol";
import {IWETH} from "./interfaces/external/weth/IWETH.sol";
import {IFolioController} from "./interfaces/IFolioController.sol";
import {IFundValuer} from "./interfaces/IFundValuer.sol";
import {IFundIssuanceHook} from "./interfaces/IFundIssuanceHook.sol";
import {BaseFund} from "./BaseFund.sol";

/**
 * @title ClosedFund
 * @author DFolio
 *
 * ClosedFund holds the logic to deposit, witthdraw and track contributions and fees.
 */
contract ClosedFund is BaseFund, ReentrancyGuard {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Address for address;
    using AddressArrayUtils for address[];

    /* ============ Events ============ */
    event FundTokenDeposited(
        address indexed _to,
        address _hookContract,
        uint256 fundTokenQuantity,
        uint256 managerFees,
        uint256 protocolFees
    );
    event FundTokenwithdrawed(
        address indexed _from,
        address indexed _to,
        address _hookContract,
        uint256 fundTokenQuantity,
        uint256 managerFees,
        uint256 protocolFees
    );

    event PremiumEdited(uint256 amount);
    event ManagerFeeEdited(uint256 amount, string kind);
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
    uint256 constant initialBuyRate = 1000000000000; // Initial buy rate for the manager

    struct ActionInfo {
        uint256 preFeeReserveQuantity; // Reserve value before fees; During issuance, represents raw quantity
        // During withdrawal, represents post-premium value
        uint256 protocolFees; // Total protocol fees (direct + manager revenue share)
        uint256 managerFee; // Total manager fee paid in reserve asset
        uint256 netFlowQuantity; // When issuing, quantity of reserve asset sent to Fund
        // When withdrawaling, quantity of reserve asset sent to withdrawaler
        uint256 fundTokenQuantity; // When issuing, quantity of Fund tokens minted to mintee
        // When withdrawaling, quantity of Fund tokens withdrawaled
        uint256 previousFundTokenSupply; // Fund token supply prior to deposit/withdrawal action
        uint256 newFundTokenSupply; // Fund token supply after deposit/withdrawal action
        int256 newPositionMultiplier; // Fund token position multiplier after deposit/withdrawal
        uint256 newReservePositionUnit; // Fund token reserve asset position unit after deposit/withdrawal
    }

    address managerDepositHook; // Deposit hook configurations
    address managerWithdrawalHook; // Withdrawal hook configurations

    uint256 managerDepositFee; // % of the deposit denominated in the reserve asset
    uint256 managerWithdrawalFee; // % of the withdrawal denominated in the reserve asset,  charged in withdrawal
    uint256 managerPerformanceFee; // % of the profits denominated in the reserve asset, charged in withdrawal
    uint256 premiumPercentage; // Premium percentage (0.01% = 1e14, 1% = 1e16). This premium is a buffer around oracle
    // prices paid by user to the Fund Token, which prevents arbitrage and oracle front running

    // List of contributors
    struct Contributor {
        uint256 totalDeposit; //wei
        uint256 tokensReceived;
        uint256 timestamp;
    } // TODO: may need to override transfer of tokens or disable transfer if we care to keep this in sync

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
     * All parameter validations are on the FolioController contract. Validations are performed already on the
     * FolioController. Initiates the positionMultiplier as 1e18 (no adjustments).
     *
     * @param _integrations           List of integrations to enable. All integrations must be approved by the Controller
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     * @param _reserveAsset           Address of the reserve asset ERC20
     * @param _manager                Address of the manager
     * @param _managerFeeRecipient    Address where the manager will receive the fees
     * @param _name                   Name of the Fund
     * @param _symbol                 Symbol of the Fund
     * @param _minContribution        Min contribution to the fund
     */

    constructor(
        address[] memory _integrations,
        address _weth,
        address _reserveAsset,
        address _controller,
        address _manager,
        address _managerFeeRecipient,
        string memory _name,
        string memory _symbol,
        uint256 _minContribution
    )
        BaseFund(
            _integrations,
            _weth,
            _reserveAsset,
            _controller,
            _manager,
            _managerFeeRecipient,
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
     * @param _managerDepositFee              Manager deposit fee
     * @param _managerWithdrawalFee           Manager withdrawal fee
     * @param _managerPerformanceFee          Manager performance fee
     * @param _premiumPercentage              Premium percentage to avoid arbitrage
     * @param _minFundTokenSupply             Min fund token supply
     * @param _managerDepositHook             Deposit hook (if any)
     * @param _managerWithdrawalHook          Withdrawal hook (if any)
     */
    function initialize(
        uint256 _managerDepositFee,
        uint256 _managerWithdrawalFee,
        uint256 _managerPerformanceFee,
        uint256 _premiumPercentage,
        uint256 _minFundTokenSupply,
        address _managerDepositHook,
        address _managerWithdrawalHook
    ) external onlyManager onlyInactive {
        IFolioController ifcontroller = IFolioController(controller);
        require(
            _managerDepositFee <= ifcontroller.getMaxManagerDepositFee(),
            "Manager deposit fee must be less than max"
        );
        require(
            _managerWithdrawalFee <= ifcontroller.getMaxManagerWithdrawalFee(),
            "Manager withdrawal fee must be less than max"
        );
        require(
            _managerPerformanceFee <=
                ifcontroller.getMaxManagerPerformanceFee(),
            "Manager performance fee must be less than max"
        );
        require(
            _premiumPercentage <= ifcontroller.getMaxFundPremiumPercentage(),
            "Premium must be less than max"
        );
        require(
            _minFundTokenSupply > 0,
            "Min Fund token supply must be greater than 0"
        );
        require(totalSupply() > 0, "The fund must receive an initial deposit by the manager");

        managerDepositFee = _managerDepositFee;
        minFundTokenSupply = _minFundTokenSupply;
        managerWithdrawalFee = _managerWithdrawalFee;
        managerPerformanceFee = _managerPerformanceFee;
        premiumPercentage = _premiumPercentage;
        managerDepositHook = _managerDepositHook;
        managerWithdrawalHook = _managerWithdrawalHook;
        active = true;
    }

    /**
     * Manager sets the initial deposit that kickstarts the supply and allows to set the fund to active
     *
     */
    function initialManagerDeposit() external onlyManager payable nonReentrant {
      require(
          msg.value >= minContribution,
          "Send at least 1000000000000 wei"
      );
      // Always wrap to WETH
      IWETH(weth).deposit{value: msg.value}();

      // TODO: Trade to reserve asset if different than WETH
      uint256 initialTokens = msg.value.div(initialBuyRate);
      _mint(manager, initialTokens);
      _udpateContributorInfo(initialTokens);

      _calculateAndEditPosition(
        weth,
        msg.value
      );
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
    ) external payable nonReentrant onlyActive {
        require(
            msg.value >= minContribution,
            "Send at least 1000000000000 wei"
        );

        uint256 baseUnits = 10 ** 18;

        // Always wrap to WETH
        IWETH(weth).deposit{value: msg.value}();

        if (reserveAsset != weth) {
            // TODO: trade from weth into reserve asset
        }

        _validateReserveAsset(reserveAsset, _reserveAssetQuantity);

        _callPreDepositHooks(_reserveAssetQuantity, msg.sender, _to);

        ActionInfo memory depositInfo =
            _createIssuanceInfo(reserveAsset, _reserveAssetQuantity);

        _validateIssuanceInfo(_minFundTokenReceiveQuantity, depositInfo);

        _transferCollateralAndHandleFees(reserveAsset, depositInfo);

        _udpateContributorInfo(depositInfo.fundTokenQuantity);

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
    ) external nonReentrant onlyContributor(msg.sender) {
        require(
            _fundTokenQuantity <= IERC20(address(this)).balanceOf(msg.sender),
            "Withdrawal amount must be less than or equal to deposited amount"
        );

        _validateReserveAsset(reserveAsset, _fundTokenQuantity);

        _callPreWithdrawalHooks(_fundTokenQuantity, msg.sender, _to);

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
    function editPremium(uint256 _premiumPercentage) external onlyManager {
        require(
            _premiumPercentage <=
                IFolioController(controller).getMaxFundPremiumPercentage(),
            "Premium must be less than maximum allowed"
        );

        premiumPercentage = _premiumPercentage;

        emit PremiumEdited(_premiumPercentage);
    }

    /**
     * Fund MANAGER ONLY. Edit manager deposit fee
     *
     * @param _managerDepositFee         Manager deposit fee percentage in 10e16 (e.g. 10e16 = 1%)
     */
    function editManagerDepositFee(uint256 _managerDepositFee)
        external
        onlyManager
        onlyInactive
    {
        require(
            _managerDepositFee <=
                IFolioController(controller).getMaxManagerDepositFee(),
            "Manager fee must be less than maximum allowed"
        );
        managerDepositFee = _managerDepositFee;
        emit ManagerFeeEdited(_managerDepositFee, "Manager Deposit Fee");
    }

    /**
     * Fund MANAGER ONLY. Edit manager deposit fee
     *
     * @param _managerWithdrawalFee         Manager withdrawal fee percentage in 10e16 (e.g. 10e16 = 1%)
     */
    function editManagerWithdrawalFee(
        uint256 _managerWithdrawalFee
    ) external onlyManager onlyInactive {
        require(
            _managerWithdrawalFee <=
                IFolioController(controller).getMaxManagerWithdrawalFee(),
            "Manager fee must be less than maximum allowed"
        );
        managerWithdrawalFee = _managerWithdrawalFee;
        emit ManagerFeeEdited(_managerWithdrawalFee, "Manager Withdrawal Fee");
    }

    /**
     * Fund MANAGER ONLY. Edit manager deposit fee
     *
     * @param _managerPerformanceFee         Manager performance fee percentage in 10e16 (e.g. 10e16 = 1%)
     */
    function editManagerPerformanceFee(
        uint256 _managerPerformanceFee
    ) external onlyManager onlyInactive {
        require(
            _managerPerformanceFee <=
                IFolioController(controller).getMaxManagerPerformanceFee(),
            "Manager fee must be less than maximum allowed"
        );
        managerPerformanceFee = _managerPerformanceFee;
        emit ManagerFeeEdited(
            _managerPerformanceFee,
            "Manager Performance Fee"
        );
    }

    /* ============ External Getter Functions ============ */

    function getPremiumPercentage() external view returns (uint256) {
        return premiumPercentage;
    }

    function getDepositManagerFee() external view returns (uint256) {
        return managerDepositFee;
    }

    function getWithdrawalManagerFee() external view returns (uint256) {
        return managerWithdrawalFee;
    }

    function getManagerPerformanceFee() external view returns (uint256) {
        return managerPerformanceFee;
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
        (, , uint256 netReserveFlow) = _getFees(_reserveAssetQuantity, true);

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

        (, , uint256 netReserveFlows) = _getFees(preFeeReserveQuantity, false);

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
            IFolioController(controller).isValidReserveAsset(_reserveAsset) &&
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
            !IFolioController(controller).isValidReserveAsset(_reserveAsset) ||
            setTotalSupply < minFundTokenSupply.add(_fundTokenQuantity)
        ) {
            return false;
        } else {
            uint256 totalWithdrawalValue =
                _getWithdrawalReserveQuantity(
                    _reserveAsset,
                    _fundTokenQuantity
                );

            (, , uint256 expectedWithdrawalQuantity) =
                _getFees(totalWithdrawalValue, false);

            uint256 existingUnit =
                getPositionRealUnit(_reserveAsset).toUint256();

            return
                existingUnit.preciseMul(setTotalSupply) >=
                expectedWithdrawalQuantity;
        }
    }

    receive() external payable {} // solium-disable-line quotes

    /* ============ Internal Functions ============ */

    function _validateReserveAsset(address _reserveAsset, uint256 _quantity)
        internal
        view
    {
        require(_quantity > 0, "Quantity must be > 0");
        require(
            IFolioController(controller).isValidReserveAsset(_reserveAsset),
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
        uint256 _fundTokenQuantity,
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
            depositInfo.managerFee,
            depositInfo.netFlowQuantity
        ) = _getFees(depositInfo.preFeeReserveQuantity, true);

        depositInfo.fundTokenQuantity = _getFundTokenMintQuantity(
            _reserveAsset,
            depositInfo.netFlowQuantity,
            depositInfo.previousFundTokenSupply
        );

        (
            depositInfo.newFundTokenSupply,
            depositInfo.newPositionMultiplier
        ) = _getDepositPositionMultiplier(depositInfo);

        depositInfo.newReservePositionUnit = _getDepositPositionUnit(
            _reserveAsset,
            depositInfo
        );

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
            withdrawalInfo.managerFee,
            withdrawalInfo.netFlowQuantity
        ) = _getFees(withdrawalInfo.preFeeReserveQuantity, false);

        withdrawalInfo.previousFundTokenSupply = totalSupply();

        (
            withdrawalInfo.newFundTokenSupply,
            withdrawalInfo.newPositionMultiplier
        ) = _getWithdrawalPositionMultiplier(
            _fundTokenQuantity,
            withdrawalInfo
        );

        withdrawalInfo.newReservePositionUnit = _getWithdrawalPositionUnit(
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
                IFolioController(controller).getFeeRecipient(),
                _depositInfo.protocolFees
            );
        }
        if (_depositInfo.managerFee > 0) {
            IERC20(_reserveAsset).transferFrom(
                msg.sender,
                managerFeeRecipient,
                _depositInfo.managerFee
            );
        }
    }

    function _handleDepositStateUpdates(
        address _reserveAsset,
        address _to,
        ActionInfo memory _depositInfo
    ) internal {
        _editPositionMultiplier(_depositInfo.newPositionMultiplier);

        editPosition(
            _reserveAsset,
            _depositInfo.newReservePositionUnit,
            address(0)
        );

        _mint(_to, _depositInfo.fundTokenQuantity);

        emit FundTokenDeposited(
            _to,
            managerDepositHook,
            _depositInfo.fundTokenQuantity,
            _depositInfo.managerFee,
            _depositInfo.protocolFees
        );
    }

    function _handleWithdrawalStateUpdates(
        address _reserveAsset,
        address _to,
        ActionInfo memory _withdrawalInfo
    ) internal {
        _editPositionMultiplier(_withdrawalInfo.newPositionMultiplier);

        editPosition(
            _reserveAsset,
            _withdrawalInfo.newReservePositionUnit,
            address(0)
        );

        emit FundTokenwithdrawed(
            msg.sender,
            _to,
            managerWithdrawalHook,
            _withdrawalInfo.fundTokenQuantity,
            _withdrawalInfo.managerFee,
            _withdrawalInfo.protocolFees
        );
    }

    function _handleRedemptionFees(
        address _reserveAsset,
        ActionInfo memory _withdrawalInfo
    ) internal {
        // Instruct the Fund to transfer protocol fee to fee recipient if there is a fee
        payProtocolFeeFromFund(_reserveAsset, _withdrawalInfo.protocolFees);

        // Instruct the Fund to transfer manager fee to manager fee recipient if there is a fee
        if (_withdrawalInfo.managerFee > 0) {
            payManagerFeeFromFund(_reserveAsset, _withdrawalInfo.managerFee);
        }
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
     * ManagerFee = (manager fee % - % to protocol) * reserveAssetQuantity
     * Protocol Fee = (% manager fee share + direct fee %) * reserveAssetQuantity
     *
     * @param _reserveAssetQuantity         Quantity of reserve asset to calculate fees from
     * @param _isDeposit ad
     *
     * @return  uint256                     Fees paid to the protocol in reserve asset
     * @return  uint256                     Fees paid to the manager in reserve asset
     * @return  uint256                     Net reserve to user net of fees
     */
    function _getFees(uint256 _reserveAssetQuantity, bool _isDeposit)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // Get protocol fee percentages
        uint256 protocolFeePercentage =
            _isDeposit
                ? IFolioController(controller).getProtocolDepositFundTokenFee()
                : IFolioController(controller)
                    .getProtocolWithdrawalFundTokenFee();
        uint256 managerFeePercentage =
            _isDeposit ? managerDepositFee : managerWithdrawalFee;

        // Calculate total notional fees
        uint256 protocolFees =
            protocolFeePercentage.preciseMul(_reserveAssetQuantity);
        uint256 managerFee =
            managerFeePercentage.preciseMul(_reserveAssetQuantity);

        uint256 netReserveFlow =
            _reserveAssetQuantity.sub(protocolFees).sub(managerFee);

        return (protocolFees, managerFee, netReserveFlow);
    }

    function _getFundTokenMintQuantity(
        address _reserveAsset,
        uint256 _netReserveFlows, // Value of reserve asset net of fees
        uint256 _fundTokenTotalSupply
    ) internal view returns (uint256) {
        uint256 premiumPercentageToApply = _getDepositPremium();
        uint256 premiumValue =
            _netReserveFlows.preciseMul(premiumPercentageToApply);

        // Get valuation of the Fund with the quote asset as the reserve asset. Returns value in precise units (1e18)
        // Reverts if price is not found
        uint256 fundValuation = IFundValuer(IFolioController(controller).getFundValuer()).calculateFundValuation(address(this), _reserveAsset);

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
            IFundValuer(IFolioController(controller).getFundValuer())
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
     * The new position multiplier is calculated as follows:
     * inflationPercentage = (newSupply - oldSupply) / newSupply
     * newMultiplier = (1 - inflationPercentage) * positionMultiplier
     */
    function _getDepositPositionMultiplier(ActionInfo memory _depositInfo)
        internal
        view
        returns (uint256, int256)
    {
        // Calculate inflation and new position multiplier. Note: Round inflation up in order to round position multiplier down
        uint256 newTotalSupply =
            _depositInfo.fundTokenQuantity.add(
                _depositInfo.previousFundTokenSupply
            );
        int256 newPositionMultiplier =
            positionMultiplier
                .mul(_depositInfo.previousFundTokenSupply.toInt256())
                .div(newTotalSupply.toInt256());

        return (newTotalSupply, newPositionMultiplier);
    }

    /**
     * Calculate deflation and new position multiplier. Note: Round deflation down in order to round position multiplier down
     *
     * The new position multiplier is calculated as follows:
     * deflationPercentage = (oldSupply - newSupply) / newSupply
     * newMultiplier = (1 + deflationPercentage) * positionMultiplier
     */
    function _getWithdrawalPositionMultiplier(
        uint256 _fundTokenQuantity,
        ActionInfo memory _withdrawalInfo
    ) internal view returns (uint256, int256) {
        uint256 newTotalSupply =
            _withdrawalInfo.previousFundTokenSupply.sub(_fundTokenQuantity);

        int256 newPositionMultiplier =
            positionMultiplier
                .mul(_withdrawalInfo.previousFundTokenSupply.toInt256())
                .div(newTotalSupply.toInt256());

        return (newTotalSupply, newPositionMultiplier);
    }

    /**
     * The new position reserve asset unit is calculated as follows:
     * totalReserve = (oldUnit * oldFundTokenSupply) + reserveQuantity
     * newUnit = totalReserve / newFundTokenSupply
     */
    function _getDepositPositionUnit(
        address _reserveAsset,
        ActionInfo memory _depositInfo
    ) internal view returns (uint256) {
        uint256 existingUnit = getPositionRealUnit(_reserveAsset).toUint256();
        uint256 totalReserve =
            existingUnit.preciseMul(_depositInfo.previousFundTokenSupply).add(
                _depositInfo.netFlowQuantity
            );

        return totalReserve.preciseDiv(_depositInfo.newFundTokenSupply);
    }

    /**
     * The new position reserve asset unit is calculated as follows:
     * totalReserve = (oldUnit * oldFundTokenSupply) - reserveQuantityToSendOut
     * newUnit = totalReserve / newFundTokenSupply
     */
    function _getWithdrawalPositionUnit(
        address _reserveAsset,
        ActionInfo memory _withdrawalInfo
    ) internal view returns (uint256) {
        uint256 existingUnit = getPositionRealUnit(_reserveAsset).toUint256();
        uint256 totalExistingUnits =
            existingUnit.preciseMul(_withdrawalInfo.previousFundTokenSupply);

        uint256 outflow =
            _withdrawalInfo
                .netFlowQuantity
                .add(_withdrawalInfo.protocolFees)
                .add(_withdrawalInfo.managerFee);

        // Require withdrawable quantity is greater than existing collateral
        require(
            totalExistingUnits >= outflow,
            "Must be greater than total available collateral"
        );

        return
            totalExistingUnits.sub(outflow).preciseDiv(
                _withdrawalInfo.newFundTokenSupply
            );
    }

    /**
     * Updates the contributor info in the array
     */
    function _udpateContributorInfo(uint256 tokensReceived) internal {
      Contributor storage contributor = contributors[msg.sender];
      // If new contributor, create one, increment count, and set the current TS
      if (contributor.totalDeposit == 0) {
          totalContributors = totalContributors.add(1);
          contributor.timestamp = block.timestamp;
      }

      totalFunds = totalFunds.add(msg.value);
      totalFundsDeposited = totalFundsDeposited.add(msg.value);
      contributor.totalDeposit = contributor.totalDeposit.add(msg.value);
      contributor.tokensReceived = contributor.tokensReceived.add(
          tokensReceived
      );

      emit ContributionLog(
          msg.sender,
          msg.value,
          tokensReceived,
          block.timestamp
      );
    }

    /**
     * If a pre-deposit hook has been configured, call the external-protocol contract. Pre-deposit hook logic
     * can contain arbitrary logic including validations, external function calls, etc.
     */
    function _callPreDepositHooks(
        uint256 _reserveAssetQuantity,
        address _caller,
        address _to
    ) internal {
        if (managerDepositHook != address(0)) {
            IFundIssuanceHook(managerDepositHook).invokePreDepositHook(
                reserveAsset,
                _reserveAssetQuantity,
                _caller,
                _to
            );
        }
    }

    /**
     * If a pre-withdrawal hook has been configured, call the external-protocol contract.
     */
    function _callPreWithdrawalHooks(
        uint256 _fundTokenQuantity,
        address _caller,
        address _to
    ) internal {
        if (managerWithdrawalHook != address(0)) {
            IFundIssuanceHook(managerWithdrawalHook).invokePreWithdrawalHook(
                _fundTokenQuantity,
                _caller,
                _to
            );
        }
    }

    function _validateOnlyContributor(address _caller) internal view {
        require(
            IERC20(address(this)).balanceOf(_caller) > 0,
            "Only someone with the fund token can withdraw"
        );
    }
}
