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
            uint256
        );

    function reserveAsset() external view returns (address);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function totalContributors() external view returns (uint256);

    function minContribution() external view returns (uint256);

    function totalCommunitiesDeposited() external view returns (uint256);

    function weth() external view returns (address);

    function minLiquidityAsset() external view returns (uint256);

    function principal() external view returns (uint256);

    function absoluteReturns() external view returns (int256);

    function totalStake() external pure returns (uint256);

    function minVotersQuorum() external pure returns (uint256);

    function minIdeaDuration() external pure returns (uint256);

    function maxIdeaDuration() external pure returns (uint256);

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

    function allocateCapitalToInvestment(uint256 _capital) external;

    function addStrategy(
        uint8 _strategyKind,
        address _integration,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _investmentDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital,
        address _strategyData
    ) external;

    function rebalanceInvestments(uint256 _fee) external;

    function moveStrategyToFinalized(int256 _returns, address _strategy) external;

    function expireCandidateStrategy(address _strategy) external;

    function updatePrincipal(uint256 _amount) external;

    function burnStrategistStake(address _strategist, uint256 _amount) external;
}
