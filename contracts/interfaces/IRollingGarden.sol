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

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IGarden} from './IGarden.sol';

/**
 * @title IGarden
 * @author Babylon Finance
 *
 * Interface for operating with SetTokens.
 */
interface IRollingGarden is IERC20, IGarden {
    function start(
        uint256 _maxDepositLimit,
        uint256 _minGardenTokenSupply,
        uint256 _minLiquidityAsset,
        uint256 _depositHardlock,
        uint256 _minContribution,
        uint256 _strategyCooldownPeriod,
        uint256 _strategyCreatorProfitPercentage,
        uint256 _strategyVotersProfitPercentage,
        uint256 _gardenCreatorProfitPercentage,
        uint256 _minVotersQuorum,
        uint256 _minIdeaDuration,
        uint256 _maxIdeaDuration
    ) external;

    function deposit(
        uint256 _reserveAssetQuantity,
        uint256 _minGardenTokenReceiveQuantity,
        address _to
    ) external payable;

    function withdraw(
        uint256 _gardenTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) external;

    function withdrawToReservePool(
        uint256 _gardenTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) external;

    function claimReturns(address[] calldata _finalizedStrategies) external;

    function getProfitsAndBabl(address[] calldata _finalizedStrategies) external returns (uint256, uint96);

    function setDepositLimit(uint256 limit) external;

    function getExpectedReserveWithdrawalQuantity(uint256 _gardenTokenQuantity) external view returns (uint256);

    function isDepositValid(address _reserveAsset, uint256 _reserveAssetQuantity) external view returns (bool);

    function isWithdrawalValid(address _reserveAsset, uint256 _gardenTokenQuantity) external view returns (bool);

    function reenableEthForInvestments() external;

    function burnAssetsFromSenderAndMintToReserve(address _contributor, uint256 _quantity) external;

    function curateStrategy(uint8 _strategyIndex, int256 _amount) external;

    function executeTopInvestment() external;

    function finalizeInvestment(uint256 _strategyIndex) external;

    function getCurrentTopStrategy() external view returns (uint8);

    function canWithdrawEthAmount(uint256 _amount) external view returns (bool);

    function claimReturns(address[] calldata _finalizedStrategies) external;

    function getProfitsAndBabl(address[] calldata _finalizedStrategies) external view returns (uint256, uint256);
}
