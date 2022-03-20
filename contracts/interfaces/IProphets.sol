// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

/**
 * @title IProphets
 * @author Babylon Finance
 *
 * Interface for interacting with the Prophets NFT
 */
interface IProphets is IERC721 {
    /* ============ Functions ============ */

    event Stake(address indexed _owner, address indexed _target, uint256 _tokenId);


    struct Attributes {
        uint256 bablLoot;
        uint64 creatorMultiplier;
        uint64 lpMultiplier;
        uint64 voterMultiplier;
        uint64 strategistMultiplier;
    }

    function getStakedProphetAttrs(address _owner, address _stakedAt) external view returns (uint256[7] memory);

    function stake(uint256 _id, address _target) external;

    function getAttributes(uint256 _id) external view returns (Attributes memory);

    function targetOf(uint256 _id) external view returns (address);

    function stakeOf(address _user, address _target) external view returns (uint256);

    function maxSupply() external pure returns (uint256);

    function prophetsSupply() external view returns (uint256);

    function ownerOf(uint256 tokenId) external view override returns (address);
}
