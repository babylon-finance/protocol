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

pragma solidity 0.7.6;

import 'hardhat/console.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IBooster} from '../../interfaces/external/convex/IBooster.sol';
import {IBasicRewards} from '../../interfaces/external/convex/IBasicRewards.sol';

/**
 * @title ConvexStakeIntegration
 * @author Babylon Finance Protocol
 *
 * Lido Integration
 */
contract ConvexStakeIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ State Variables ============ */

    IBooster private constant booster = IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address private constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52; // crv
    address private constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // cvx

    mapping(address => uint256) private cacheConvexTokenToPid;
    uint256 private elementsCached = 0;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller) PassiveIntegration('convex_v2', _controller) {
        _updateCache();
    }

    /**
     * Gets the PID in convex of a convex lp token
     * @param _asset                         Address of the convex lp token
     * @return uint256                       Pid of the pool in convex
     */
    function getPid(address _asset) public view returns (bool, uint256) {
        if (cacheConvexTokenToPid[_asset] > 0) {
            return (true, cacheConvexTokenToPid[_asset] - 1);
        }
        uint256 poolLength = booster.poolLength();
        if (elementsCached >= poolLength) {
            return (false, 0);
        }
        for (uint256 i = elementsCached; i < poolLength; i++) {
            (, address token, , , , ) = booster.poolInfo(i);
            if (token == _asset) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    /* ============ Internal Functions ============ */

    function _updateCache() public {
        uint256 poolLength = booster.poolLength();
        if (elementsCached >= poolLength) {
            return;
        }
        for (uint256 i = elementsCached; i < poolLength; i++) {
            (, address token, , , , ) = booster.poolInfo(i);
            cacheConvexTokenToPid[token] = i + 1;
        }
        elementsCached = poolLength;
    }

    function _getSpender(address _asset, uint8 _op) internal view override returns (address) {
        if (_op == 0) {
            return address(booster);
        }
        // Reward pool
        return _getRewardPool(_asset);
    }

    function _getExpectedShares(
        address, /* _asset */
        uint256 _amount
    ) internal pure override returns (uint256) {
        return _amount;
    }

    function _getPricePerShare(
        address /* _asset */
    ) internal pure override returns (uint256) {
        return 1e18;
    }

    function _getInvestmentAsset(address _asset) internal view override returns (address lptoken) {
        (bool found, uint256 pid) = getPid(_asset);
        require(found, 'Pid not found');
        (lptoken, , , , , ) = booster.poolInfo(pid);
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _asset                          Address of the vault
     * hparam  _investmentTokensOut            Amount of investment tokens to send
     * hparam  _tokenIn                        Addresses of tokens to send to the investment
     * @param  _maxAmountIn                    Amounts of tokens to send to the investment
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getEnterInvestmentCalldata(
        address, /* _strategy */
        address _asset,
        uint256, /* _investmentTokensOut */
        address, /* _tokenIn */
        uint256 _maxAmountIn
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        (bool found, uint256 pid) = getPid(_asset);
        require(found, 'Convex pool does not exist');
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('deposit(uint256,uint256,bool)', pid, _maxAmountIn, true);
        return (address(booster), 0, methodData);
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _asset                          Address of the investment
     * hparam  _investmentTokensIn             Amount of investment tokens to receive
     * hparam  _tokenOut                       Addresses of tokens to receive
     * hparam  _minAmountOut                   Amounts of investment tokens to receive
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getExitInvestmentCalldata(
        address, /* _strategy */
        address _asset,
        uint256, /* _investmentTokensIn */
        address, /* _tokenOut */
        uint256 /* _minAmountOut */
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Withdraw all and claim
        bytes memory methodData = abi.encodeWithSignature('withdrawAllAndUnwrap(bool)', true);
        // Go through the reward pool instead of the booster
        return (_getRewardPool(_asset), 0, methodData);
    }

    function _getRewardPool(address _asset) private view returns (address reward) {
        (bool found, uint256 pid) = getPid(_asset);
        require(found, 'Pid not found');
        (, , , reward, , ) = booster.poolInfo(pid);
    }

    function _getResultAsset(address _investment) internal view virtual override returns (address) {
        return _getRewardPool(_investment);
    }

    function _getConvexLPToken(address _asset) private view returns (address token) {
        (bool found, uint256 pid) = getPid(_asset);
        require(found, 'Pid not found');
        (, token, , , , ) = booster.poolInfo(pid);
    }

    function _getRewards(address _asset) internal view override returns (address token, uint256 balance) {
        IBasicRewards rewards = IBasicRewards(_getRewardPool(_asset));
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        uint256 totalAmount = rewards.earned(msg.sender) * 2; // * 2 accounts roughly for CVX
        // add extra rewards and convert to reward token
        uint256 extraRewardsLength = rewards.extraRewardsLength();
        if (extraRewardsLength > 0) {
            for (uint256 i = 0; i < extraRewardsLength; i++) {
                IBasicRewards extraRewards = IBasicRewards(rewards.extraRewards(i));
                totalAmount = totalAmount.add(
                    oracle.getPrice(extraRewards.rewardToken(), rewards.extraRewards(i)).preciseMul(
                        extraRewards.earned(msg.sender)
                    )
                );
            }
        }
        return (rewards.rewardToken(), totalAmount);
    }
}
