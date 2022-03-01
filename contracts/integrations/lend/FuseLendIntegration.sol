

pragma solidity >=0.7.0 <0.9.0;

import {IComptroller} from '../../interfaces/external/compound/IComptroller.sol';
import {IRewardsDistributor} from '../../interfaces/external/compound/IRewardsDistributor.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

import {CompoundLendIntegration} from './CompoundLendIntegration.sol';

/**
 * @title FuseLendIntegration
 * @author Babylon Finance
 *
 * Class that houses Fuse lending logic.
 */
contract FuseLendIntegration is CompoundLendIntegration {
    /* ============ State Variables ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller             Address of the controller
     * @param _comptroller            Address of the fuse pool comptroller
     */
    constructor(IBabController _controller, IComptroller _comptroller)
        CompoundLendIntegration('fuselend', _controller, _comptroller)
    {}

    /* ============ Internal Functions ============ */

    function _getRewardToken() internal view override returns (address) {
        address[] memory rewards = IComptroller(comptroller).getRewardsDistributors();
        if (rewards.length > 0) {
            return IRewardsDistributor(rewards[0]).rewardToken();
        }
        return address(0);
    }

    function _getRewardsAccrued(address _strategy) internal view override returns (uint256) {
        address[] memory rewards = IComptroller(comptroller).getRewardsDistributors();
        if (rewards.length > 0) {
            return IRewardsDistributor(rewards[0]).compAccrued(_strategy);
        }
        return 0;
    }

    function _claimRewardsCallData(address _strategy)
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address[] memory rewards = IComptroller(comptroller).getRewardsDistributors();
        if (rewards.length > 0) {
            return (rewards[0], 0, abi.encodeWithSignature('claimRewards(address)', _strategy));
        }
        return (address(0), 0, bytes(''));
    }
}
