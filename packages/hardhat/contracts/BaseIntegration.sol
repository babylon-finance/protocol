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

pragma solidity 0.7.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFolioController } from "./interfaces/IFolioController.sol";
import { IIntegration } from "./interfaces/IIntegration.sol";
import { IWETH } from "./interfaces/external/weth/IWETH.sol";
import { IFund } from "./interfaces/IFund.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";

/**
 * @title BaseIntegration
 * @author DFolio
 *
 * Abstract class that houses common Integration-related state and functions.
 */
abstract contract BaseIntegration is IIntegration {
    using PreciseUnitMath for uint256;

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyProtocol() {
      require(msg.sender == controller, "Only controller can call this");
      _;
    }


    /* ============ State Variables ============ */

    // Address of the controller
    IFolioController public controller;
    // Wrapped ETH address
    IWETH public immutable weth;
    mapping(address => bool) public initializedByFund;
    bool initialized;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     */

    constructor(IWETH _weth, IFolioController _controller) public {
      require(_controller != address(0), "Controller must be non-zero address.");
      controller = _controller;
      weth = _weth;
      initialized = false;
    }

    /* ============ External Functions ============ */

    /**
     * Initializes the integration.
     * @param _fund addres of the fund
     */
    function initialize(address _fund) virtual public {
      require(!initializedByFund[_fund], "integration has already been initialized");
      IFund(_fund).initializeIntegration();
      initializedByFund[_fund] = true;
    }

    /**
     * Updates the position in the fund with the new units
     *
     * @param _fund                     Address of the fund
     * @param _component                Address of the ERC20
     * @param _newUnit                  New unit of the fund position
     */
    function updateFundPosition(address _fund, address _component, int256 _newUnit) external {
      IFund(_fund).calculateAndEditPosition(_fund, _component, _newUnit);
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
        IERC20(_token).transferFrom(_from, _to, _quantity);
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
    function payProtocolFeeFromFund(address _fund, address _token, uint256 _feeQuantity) internal {
        if (_feeQuantity > 0) {
          IERC20(_token).transferFrom(_fund, controller.feeRecipient(), _feeQuantity);
        }
    }

    /**
     * Returns true if the integration is in process of initialization on the fund
     */
    function isFundPendingInitialization(address _fund) internal view returns(bool) {
        return _fund.isPendingIntegration(address(this));
    }

    /**
     * Returns true if the address is the SetToken's manager
     */
    function isFundManager(address _fund, address _toCheck) internal view returns(bool) {
        return _fund.manager() == _toCheck;
    }

    /**
     * Returns true if Fund must be enabled on the controller
     * and module is registered on the SetToken
     */
    function isFundValidAndInitialized(address _fund) internal view returns(bool) {
        return controller.isFund(address(_fund)) &&
            _fund.isInitializedIntegration(address(this));
    }

}
