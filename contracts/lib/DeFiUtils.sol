/*
    Copyright 2021 Babylon Finance.
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.7.6;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

library DeFiUtils {
    function toTradePathString(address[3] memory _tokens) internal view returns (string memory) {
        address[] memory args = new address[](3);
        args[0] = _tokens[0];
        args[1] = _tokens[1];
        args[2] = _tokens[2];
        return toTradePathString(args);
    }

    function toTradePathString(address[2] memory _tokens) internal view returns (string memory) {
        address[] memory args = new address[](2);
        args[0] = _tokens[0];
        args[1] = _tokens[1];
        return toTradePathString(args);
    }

    function toTradePathString(address[] memory _tokens) internal view returns (string memory) {
        string memory result;
        for (uint256 i = 0; i < _tokens.length; i++) {
            result = string(abi.encodePacked(result, ERC20(_tokens[i]).symbol(), i != _tokens.length - 1 ? '->' : ''));
        }
        return result;
    }
}
