/*
    Copyright 2021 Babylon Finance

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
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {BaseIntegration} from '../BaseIntegration.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';

/**
 * @title BorrowIntetration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with lending protocols
 */
abstract contract BorrowIntegration is BaseIntegration, ReentrancyGuard {
    using SafeMath for uint256;

    /* ============ Struct ============ */

    struct DebtInfo {
        IStrategy strategy; // Idea address
        IGarden garden; // Garden address
        address asset; // Asset involved in the operation
        uint256 amount; // Amount involved in the operation
        uint8 borrowOp; // Borrow operation type
    }

    uint8 constant BORROW_OPERATION_BORROW = 0;
    uint8 constant BORROW_OPERATION_REPAY = 1;

    /* ============ Events ============ */

    event AmountBorrowed(
        IStrategy indexed strategy,
        IGarden indexed garden,
        address asset,
        uint256 amount,
        uint256 protocolFee
    );

    event AmountRepaid(
        IStrategy indexed strategy,
        IGarden indexed garden,
        address asset,
        uint256 amount,
        uint256 protocolFee
    );

    /* ============ State Variables ============ */
    uint256 public maxCollateralFactor;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     * @param _maxCollateralFactor    Max collateral factor allowed
     */
    constructor(
        string memory _name,
        address _weth,
        address _controller,
        uint256 _maxCollateralFactor
    ) BaseIntegration(_name, _weth, _controller) {
        maxCollateralFactor = _maxCollateralFactor;
    }

    /* ============ External Functions ============ */
    // Governance function
    function updateMaxCollateralFactor(uint256 _newMaxCollateralFactor) external onlyProtocol {
        maxCollateralFactor = _newMaxCollateralFactor;
    }

    /**
     * Borrows an asset
     * @param asset The asset to be borrowed
     * @param amount The amount to borrow
     */
    function borrow(address asset, uint256 amount) external nonReentrant onlyIdea {
        amount = normalizeAmountWithDecimals(asset, amount);

        DebtInfo memory debtInfo = _createDebtInfo(asset, amount, BORROW_OPERATION_BORROW);

        _validatePreBorrow(debtInfo);

        // Pre actions (enter markets for compound)
        (address targetAddressP, uint256 callValueP, bytes memory methodDataP) =
            _getPreActionCallData(asset, amount, BORROW_OPERATION_BORROW);

        if (targetAddressP != address(0)) {
            // Invoke protocol specific call
            debtInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }

        (address targetAddress, uint256 callValue, bytes memory methodData) = _getBorrowCalldata(asset, amount);
        // Invoke protocol specific call
        debtInfo.strategy.invokeFromIntegration(targetAddress, callValue, methodData);
        // Validate borrow
        _validatePostBorrow(debtInfo);

        // Protocol Fee
        uint256 protocolFee = _accrueProtocolFee(address(debtInfo.strategy), asset, amount);

        _updateStrategyPosition(msg.sender, asset, int256(-amount), 3);

        emit AmountBorrowed(debtInfo.strategy, debtInfo.garden, asset, amount, protocolFee);
    }

    /**
     * Repays a borrowed asset debt
     * @param asset The asset to be repaid
     * @param amount The amount to repay
     */
    function repay(address asset, uint256 amount) external nonReentrant onlyIdea {
        amount = normalizeAmountWithDecimals(asset, amount);

        DebtInfo memory debtInfo = _createDebtInfo(asset, amount, BORROW_OPERATION_REPAY);

        _validatePreRepay(debtInfo);

        // Pre actions (enter markets for compound)
        (address targetAddressP, uint256 callValueP, bytes memory methodDataP) =
            _getPreActionCallData(asset, amount, BORROW_OPERATION_REPAY);

        if (targetAddressP != address(0)) {
            // Invoke protocol specific call
            debtInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }
        // Approves the repayment contract to take the tokens
        debtInfo.strategy.invokeApprove(_getSpender(asset), asset, amount);

        (address targetAddress, uint256 callValue, bytes memory methodData) = _getRepayCalldata(asset, amount);

        // Invoke protocol specific call
        debtInfo.strategy.invokeFromIntegration(targetAddress, callValue, methodData);
        // Validate borrow
        _validatePostRepay(debtInfo);
        // Protocol Fee
        uint256 protocolFee = _accrueProtocolFee(address(debtInfo.strategy), asset, amount);
        _updateStrategyPosition(msg.sender, asset, 0, 0);

        emit AmountRepaid(debtInfo.strategy, debtInfo.garden, asset, amount, protocolFee);
    }

    /* ============ Internal Functions ============ */

    /**
     * Create and return DebtInfo struct
     *
     * @param _asset               The asset involved in the op
     * @param _amount              The amount involved in the op
     * @param _borrowOp            Type of borrow operation
     * return DebtInfo             Struct containing data for the debt position
     */
    function _createDebtInfo(
        address _asset,
        uint256 _amount,
        uint8 _borrowOp
    ) internal view returns (DebtInfo memory) {
        DebtInfo memory debtInfo;
        debtInfo.strategy = IStrategy(msg.sender);
        debtInfo.garden = IGarden(debtInfo.strategy.garden());
        debtInfo.asset = _asset;
        debtInfo.amount = _amount;
        debtInfo.borrowOp = _borrowOp;

        return debtInfo;
    }

    /**
     * Validate pre borrow.
     *
     * hparam _debtInfo               Struct containing debt information used in internal functions
     */
    function _validatePreBorrow(
        DebtInfo memory /* _debtInfo */
    ) internal view {
        // TODO: Check healthy collateral factor
        require(_getRemainingLiquidity() > 0, 'Not enough liquidity');
    }

    /**
     * Validate post borrow.
     *
     * @param _debtInfo               Struct containing debt information used in internal functions
     */
    function _validatePostBorrow(DebtInfo memory _debtInfo) internal view {
        require(
            IERC20(_debtInfo.asset).balanceOf(address(_debtInfo.strategy)) >= _debtInfo.amount,
            'Did not receive the borrowed asset'
        );
        require(_getRemainingLiquidity() > 0, 'Not enough liquidity');
    }

    /**
     * Validate pre repaid.
     *
     * @param _debtInfo               Struct containing debt information used in internal functions
     */
    function _validatePreRepay(DebtInfo memory _debtInfo) internal view {
        require(
            IERC20(_debtInfo.asset).balanceOf(address(_debtInfo.strategy)) >= _debtInfo.amount,
            'We do not have enough to repay debt'
        );
        require(_getBorrowBalance(_debtInfo.asset) > 0, 'No debt to repay');
    }

    /**
     * Validate post repaid.
     *
     * @param _debtInfo               Struct containing debt information used in internal functions
     */
    function _validatePostRepay(DebtInfo memory _debtInfo) internal view {
        // debt is paid
        require(_getBorrowBalance(_debtInfo.asset) == 0, 'No debt to repay');
    }

    /* ============ Virtual Functions ============ */

    /**
     * Return borrow token calldata
     *
     * hparam  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getBorrowCalldata(
        address, /* _asset */
        uint256 /* _amount */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        require(false, 'This needs to be overriden');
        return (address(0), 0, bytes(''));
    }

    /**
     * Return repay borrowed asset calldata
     *
     * hparam  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getRepayCalldata(
        address, /* _asset */
        uint256 /* _amount */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        require(false, 'This needs to be overriden');
        return (address(0), 0, bytes(''));
    }

    /**
     * Return pre action calldata
     *
     * hparam  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * hparam  _borrowOp                Type of Borrow op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address, /* _asset */
        uint256, /* _amount */
        uint256 /* _borrowOp */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        require(false, 'This needs to be overriden');
        return (address(0), 0, bytes(''));
    }

    /**
     * Get the amount of borrowed debt that needs to be repaid
     * hparam asset   The underlying asset
     *
     */
    function _getBorrowBalance(
        address /* asset */
    ) internal view virtual returns (uint256) {
        require(false, 'This method must be overriden');
        return 0;
    }

    /**
     * Get the amount of collateral supplied
     * hparam asset   The collateral asset
     *
     */
    function _getCollateralBalance(
        address /* asset */
    ) internal view virtual returns (uint256) {
        require(false, 'This method must be overriden');
        return 0;
    }

    /**
     * Get the remaining liquidity available to borrow
     *
     */
    function _getRemainingLiquidity() public view virtual returns (uint256) {
        require(false, 'This method must be overriden');
        return 0;
    }

    function _getCollateralAsset(
        address, /* _asset */
        uint8 /* _borrowOp */
    ) internal view virtual returns (address) {
        require(false, 'This method must be overriden');
        return address(0);
    }

    function _getSpender(
        address /* asset */
    ) internal view virtual returns (address) {
        require(false, 'This method must be overriden');
        return address(0);
    }
}
