/*
    Copyright 2020 Babylon Finance.

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

import 'hardhat/console.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IIntegration} from '../interfaces/IIntegration.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';

/**
 * @title BaseIntegration
 * @author Babylon Finance
 *
 * Abstract class that houses common Integration-related state and functions.
 */
abstract contract BaseIntegration {
    using SafeCast for int256;
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for uint256;

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyProtocol() {
        require(msg.sender == controller, 'Only controller can call this');
        _;
    }

    modifier onlyIdea() {
        IStrategy strategy = IStrategy(msg.sender);
        address garden = strategy.garden();
        require(IBabController(controller).isSystemContract(garden), 'Only a garden can call this');
        require(IGarden(garden).isStrategy(msg.sender), 'Sender myst be an investment strategy from the garden');
        _;
    }

    /* ============ State Variables ============ */

    // Address of the controller
    address public controller;
    // Wrapped ETH address
    address public immutable weth;
    // Name of the integration
    string public name;
    mapping(address => bool) public initializedByGarden;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     */

    constructor(
        string memory _name,
        address _weth,
        address _controller
    ) {
        require(_controller != address(0), 'Controller must be non-zero address.');
        name = _name;
        controller = _controller;
        weth = _weth;
    }

    /* ============ External Functions ============ */

    /**
     * Returns the name of the integration
     */
    function getName() external view returns (string memory) {
        return name;
    }

    /* ============ Internal Functions ============ */

    /**
     * Updates the position in the garden with the new units
     *
     * @param _strategy           Address of the investment strategy
     * @param _component                Address of the ERC20
     * @param _deltaOperation           Delta balance of the operation
     */
    function _updateStrategyPosition(
        address _strategy,
        address _component,
        int256 _deltaOperation,
        uint8 _subpositionStatus
    )
        internal
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 _newTotal = IStrategy(_strategy).getPositionBalance(_component).add(_deltaOperation).toUint256();
        return
            IStrategy(_strategy).calculateAndEditPosition(_component, _newTotal, _deltaOperation, _subpositionStatus);
    }

    /**
     * Transfers tokens from an address (that has set allowance on the module).
     *
     * @param  _token          The address of the ERC20 token
     * @param  _from           The address to transfer from
     * @param  _to             The address to transfer to
     * @param  _quantity       The number of tokens to transfer
     */
    function transferFrom(
        ERC20 _token,
        address _from,
        address _to,
        uint256 _quantity
    ) internal {
        require(ERC20(_token).transferFrom(_from, _to, _quantity), 'Integration transfer failed');
    }

    /**
     * Gets the total fee for this integration of the passed in index (fee % * quantity)
     */
    function getIntegrationFee(
        uint256, /* _feeIndex */
        uint256 _quantity
    ) internal view returns (uint256) {
        uint256 feePercentage = IBabController(controller).getIntegrationFee(address(this));
        return _quantity.preciseMul(feePercentage);
    }

    /**
     * Pays the _feeQuantity from the garden denominated in _token to the protocol fee recipient
     */
    function payProtocolFeeFromIdea(
        address _strategy,
        address _token,
        uint256 _feeQuantity
    ) internal {
        if (_feeQuantity > 0) {
            ERC20(_token).transferFrom(_strategy, IBabController(controller).getTreasury(), _feeQuantity);
        }
    }

    /**
     * Retrieve fee from controller and calculate total protocol fee and send from strategy to protocol recipient
     *
     * @param _strategy                           Address of the strategy
     * @param _token                              Address of the token to pay it with
     * @param _exchangedQuantity                  Amount of reserve asset that the integration handled
     * @return uint256                            Amount of receive token taken as protocol fee
     */
    function _accrueProtocolFee(
        address _strategy,
        address _token,
        uint256 _exchangedQuantity
    ) internal returns (uint256) {
        uint256 protocolFeeTotal = getIntegrationFee(0, _exchangedQuantity);

        payProtocolFeeFromIdea(_strategy, _token, protocolFeeTotal);

        return protocolFeeTotal;
    }

    /**
      Normalize all the amounts of all tokens so all can be called with 10^18.
      e.g Call functions like borrow, supply with parseEther
    */
    function normalizeAmountWithDecimals(address _asset, uint256 _amount) internal view returns (uint256) {
        // USDC and USDT have only 6 decimals
        uint256 newAmount = _amount;
        // TODO: try/catch
        uint8 decimalsAsset = ERC20(_asset).decimals();
        if (decimalsAsset < 18) {
            newAmount = _amount.div(10**(18 - decimalsAsset));
        }
        return newAmount;
    }
}
