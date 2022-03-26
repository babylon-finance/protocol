// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import '@openzeppelin/contracts/proxy/Proxy.sol';

import "./VTable.sol";
import "./modules/VTableUpdateModule.sol";

/**
 * @title VTableProxy
 */
contract VTableProxy is Proxy {
    using VTable for VTable.VTableStore;

    bytes4 private constant _FALLBACK_SIGN = 0xffffffff;

    constructor(address updatemodule) {
        VTable.VTableStore storage vtable = VTable.instance();

        vtable.setOwner(msg.sender);
        vtable.setFunction(VTableUpdateModule(updatemodule).updateVTable.selector, updatemodule);
    }

    function _implementation() internal view virtual override returns (address module) {
        VTable.VTableStore storage vtable = VTable.instance();

        module = vtable.getFunction(msg.sig);
        if (module != address(0)) return module;

        module = vtable.getFunction(_FALLBACK_SIGN);
        if (module != address(0)) return module;

        revert("VTableProxy: No implementation found");
    }
}
