/*
    Copyright 2021 Babylon Finance.
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

import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

import {ITimelock} from '../interfaces/ITimelock.sol';

contract Timelock is ITimelock {
    using LowGasSafeMath for uint256;

    /* ============ Events ============ */

    event NewAdmin(address indexed newAdmin);
    event NewPendingAdmin(address indexed newPendingAdmin);
    event NewDelay(uint256 indexed newDelay);
    event CancelTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );
    event ExecuteTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );
    event QueueTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    uint256 public constant override GRACE_PERIOD = 14 days;
    uint256 public constant MINIMUM_DELAY = 2 days;
    uint256 public constant MAXIMUM_DELAY = 30 days;

    address public admin;
    address public pendingAdmin;
    uint256 public override delay;

    mapping(bytes32 => bool) public override queuedTransactions;

    /* ============ Functions ============ */

    /* ============ Constructor ============ */

    constructor(address admin_, uint256 delay_) {
        require(delay_ >= MINIMUM_DELAY, 'Timelock::constructor: Delay must exceed minimum delay.');
        require(delay_ <= MAXIMUM_DELAY, 'Timelock::setDelay: Delay must not exceed maximum delay.');

        admin = admin_;
        delay = delay_;
    }

    /* ============ Fallback ============ */

    receive() external payable {}

    /* ============ External Functions ============ */

    /* ===========  Token related Gov Functions ====== */

    function setDelay(uint256 delay_) external {
        require(msg.sender == address(this), 'Timelock::setDelay: Call must come from Timelock.');
        require(delay_ >= MINIMUM_DELAY, 'Timelock::setDelay: Delay must exceed minimum delay.');
        require(delay_ <= MAXIMUM_DELAY, 'Timelock::setDelay: Delay must not exceed maximum delay.');
        delay = delay_;

        emit NewDelay(delay);
    }

    function acceptAdmin() external override {
        require(msg.sender == pendingAdmin, 'Timelock::acceptAdmin: Call must come from pendingAdmin.');
        admin = msg.sender;
        pendingAdmin = address(0);

        emit NewAdmin(admin);
    }

    function setPendingAdmin(address pendingAdmin_) external {
        require(msg.sender == address(this), 'Timelock::setPendingAdmin: Call must come from Timelock.');
        pendingAdmin = pendingAdmin_;

        emit NewPendingAdmin(pendingAdmin);
    }

    function queueTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) external override returns (bytes32) {
        require(msg.sender == admin, 'Timelock::queueTransaction: Call must come from admin.');
        require(
            eta >= getBlockTimestamp().add(delay),
            'Timelock::queueTransaction: Estimated execution block must satisfy delay.'
        );

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, target, value, signature, data, eta);
        return txHash;
    }

    function cancelTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) external override {
        require(msg.sender == admin, 'Timelock::cancelTransaction: Call must come from admin.');

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, target, value, signature, data, eta);
    }

    function executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) external payable override returns (bytes memory) {
        require(msg.sender == admin, 'Timelock::executeTransaction: Call must come from admin.');

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], 'Transaction is not queued');
        require(getBlockTimestamp() >= eta, 'Transaction is too young');
        require(getBlockTimestamp() <= eta.add(GRACE_PERIOD), 'Transaction is stale');

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, 'Timelock::executeTransaction: Transaction execution reverted.');

        emit ExecuteTransaction(txHash, target, value, signature, data, eta);

        return returnData;
    }

    /* ============ Internal Only Function ============ */

    function getBlockTimestamp() internal view returns (uint256) {
        // solium-disable-next-line security/no-block-members
        return block.timestamp;
    }
}
