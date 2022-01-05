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
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {IWETH} from '../interfaces/external/weth/IWETH.sol';
import {IHypervisor} from '../interfaces/IHypervisor.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

contract Assistant is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /* ============ Events ============ */
    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyGovernanceOrEmergency {
        IBabController controller = IBabController(0xD4a5b5fcB561dAF3aDF86F8477555B92FBa43b5F);
        require(
            msg.sender == controller.owner() || msg.sender == controller.EMERGENCY_OWNER(),
            'Not enough privileges'
        );
        _;
    }

    /* ============ State Variables ============ */
    /* ============ Constants ============ */

    /* ============ Constructor ============ */

    function initialize() public {
        OwnableUpgradeable.__Ownable_init();
    }

    /* ============ External Functions ============ */
    function setupFusePool() external onlyGovernanceOrEmergency {
        IERC20 BABL = IERC20(0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74);
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address treasury = 0xD7AAf4676F0F52993cb33aD36784BF970f0E1259;
        ISwapRouter swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        uint256 daiAmount = 90000e18; // 90k
        uint256 bablAmount = 2000e18; // 2k
        // 1. Change all ETH to WETH
        IWETH(WETH9).deposit{value: address(this).balance}();

        // Approve the router to spend DAI.
        TransferHelper.safeApprove(DAI, address(swapRouter), daiAmount);
        // Swap all DAI for WETH in univ3
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: DAI,
                tokenOut: WETH9,
                fee: 500, // 0.05%
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: daiAmount, //90k DAI
                amountOutMinimum: 22e18, //24 ETH out min
                sqrtPriceLimitX96: 0
            });
        // 2. The call to `exactInputSingle` executes the swap.
        uint256 amountOut = swapRouter.exactInputSingle(params);
        require(amountOut >= 22e18);
        uint256 ethAmount = 655e17; // 65.5 ETH
        //3. Fund new hypervisor on visor
        IHypervisor visor = IHypervisor(0x5e6c481dE496554b66657Dd1CA1F70C61cf11660);
        BABL.safeApprove(address(visor), bablAmount);
        IERC20(WETH9).safeApprove(address(visor), ethAmount);
        uint256 shares = visor.deposit(ethAmount, bablAmount, treasury);
        require(shares == visor.balanceOf(treasury) && visor.balanceOf(treasury) > 0, 'Not enough lp tokens');

        // 4. Send remaining WETH back to the treasury
        IERC20(WETH9).safeTransferFrom(address(this), treasury, IERC20(WETH9).balanceOf(address(this)));
    }

    /* ============ External Getter Functions ============ */
    /* ============ Internal Only Function ============ */

    // Can receive ETH
    // solhint-disable-next-line
    receive() external payable {}
}
