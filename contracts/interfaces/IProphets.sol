// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

/**
 * @title IProphets
 * @author Babylon Finance
 *
 * Interface for interacting with the Prophets NFT
 */
interface IProphets is IERC721 {
    /* ============ Functions ============ */

    function getStakedProphetAttrs(address _owner, address _stakedAt) external view returns (uint256[7] memory);

    function stake(uint256 _id, address _target) external;
}
