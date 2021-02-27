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

    /* ============ Structs ============ */
    struct Contributor {
        uint256 totalDeposit; //wei
        uint256 tokensReceived;
        uint256 timestamp;
    }

    struct SubPosition {
      address integration;
      int256 balance;
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

    function setActive() external;
    function setDisabled() external;

    function active() external view returns (bool);
    function controller() external view returns (address);
    function creator() external view returns (address);
    function fundEndsBy() external view returns (uint256);
    function fundIdeas() external view returns (address);
    function getContributor(address _contributor) external view returns (uint256, uint256, uint256);
    function getIntegrations() external view returns (address[] memory);
    function getReserveAsset() external view returns (address);
    function hasIntegration(address _integration) external view returns (bool);
    function isValidIntegration(address _integration) external returns (bool);
    function name() external view returns (string memory);
    function totalContributors() external view returns (uint256);
    function totalFundsDeposited() external view returns (uint256);
    function weth() external view returns (address);

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
        int256 _deltaBalance,
        uint8 _subpositionStatus
    )
      external
      returns (
          uint256,
          uint256,
          uint256
      );

    function tradeFromInvestmentIdea(
      string memory _integrationName,
      address _sendToken,
      uint256 _sendQuantity,
      address _receiveToken,
      uint256 _minReceiveQuantity,
      bytes memory _data) external;

    function callIntegration(address _integration, uint256 _value, bytes calldata _data,
        address[] memory _tokensNeeded,
        uint256[] memory _tokenAmountsNeeded) external returns (bytes memory _returnValue);
    function invokeApprove(address _spender, address _asset, uint256 _quantity) external;
    function invokeFromIntegration(
      address _target,
      uint256 _value,
      bytes calldata _data
    ) external returns (bytes memory _returnValue);
}
