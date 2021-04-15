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

/**
 * @title IGarden
 * @author Babylon Finance
 *
 * Interface for operating with SetTokens.
 */
interface IGarden is IERC20 {
    /* ============ Functions ============ */
    function setActive() external;

    function setDisabled() external;

    function active() external view returns (bool);

    function controller() external view returns (address);

    function creator() external view returns (address);

    function gardenEndsBy() external view returns (uint256);

    function getContributor(address _contributor)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256[] calldata,
            uint256,
            uint256
        );

    function reserveAsset() external view returns (address);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function totalContributors() external view returns (uint256);

    function minContribution() external view returns (uint256);

    function totalCommunitiesDeposited() external view returns (uint256);

    function WETH() external view returns (address);

    function minLiquidityAsset() external view returns (uint256);

    function principal() external view returns (uint256);

    function absoluteReturns() external view returns (int256);

    function totalStake() external pure returns (uint256);

    function minVotersQuorum() external pure returns (uint256);

    function minStrategyDuration() external pure returns (uint256);

    function maxStrategyDuration() external pure returns (uint256);

    function strategyCooldownPeriod() external pure returns (uint256);

    function initialBuyRate() external pure returns (uint256);

    function strategyCreatorProfitPercentage() external pure returns (uint256);

    function strategyVotersProfitPercentage() external pure returns (uint256);

    function gardenCreatorProfitPercentage() external pure returns (uint256);

    function getStrategies() external view returns (address[] memory);

    function getFinalizedStrategies() external view returns (address[] memory);

    function strategies(uint256 _index) external view returns (address);

    function isStrategy(address _strategy) external view returns (bool);

    function startWithdrawalWindow(uint256 _amount) external;

    function allocateCapitalToStrategy(uint256 _capital) external;

    function addStrategy(
        uint8 _strategyKind,
        address _integration,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _strategyDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital,
        address _strategyData
    ) external;

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
        uint256 _minStrategyDuration,
        uint256 _maxStrategyDuration
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

    function claimReturns(address[] calldata _finalizedStrategies) external;

    function getActiveCapital() external view returns (uint256, address);

    function getContributorPower(
        address _contributor,
        uint256 _from,
        uint256 _to
    ) external view returns (uint256);

    function getProfitsAndBabl(address[] calldata _finalizedStrategies) external view returns (uint256, uint96);

    function setDepositLimit(uint256 limit) external;

    function getExpectedReserveWithdrawalQuantity(uint256 _gardenTokenQuantity) external view returns (uint256);

    function getLockedBalance(address _contributor) external view returns (uint256);

    function isDepositValid(address _reserveAsset, uint256 _reserveAssetQuantity) external view returns (bool);

    function isWithdrawalValid(address _reserveAsset, uint256 _gardenTokenQuantity) external view returns (bool);

    function reenableEthForStrategies() external;

    function burnAssetsFromSenderAndMintToReserve(address _contributor, uint256 _quantity) external;

    function canWithdrawEthAmount(uint256 _amount) external view returns (bool);

    function rebalanceStrategies(uint256 _fee) external;

    function moveStrategyToFinalized(int256 _returns, address _strategy) external;

    function expireCandidateStrategy(address _strategy) external;

    function updatePrincipal(uint256 _amount) external;

    function burnStrategistStake(address _strategist, uint256 _amount) external;
}
