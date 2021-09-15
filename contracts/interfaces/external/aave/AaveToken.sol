pragma solidity >=0.7.0 <0.9.0;

interface AaveToken {
    function underlyingAssetAddress() external view returns (address);
}
