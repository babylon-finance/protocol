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
import { IFund } from "./IFund.sol";


/**
 * @title IFund
 * @author DFolio
 *
 * Interface for operating with SetTokens.
 */
interface IClosedFund is IERC20, IFund {

    function initialize(
        uint256 _managerDepositFee,
        uint256 _managerWithdrawalFee,
        uint256 _managerPerformanceFee,
        uint256 _premiumPercentage,
        uint256 _minFundTokenSupply,
        address _managerDepositHook,
        address _managerWithdrawalHook
    ) external;

    function deposit(
        uint256 _reserveAssetQuantity,
        uint256 _minFundTokenReceiveQuantity,
        address _to
    ) external payable;

    function withdraw(
        uint256 _fundTokenQuantity,
        uint256 _minReserveReceiveQuantity,
        address payable _to
    ) external;

    function editPremium(uint256 _premiumPercentage) external;
    function editManagerDepositFee(uint256 _managerDepositFee) external;
    function editManagerWithdrawalFee(uint256 _managerWithdrawalFee) external;
    function editManagerPerformanceFee(uint256 _managerPerformanceFee) external;
    function setDepositLimit(uint limit) external;
    function setFundEndDate(uint256 _endsTimestamp) external;

    function getPremiumPercentage() external view returns (uint256);
    function getDepositManagerFee() external view returns (uint256);
    function getWithdrawalManagerFee() external view returns (uint256);
    function getManagerPerformanceFee() external view returns (uint256);
    function getExpectedFundTokensDepositdQuantity(
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    ) external view returns (uint256);
    function getExpectedReserveWithdrawalQuantity(
        address _reserveAsset,
        uint256 _fundTokenQuantity
    ) external view returns (uint256);
    function isDepositValid(
        address _reserveAsset,
        uint256 _reserveAssetQuantity
    ) external view returns (bool);
    function isWithdrawalValid(
        address _reserveAsset,
        uint256 _fundTokenQuantity
    ) external view returns (bool);

}
