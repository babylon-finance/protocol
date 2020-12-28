/*
    Copyright 2020 DFolio

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
 * @author DFolio
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
    /**
     * A struct that stores a component's cash position details and external positions
     * This data structure allows O(1) access to a component's cash position units and
     * virtual units.
     *
     * @param component           Address of token in the Position
     * @param integration         If not in default state, the address of associated module
     * @param positionState       Position ENUM. Default is 0; External is 1
     * @param unit                Each unit is the # of components per 10^18 of a SetToken
     * @param virtualUnit         Virtual value of a component's DEFAULT position. Stored as virtual for efficiency
     *                            updating all units at once via the position multiplier. Virtual units are achieved
     *                            by dividing a "real" value by the "positionMultiplier"
     */
    struct Position {
      address component;
      address integration;
      uint8 positionState;
      int256 unit;
      int256 virtualUnit;
      uint256 enteredAt;
      uint256 exitedAt;
      uint256[] updatedAt;
      bytes data;
    }


    /* ============ Functions ============ */

    function addInvestment(address _investment) external;
    function removeInvestment(address _investment) external;
    function editInvestmentUnit(address _investment, int256 _realUnit) external;
    function editPositionMultiplier(int256 _newMultiplier) external;

    function mint(address _account, uint256 _quantity) external;
    function burn(address _account, uint256 _quantity) external;

    function addIntegration(address _integration) external;
    function removeIntegration(address _integration) external;
    function initializeIntegration() external;

    function setActive(bool _active) external;
    function setManager(address _manager) external;

    function manager() external view returns (address);
    function active() external view returns (bool);
    function integrationStates(address _integration) external view returns (IntegrationState);
    function getIntegrations() external view returns (address[] memory);

    function getDefaultPositionRealUnit(address _component) external view returns(int256);
    function getTotalPositionRealUnits(address _component) external view returns(int256);
    function calculateAndEditPosition(address _component, uint256 _componentPreviousBalance)
        external returns (uint256, uint256, uint256);
    function getPositions() external view returns(address[] memory);
    function isPosition(address _position) external view returns(bool);

    function positionMultiplier() external view returns (int256);
    // function getPositions() external view returns (Position[] memory);
    function getTotalInvestmentRealUnits(address _component) external view returns(int256);

    function isInitializedIntegration(address _integration) external view returns(bool);
    function isPendingIntegration(address _integration) external view returns(bool);
}
