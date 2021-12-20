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
    function initialize(
        address _reserveAsset,
        address _controller,
        address _creator,
        string memory _name,
        string memory _symbol,
        uint256[] calldata _gardenParams,
        uint256 _initialContribution,
        bool[] memory _publicGardenStrategistsStewards
    ) external payable;

    function makeGardenPublic() external;

    function transferCreatorRights(address _newCreator, uint8 _index) external;

    function addExtraCreators(address[4] memory _newCreators) external;

    function setPublicRights(bool _publicStrategist, bool _publicStewards) external;

    function privateGarden() external view returns (bool);

    function publicStrategists() external view returns (bool);

    function publicStewards() external view returns (bool);

    function controller() external view returns (address);

    function creator() external view returns (address);

    function isGardenStrategy(address _strategy) external view returns (bool);

    function getContributor(address _contributor)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        );

    function reserveAsset() external view returns (address);

    function totalContributors() external view returns (uint256);

    function gardenInitializedAt() external view returns (uint256);

    function minContribution() external view returns (uint256);

    function depositHardlock() external view returns (uint256);

    function minLiquidityAsset() external view returns (uint256);

    function minStrategyDuration() external view returns (uint256);

    function maxStrategyDuration() external view returns (uint256);

    function reserveAssetRewardsSetAside() external view returns (uint256);

    function absoluteReturns() external view returns (int256);

    function totalStake() external view returns (uint256);

    function minVotesQuorum() external view returns (uint256);

    function minVoters() external view returns (uint256);

    function maxDepositLimit() external view returns (uint256);

    function strategyCooldownPeriod() external view returns (uint256);

    function getStrategies() external view returns (address[] memory);

    function extraCreators(uint256 index) external view returns (address);

    function getFinalizedStrategies() external view returns (address[] memory);

    function strategyMapping(address _strategy) external view returns (bool);

    function finalizeStrategy(
        uint256 _profits,
        int256 _returns,
        uint256 _burningAmount
    ) external;

    function allocateCapitalToStrategy(uint256 _capital) external;

    function addStrategy(
        string memory _name,
        string memory _symbol,
        uint256[] calldata _stratParams,
        uint8[] calldata _opTypes,
        address[] calldata _opIntegrations,
        bytes calldata _opEncodedDatas
    ) external;

    function deposit(
        uint256 _reserveAssetQuantity,
        uint256 _minGardenTokenReceiveQuantity,
        address _to,
        bool mintNFT
    ) external payable;

    function depositBySig(
        uint256 _amountIn,
        uint256 _minAmountOut,
        bool _mintNft,
        uint256 _nonce,
        uint256 _maxFee,
        uint256 _pricePerShare,
        uint256 _fee,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function withdraw(
        uint256 _gardenTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to,
        bool _withPenalty,
        address _unwindStrategy
    ) external;

    function withdrawBySig(
        uint256 _gardenTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        uint256 _nonce,
        uint256 _maxFee,
        bool _withPenalty,
        address _unwindStrategy,
        uint256 _pricePerShare,
        uint256 _strategyNAV,
        uint256 _fee,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function claimReturns(address[] calldata _finalizedStrategies) external;

    function claimRewardsBySig(
        uint256 _babl,
        uint256 _profits,
        uint256 _nonce,
        uint256 _maxFee,
        uint256 _fee,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function getLockedBalance(address _contributor) external view returns (uint256);

    function updateGardenParams(uint256[9] memory _newParams) external;

    function expireCandidateStrategy(address _strategy) external;

    function payKeeper(address payable _keeper, uint256 _fee) external;

    function keeperDebt() external view returns (uint256);

    function totalKeeperFees() external view returns (uint256);
}
