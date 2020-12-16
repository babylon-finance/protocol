pragma solidity >=0.6.0 <0.7.0;
import "@openzeppelin/contracts/presets/ERC20PresetMinterPauser.sol";

contract FundERC20 is ERC20PresetMinterPauser {

  constructor(string memory name, string memory symbol) ERC20PresetMinterPauser(name, symbol) public {}

  function burn(address account, uint256 amount) public {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only admin can burn");
    _burn(account, amount);
  }

  function grantAdminAndRevoke(address newadmin) public {
    grantRole(DEFAULT_ADMIN_ROLE, newadmin);
    grantRole(MINTER_ROLE, newadmin);
    revokeRole(MINTER_ROLE, msg.sender);
    revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }
}
