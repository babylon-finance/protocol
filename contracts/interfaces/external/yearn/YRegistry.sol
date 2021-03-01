// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

interface YRegistry {
  function getName() external pure returns (string memory);
  function getVault(uint256 index) external view returns (address vault);
  function getVaultsLength() external view returns (uint256);
  function getVaults() external view returns (address[] memory);
  function getVaultInfo(address _vault)
    external
    view
    returns (
        address controller,
        address token,
        address strategy,
        bool isWrapped,
        bool isDelegated
    );
  function getVaultsInfo()
    external
    view
    returns (
        address[] memory vaultsAddresses,
        address[] memory controllerArray,
        address[] memory tokenArray,
        address[] memory strategyArray,
        bool[] memory isWrappedArray,
        bool[] memory isDelegatedArray
    );
}
