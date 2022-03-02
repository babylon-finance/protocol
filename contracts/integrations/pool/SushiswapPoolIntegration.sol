// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;
pragma abicoder v1;

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
