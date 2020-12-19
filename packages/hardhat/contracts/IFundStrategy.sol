pragma solidity >=0.7.0 <0.9.0;

// import "hardhat/console.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface IFundStrategy {

  function getName() external pure returns (string memory);
}
