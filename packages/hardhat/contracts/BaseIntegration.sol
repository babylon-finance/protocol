/*
    Copyright 2020 DFolio.

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

pragma solidity 0.6.10;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ExplicitERC20 } from "../../lib/ExplicitERC20.sol";
import { IController } from "./interfaces/IController.sol";
import { IInvestment } from "./interfaces/IInvestment.sol";
import { IFund } from "./interfaces/IFund.sol";
import { Invoke } from "./Invoke.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";

/**
 * @title BaseIntegration
 * @author DFolio
 *
 * Abstract class that houses common Integration-related state and functions.
 */
abstract contract BaseIntegration is IInvestment {
    using PreciseUnitMath for uint256;
    using Invoke for IFund;

    /* ============ State Variables ============ */

    // Address of the controller
    IController public controller;

    /* ============ Modifiers ============ */

    modifier onlyManagerAndValidFund(IFund _fund) {
        require(isFundManager(_fund, msg.sender), "Must be the Fund manager");
        require(isFundValidAndInitialized(_setToken), "Must be a valid and initialized Fund");
        _;
    }

    modifier onlyFundManager(IFund _fund, address _caller) {
        require(isFundManager(_fund, _caller), "Must be the Fund manager");
        _;
    }

    modifier onlyValidAndInitializedFund(IFund _fund) {
        require(isFundValidAndInitialized(_fund), "Must be a valid and initialized Fund");
        _;
    }

    /**
     * Throws if the sender is not a funds's investment
     */
    modifier onlyIntegration(IIntegration _integration) {
        require(
            _integration.integrationStates(msg.sender) == IFund.IntegrationState.INITIALIZED,
            "Only the module can call"
        );

        require(
            controller.isIntegration(msg.sender),
            "Module must be enabled on controller"
        );
        _;
    }

    /**
     * Utilized during module initializations to check that the module is in pending state
     * and that the SetToken is valid
     */
    modifier onlyValidAndPendingFund(IFund _fund) {
        require(controller.isFund(address(_fund)), "Must be controller-enabled Fund");
        require(isFundPendingInitialization(_fund), "Must be pending initialization");
        _;
    }

    /* ============ Constructor ============ */

    /**
     * Set state variables and map asset pairs to their oracles
     *
     * @param _controller             Address of controller contract
     */
    constructor(IController _controller) public {
        controller = _controller;
    }

    /* ============ Internal Functions ============ */

    /**
     * Transfers tokens from an address (that has set allowance on the module).
     *
     * @param  _token          The address of the ERC20 token
     * @param  _from           The address to transfer from
     * @param  _to             The address to transfer to
     * @param  _quantity       The number of tokens to transfer
     */
    function transferFrom(IERC20 _token, address _from, address _to, uint256 _quantity) internal {
        ExplicitERC20.transferFrom(_token, _from, _to, _quantity);
    }

    /**
     * Gets the integration for the module with the passed in name. Validates that the address is not empty
     */
    function getAndValidateAdapter(string memory _integrationName) internal view returns(address) {
        bytes32 integrationHash = getNameHash(_integrationName);
        return getAndValidateAdapterWithHash(integrationHash);
    }

    /**
     * Gets the integration for the module with the passed in hash. Validates that the address is not empty
     */
    function getAndValidateAdapterWithHash(bytes32 _integrationHash) internal view returns(address) {
        address adapter = controller.getIntegrationRegistry().getIntegrationAdapterWithHash(
            address(this),
            _integrationHash
        );

        require(adapter != address(0), "Must be valid adapter");
        return adapter;
    }

    /**
     * Gets the total fee for this integration of the passed in index (fee % * quantity)
     */
    function getIntegrationFee(uint256 _feeIndex, uint256 _quantity) internal view returns(uint256) {
        uint256 feePercentage = controller.getIntegrationFee(address(this), _feeIndex);
        return _quantity.preciseMul(feePercentage);
    }

    /**
     * Pays the _feeQuantity from the _setToken denominated in _token to the protocol fee recipient
     */
    function payProtocolFeeFromFund(IFund _fund, address _token, uint256 _feeQuantity) internal {
        if (_feeQuantity > 0) {
            _fund.strictInvokeTransfer(_token, controller.feeRecipient(), _feeQuantity);
        }
    }

    /**
     * Returns true if the integration is in process of initialization on the fund
     */
    function isFundPendingInitialization(IFund _fund) internal view returns(bool) {
        return _fund.isPendingIntegration(address(this));
    }

    /**
     * Returns true if the address is the SetToken's manager
     */
    function isFundManager(IFund _fund, address _toCheck) internal view returns(bool) {
        return _fund.manager() == _toCheck;
    }

    /**
     * Returns true if Fund must be enabled on the controller
     * and module is registered on the SetToken
     */
    function isFundValidAndInitialized(IFund _fund) internal view returns(bool) {
        return controller.isFund(address(_fund)) &&
            _fund.isInitializedIntegration(address(this));
    }

    /**
     * Hashes the string and returns a bytes32 value
     */
    function getNameHash(string memory _name) internal pure returns(bytes32) {
        return keccak256(bytes(_name));
    }
}
