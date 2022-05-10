// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SignedSafeMath} from '@openzeppelin/contracts/math/SignedSafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';

import {IBabController} from '../interfaces/IBabController.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IIntegration} from '../interfaces/IIntegration.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IBaseIntegration} from '../interfaces/IBaseIntegration.sol';

import {LowGasSafeMath} from '../lib/LowGasSafeMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';

/**
 * @title BaseIntegration
 * @author Babylon Finance
 *
 * Abstract class that houses common Integration-related state and functions.
 */
abstract contract BaseIntegration is IBaseIntegration {
    using SafeCast for int256;
    using LowGasSafeMath for uint256;
    using SignedSafeMath for int256;
    using PreciseUnitMath for uint256;

    /* ============ Modifiers ============ */

    modifier onlySystemContract() {
        require(controller.isSystemContract(msg.sender), 'Only system can call this');
        _;
    }

    /* ============ Constants ============ */

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant ETH_ADD_CURVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant SNX = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
    address internal constant sETH = 0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb;
    address internal constant sUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    /* ============ State Variables ============ */

    // Address of the controller
    IBabController public immutable controller;

    // Name of the integration
    string public override name;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */

    constructor(string memory _name, IBabController _controller) {
        require(address(_controller) != address(0), 'Controller must be defined');
        name = _name;
        controller = _controller;
    }

    /* ============ External Functions ============ */

    /* ============ Internal Functions ============ */

    function _getTokenOrETHBalance(address _strategy, address _token) internal view returns (uint256) {
        if (_token == address(0) || _token == ETH_ADD_CURVE) {
            return _strategy.balance;
        }
        return ERC20(_token).balanceOf(_strategy);
    }

    function _getDurationStrategy(address _strategy) internal view returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        (, , , , uint256 executedAt, , ) = strategy.getStrategyState();
        return block.timestamp.sub(executedAt);
    }

    function _getPrice(address _tokenIn, address _tokenOut) internal view returns (uint256) {
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        return oracle.getPrice(_tokenIn, _tokenOut);
    }
}
