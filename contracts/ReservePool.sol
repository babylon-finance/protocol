/*
    Copyright 2020 Babylon Finance

    Modified from (Set Protocol CommunityValuer)

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

import "hardhat/console.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IWETH } from "./interfaces/external/weth/IWETH.sol";
import { IBabController } from "./interfaces/IBabController.sol";
import { IRollingCommunity } from "./interfaces/IRollingCommunity.sol";
import { ICommunityValuer } from "./interfaces/ICommunityValuer.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { PreciseUnitMath } from "./lib/PreciseUnitMath.sol";

/**
 * @title ReservePool
 * @author Babylon Finance
 *
 * Contract that holds the reserve pool of the protocol.
 * The reserve pool of the protocol is used to provide liquidity to community depositors.
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
    event ReservePoolDeposit(address indexed sender, uint amount, uint timestamp);
    event ReservePoolClaim(address indexed sender, uint tokenAmount, uint wethAmount, uint timestamp);
    event MaxPercentageCommunityOwnershipChanged(uint newMax, uint oldMax);

    /* ============ Modifiers ============ */


    /* ============ State Variables ============ */

    string constant NAME = "Babylon Reserve Token";
    string constant SYMBOL = "RBABL";

    uint256 constant MIN_DEPOSIT = 1e17; // Min Deposit
    uint256 constant LOCK_WINDOW = 7 days; // How long your deposit will be locked
    uint256 constant MAX_OWNERSHIP = 5e17; // 20% is the actual max ownership of the reserve pool allowed per community
    uint256 constant MIN_NAV = 100 * 1e18; // Absolute min NAV of the community in WETH. 500

    // Instance of the Controller contract
    address public controller;
    address public constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    mapping(address => uint256) public userTimelock; // Balances of timelock per user

    uint256 public maxPercentageCommunityOwnership = 1e17; // 10% (0.01% = 1e14, 1% = 1e16)
    uint256 public minCommunityNAV = 1e17; // 10% (0.01% = 1e14, 1% = 1e16)

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
     * Updates the max percentage community ownership
     *
     * @param _newMax         New Max Percentage community ownership
     */
    function editMaxPercentageCommunityOwnership(uint256 _newMax) external {
      require(_newMax < MAX_OWNERSHIP, "Must be < total Max");

      uint256 oldMax = maxPercentageCommunityOwnership;

      maxPercentageCommunityOwnership = _newMax;

      emit MaxPercentageCommunityOwnershipChanged(maxPercentageCommunityOwnership, oldMax);
    }

    /**
     * Updates the min community NAV to enable Reserve Pool for a community
     *
     * @param _newMinCommunityNav         New Min Community NAV
     */
    function editMinCommunityNAV(uint256 _newMinCommunityNav) external {
      require(_newMinCommunityNav >= MIN_NAV, "Must be > min nav");

      uint256 oldNAV = minCommunityNAV;

      minCommunityNAV = _newMinCommunityNav;

      emit MaxPercentageCommunityOwnershipChanged(minCommunityNAV, oldNAV);
    }

    /**
     * Deposits ETH and obtains RBABL. The Babylon Finance Reserve Pool tokens
     *
     */
    function deposit() external payable nonReentrant {
      require(msg.value >= MIN_DEPOSIT, "Send at least 0.1 eth");
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
      require(_amount <= balanceOf(msg.sender), "Insufficient balance");
      require(block.timestamp.sub(userTimelock[msg.sender]) > LOCK_WINDOW, "The principal is still locked");
      uint ethAmount = _amount.preciseDiv(totalSupply()).preciseMul(getReservePoolValuation());
      require(IWETH(weth).balanceOf(address(this)) >= ethAmount, "Not enough liquidity in the reserve pool");
      _burn(msg.sender, _amount);
      IWETH(weth).withdraw(ethAmount);
      _to.transfer(ethAmount);
      emit ReservePoolClaim(msg.sender, _amount, ethAmount, block.timestamp);
    }

    /**
     * Exchanges the reserve pool tokens for the underlying amount of weth.
     * Only a community or the owner can call this
     * @param _community               Community that the sender wants to sell tokens of
     * @param _amount                  Quantity of the community tokens that sender wants to sell
     */
    function sellTokensToLiquidityPool(address _community, uint256 _amount) external nonReentrant returns (uint256) {
      require(IBabController(controller).isSystemContract(_community), "Only valid communities");
      require(IRollingCommunity(_community).balanceOf(msg.sender) >= _amount, "Sender does not have enough tokens");
      require(isReservePoolAllowedToBuy(_community, _amount), "Check if the buy is allowed");
      // TODO: Make dynamic
      uint256 discount = 1e17;
      // Get valuation of the Community with the quote asset as the reserve asset.
      uint256 communityValuation = ICommunityValuer(IBabController(controller).getCommunityValuer()).calculateCommunityValuation(_community, weth);
      uint256 amountValue = communityValuation.preciseMul(_amount);
      uint256 amountDiscounted = amountValue - amountValue.preciseMul(discount);
      require(IWETH(weth).balanceOf(address(this)) >= amountDiscounted, "There needs to be enough WETH");
      // Mints tokens to the reserve pool
      IRollingCommunity(_community).burnAssetsFromSenderAndMintToReserve(msg.sender, _amount);
      require(IWETH(weth).transfer(msg.sender, amountDiscounted), "WETH transfer failed");
      return amountDiscounted;
    }

    /**
     * Withdraws the principal and profits from the community using its participation tokens.
     * Only a keeper or owner can call this.
     * @param _community                Address of the community contract
     * @param _amount                   Amount of the community tokens to redeem
     */
    function redeemETHFromCommunityTokens(address _community, uint256 _amount) external nonReentrant {
      bool isValidKeeper = IBabController(controller).isValidKeeper(msg.sender);
      IRollingCommunity community = IRollingCommunity(_community);
      require(isValidKeeper || msg.sender == IBabController(controller).owner(), "Only owner can call this");
      require(_amount > 0, "There needs to be tokens to redeem");
      require(community.active(), "Community must be active");
      // Get valuation of the Community with the quote asset as the reserve asset.
      uint256 communityValuation = ICommunityValuer(IBabController(controller).getCommunityValuer()).calculateCommunityValuation(_community, weth);
      require(communityValuation > 0, "Community must be worth something");
      // Check that the community has normal liquidity
      uint minReceive = communityValuation.preciseMul(community.totalSupply()).preciseDiv(_amount);
      require(community.canWithdrawEthAmount(minReceive), "Not enough liquidity in the fund");
      uint rewards = address(this).balance;
      community.withdraw(_amount, minReceive.mul(95).div(100), msg.sender);
      rewards = address(this).balance.sub(rewards);
      IWETH(weth).deposit{value: rewards}();
      // TODO: Create a new fee in protocol
      uint256 protocolFee = IBabController(controller).getProtocolWithdrawalCommunityTokenFee().preciseMul(rewards);
      // Send to the treasury the protocol fee
      require(IWETH(weth).transfer(
          IBabController(controller).getTreasury(),
          protocolFee
      ), "Protocol fee failed");
    }

    receive() external payable {} // solium-disable-line quotes

    /* ============ Public View Functions ============ */

    function getReservePoolValuation() public view returns (uint256) {
      uint total = 0;
      address[] memory _communities = IBabController(controller).getCommunities();
      for (uint i = 0; i < _communities.length; i++) {
        uint256 communityBalance = IRollingCommunity(_communities[i]).balanceOf(address(this));
        if (communityBalance > 0) {
          uint256 communityValuation = ICommunityValuer(IBabController(controller).getCommunityValuer()).calculateCommunityValuation(_communities[i], weth);
          total = total.add(communityValuation.preciseMul(communityBalance));
        }
      }
      return total.add(IWETH(weth).balanceOf(address(this)));
    }

    /**
     * Returns whether or not the reserve pool can buy tokens of this community
     *
     * @param _community The community to check
     * @param _newAmount The amount of community tokens to buy
    */
    function isReservePoolAllowedToBuy(address _community, uint256 _newAmount) public view returns (bool) {
      // TODO: Check only RollingCommunity not ClosedCommunity
      uint256 totalNav = ICommunityValuer(IBabController(controller).getCommunityValuer()).calculateCommunityValuation(_community, weth).preciseMul(ERC20(_community).totalSupply());
      if (totalNav < minCommunityNAV) {
        return false;
      }
      uint256 newCommunityTokensInReservePool = IRollingCommunity(_community).balanceOf(address(this)).add(_newAmount);
      if (newCommunityTokensInReservePool.preciseDiv(ERC20(_community).totalSupply()) > maxPercentageCommunityOwnership) {
        return false;
      }
      return true;
    }
}
