// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {ECDSA} from '@openzeppelin/contracts/cryptography/ECDSA.sol';
import {ERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';

import {Errors, _require, _revert} from '../lib/BabylonErrors.sol';
import {AddressArrayUtils} from '../lib/AddressArrayUtils.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {Math} from '../lib/Math.sol';

import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IStrategyFactory} from '../interfaces/IStrategyFactory.sol';
import {IGardenValuer} from '../interfaces/IGardenValuer.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IGardenNFT} from '../interfaces/IGardenNFT.sol';
import {IMardukGate} from '../interfaces/IMardukGate.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IStrategyGarden} from '../interfaces/IGarden.sol';
import {IHeart} from '../interfaces/IHeart.sol';

import {VTableBeaconProxy} from '../proxy/VTableBeaconProxy.sol';
import {VTableBeacon} from '../proxy/VTableBeacon.sol';

import {BaseGardenModule} from './BaseGardenModule.sol';
import {ControllerLib} from '../lib/ControllerLib.sol';

/**
 * @title StrategyGardenModule
 *
 * Strategy related functions of the Garden contract
 */
contract StrategyGardenModule is BaseGardenModule, IStrategyGarden {
    using SafeCast for int256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for int256;
    using SafeDecimalMath for int256;

    using SafeCast for uint256;
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    using Address for address;
    using AddressArrayUtils for address[];

    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using ControllerLib for IBabController;

    /* ============ Events ============ */
    event AddStrategy(address indexed _strategy, string _name, uint256 _expectedReturn);

    /* ============ Constants ============ */
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Strategy cooldown period
    uint256 private constant MIN_COOLDOWN_PERIOD = 60 seconds;
    uint256 private constant MAX_COOLDOWN_PERIOD = 7 days;
    uint256 private constant MAX_TOTAL_STRATEGIES = 20; // Max number of strategies

    /* ============ Structs ============ */

    /* ============ State Variables ============ */

    /* ============ Modifiers ============ */

    function _onlyUnpaused() private view {
        // Do not execute if Globally or individually paused
        _require(!controller.isPaused(address(this)), Errors.ONLY_UNPAUSED);
    }

    /**
     * Throws if the sender is not an strategy of this garden
     */
    function _onlyStrategy() private view {
        _require(strategyMapping[msg.sender], Errors.ONLY_STRATEGY);
    }

    /* ============ Constructor ============ */

    /* ============ External Functions ============ */

    /**
     * @notice
     *  When strategy ends puts saves returns, rewards and marks strategy as
     *  finalized.
     *
     * @param _rewards        Amount of Reserve Asset to set aside forever
     * @param _returns        Profits or losses that the strategy received
     * @param _burningAmount  The amount of strategist stake to burn in case of
     *                        strategy losses.
     */
    function finalizeStrategy(
        uint256 _rewards,
        int256 _returns,
        uint256 _burningAmount
    ) external override nonReentrant {
        _onlyUnpaused();
        _onlyStrategy();

        // burn stategist stake
        address strategist = IStrategy(msg.sender).strategist();
        if (_burningAmount > 0) {
            if (_burningAmount >= balanceOf(strategist)) {
                // Avoid underflow condition
                _burningAmount = balanceOf(strategist);
            }
            _burn(strategist, _burningAmount);
        }
        uint256 stake = IStrategy(msg.sender).stake();
        uint256 lockedBalance = contributors[strategist].lockedBalance;
        contributors[strategist].lockedBalance = lockedBalance > stake ? lockedBalance.sub(stake) : 0;

        reserveAssetRewardsSetAside = reserveAssetRewardsSetAside.add(_rewards);

        // Mark strategy as finalized
        absoluteReturns = absoluteReturns.add(_returns);
        strategies = strategies.remove(msg.sender);
        finalizedStrategies.push(msg.sender);
        strategyMapping[msg.sender] = false;
        if (address(this) == address(IHeart(controller.heart()).heartGarden())) {
            // BABL Rewards are sent to the heart Garden during finalization, no claim option afterwards for users
            // _rewards (set aside) must also be zero in this case
            rewardsDistributor.sendBABLToContributor(address(this), IStrategy(msg.sender).strategyRewards());
        }
    }

    /**
     * @notice
     *   Pays gas costs back to the keeper from executing transactions
     *   including the past debt
     * @dev
     *   We assume that calling keeper functions should be less expensive than 2000 DAI.
     * @param _keeper  Keeper that executed the transaction
     * @param _fee     The fee paid to keeper to compensate the gas cost
     */
    function payKeeper(address payable _keeper, uint256 _fee) public override nonReentrant {
        _onlyUnpaused();
        _require(msg.sender == address(this) || strategyMapping[msg.sender], Errors.ONLY_STRATEGY);
        _require(controller.isValidKeeper(_keeper), Errors.ONLY_KEEPER);

        uint256 pricePerTokenUnitInDAI = IPriceOracle(controller.priceOracle()).getPrice(reserveAsset, DAI);
        uint256 feeInDAI =
            pricePerTokenUnitInDAI.preciseMul(_fee).mul(
                10**(uint256(18).sub(ERC20Upgradeable(reserveAsset).decimals()))
            );

        _require(feeInDAI <= 2000 * 1e18, Errors.FEE_TOO_HIGH);

        keeperDebt = keeperDebt.add(_fee);
        uint256 liquidReserve = _liquidReserve();
        // Pay Keeper in Reserve Asset
        if (keeperDebt > 0 && liquidReserve > 0) {
            uint256 toPay = liquidReserve > keeperDebt ? keeperDebt : liquidReserve;
            IERC20(reserveAsset).safeTransfer(_keeper, toPay);
            totalKeeperFees = totalKeeperFees.add(toPay);
            keeperDebt = keeperDebt.sub(toPay);
        }
    }

    /**
     * Creates a new strategy calling the factory and adds it to the array
     * @param _name                          Name of the strategy
     * @param _symbol                        Symbol of the strategy
     * @param _stratParams                   Num params for the strategy
     * @param _opTypes                      Type for every operation in the strategy
     * @param _opIntegrations               Integration to use for every operation
     * @param _opEncodedDatas               Param for every operation in the strategy
     */
    function addStrategy(
        string memory _name,
        string memory _symbol,
        uint256[] calldata _stratParams,
        uint8[] calldata _opTypes,
        address[] calldata _opIntegrations,
        bytes calldata _opEncodedDatas
    ) external override {
        _onlyUnpaused();
        _require(balanceOf(msg.sender) > 0, Errors.ONLY_CONTRIBUTOR);
        bool canCreateStrategy =
            publicStrategists ||
                IMardukGate(controller.mardukGate()).canAddStrategiesInAGarden(address(this), msg.sender);
        _require(canCreateStrategy, Errors.USER_CANNOT_ADD_STRATEGIES);
        _require(strategies.length < MAX_TOTAL_STRATEGIES, Errors.VALUE_TOO_HIGH);
        address strategy =
            IStrategyFactory(controller.strategyFactory()).createStrategy(
                _name,
                _symbol,
                msg.sender,
                address(this),
                _stratParams
            );
        strategyMapping[strategy] = true;
        totalStake = totalStake.add(_stratParams[1]);
        contributors[msg.sender].lockedBalance = contributors[msg.sender].lockedBalance.add(_stratParams[1]);
        strategies.push(strategy);
        IStrategy(strategy).setData(_opTypes, _opIntegrations, _opEncodedDatas);
        isGardenStrategy[strategy] = true;
        emit AddStrategy(strategy, _name, _stratParams[3]);
    }

    /**
     * Allocates garden capital to an strategy
     *
     * @param _capital        Amount of capital to allocate to the strategy
     */
    function allocateCapitalToStrategy(uint256 _capital) external override {
        _onlyStrategy();

        uint256 protocolMgmtFee = controller.protocolManagementFee().preciseMul(_capital);
        _require(_capital.add(protocolMgmtFee) <= _liquidReserve(), Errors.MIN_LIQUIDITY);

        // Take protocol mgmt fee to the heart
        IERC20(reserveAsset).safeTransfer(controller.heart(), protocolMgmtFee);

        // Send Capital to strategy
        IERC20(reserveAsset).safeTransfer(msg.sender, _capital);
    }

    /*
     * Remove an expire candidate from the strategy Array
     */
    function expireCandidateStrategy() external override {
        _onlyStrategy();
        strategies = strategies.remove(msg.sender);
        strategyMapping[msg.sender] = false;
        address strategist = IStrategy(msg.sender).strategist();
        uint256 stake = IStrategy(msg.sender).stake();
        uint256 lockedBalance = contributors[strategist].lockedBalance;
        contributors[strategist].lockedBalance = lockedBalance > stake ? lockedBalance.sub(stake) : 0;
    }

    function resetStrategistLock(address _strategist) external {
        _require(msg.sender == controller.EMERGENCY_OWNER(), Errors.ONLY_GOVERNANCE_OR_EMERGENCY);
        contributors[_strategist].lockedBalance = 0;
    }

    /**
     * PRIVILEGE FUNCTION to update Garden Strategy Rewards
     * To be used by Governance or Emergency only.
     *
     * @param _strategy   Address of the strategy to patch
     * @param _newTotalBABLAmount  The new BABL rewards
     * @param _newCapitalReturned  The new capital returned
     * @param _diffRewardsToSetAside  Diff of rewards to set aside
     * @param _addOrSubstractSetAside Whether to add or substract set aside rewards
     */
    function updateStrategyRewards(
        address _strategy,
        uint256 _newTotalBABLAmount,
        uint256 _newCapitalReturned,
        uint256 _diffRewardsToSetAside,
        bool _addOrSubstractSetAside
    ) external override {
        controller.onlyGovernanceOrEmergency();
        _require(isGardenStrategy[_strategy] && !strategyMapping[_strategy], Errors.STRATEGY_GARDEN_MISMATCH);
        uint256 oldRewards = IStrategy(_strategy).strategyRewards();
        address heartGarden = address(IHeart(controller.heart()).heartGarden());
        bool bablDiff = oldRewards != _newTotalBABLAmount;
        int256 profitDiff = int256(_newCapitalReturned).sub(int256(IStrategy(_strategy).capitalReturned()));
        // update absolute returns
        absoluteReturns = absoluteReturns.add(profitDiff);
        // update rewardsToSetAside
        // heart garden safety control (it should not setAside as it is auto-compounded)
        if (_diffRewardsToSetAside != 0) {
            reserveAssetRewardsSetAside = address(this) == heartGarden
                ? 0
                : (
                    _addOrSubstractSetAside
                        ? reserveAssetRewardsSetAside.add(_diffRewardsToSetAside)
                        : reserveAssetRewardsSetAside.sub(_diffRewardsToSetAside)
                );
        }
        if (profitDiff != 0 || bablDiff) {
            // Update strategy rewards if needed
            // save gas instead
            IStrategy(_strategy).updateStrategyRewards(_newTotalBABLAmount, _newCapitalReturned);
        }
        if (address(this) == heartGarden && bablDiff) {
            // Send BABL if needed to/from heart garden
            // Only for heart garden strategies
            if (oldRewards < _newTotalBABLAmount) {
                // Send difference if Heart Garden Strategy got less rewards previously
                rewardsDistributor.sendBABLToContributor(address(this), _newTotalBABLAmount.sub(oldRewards));
            } else {
                // Send back the difference if Heart Garden Strategy got more rewards previously
                IERC20 BABL = IERC20(address(rewardsDistributor.babltoken()));
                BABL.safeTransfer(address(rewardsDistributor), oldRewards.sub(_newTotalBABLAmount));
            }
        }
    }

    /* ============ External Getter Functions ============ */

    /* ============ Internal Functions ============ */

    /**
     * Gets liquid reserve available for to Garden.
     */
    function _liquidReserve() private view returns (uint256) {
        uint256 reserve = IERC20(reserveAsset).balanceOf(address(this)).sub(reserveAssetRewardsSetAside);
        return reserve > keeperDebt ? reserve.sub(keeperDebt) : 0;
    }
}
