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

import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IHypervisor} from './interfaces/IHypervisor.sol';
import {IBabController} from './interfaces/IBabController.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IWETH} from './interfaces/external/weth/IWETH.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {IMasterSwapper} from './interfaces/IMasterSwapper.sol';
import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from './lib/SafeDecimalMath.sol';
import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';
import {Errors, _require, _revert} from './lib/BabylonErrors.sol';

/**
 * @title HeartPump
 * @author Babylon Finance
 *
 * Contract that assists The Heart of Babylon garden with BABL staking.
 *
 */
contract Heart is OwnableUpgradeable {
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ Modifiers ============ */

    modifier onlyGovernanceOrEmergency {
        _require(
            msg.sender == owner() || msg.sender == controller.EMERGENCY_OWNER(),
            Errors.ONLY_GOVERNANCE_OR_EMERGENCY
        );
        _;
    }

    /* ============ Constants ============ */

    // Babylon addresses
    address private constant TREASURY = 0xD7AAf4676F0F52993cb33aD36784BF970f0E1259;
    uint256 private constant DEFAULT_TRADE_SLIPPAGE = 25e15; // 2.5%

    // Tokens
    IWETH private constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant BABL = IERC20(0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74);
    IERC20 private constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IGarden private constant HEART_GARDEN = IGarden(0x0);

    // Visor
    IHypervisor visor = IHypervisor(0x5e6c481dE496554b66657Dd1CA1F70C61cf11660);

    // Fuse
    address private constant BABYLON_FUSE_POOL_ADDRESS = 0xC7125E3A2925877C7371d579D29dAe4729Ac9033;

    /* ============ State Variables ============ */

    // Instance of the Controller contract
    IBabController public controller;

    /* Assets that are wanted by the heart pump */
    address[] public wantedAssets;

    address[] public votedGardens;
    uint256[] public gardenWeights;

    // Timestamp when the heart was last pumped
    uint256 public _lastPump;
    // Timestamp when the votes were sent by the keeper last
    uint256 public _lastVotes;

    /* ============ Initializer ============ */

    /**
     * Set state variables and map asset pairs to their oracles
     *
     * @param _controller             Address of controller contract
     */
    function initialize(IBabController _controller, address[] calldata _wantedAssets) public {
        OwnableUpgradeable.__Ownable_init();
        _require(address(_controller) != address(0), Errors.ADDRESS_IS_ZERO);
        controller = _controller;
        setWantedAssets(_wantedAssets);
    }

    /* ============ External Functions ============ */

    /**
     * Function to pump blood to the heart
     *
     * Note: Anyone can call this. Keeper in Defender will be set up to do it.
     */
    function pump() public {
        _require(block.timestamp.sub(_lastPump) > 1 weeks, Errors.HEART_ALREADY_PUMPED);
        _require(block.timestamp.sub(_lastVotes) < 1 weeks, Errors.HEART_VOTES_MISSING);
        // Consolidate all fees
        _consolidateFeesToWeth();
        uint256 wethBalance = WETH.balanceOf(address(this));
        _require(wethBalance > 5e18, Errors.HEART_MINIMUM_FEES);
        // 50% for buybacks
        _buyback(wethBalance.preciseMul(5e17));
        // 20% to BABL-ETH pair
        _addLiquidity(wethBalance.preciseMul(2e17));
        // 20% to Garden Investments
        _investInGardens(wethBalance.preciseMul(2e17));
        // 10% lend in fuse pool
        _lendFusePool(wethBalance.preciseMul(1e17));
        _lastPump = block.timestamp;
    }

    /**
     * Resolves garden votes for this cycle
     *
     * Note: Only keeper can call this
     * @param _gardens             Gardens that are going to receive investment
     * @param _weights             Weight for the investment in each garden
     */
    function resolveGardenVotes(address[] memory _gardens, uint256[] memory _weights) public {
        _onlyKeeper();
        _require(_gardens.length == _weights.length, Errors.HEART_VOTES_LENGTH);
        delete votedGardens;
        delete gardenWeights;
        for (uint256 i = 0; i < _gardens.length; i++) {
            votedGardens.push(_gardens[i]);
            gardenWeights.push(_weights[i]);
        }
        _lastVotes = block.timestamp;
    }

    /**
     * Set the assets wanted by the heart
     *
     * @param _wantedAssets             List of addresses
     */
    function setWantedAssets(address[] calldata _wantedAssets) public onlyGovernanceOrEmergency {
        delete wantedAssets;
        for (uint256 i = 0; i < _wantedAssets.length; i++) {
            wantedAssets.push(_wantedAssets[i]);
        }
    }

    /* ============ Internal Functions ============ */

    /**
     * Consolidates all reserve asset fees to weth
     *
     */
    function _consolidateFeesToWeth() private {
        address[] memory reserveAssets = controller.getReserveAssets();
        for (uint256 i = 0; i < reserveAssets.length; i++) {
            address reserveAsset = reserveAssets[i];
            uint256 balance = IERC20(reserveAsset).balanceOf(address(this));
            if (reserveAssets[i] != address(BABL) && reserveAssets[i] != address(WETH) && balance > 0) {
                _trade(reserveAssets[i], address(WETH), balance);
            }
        }
        // EMIT event: Fees collected
    }

    /**
     * Adds liquidity to the BABL-ETH pair through the hypervisor
     *
     * Note: Address of the heart needs to be whitelisted by Visor.
     */
    function _addLiquidity(uint256 _wethBalance) private {
        // Buy BABL again with half to add 50/50
        _trade(address(WETH), address(BABL), _wethBalance.preciseMul(5e17)); // 50%
        uint256 bablBalance = BABL.balanceOf(address(this));
        BABL.approve(address(visor), bablBalance);
        WETH.approve(address(visor), _wethBalance);
        uint256 shares = visor.deposit(_wethBalance, bablBalance, TREASURY);
        _require(shares == visor.balanceOf(TREASURY) && visor.balanceOf(TREASURY) > 0, Errors.HEART_LP_TOKENS);
    }

    /**
     * Buys back BABL through the uniswap V3 BABL-ETH pool
     *
     */
    function _buyback(uint256 _amount) private {
        _trade(address(WETH), address(BABL), _amount); // 50%
        // Gift 100% BABL back to garden
        IERC20(BABL).transferFrom(address(this), address(HEART_GARDEN), IERC20(BABL).balanceOf(address(this)));
    }

    /**
     * Invests in gardens using WETH converting it to garden reserve asset first
     *
     * @param _wethAmount             Total amount of weth to invest in all gardens
     */
    function _investInGardens(uint256 _wethAmount) private {
        for (uint256 i = 0; i < votedGardens.length; i++) {
            address reserveAsset = IGarden(votedGardens[i]).reserveAsset();
            _trade(address(WETH), reserveAsset, _wethAmount.preciseMul(gardenWeights[i]));
            // Gift it to garden
            // EMIT event
            IERC20(reserveAsset).transferFrom(
                address(this),
                votedGardens[i],
                IERC20(reserveAsset).balanceOf(address(this))
            );
        }
    }

    /**
     * Lends an amount of WETH converting it first to the pool asset that is the lowest (except BABL)
     *
     * @param _wethAmount             Total amount of weth to lend
     */
    function _lendFusePool(uint256 _wethAmount) private {}

    /**
     * Trades _tokenIn to _tokenOut using Uniswap V3
     *
     * @param _tokenIn             Token that is sold
     * @param _tokenOut            Token that is purchased
     * @param _amount              Amount of tokenin to sell
     */
    function _trade(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount
    ) private returns (uint256) {
        // Uses on chain oracle for all internal strategy operations to avoid attacks
        uint256 pricePerTokenUnit = IPriceOracle(controller.priceOracle()).getPrice(_tokenIn, _tokenOut);
        _require(pricePerTokenUnit != 0, Errors.NO_PRICE_FOR_TRADE);
        // minAmount must have receive token decimals
        uint256 exactAmount =
            SafeDecimalMath.normalizeAmountTokens(_tokenIn, _tokenOut, _amount.preciseMul(pricePerTokenUnit));
        uint256 minAmountExpected = exactAmount.sub(exactAmount.preciseMul(DEFAULT_TRADE_SLIPPAGE));
        IMasterSwapper(controller.masterSwapper()).trade(
            address(this),
            _tokenIn,
            _amount,
            _tokenOut,
            minAmountExpected
        );
        return minAmountExpected;
    }

    /**
     * Throws if the sender is not a keeper in the protocol
     */
    function _onlyKeeper() private view {
        _require(controller.isValidKeeper(msg.sender), Errors.ONLY_KEEPER);
    }
}
