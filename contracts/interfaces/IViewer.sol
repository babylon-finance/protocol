// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IGarden} from '../interfaces/IGarden.sol';
import {IHeart} from '../interfaces/IHeart.sol';

interface IStrategyViewer {
    function getCompleteStrategy(address _strategy)
        external
        view
        returns (
            address,
            string memory,
            uint256[16] memory,
            bool[] memory,
            uint256[] memory
        );

    function getOperationsStrategy(address _strategy)
        external
        view
        returns (
            uint8[] memory,
            address[] memory,
            bytes[] memory
        );

    function getUserStrategyActions(address[] memory _strategies, address _user)
        external
        view
        returns (uint256, uint256);
}

interface IGardenViewer {
    struct PartialGardenInfo {
        address addr;
        string name;
        bool publicLP;
        uint256 verified;
        uint256 totalContributors;
        address reserveAsset;
        uint256 netAssetValue;
    }

    function getGardenPrincipal(address _garden) external view returns (uint256);

    function getGardenDetails(address _garden)
        external
        view
        returns (
            string memory name,
            string memory symbol,
            address[5] memory creators,
            address reserveAsset,
            bool[4] memory actors,
            address[] memory strategies,
            address[] memory finalizedStrategies,
            uint256[13] memory params,
            uint256[10] memory stats,
            uint256[3] memory profits
        );

    function getGardenPermissions(address _garden, address _user)
        external
        view
        returns (
            bool,
            bool,
            bool
        );

    function getGardensUser(address _user, uint256 _offset)
        external
        view
        returns (
            address[] memory,
            bool[] memory,
            PartialGardenInfo[] memory
        );

    function getGardenUserAvgPricePerShare(IGarden _garden, address _user) external view returns (uint256);

    function getPotentialVotes(address _garden, address[] calldata _members) external view returns (uint256);

    function getContributor(IGarden _garden, address _user) external view returns (uint256[10] memory);

    function getContributionAndRewards(IGarden _garden, address _user)
        external
        view
        returns (
            uint256[10] memory,
            uint256[] memory,
            uint256[] memory
        );

    function getPriceAndLiquidity(address _tokenIn, address _reserveAsset) external view returns (uint256, uint256);

    function getAllProphets(address _address) external view returns (uint256[] memory);
}

interface IHeartViewer {
    function heart() external view returns (IHeart);

    function getAllHeartDetails()
        external
        view
        returns (
            address[2] memory, // address of the heart garden
            uint256[7] memory, // total stats
            uint256[] memory, // fee weights
            address[] memory, // voted gardens
            uint256[] memory, // garden weights
            uint256[2] memory, // weekly babl reward
            uint256[2] memory, // dates
            uint256[2] memory // liquidity
        );

    function getGovernanceProposals(uint256[] calldata _ids)
        external
        view
        returns (
            address[] memory, // proposers
            uint256[] memory, // endBlocks
            uint256[] memory, // for votes - against votes
            uint256[] memory // state
        );

    function getBondDiscounts(address[] calldata _assets) external view returns (uint256[] memory);
}

interface IViewer is IGardenViewer, IHeartViewer, IStrategyViewer {}
