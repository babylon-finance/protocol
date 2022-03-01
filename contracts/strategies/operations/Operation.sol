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

pragma solidity 0.8.9;
pragma abicoder v2;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IOperation} from '../../interfaces/IOperation.sol';
import {ITradeIntegration} from '../../interfaces/ITradeIntegration.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IHarvestUniv3Pool} from '../../interfaces/external/harvest/IHarvestUniv3Pool.sol';
import {IUniswapViewer} from '../../interfaces/external/uniswap-v3/IUniswapViewer.sol';
import {IUniVaultStorage} from '../../interfaces/external/uniswap-v3/IUniVaultStorage.sol';
import {INFTPositionManager} from '../../interfaces/external/uniswap-v3/INFTPositionManager.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';

/**
 * @title LongStrategy
 * @author Babylon Finance
 *
 * Holds the data for a long strategy
 */
abstract contract Operation is IOperation {
    using SafeMath for uint256;
    using BytesLib for uint256;
    using SafeDecimalMath for uint256;

    /* ============ Modifiers ============ */

    modifier onlyStrategy() {
        IStrategy strategy = IStrategy(msg.sender);
        IGarden garden = strategy.garden();
        require(IBabController(controller).isSystemContract(address(garden)), 'Only a garden can call this');
        require(garden.strategyMapping(msg.sender), 'Sender must be a strategy');
        _;
    }

    /* ============ State Variables ============ */
    uint256 internal constant MIN_TRADE_AMOUNT = 1000;
    uint256 internal constant SLIPPAGE_ALLOWED = 1e16; // 1%
    uint256 internal constant HUNDRED_PERCENT = 1e18; // 100%
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniswapViewer private constant uniswapViewer = IUniswapViewer(0x25c81e249F913C94F263923421622bA731E6555b);
    INFTPositionManager private constant nftPositionManager =
        INFTPositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    // Address of the controller
    address public controller;
    // Name of the operation
    string public name;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _controller) {
        require(_controller != address(0), 'Controller must be defined');
        name = _name;
        controller = _controller;
    }

    /* ============ Virtual External Functions ============ */

    function validateOperation(
        bytes calldata _data,
        IGarden _garden,
        address _integration,
        uint256 _index
    ) external view virtual override;

    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8 _assetStatus,
        bytes calldata _data,
        IGarden _garden,
        address _integration
    )
        external
        virtual
        override
        returns (
            address,
            uint256,
            uint8
        );

    function exitOperation(
        address _asset,
        uint256 _remaining,
        uint8 _assetStatus,
        uint256 _percentage,
        bytes calldata _data,
        IGarden _garden,
        address _integration
    )
        external
        virtual
        override
        returns (
            address,
            uint256,
            uint8
        );

    function getNAV(
        bytes calldata _data,
        IGarden _garden,
        address _integration
    ) external view virtual override returns (uint256, bool);

    /* ============ External Functions ============ */

    /**
     * Returns the name of the operation
     */
    function getName() external view override returns (string memory) {
        return name;
    }

    /**
     * Returns the price of the pair through the price oracle
     */
    function _getPrice(address _assetOne, address _assetTwo) internal view returns (uint256) {
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        try
            oracle.getPrice(_assetOne == address(0) ? WETH : _assetOne, _assetTwo == address(0) ? WETH : _assetTwo)
        returns (uint256 price) {
            return price;
        } catch {
            return 0;
        }
    }

    /**
     * Returns the price of the pair through the price oracle including univ2
     */
    function _getPriceNAV(address _assetOne, address _assetTwo) internal view returns (uint256) {
        IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
        return
            oracle.getPriceNAV(_assetOne == address(0) ? WETH : _assetOne, _assetTwo == address(0) ? WETH : _assetTwo);
    }

    /**
     * Calculates the value of a univ3 lp token held by a harvest vault
     * @param _pool                      Address of the harvest vault
     * @param _reserve                   Address of the reserve asset
     */
    function _getPriceUniV3LpToken(address _pool, address _reserve) internal view returns (uint256) {
        uint256 priceToken0 = _getPrice(IHarvestUniv3Pool(_pool).token0(), _reserve);
        uint256 priceToken1 = _getPrice(IHarvestUniv3Pool(_pool).token1(), _reserve);
        uint256 uniswapPosId = IUniVaultStorage(IHarvestUniv3Pool(_pool).getStorage()).posId();
        (uint256 amount0, uint256 amount1) = uniswapViewer.getAmountsForPosition(uniswapPosId);
        (, , , , , , , uint128 totalSupply, , , , ) = nftPositionManager.positions(uniswapPosId);
        if (totalSupply == 0) {
            return 0;
        }
        uint256 priceinReserveToken0 =
            SafeDecimalMath.normalizeAmountTokens(
                IHarvestUniv3Pool(_pool).token0(),
                _reserve,
                amount0.mul(priceToken0).div(totalSupply)
            );
        uint256 priceinReserveToken1 =
            SafeDecimalMath.normalizeAmountTokens(
                IHarvestUniv3Pool(_pool).token1(),
                _reserve,
                amount1.mul(priceToken1).div(totalSupply)
            );
        return priceinReserveToken0.add(priceinReserveToken1);
    }
}
