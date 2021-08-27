// SPDX-License-Identifier: MIT

pragma solidity >=0.4.24;

// https://docs.synthetix.io/contracts/source/interfaces/idepot
interface ISnxDepot {
    // Views
    function fundsWallet() external view returns (address payable);

    function maxEthPurchase() external view returns (uint256);

    function minimumDepositAmount() external view returns (uint256);

    function synthsReceivedForEther(uint256 amount) external view returns (uint256);

    function totalSellableDeposits() external view returns (uint256);

    // Mutative functions
    function depositSynths(uint256 amount) external;

    function exchangeEtherForSynths() external payable returns (uint256);

    function exchangeEtherForSynthsAtRate(uint256 guaranteedRate) external payable returns (uint256);

    function withdrawMyDepositedSynths() external;

    // Note: On mainnet no SNX has been deposited. The following functions are kept alive for testnet SNX faucets.
    function exchangeEtherForSNX() external payable returns (uint256);

    function exchangeEtherForSNXAtRate(uint256 guaranteedRate, uint256 guaranteedSynthetixRate)
        external
        payable
        returns (uint256);

    function exchangeSynthsForSNX(uint256 synthAmount) external returns (uint256);

    function synthetixReceivedForEther(uint256 amount) external view returns (uint256);

    function synthetixReceivedForSynths(uint256 amount) external view returns (uint256);

    function withdrawSynthetix(uint256 amount) external;
}
