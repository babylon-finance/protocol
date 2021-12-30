/*
    Copyright 2021 Babylon Finance

    Modified from (Set Protocol IPriceOracle)

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

/**
 * @title IPriceOracle
 * @author Babylon Finance
 *
 * Interface for interacting with PriceOracle
 */
interface ITokenIdentifier {
    /* ============ Functions ============ */

    function identifyTokens(address _tokenIn, address _tokenOut)
        external
        view
        returns (
            uint8,
            uint8,
            address,
            address
        );

    function overrideYearnVault(address _vault, bool _value) external;

    function overrideSynth(address _synth, bool _value) external;

    function overrideCreamPair(address _creamToken, address _underlying) external;

    function overrideAavePair(address _aaveToken, address _underlying) external;

    function overrideCompoundpair(address _cToken, address _underlying) external;
}
