pragma solidity >=0.7.0 <0.9.0;

// import "hardhat/console.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./FundToken.sol";

contract HedgeFund {
    address public manager;
    bool public active;
    string public name;

    modifier onlyManager(address _caller) {
        require(
            _caller == manager,
            "Only the fund manager can modify fund state"
        );
        _;
    }

    constructor(
        string memory _name,
        bool _active,
        address _manager
    ) public {
        manager = _manager;
        name = _name;
        active = _active;
    }

    function setActive(bool _active, address _caller)
        public
        onlyManager(_caller)
    {
        active = _active;
    }

    function setManager(address _manager, address _caller)
        public
        onlyManager(_caller)
    {
        manager = _manager;
    }
}
