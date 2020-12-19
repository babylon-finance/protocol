pragma solidity >=0.7.0 <0.9.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./FundToken.sol";
import "./HedgeFund.sol";

contract Holder {
    using SafeMath for uint256;

    struct HedgeFundMapping {
        HedgeFund hedgeFund;
        uint256 index;
    }

    address public protocolManager;

    // Hedge Funds List
    HedgeFundMapping[] public hedgeFunds;
    uint256 public currentHedgeFundIndex = 1;
    uint256 public totalHedgeFunds = 0;
    mapping(string => uint256) public hedgeFundsMapping;

    // Functions
    constructor() public {
        protocolManager = msg.sender;
    }

    modifier onlyProtocol {
        require(
            msg.sender == protocolManager,
            "Only protocol can add strategies"
        );
        _;
    }

    function addHedgeFund(
        string memory _name,
        string memory _tokenName,
        string memory _symbol
    ) public onlyProtocol {
        require(
            hedgeFundsMapping[_name] == 0,
            "The hedge fund already exists."
        );
        HedgeFund newHedgeFund = new HedgeFund(
            _name,
            _tokenName,
            _symbol,
            true,
            msg.sender
        );
        hedgeFunds.push(HedgeFundMapping(newHedgeFund, currentHedgeFundIndex));
        hedgeFundsMapping[_name] = currentHedgeFundIndex;
        currentHedgeFundIndex++;
        totalHedgeFunds++;
    }

    function disableHedgeFund(string memory _name) public onlyProtocol {
        uint256 atIndex = hedgeFundsMapping[_name];
        HedgeFundMapping storage _hedgeFundMapping = hedgeFunds[atIndex.sub(1)];
        require(
            _hedgeFundMapping.hedgeFund.active(),
            "The hedge fund needs to be active."
        );
        _hedgeFundMapping.hedgeFund.setActive(false, msg.sender);
        totalHedgeFunds--;
    }

    function reenableHedgeFund(string memory _name) public onlyProtocol {
        uint256 atIndex = hedgeFundsMapping[_name];
        HedgeFundMapping storage _hedgeFundMapping = hedgeFunds[atIndex.sub(1)];
        require(
            !_hedgeFundMapping.hedgeFund.active(),
            "The hedge fund needs to be disabled."
        );
        _hedgeFundMapping.hedgeFund.setActive(true, msg.sender);
        totalHedgeFunds++;
    }

    function getHedgeFund(string memory _name)
        public
        view
        returns (
            string memory name,
            bool active,
            uint256 index
        )
    {
        uint256 atIndex = hedgeFundsMapping[_name];
        HedgeFundMapping storage _hedgeFundMapping = hedgeFunds[atIndex.sub(1)];
        return (
            _hedgeFundMapping.hedgeFund.name(),
            _hedgeFundMapping.hedgeFund.active(),
            _hedgeFundMapping.index
        );
    }
}
