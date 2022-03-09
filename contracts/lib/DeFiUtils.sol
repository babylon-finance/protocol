// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

library DeFiUtils {
    function toTradePathString(address[] memory _tokens) internal view returns (string memory) {
        string memory result;
        for (uint256 i = 0; i < _tokens.length; i++) {
            result = string(abi.encodePacked(result, ERC20(_tokens[i]).symbol(), i != _tokens.length - 1 ? '->' : ''));
        }
        return result;
    }
}
