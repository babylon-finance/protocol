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
pragma abicoder v2;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title VTableBeacon
 * @notice Redirects calls to an implementation based on the method signature
 */
contract VTableBeacon is Ownable {
    struct ModuleDefinition {
        address implementation;
        bytes4[] selectors;
    }

    bytes4 private constant _FALLBACK_SIGN = 0xffffffff;

    // Mapping of methods signatures to their implementations
    mapping(bytes4 => address) private _delegates;

    event VTableUpdate(bytes4 indexed selector, address oldImplementation, address newImplementation);

    function implementation(bytes4 selector) external view virtual returns (address module) {
        module = _delegates[msg.sig];
        if (module != address(0)) return module;

        module = _delegates[_FALLBACK_SIGN];
        if (module != address(0)) return module;

        revert("VTableProxy: No implementation found");
    }

    /**
     * @dev Updates the vtable
     */
    function updateVTable(ModuleDefinition[] calldata modules) external onlyOwner {
        for (uint256 i = 0; i < modules.length; ++i) {
            ModuleDefinition memory module = modules[i];
            for (uint256 j = 0; j < module.selectors.length; ++j) {
                bytes4 selector = module.selectors[j];
                emit VTableUpdate(selector, _delegates[selector], module.implementation);
                _delegates[selector] = module.implementation;
            }
        }
    }
}
