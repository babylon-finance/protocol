/*
    Copyright 2020 Babylon Finance

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

    function gardenIdeas() external view returns (address);

    function getContributor(address _contributor)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function getIntegrations() external view returns (address[] memory);

    function getReserveAsset() external view returns (address);

    function hasIntegration(address _integration) external view returns (bool);

    function isValidIntegration(address _integration) external returns (bool);

    function name() external view returns (string memory);

    function totalContributors() external view returns (uint256);

    function totalCommunitiesDeposited() external view returns (uint256);

    function weth() external view returns (address);

    function minLiquidityAsset() external view returns (uint256);

    function getReserveBalance() external view returns (uint256);

    function totalStake() external pure returns (uint256);

    function minVotersQuorum() external pure returns (uint256);

    function minIdeaDuration() external pure returns (uint256);

    function maxIdeaDuration() external pure returns (uint256);

    function strategyCooldownPeriod() external pure returns (uint256);

    function strategyCreatorProfitPercentage() external pure returns (uint256);

    function strategyVotersProfitPercentage() external pure returns (uint256);

    function gardenCreatorProfitPercentage() external pure returns (uint256);

    function getStrategies() external view returns (address[] memory);

    function isStrategy(address _strategy) external view returns (bool);

    function startRedemptionWindow(uint256 _amount) external;

    function allocateCapitalToInvestment(uint256 _capital) external;
    function addStrategy(
      uint256 _maxCapitalRequested,
      uint256 _stake,
      uint256 _investmentDuration,
      uint256 _expectedReturn,
      uint256 _minRebalanceCapital
    ) external;

    function rebalanceInvestments() external;

    function callIntegration(
        address _integration,
        uint256 _value,
        bytes calldata _data,
        address[] memory _tokensNeeded,
        uint256[] memory _tokenAmountsNeeded
    ) external returns (bytes memory _returnValue);

    function invokeApprove(
        address _spender,
        address _asset,
        uint256 _quantity
    ) external;

    function invokeFromIntegration(
        address _target,
        uint256 _value,
        bytes calldata _data
    ) external returns (bytes memory _returnValue);

    function updateReserveBalance(uint256 _amount) external;
}
