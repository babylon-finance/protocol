// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;

/**
 * @title IHeart
 * @author Babylon Finance
 *
 * Interface for interacting with the Heart
 */
interface IHeart {
    // View functions

    function getVotedGardens() external view returns (address[] memory);

    function getGardenWeights() external view returns (uint256[] memory);

    function minAmounts(address _reserve) external view returns (uint256);

    function assetToCToken(address _asset) external view returns (address);

    function assetToLend() external view returns (address);

    function assetForPurchases() external view returns (address);

    function lastPumpAt() external view returns (uint256);

    function lastVotesAt() external view returns (uint256);

    function tradeSlippage() external view returns (uint256);

    function weeklyRewardAmount() external view returns (uint256);

    function bablRewardLeft() external view returns (uint256);

    function getFeeDistributionWeights() external view returns (uint256[] memory);

    function getTotalStats() external view returns (uint256[7] memory);

    function votedGardens(uint256 _index) external view returns (address);

    function gardenWeights(uint256 _index) external view returns (uint256);

    function feeDistributionWeights(uint256 _index) external view returns (uint256);

    function totalStats(uint256 _index) external view returns (uint256);

    // Non-view

    function pump() external;

    function voteProposal(uint256 _proposalId, bool _isApprove) external;

    function resolveGardenVotesAndPump(address[] memory _gardens, uint256[] memory _weights) external;

    function resolveGardenVotes(address[] memory _gardens, uint256[] memory _weights) external;

    function updateMarkets() external;

    function setHeartGardenAddress(address _heartGarden) external;

    function updateFeeWeights(uint256[] calldata _feeWeights) external;

    function updateAssetToLend(address _assetToLend) external;

    function updateAssetToPurchase(address _purchaseAsset) external;

    function lendFusePool(address _assetToLend, uint256 _lendAmount) external;

    function borrowFusePool(address _assetToBorrow, uint256 _borrowAmount) external;

    function sellWantedAssetToHeart(address _assetToSell, uint256 _amountToSell) external;

    function addReward(uint256 _bablAmount, uint256 _weeklyRate) external;

    function setMinTradeAmount(address _asset, uint256 _minAmount) external;

    function setTradeSlippage(uint256 _tradeSlippage) external;
}
