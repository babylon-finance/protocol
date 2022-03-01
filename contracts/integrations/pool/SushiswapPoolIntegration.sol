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

pragma solidity 0.8.9;

import {UniswapPoolIntegration} from './UniswapPoolIntegration.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

/**
 * @title SushiswapPoolIntegration
 * @author Babylon Finance Protocol
 *
 * Sushiswap Protocol pool integration
 */
contract SushiswapPoolIntegration is UniswapPoolIntegration {
    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _sushiswapRouterAddress         Address of Sushiswap router
     */
    constructor(IBabController _controller, address _sushiswapRouterAddress)
        UniswapPoolIntegration(_controller, _sushiswapRouterAddress)
    {
        name = 'sushiswap_pool';
    }
}
