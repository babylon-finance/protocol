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

/**
 * @title IGarden
 * @author Babylon Finance
 *
 * Interface for operating with a Garden.
 */
interface IGarden {
    /* ============ Functions ============ */
    function setActive() external;

    function setDisabled() external;

    function active() external view returns (bool);

    function guestListEnabled() external view returns (bool);

    function controller() external view returns (address);

    function nftAddress() external view returns (address);

    function creator() external view returns (address);

    function getContributor(address _contributor)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256[] memory,
            uint256,
            uint256,
            uint256
        );

    function reserveAsset() external view returns (address);

    function totalContributors() external view returns (uint256);

    function gardenInitializedAt() external view returns (uint256);

    function minContribution() external view returns (uint256);

    function maxContributors() external view returns (uint256);

    function WETH() external view returns (address);

    function minLiquidityAsset() external view returns (uint256);

    function principal() external view returns (uint256);

    function reserveAssetRewardsSetAside() external view returns (uint256);

    function reserveAssetPrincipalWindow() external view returns (uint256);

    function absoluteReturns() external view returns (int256);

    function totalStake() external view returns (uint256);

    function minVotersQuorum() external view returns (uint256);

    function minStrategyDuration() external view returns (uint256);

    function maxStrategyDuration() external view returns (uint256);

    function strategyCooldownPeriod() external view returns (uint256);

    function getStrategies() external view returns (address[] memory);

    function getFinalizedStrategies() external view returns (address[] memory);

    function strategies(uint256 _index) external view returns (address);

    function isStrategy(address _strategy) external view returns (bool);

    function startWithdrawalWindow(
        uint256 _amount,
        uint256 _profits,
        int256 _returns,
        address _strategy
    ) external;

    function allocateCapitalToStrategy(uint256 _capital) external;

    function addStrategy(
        uint8 _strategyKind,
        address _integration,
        uint256 _maxCapitalRequested,
        uint256 _stake,
        uint256 _strategyDuration,
        uint256 _expectedReturn,
        uint256 _minRebalanceCapital,
        address _strategyData,
        string memory _name,
        string memory _symbol
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

    function getContributorPower(
        address _contributor,
        uint256 _from,
        uint256 _to
    ) external view returns (uint256);

    function getGardenTokenMintQuantity(
        address _reserveAsset,
        uint256 _netReserveFlows,
        uint256 _gardenTokenTotalSupply
    ) external view returns (uint256);

    function getExpectedReserveWithdrawalQuantity(uint256 _gardenTokenQuantity) external view returns (uint256);

    function getLockedBalance(address _contributor) external view returns (uint256);

    function isWithdrawalValid(address _reserveAsset, uint256 _gardenTokenQuantity) external view returns (bool);

    function reenableEthForStrategies() external;

    function rebalanceStrategies(uint256 _fee) external;

    function expireCandidateStrategy(address _strategy) external;

    function burnStrategistStake(address _strategist, uint256 _amount) external;
}
