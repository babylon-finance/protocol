pragma solidity >=0.7.0 <0.9.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./FundToken.sol";
import "./Fund.sol";

contract DFolio {
    using SafeMath for uint256;

    struct FundMapping {
        Fund hedgeFund;
        uint256 index;
    }

    address public protocolManager;

    //  Funds List
    FundMapping[] public hedgeFunds;
    uint256 public currentFundIndex = 1;
    uint256 public totalFunds = 0;
    mapping(string => uint256) public hedgeFundsMapping;

    // Functions
    constructor() {
        protocolManager = msg.sender;
    }

    modifier onlyProtocol {
        require(
            msg.sender == protocolManager,
            "Only protocol can add strategies"
        );
        _;
    }

    function addFund(
        string memory _name,
        string memory _tokenName,
        string memory _symbol
    ) public onlyProtocol {
        require(
            hedgeFundsMapping[_name] == 0,
            "The hedge fund already exists."
        );
        Fund newFund = new Fund(
            _name,
            _tokenName,
            _symbol,
            msg.sender
        );
        hedgeFunds.push(FundMapping(newFund, currentFundIndex));
        hedgeFundsMapping[_name] = currentFundIndex;
        currentFundIndex++;
        totalFunds++;
    }

    function getAllFunds() external view returns (address[] memory) {
        address[] memory ret = new address[](totalFunds);
        for (uint i = 0; i < totalFunds; i++) {
            ret[i] = address(hedgeFunds[i].hedgeFund);
        }
        return ret;
    }

    function disableFund(string memory _name) public onlyProtocol {
        uint256 atIndex = hedgeFundsMapping[_name];
        FundMapping storage _hedgeFundMapping = hedgeFunds[atIndex.sub(1)];
        require(
            _hedgeFundMapping.hedgeFund.active(),
            "The hedge fund needs to be active."
        );
        _hedgeFundMapping.hedgeFund.setActive(false);
        totalFunds--;
    }

    function reenableFund(string memory _name) public onlyProtocol {
        uint256 atIndex = hedgeFundsMapping[_name];
        FundMapping storage _hedgeFundMapping = hedgeFunds[atIndex.sub(1)];
        require(
            !_hedgeFundMapping.hedgeFund.active(),
            "The hedge fund needs to be disabled."
        );
        _hedgeFundMapping.hedgeFund.setActive(true);
        totalFunds++;
    }

    function getFund(string memory _name)
        public
        view
        returns (
            string memory name,
            bool active,
            uint256 index
        )
    {
        uint256 atIndex = hedgeFundsMapping[_name];
        FundMapping storage _hedgeFundMapping = hedgeFunds[atIndex.sub(1)];
        return (
            _hedgeFundMapping.hedgeFund.name(),
            _hedgeFundMapping.hedgeFund.active(),
            _hedgeFundMapping.index
        );
    }
}
