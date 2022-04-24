// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IBabController} from '../interfaces/IBabController.sol';
import {IConvexRegistry} from '../interfaces/IConvexRegistry.sol';
import {IBooster} from '../interfaces/external/convex/IBooster.sol';
import {ControllerLib} from '../lib/ControllerLib.sol';

/**
 * @title ConvexRegistry
 * @author Babylon Finance Protocol
 *
 * Abstraction for all the different convex pools
 */
contract ConvexRegistry is IConvexRegistry {
    using ControllerLib for IBabController;

    /* ============ Constants ============ */

    IBabController public immutable controller;
    IBooster public constant override booster = IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    /* ============ State Variables ============ */

    mapping(address => uint256) private cacheConvexTokenToPid;
    uint256 private elementsCached = 0;

    // Mapping of valid Vaults
    mapping(address => bool) public override convexPools;
    address[] public convexList;

    /* ============ Modifiers ============ */

    /* ============ Constructor ============ */

    constructor(IBabController _controller) {
        require(address(_controller) != address(0), 'Controller is not valid');
        controller = _controller;
        updateCache();
    }

    /* ============ External Functions ============ */

    /**
     * Refreshes convex vaults
     */
    function updateCache() public override {
        uint256 poolLength = booster.poolLength();
        if (elementsCached >= poolLength) {
            return;
        }
        for (uint256 i = elementsCached; i < poolLength; i++) {
            (, address token, , address reward, , ) = booster.poolInfo(i);
            cacheConvexTokenToPid[token] = i + 1;
            cacheConvexTokenToPid[reward] = i + 1;
            convexPools[token] = true;
            convexPools[reward] = true;
            convexList.push(token);
            convexList.push(reward);
        }
        elementsCached = poolLength;
    }

    /**
     * Gets the PID in convex of a convex lp token
     * @param _asset                         Address of the convex lp token
     * @return uint256                       Pid of the pool in convex
     */
    function getPid(address _asset) public view override returns (bool, uint256) {
        if (cacheConvexTokenToPid[_asset] > 0) {
            return (true, cacheConvexTokenToPid[_asset] - 1);
        }
        uint256 poolLength = booster.poolLength();
        if (elementsCached >= poolLength) {
            return (false, 0);
        }
        for (uint256 i = elementsCached; i < poolLength; i++) {
            (, address token, , address reward , , ) = booster.poolInfo(i);
            if (token == _asset || reward == _asset) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    /**
     * Gets the reward pool address given a convex token
     * @param _asset                         Address of the convex token
     * @return reward                        Address of the reward pool
     */
    function getRewardPool(address _asset) external view override returns (address reward) {
        (bool found, uint256 pid) = getPid(_asset);
        require(found, 'Pid not found');
        (, , , reward, , ) = booster.poolInfo(pid);
    }

    /**
     * Gets the input token address given a convex token
     * @param _pool                          Address of the convex token
     * @return inputToken                    Address of the input token
     */
    function getConvexInputToken(address _pool) external view override returns (address inputToken) {
        (bool found, uint256 pid) = getPid(_pool);
        require(found, 'Pid not found');
        (inputToken, , , , , ) = booster.poolInfo(pid);
    }

    /**
     * Gets all the convex tokens
     * @return address[]                       Addresses of the convex tokens
     */
    function getAllConvexPools() external view override returns (address[] memory) {
        return convexList;
    }
}
