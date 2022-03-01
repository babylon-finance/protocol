// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;

import {PriceOracle} from '../PriceOracle.sol';
import {ITokenIdentifier} from '../interfaces/ITokenIdentifier.sol';
import {IBabController} from '../interfaces/IBabController.sol';

/**
 * @title PriceOracle
 * @author Babylon Finance Protocol
 *
 * Uses Uniswap V3 to get a price of a token pair
 */
contract RevertOracle is PriceOracle {
    constructor(ITokenIdentifier _tokenIdentifier, IBabController _controller)
        PriceOracle(_tokenIdentifier, _controller)
    {}

    function getPrice(
        address, /* _tokenIn */
        address /* _tokenOut */
    ) public pure override returns (uint256) {
        require(false, 'Price not found');
        return 0;
    }
}
