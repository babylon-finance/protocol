pragma solidity 0.7.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./FundToken.sol";
import "./investments/Investment.sol";

contract Fund {
    using SafeMath for uint256;

    // Events
    event ContributionLog(
        address indexed contributor,
        uint256 amount,
        uint256 timestamp
    );
    event WithdrawalLog(address indexed sender, uint amount, uint timestamp);
    event ClaimLog(address indexed sender, uint originalAmount, uint amount, uint timestamp);

    struct Contributor {
        uint256 amount; //wei
        uint256 timestamp;
        bool claimed;
    }

    mapping(address => Contributor) public contributors;

    // Fund Properties
    address public protocol;
    address public manager;
    bool public active;
    string public name;
    uint256 public totalContributors;
    uint256 public totalFunds;

    //Strategies
    struct FundInvestmentRel {
      bool initialized;
      uint weight;
      Investment investment;
    }
    uint public investmentsCount;
    mapping (address => FundInvestmentRel) public investmentMapping;
    FundInvestmentRel[] public investments;

    // Token Properties
    FundToken public token;
    uint256 public minContribution = 1000000000000; //wei

    modifier onlyManager {
        require(
            msg.sender == manager,
            "Only the fund manager can modify fund state"
        );
        _;
    }

    modifier onlyManagerOrProtocol {
        require(
            msg.sender == manager || msg.sender == protocol,
            "Only the fund manager or the protocol can modify fund state"
        );
        _;
    }

    modifier onlyContributor(address payable _caller) {
        require(
            contributors[_caller].amount > 0,
            "Only the contributor can withdraw their funds"
        );
        _;
    }

    modifier fundIsActive() {
        require(
            active == true,
            "Fund must be active to deposit funds"
        );
        _;
    }

    constructor(
        string memory _name,
        string memory _tokenName,
        string memory _tokenSymbol,
        address _manager
    ) {
        token = new FundToken(_tokenName, _tokenSymbol);
        manager = _manager;
        protocol = msg.sender;
        name = _name;
        active = false;
        investmentsCount = 0;
    }

    /**
      The investment contract needs to have been deployed prior to calling this
    */
    function addInvestmentToFund(address investmentAddress) public onlyManager {
      require(investmentsCount < 10, "A fund can only have a maximum of 10 strategies");
      FundInvestmentRel storage fundInvestmentRel = investmentMapping[investmentAddress];
      require(!fundInvestmentRel.initialized, "This strategy is already in the fund");
      fundInvestmentRel.weight = 0;
      fundInvestmentRel.initialized = true;
      fundInvestmentRel.investment = Investment(investmentAddress);
      investments.push(fundInvestmentRel);
      investmentsCount ++;
    }

    /**
     * Setting the weight of an investment to 0 effectively disables it
    */
    function changeWeightsInvestments(uint[] memory newWeights) public onlyManager {
      uint totalWeights = 0;
      require(newWeights.length == investmentsCount, "The weights need to match the current investments");
      for (uint i = 0; i < newWeights.length; i++) {
        FundInvestmentRel storage fundInvestmentRel = investments[i];
        totalWeights += newWeights[i];
        fundInvestmentRel.weight = newWeights[i];
      }
      require(totalWeights == 100, "Total weights must add up to a 100");
    }

    function setActive(bool _active) public onlyManagerOrProtocol {
      if (_active) {
        require(investmentsCount > 0, "The fund needs to have investments to be active");
      }
      active = _active;
    }

    function setManager(address _manager) public onlyManager{
      manager = _manager;
    }

    function depositFunds() public payable fundIsActive {
      require(
          msg.value >= minContribution,
          "Send at least 1000000000000 wei"
      );
      Contributor storage contributor = contributors[msg.sender];

      // If new contributor, create one, increment count, and set the current TS
      if (contributor.amount == 0) {
          totalContributors = totalContributors.add(1);
          contributor.timestamp = block.timestamp;
      }

      totalFunds = totalFunds.add(msg.value);
      contributor.amount = contributor.amount.add(msg.value);
      token.mint(msg.sender, msg.value.div(minContribution));
      emit ContributionLog(msg.sender, msg.value, block.timestamp);
    }

    // TODO(tylerm): Move this into a utils contract
    function transferEth(address payable _to, uint amount) private {
        // Call returns a boolean value indicating success or failure.
        // This is the current recommended method to use.
        (bool sent,) = _to.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    function withdrawFunds(uint _amount) public onlyContributor(msg.sender) {
        Contributor storage contributor = contributors[msg.sender];
        require(_amount <= contributor.amount, 'Withdrawl amount must be less than or equal to deposited amount');
        contributor.amount = contributor.amount.sub(_amount);
        totalFunds = totalFunds.sub(_amount);
        if (contributor.amount == 0) {
          totalContributors = totalContributors.sub(1);
        }
        token.burn(msg.sender, _amount.div(minContribution));
        transferEth(msg.sender, _amount);
        emit WithdrawalLog(msg.sender, _amount, block.timestamp);
    }
}
