/*
    Copyright 2020 Babylon Finance

    Modified from (Set Protocol FundValuer)

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
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/SafeCast.sol";
import { SignedSafeMath } from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IWETH } from "./interfaces/external/weth/IWETH.sol";
import { IBabController } from "./interfaces/IBabController.sol";
import { IClosedFund } from "./interfaces/IClosedFund.sol";
import { IFundValuer } from "./interfaces/IFundValuer.sol";
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
contract ReservePool is ERC20, ReentrancyGuard {
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;

    /* ============ Events ============ */
    event ReservePoolDeposit(address indexed sender, uint amount, uint timestamp);
    event ReservePoolClaim(address indexed sender, uint tokenAmount, uint wethAmount, uint timestamp);

    /* ============ Modifiers ============ */


    /* ============ State Variables ============ */

    string constant NAME = "Babylon Reserve Token";
    string constant SYMBOL = "RBABL";

    uint256 constant MIN_DEPOSIT = 1e17; // Min Deposit

    // Instance of the Controller contract
    address public controller;
    address public constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    mapping(address => uint256) public communityTokenBalances; // Balances of tokens per community

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

    function getReservePoolValuation() public returns (uint256) {
      uint total = 0;
      address[] memory _communities = IBabController(controller).getFunds();
      for (uint i = 0; i < _communities.length; i++) {
        uint256 communityBalance = IClosedFund(_communities[i]).balanceOf(address(this));
        if (communityBalance > 0) {
          uint256 communityValuation = IFundValuer(IBabController(controller).getFundValuer()).calculateFundValuation(_communities[i], weth);
          total = total.add(communityValuation.preciseMul(communityBalance));
        }
      }
      return total.add(IWETH(weth).balanceOf(address(this)));
    }

    /**
     * Deposits ETH and obtains RBABL. The Babylon Finance Reserve Pool tokens
     *
     */
    function deposit() external payable nonReentrant {
      require(msg.value >= MIN_DEPOSIT, "Send at least 0.1 eth");
      _mint(msg.sender, msg.value);
      IWETH(weth).deposit{value: msg.value}();
      emit ReservePoolDeposit(msg.sender, msg.value, block.timestamp);
    }

    /**
     * Exchanges the reserve pool tokens for the underlying amount of weth.
     *
     * @param _amount               Quantity of the reserve token to exchange
     * @param _to                   Address to send component assets to
     */
    function claim(uint256 _amount, address payable _to) external nonReentrant {
      require(_amount < balanceOf(msg.sender), "Insufficient balance");
      _burn(msg.sender, _amount);
      uint ethAmount = _amount.preciseDiv(totalSupply()).preciseMul(getReservePoolValuation());
      require(IWETH(weth).balanceOf(address(this)) >= ethAmount, "Not enough liquidity in the reserve pool");
      IWETH(weth).withdraw(ethAmount);
      _to.transfer(ethAmount);
      emit ReservePoolClaim(msg.sender, _amount, ethAmount, block.timestamp);
    }

    /**
     * Exchanges the reserve pool tokens for the underlying amount of weth.
     *
     * @param _community               Community that the sender wants to sell tokens of
     * @param _amount                  Quantity of the community tokens that sender wants to sell
     */
    function sellTokensToLiquidityPool(address _community, uint256 _amount) external nonReentrant {
      require(IClosedFund(_community).balanceOf(msg.sender) >= _amount, "Sender does not have enough tokens");
      uint256 discount = IBabController(controller).protocolReservePoolDiscount();
      // Get valuation of the Fund with the quote asset as the reserve asset.
      uint256 fundValuation = IFundValuer(IBabController(controller).getFundValuer()).calculateFundValuation(_community, weth);
      uint256 amountValue = fundValuation.preciseMul(_amount);
      uint256 amountDiscounted = amountValue - amountValue.preciseMul(discount);
      require(IWETH(weth).balanceOf(address(this)) >= amountDiscounted, "There needs to be enough WETH");
      require(ERC20(_community).transferFrom(
          msg.sender,
          address(this),
          _amount
      ), "Failed transfer to reserve pool");
      require(IWETH(weth).transfer(msg.sender, amountDiscounted), "WETH transfer failed");
    }

    /**
     * Withdraws the principal and profits from the community using its participation tokens.
     *
     * @param _community                Address of the community contract
     * @param _amount                   Amount of the community tokens to redeem
     */
    function redeemETHFromCommunityTokens(address _community, uint256 _amount) external nonReentrant {
      require(msg.sender == IBabController(controller).owner(), "Only owner can call this");
      require(_amount > 0, "There needs to be tokens to redeem");
      require(IClosedFund(_community).active(), "Community must be active");
      // Get valuation of the Fund with the quote asset as the reserve asset.
      uint256 fundValuation = IFundValuer(IBabController(controller).getFundValuer()).calculateFundValuation(_community, weth);
      require(fundValuation > 0, "Fund must be worth something");
      uint minReceive = fundValuation.preciseMul(IClosedFund(_community).totalSupply()).preciseDiv(_amount);
      IClosedFund(_community).withdraw(_amount, minReceive.mul(98).div(100), msg.sender);
      IWETH(weth).deposit{value: address(this).balance}();
    }

}
