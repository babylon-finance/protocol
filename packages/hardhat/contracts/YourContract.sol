pragma solidity >=0.6.0 <0.7.0;

import "hardhat/console.sol";

contract YourContract {
    string public purpose = "🛠 Programming Unstoppable Money 2";

    function setPurpose(string memory newPurpose) public {
        purpose = newPurpose;
        // console.log(msg.sender, "set purpose to", purpose);
        //emit SetPurpose(msg.sender, purpose);
    }

    //event SetPurpose(address sender, string purpose);
}
