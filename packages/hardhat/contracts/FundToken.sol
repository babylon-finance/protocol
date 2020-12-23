pragma solidity 0.7.4;

import "@openzeppelin/contracts/presets/ERC20PresetMinterPauser.sol";

contract FundToken is ERC20PresetMinterPauser {
    constructor(string memory name, string memory symbol) ERC20PresetMinterPauser(name, symbol) {}

    function burn(address account, uint256 amount) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only admin can burn");
        _burn(account, amount);
    }
}
