/*
    Copyright 2020 Babylon Finance

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

/**
 * @title IFund
 * @author Babylon Finance
 *
 * Interface for operating with SetTokens.
 */
interface IFund is IERC20 {

    /* ============ Enums ============ */

    enum IntegrationState {
        NONE,
        PENDING,
        INITIALIZED
    }

    /* ============ Structs ============ */

    struct SubPosition {
      address integration;
      uint256 balance;
      uint8 status;
    }

    /**
     * A struct that stores a component's cash position details and external positions
     * This data structure allows O(1) access to a component's cash position units and
     * virtual units.
     *
     * @param component           Address of token in the Position
     * @param balance                Balance of this component
     * @param enteredAt           Timestamp when this position was entered
     * @param exitedAt            Timestamp when this position was exited
     * @param updatedAt           Timestamp when this position was updated
     */
    struct Position {
      address component;
      uint8 positionState;
      int256 balance;
      SubPosition[] subpositions;
      uint8 subpositionsCount;
      uint256 enteredAt;
      uint256 exitedAt;
      uint256[] updatedAt;
    }


    /* ============ Functions ============ */

    function addIntegration(address _integration) external;
    function removeIntegration(address _integration) external;
    function initializeIntegration() external;

    function setActive() external;
    function setDisabled() external;

    function controller() external view returns (address);
    function creator() external view returns (address);
    function active() external view returns (bool);
    function integrationStates(address _integration) external view returns (IntegrationState);
    function getIntegrations() external view returns (address[] memory);

    function isPosition(address _component) external view returns (bool);
    function getPositionCount() external view returns (uint256);
    function getPositions() external view returns (address[] memory);
    function hasSufficientBalance(address _component, uint256 _balance)
        external
        view
        returns (bool);
    function getPositionBalance(address _component) external view returns(int256);
    function calculateAndEditPosition(
        address _component,
        uint256 _newBalance,
        uint256 _deltaBalance,
        uint8 _subpositionStatus
    )
      external
      returns (
          uint256,
          uint256,
          uint256
      );

    function callIntegration(address _integration, uint256 _value, bytes calldata _data) external returns (bytes memory _returnValue);
    function invokeApprove(address _spender, address _asset, uint256 _quantity) external;
    function invokeFromIntegration(
      address _target,
      uint256 _value,
      bytes calldata _data
    ) external returns (bytes memory _returnValue);

    function isInitializedIntegration(address _integration) external view returns(bool);
    function isPendingIntegration(address _integration) external view returns(bool);
}
