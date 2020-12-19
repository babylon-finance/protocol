pragma solidity >=0.7.0 <0.9.0;

interface IProtocolStrategyRegistry {

  function addStrategyToRegistry(string memory _name, address _implementationContract) external;
  function checkStrategy(address _implementationContract) external view returns (bool);

}
