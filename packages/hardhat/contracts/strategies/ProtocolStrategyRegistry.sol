pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./FundStrategy.sol";

contract ProtocolStrategyRegistry {
  using SafeMath for uint256;

  address public protocol;
  mapping(address => FundStrategy) public allStrategies;
  mapping(string => FundStrategy) public allStrategiesByName;
  FundStrategy[] public strategies;
  uint public strategiesCount;

  constructor(address _protocolAddress) public {
    protocol = _protocolAddress;
    strategiesCount = 0;
  }

  function addStrategyToRegistry(string memory _name, address _implementationContract) public onlyFund {
    // require(!.active, "Strategy already exists in the registry");
    // require(!allStrategiesByName[_name].active, "Strategy with this name already exists in the registry");

    FundStrategy newStrategy = new FundStrategy(_implementationContract, _name);

    allStrategies[_implementationContract] = newStrategy;
    allStrategiesByName[_name] = newStrategy;

    strategiesCount ++;
  }

  function checkStrategy(address _implementationContract) public view returns (bool) {
    bool active = allStrategies[_implementationContract].active();
    return active == true;
  }

  modifier onlyFund() {
    require(protocol == msg.sender, "Ownable: caller is not the fund contract");
    _;
  }
}
