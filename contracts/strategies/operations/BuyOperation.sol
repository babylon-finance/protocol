// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {Operation} from './Operation.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {LowGasSafeMath as SafeMath} from '../../lib/LowGasSafeMath.sol';
import {ITradeIntegration} from '../../interfaces/ITradeIntegration.sol';

/**
 * @title BuyOperation
 * @author Babylon Finance
 *
 * Executes a buy operation
 */
contract BuyOperation is Operation {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;
    using BytesLib for bytes;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, address _controller) Operation(_name, _controller) {}

    /**
     * Sets operation data for the buy operation
     *
     * @param _data                   Operation data
     */
    function validateOperation(
        bytes calldata _data,
        IGarden _garden,
        address, /* _integration */
        uint256 /* _index */
    ) external view override onlyStrategy {
        address asset = BytesLib.decodeOpDataAddress(_data);
        require(asset != address(0), 'Incorrect asset address');
        require(asset != _garden.reserveAsset(), 'Receive token must be different');
    }

    /**
     * Executes the buy operation
     * @param _asset              Asset to receive into this operation
     * @param _capital            Amount of asset received
     * param _assetStatus        Status of the asset amount
     * @param _data               OpData e.g. Address of the token to buy
     * param _garden             Garden of the strategy
     * param _integration        Address of the integration to execute
     */
    function executeOperation(
        address _asset,
        uint256 _capital,
        uint8, /* _assetStatus */
        bytes calldata _data,
        IGarden, /* _garden */
        address /* _integration */
    )
        external
        override
        onlyStrategy
        returns (
            address,
            uint256,
            uint8
        )
    {
        address token = BytesLib.decodeOpDataAddress(_data);
        // Replace old AXS with new AXS
        if (token == 0xF5D669627376EBd411E34b98F19C868c8ABA5ADA) {
            token = 0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b;
        }
        IStrategy(msg.sender).trade(_asset, _capital, token);
        return (token, ERC20(token).balanceOf(address(msg.sender)), 0); // liquid
    }

    /**
     * Exits the buy operation.
     * @param _percentage of capital to exit from the strategy
     */
    function exitOperation(
        address _asset,
        uint256, /* _remaining */
        uint8, /* _assetStatus */
        uint256 _percentage,
        bytes calldata, /*_data */
        IGarden, /*_garden */
        address /* _integration */
    )
        external
        view
        override
        onlyStrategy
        returns (
            address,
            uint256,
            uint8
        )
    {
        require(_percentage <= HUNDRED_PERCENT, 'Unwind Percentage <= 100%');
        uint256 balance = ERC20(_asset).balanceOf(address(msg.sender)).preciseMul(_percentage);
        return (_asset, balance, 0);
    }

    /**
     * Gets the NAV of the buy op in the reserve asset
     *
     * @param _data               OpData e.g. Asset bought
     * @param _garden             Garden the strategy belongs to
     * param _integration         Status of the asset amount
     * @return _nav               NAV of the strategy
     */
    function getNAV(
        bytes calldata _data,
        IGarden _garden,
        address /* _integration */
    ) external view override returns (uint256, bool) {
        address token = BytesLib.decodeOpDataAddress(_data); // 64 bytes (w/o signature prefix bytes4)
        if (!IStrategy(msg.sender).isStrategyActive()) {
            return (0, true);
        }
        // Replace old AXS with new AXS
        if (token == 0xF5D669627376EBd411E34b98F19C868c8ABA5ADA) {
            token = 0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b;
        }
        uint256 price = _getPriceNAV(_garden.reserveAsset(), token);
        uint256 NAV =
            SafeDecimalMath
                .normalizeAmountTokens(token, _garden.reserveAsset(), ERC20(token).balanceOf(msg.sender))
                .preciseDiv(price);
        require(NAV != 0, 'NAV has to be bigger 0');
        return (NAV, true);
    }
}
