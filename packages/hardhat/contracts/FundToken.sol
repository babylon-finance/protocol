pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/presets/ERC20PresetMinterPauser.sol";

contract FundToken is ERC20PresetMinterPauser {
    constructor(string memory name, string memory symbol) ERC20PresetMinterPauser(name, symbol) {}

    function burn(address account, uint256 amount) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only admin can burn");
        _burn(account, amount);
    }

    function grantAdminAndRevoke(address newadmin, address prevadmin) public {
        grantRole(DEFAULT_ADMIN_ROLE, newadmin);
        grantRole(MINTER_ROLE, newadmin);
        revokeRole(MINTER_ROLE, prevadmin);
        revokeRole(DEFAULT_ADMIN_ROLE, prevadmin);
    }
}
