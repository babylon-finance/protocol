pragma solidity >=0.7.0 <0.9.0;

// import "hardhat/console.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./FundToken.sol";

contract Holder {

  struct HedgeFund {
    string name;
    bool active;
    uint index;
  }

  address public protocolManager;

  // Hedge Funds List
  HedgeFund[] public hedgeFunds;
  uint public currentHedgeFundIndex = 1;
  uint public totalHedgeFunds = 0;
  mapping (string => uint) public hedgeFundsMapping;

  // Functions
  constructor() public {
    protocolManager = msg.sender;
  }

  modifier onlyProtocol {
    require(msg.sender == protocolManager, "Only protocol can add strategies");
    _;
  }

  function addHedgeFund(string memory name) onlyProtocol public {
    require(hedgeFundsMapping[name] == 0, "The hedge fund already exists.");
    hedgeFunds.push(HedgeFund(name, true, currentHedgeFundIndex));
    hedgeFundsMapping[name] = currentHedgeFundIndex;
    currentHedgeFundIndex ++;
    totalHedgeFunds ++;
  }

  function disableHedgeFund(string memory name) onlyProtocol public {
    uint atIndex = hedgeFundsMapping[name];
    HedgeFund storage hedgeFund = hedgeFunds[atIndex - 1];
    require(hedgeFund.active, "The hedge fund needs to be active.");
    hedgeFund.active = false;
    hedgeFund.index = 0;
    totalHedgeFunds --;
  }

  function reenableHedgeFund(string memory name) onlyProtocol public {
    uint atIndex = hedgeFundsMapping[name];
    HedgeFund storage hedgeFund = hedgeFunds[atIndex - 1];
    require(!hedgeFund.active, "The hedge fund needs to be disabled.");
    hedgeFund.active = true;
    hedgeFund.index = atIndex;
    totalHedgeFunds ++;
  }

  function getHedgeFund(string memory _name) public view returns (string memory name, bool active, uint index) {
    uint atIndex = hedgeFundsMapping[_name];
    HedgeFund storage hedgeFund = hedgeFunds[atIndex - 1];
    return (hedgeFund.name, hedgeFund.active, hedgeFund.index);
  }

  function transferEth(address payable _to, uint amount) private {
    // Call returns a boolean value indicating success or failure.
    // This is the current recommended method to use.
    (bool sent, bytes memory data) = _to.call{value: amount}("");
    require(sent, "Failed to send Ether");
  }


}
