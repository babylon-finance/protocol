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

import {IIntegration} from './IIntegration.sol';

/**
 * @title ITrade
 * @author Babylon Finance
 *
 * Interface for trading protocol integrations
 */
interface ITradeIntegration is IIntegration {
    function trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) external;

    function getConversionRates(
        address _sourceToken,
        address _destinationToken,
        uint256 _sourceQuantity
    ) external returns (uint256, uint256);
}
