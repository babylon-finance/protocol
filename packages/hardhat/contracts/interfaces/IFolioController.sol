/*
    Copyright 2020 DFolio.

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

/**
 * @title IFolioController
 * @author DFolio
 *
 * Interface for interacting with FolioController
 */

interface IFolioController {

    /* ============ Functions ============ */

    function addFund(address _fund) external;
    function feeRecipient() external view returns(address);
    function getModuleFee(address _module, uint256 _feeType) external view returns(uint256);
    function isFund(address _fund) external view returns(bool);
    function isSystemContract(address _contractAddress) external view returns (bool);
    function isValidIntegration(string memory _name) external view returns (bool);

    // TODO: FILL
}
