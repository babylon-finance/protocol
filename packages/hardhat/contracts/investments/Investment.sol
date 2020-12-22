pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract Investment {
  using SafeMath for uint256;

  address public owner;

  // Strat attributes
  bool public initialized;
  string public name;

  constructor(address _fundContract, string memory _name) public {
    owner = _fundContract;
    name = name;
    initialized = true;
  }


  function start() public onlyFund {
    // override
  }

  function exit() public onlyFund {
    //
  }

  // function want() external view returns (address);
  //
  // function deposit() external;
  //
  // // NOTE: must exclude any tokens used in the yield
  // // Controller role - withdraw should return to Controller
  // function withdraw(address) external;
  //
  // // Controller | Vault role - withdraw should always return to Vault
  // function withdraw(uint256) external;
  //
  // function skim() external;
  //
  // // Controller | Vault role - withdraw should always return to Vault
  // function withdrawAll() external returns (uint256);
  //
  // function balanceOf() external view returns (uint256);

  modifier onlyFund() {
    require(owner == msg.sender, "Ownable: caller is not the fund contract");
    _;
  }
}
