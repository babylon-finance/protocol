/*
    Copyright 2021 Babylon Finance

    Modified from (Set Protocol GardenValuer)

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

import 'hardhat/console.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IWETH} from './interfaces/external/weth/IWETH.sol';
import {IBabController} from './interfaces/IBabController.sol';
import {IRollingGarden} from './interfaces/IRollingGarden.sol';
import {IGardenValuer} from './interfaces/IGardenValuer.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';

/**
 * @title ReservePool
 * @author Babylon Finance
 *
 * Contract that holds the reserve pool of the protocol.
 * The reserve pool of the protocol is used to provide liquidity to garden depositors.
 * The reserve pool gets a discount for this liquidity provisioning.
 *
 */
contract ReservePool is ERC20, ReentrancyGuard, Ownable {
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;

    /* ============ Events ============ */
    event ReservePoolDeposit(address indexed sender, uint256 amount, uint256 timestamp);
    event ReservePoolClaim(address indexed sender, uint256 tokenAmount, uint256 wethAmount, uint256 timestamp);
    event MaxPercentageGardenOwnershipChanged(uint256 newMax, uint256 oldMax);

    /* ============ Modifiers ============ */

    /* ============ State Variables ============ */

    string constant NAME = 'Babylon Reserve Token';
    string constant SYMBOL = 'RBABL';

    uint256 constant MIN_DEPOSIT = 1e17; // Min Deposit
    uint256 constant LOCK_WINDOW = 7 days; // How long your deposit will be locked
    uint256 constant MAX_OWNERSHIP = 5e17; // 20% is the actual max ownership of the reserve pool allowed per garden
    uint256 constant MIN_NAV = 100 * 1e18; // Absolute min NAV of the garden in WETH. 500

    // Instance of the Controller contract
    address public controller;
    address public constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    mapping(address => uint256) public userTimelock; // Balances of timelock per user

    uint256 public maxPercentageGardenOwnership = 1e17; // 10% (0.01% = 1e14, 1% = 1e16)
    uint256 public minGardenNAV = 1e17; // 10% (0.01% = 1e14, 1% = 1e16)

    /* ============ Constructor ============ */

    /**
     * Set state variables and map asset pairs to their oracles
     *
     * @param _controller             Address of controller contract
     */
    constructor(address _controller) ERC20(NAME, SYMBOL) {
        controller = _controller;
    }

    /* ============ External Functions ============ */

    /**
     * Updates the max percentage garden ownership
     *
     * @param _newMax         New Max Percentage garden ownership
     */
    function editMaxPercentageGardenOwnership(uint256 _newMax) external {
        require(_newMax < MAX_OWNERSHIP, 'Must be < total Max');

        uint256 oldMax = maxPercentageGardenOwnership;

        maxPercentageGardenOwnership = _newMax;

        emit MaxPercentageGardenOwnershipChanged(maxPercentageGardenOwnership, oldMax);
    }

    /**
     * Updates the min garden NAV to enable Reserve Pool for a garden
     *
     * @param _newMinGardenNav         New Min Garden NAV
     */
    function editMinGardenNAV(uint256 _newMinGardenNav) external {
        require(_newMinGardenNav >= MIN_NAV, 'Must be > min nav');

        uint256 oldNAV = minGardenNAV;

        minGardenNAV = _newMinGardenNav;

        emit MaxPercentageGardenOwnershipChanged(minGardenNAV, oldNAV);
    }

    /**
     * Deposits ETH and obtains RBABL. The Babylon Finance Reserve Pool tokens
     *
     */
    function deposit() external payable nonReentrant {
        require(msg.value >= MIN_DEPOSIT, 'Send at least 0.1 eth');
        _mint(msg.sender, msg.value);
        IWETH(weth).deposit{value: msg.value}();
        userTimelock[msg.sender] = block.timestamp; // Window resets with every deposit
        emit ReservePoolDeposit(msg.sender, msg.value, block.timestamp);
    }

    /**
     * Exchanges the reserve pool tokens for the underlying amount of weth.
     *
     * @param _amount               Quantity of the reserve token to exchange
     * @param _to                   Address to send component assets to
     */
    function claim(uint256 _amount, address payable _to) external nonReentrant {
        require(_amount <= balanceOf(msg.sender), 'Insufficient balance');
        require(block.timestamp.sub(userTimelock[msg.sender]) > LOCK_WINDOW, 'The principal is still locked');
        uint256 ethAmount = _amount.preciseDiv(totalSupply()).preciseMul(getReservePoolValuation());
        require(IWETH(weth).balanceOf(address(this)) >= ethAmount, 'Not enough liquidity in the reserve pool');
        _burn(msg.sender, _amount);
        IWETH(weth).withdraw(ethAmount);
        _to.transfer(ethAmount);
        emit ReservePoolClaim(msg.sender, _amount, ethAmount, block.timestamp);
    }

    /**
     * Exchanges the reserve pool tokens for the underlying amount of weth.
     * Only a garden or the owner can call this
     * @param _garden               Garden that the sender wants to sell tokens of
     * @param _amount                  Quantity of the garden tokens that sender wants to sell
     */
    function sellTokensToLiquidityPool(address _garden, uint256 _amount) external nonReentrant returns (uint256) {
        require(IBabController(controller).isSystemContract(_garden), 'Only valid gardens');
        require(IRollingGarden(_garden).balanceOf(msg.sender) >= _amount, 'Sender does not have enough tokens');
        require(isReservePoolAllowedToBuy(_garden, _amount), 'Check if the buy is allowed');
        // TODO: Make dynamic
        uint256 discount = 1e17;
        // Get valuation of the Garden with the quote asset as the reserve asset.
        uint256 gardenValuation =
            IGardenValuer(IBabController(controller).getGardenValuer()).calculateGardenValuation(_garden, weth);
        uint256 amountValue = gardenValuation.preciseMul(_amount);
        uint256 amountDiscounted = amountValue - amountValue.preciseMul(discount);
        require(IWETH(weth).balanceOf(address(this)) >= amountDiscounted, 'There needs to be enough WETH');
        // Mints tokens to the reserve pool
        IRollingGarden(_garden).burnAssetsFromSenderAndMintToReserve(msg.sender, _amount);
        require(IWETH(weth).transfer(msg.sender, amountDiscounted), 'WETH transfer failed');
        return amountDiscounted;
    }

    /**
     * Withdraws the principal and profits from the garden using its participation tokens.
     * Only a keeper or owner can call this.
     * @param _garden                Address of the garden contract
     * @param _amount                   Amount of the garden tokens to redeem
     */
    function redeemETHFromGardenTokens(address _garden, uint256 _amount) external nonReentrant {
        bool isValidKeeper = IBabController(controller).isValidKeeper(msg.sender);
        IRollingGarden garden = IRollingGarden(_garden);
        require(
            isValidKeeper || msg.sender == IBabController(controller).owner(),
            'Only owner or keeper can call this'
        );
        require(_amount > 0, 'There needs to be tokens to redeem');
        require(garden.active(), 'Garden must be active');
        // Get valuation of the Garden with the quote asset as the reserve asset.
        uint256 gardenValuation =
            IGardenValuer(IBabController(controller).getGardenValuer()).calculateGardenValuation(_garden, weth);
        require(gardenValuation > 0, 'Garden must be worth something');
        // Check that the garden has normal liquidity
        uint256 minReceive = gardenValuation.preciseMul(garden.totalSupply()).preciseDiv(_amount);
        require(garden.canWithdrawEthAmount(minReceive), 'Not enough liquidity in the fund');
        uint256 rewards = address(this).balance;
        garden.withdraw(_amount, minReceive.mul(95).div(100), msg.sender);
        rewards = address(this).balance.sub(rewards);
        IWETH(weth).deposit{value: rewards}();
        // TODO: Create a new fee in protocol
        uint256 protocolFee = IBabController(controller).getProtocolWithdrawalGardenTokenFee().preciseMul(rewards);
        // Send to the treasury the protocol fee
        require(IWETH(weth).transfer(IBabController(controller).getTreasury(), protocolFee), 'Protocol fee failed');
    }

    receive() external payable {} // solium-disable-line quotes

    /* ============ Public View Functions ============ */

    function getReservePoolValuation() public view returns (uint256) {
        uint256 total = 0;
        address[] memory _gardens = IBabController(controller).getGardens();
        for (uint256 i = 0; i < _gardens.length; i++) {
            uint256 gardenBalance = IRollingGarden(_gardens[i]).balanceOf(address(this));
            if (gardenBalance > 0) {
                uint256 gardenValuation =
                    IGardenValuer(IBabController(controller).getGardenValuer()).calculateGardenValuation(
                        _gardens[i],
                        weth
                    );
                total = total.add(gardenValuation.preciseMul(gardenBalance));
            }
        }
        return total.add(IWETH(weth).balanceOf(address(this)));
    }

    /**
     * Returns whether or not the reserve pool can buy tokens of this garden
     *
     * @param _garden The garden to check
     * @param _newAmount The amount of garden tokens to buy
     */
    function isReservePoolAllowedToBuy(address _garden, uint256 _newAmount) public view returns (bool) {
        // TODO: Check only RollingGarden not ClosedGarden
        uint256 totalNav =
            IGardenValuer(IBabController(controller).getGardenValuer())
                .calculateGardenValuation(_garden, weth)
                .preciseMul(ERC20(_garden).totalSupply());
        if (totalNav < minGardenNAV) {
            return false;
        }
        uint256 newGardenTokensInReservePool = IRollingGarden(_garden).balanceOf(address(this)).add(_newAmount);
        if (newGardenTokensInReservePool.preciseDiv(ERC20(_garden).totalSupply()) > maxPercentageGardenOwnership) {
            return false;
        }
        return true;
    }
}
