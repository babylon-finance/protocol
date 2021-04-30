/*
    Copyright 2021 Babylon Finance

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

import {IGarden} from './IGarden.sol';
import {IStrategy} from './IStrategy.sol';

/**
 * @title IOperation
 * @author Babylon Finance
 *
 * Interface for an strategy operation
 */
interface IOperation {
    function validateOperation(
        bytes32 _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external view;

    function executeOperation(
        address _asset,
        uint256 _capital,
        bytes32 _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external returns (address, uint256);

    function exitOperation(
        uint256 _percentage,
        bytes32 _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external;

    function getNAV(
        bytes32 _data,
        IGarden _garden,
        IStrategy _strategy,
        address _integration
    ) external view returns (uint256);

    function getName() external view returns (string memory);
}
