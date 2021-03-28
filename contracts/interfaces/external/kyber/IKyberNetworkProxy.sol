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

pragma solidity 0.7.4;

interface IKyberNetworkProxy {
    function getExpectedRate(
        address _src,
        address _dest,
        uint256 _srcQty
    ) external view returns (uint256, uint256);

    function trade(
        address _src,
        uint256 _srcAmount,
        address _dest,
        address _destAddress,
        uint256 _maxDestAmount,
        uint256 _minConversionRate,
        address _referalFeeAddress
    ) external payable returns (uint256);
}
