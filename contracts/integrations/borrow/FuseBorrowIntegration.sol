

pragma solidity >=0.7.0 <0.9.0;

import {IComptroller} from '../../interfaces/external/compound/IComptroller.sol';
import {ICToken} from '../../interfaces/external/compound/ICToken.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

import {CompoundBorrowIntegration} from './CompoundBorrowIntegration.sol';

/**
 * @title FuseBorrowIntegration
 * @author Babylon Finance
 *
 * Class that houses fuse borrowing logic.
 */
contract FuseBorrowIntegration is CompoundBorrowIntegration {
    /* ============ State Variables ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller             Address of the controller
     * @param _maxCollateralFactor    Max collateral factor allowed
     * @param _comptroller            Address of the fuse pool comptroller
     */
    constructor(
        IBabController _controller,
        uint256 _maxCollateralFactor,
        IComptroller _comptroller
    ) CompoundBorrowIntegration('fuseborrow', _controller, _maxCollateralFactor, _comptroller) {}
}
