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

    enum ModuleState {
        NONE,
        PENDING,
        INITIALIZED
    }

    /* ============ Structs ============ */
    /**
     * The base definition of a SetToken Position
     *
     * @param component           Address of token in the Position
     * @param module              If not in default state, the address of associated module
     * @param unit                Each unit is the # of components per 10^18 of a SetToken
     * @param positionState       Position ENUM. Default is 0; External is 1
     * @param data                Arbitrary data
     */
    struct Position {
        address component;
        address module;
        int256 unit;
        uint8 positionState;
        bytes data;
    }

    /**
     * A struct that stores a component's cash position details and external positions
     * This data structure allows O(1) access to a component's cash position units and
     * virtual units.
     *
     * @param virtualUnit               Virtual value of a component's DEFAULT position. Stored as virtual for efficiency
     *                                  updating all units at once via the position multiplier. Virtual units are achieved
     *                                  by dividing a "real" value by the "positionMultiplier"
     * @param componentIndex
     * @param externalPositionModules   List of external modules attached to each external position. Each module
     *                                  maps to an external position
     * @param externalPositions         Mapping of module => ExternalPosition struct for a given component
     */
    struct ComponentPosition {
      int256 virtualUnit;
      address[] externalPositionModules;
      mapping(address => ExternalPosition) externalPositions;
    }

    /**
     * A struct that stores a component's external position details including virtual unit and any
     * auxiliary data.
     *
     * @param virtualUnit       Virtual value of a component's EXTERNAL position.
     * @param data              Arbitrary data
     */
    struct ExternalPosition {
      int256 virtualUnit;
      bytes data;
    }


    /* ============ Functions ============ */

    function invoke(address _target, uint256 _value, bytes calldata _data) external returns(bytes memory);
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
    function integrationStates(address _module) external view returns (ModuleState);
    function getIntegrations() external view returns (address[] memory);

    function getDefaultPositionRealUnit(address _component) external view returns(int256);
    function getInvestments() external view returns(address[] memory);
    function isInvestment(address _investment) external view returns(bool);

    function positionMultiplier() external view returns (int256);
    // function getPositions() external view returns (Position[] memory);
    function getTotalInvestmentRealUnits(address _component) external view returns(int256);

    function isInitializedIntegration(address _integration) external view returns(bool);
    function isPendingIntegration(address _integration) external view returns(bool);
}
