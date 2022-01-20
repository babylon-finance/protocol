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

import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import {ICurveAddressProvider} from '../../interfaces/external/curve/ICurveAddressProvider.sol';
import {ICurveRegistry} from '../../interfaces/external/curve/ICurveRegistry.sol';
import {ISynthetix} from '../../interfaces/external/synthetix/ISynthetix.sol';
import {ISnxProxy} from '../../interfaces/external/synthetix/ISnxProxy.sol';
import {ISnxSynth} from '../../interfaces/external/synthetix/ISnxSynth.sol';
import {ITradeIntegration} from '../../interfaces/ITradeIntegration.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {BaseIntegration} from '../BaseIntegration.sol';

import {Strings} from '../../lib/Strings.sol';
import {DeFiUtils} from '../../lib/DeFiUtils.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';

import 'hardhat/console.sol';

/**
 * @title MasterSwapper
 * @author Babylon Finance Protocol
 *
 * Master class for integration with trading protocols
 */

// - MasterSwapper
//   * Uni V2 TWAP
//   * Synthetix Contract. Exchange
//     Support proxy or no proxy between synths
//     - Only between pairs of synths. Great for bigger trades
//
// * Implement CurveTradeIntegration
// * Implement SynthetixTradeIntegration
// * Implemen  UniswapV2TradeIntegration
contract MasterSwapper is BaseIntegration, ReentrancyGuard, ITradeIntegration {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;
    using PreciseUnitMath for uint256;
    using Strings for address;
    using Strings for bytes;
    using DeFiUtils for address[3];
    using DeFiUtils for address[2];

    /* ============ Struct ============ */

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyGovernanceOrEmergency {
        require(
            msg.sender == controller.owner() || msg.sender == controller.EMERGENCY_OWNER(),
            'Not enough privileges'
        );
        _;
    }

    /* ============ Events ============ */

    /* ============ Constants ============ */

    IUniswapV3Factory internal constant uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    ICurveAddressProvider internal constant curveAddressProvider =
        ICurveAddressProvider(0x0000000022D53366457F9d5E68Ec105046FC4383);

    /* ============ State Variables ============ */

    ITradeIntegration public univ2;
    ITradeIntegration public univ3;
    ITradeIntegration public curve;
    ITradeIntegration public synthetix;

    /* ============ Constructor ============ */

    /**
     * Creates the master swapper
     *
     * @param _controller             Address of the controller
     * @param _curve                  Address of curve trade integration
     * @param _univ3                  Address of univ3 trade integration
     * @param _synthetix              Address of synthetix trade integration
     * @param _univ2                  Address of univ2 trade integration
     */
    constructor(
        IBabController _controller,
        ITradeIntegration _curve,
        ITradeIntegration _univ3,
        ITradeIntegration _synthetix,
        ITradeIntegration _univ2
    ) BaseIntegration('master_swapper_v3', _controller) {
        curve = _curve;
        univ3 = _univ3;
        synthetix = _synthetix;
        univ2 = _univ2;
    }

    /* ============ External Functions ============ */

    /**
     * Executes a trade choosing the appropriate protocol for it
     * @dev
     *
     * @param _strategy             Address of the strategy
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _minReceiveQuantity   Min units of wanted token to be received from the exchange
     */
    function trade(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) public override nonReentrant {
        _trade(_strategy, _sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity);
    }

    /**
     * @dev
     *   Should be never called. Only implemented to satisfy ITradeIntegration
     */
    function trade(
        address,
        address,
        uint256,
        address,
        uint256,
        address
    ) public override nonReentrant {
        revert('no impl');
    }

    /**
     * Function to update the internal mappings of the swapper
     * @param _index                   Index to update
     * @param _newAddress              New address
     */
    function updateTradeAddress(uint256 _index, address _newAddress) external onlyGovernanceOrEmergency {
        require(_newAddress != address(0), 'New address i not valid');
        if (_index == 0) {
            curve = ITradeIntegration(_newAddress);
        }
        if (_index == 1) {
            univ3 = ITradeIntegration(_newAddress);
        }
        if (_index == 2) {
            synthetix = ITradeIntegration(_newAddress);
        }
        if (_index == 3) {
            univ2 = ITradeIntegration(_newAddress);
        }
    }

    function isTradeIntegration(address _integration) external view returns (bool) {
        return
            _integration == address(curve) ||
            _integration == address(univ3) ||
            _integration == address(synthetix) ||
            _integration == address(univ2);
    }

    /* ============ Internal Functions ============ */

    function _trade(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) private {
        if (_sendToken == _receiveToken) {
            return;
        }
        string memory error;

        // Synthetix Direct
        address _sendTokenSynth = _getSynth(_sendToken);
        address _receiveTokenSynth = _getSynth(_receiveToken);
        if (
            (_sendTokenSynth != address(0) && _receiveTokenSynth != address(0)) ||
            (_sendTokenSynth != address(0) && (_receiveToken == DAI || _receiveToken == USDC)) ||
            (_receiveToken != address(0) && (_sendTokenSynth == DAI || _sendTokenSynth == USDC))
        ) {
            try
                ITradeIntegration(synthetix).trade(
                    _strategy,
                    _sendToken,
                    _sendQuantity,
                    _receiveToken,
                    _minReceiveQuantity
                )
            {
                return;
            } catch Error(string memory _err) {
                error = string(
                    abi.encodePacked(error, 'Synt:', [_sendToken, _receiveToken].toTradePathString(), ':', _err, ';')
                );
            }
        }
        // Curve Direct
        try ITradeIntegration(curve).trade(_strategy, _sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity) {
            return;
        } catch Error(string memory _err) {
            error = string(
                abi.encodePacked(error, 'Curve:', [_sendToken, _receiveToken].toTradePathString(), ':', _err, ';')
            );
        }
        // Abstract Synths out
        if (_sendTokenSynth != address(0)) {
            uint256 reserveBalance = _getTokenOrETHBalance(_strategy, DAI);
            // Trade to DAI through sUSD
            try ITradeIntegration(synthetix).trade(_strategy, _sendToken, _sendQuantity, DAI, 1) {
                // Change DAI to receive token
                _trade(
                    _strategy,
                    DAI,
                    _getTokenOrETHBalance(_strategy, DAI).sub(reserveBalance),
                    _receiveToken,
                    _minReceiveQuantity
                );
                return;
            } catch Error(string memory _err) {
                error = string(
                    abi.encodePacked(
                        error,
                        'Synt:',
                        [_sendToken, DAI, _receiveToken].toTradePathString(),
                        ':',
                        _err,
                        ';'
                    )
                );
            }
        }
        // Trade to DAI and then do DAI to synh
        if (_receiveTokenSynth != address(0)) {
            uint256 reserveBalance = 0;

            if (_sendToken != DAI) {
                reserveBalance = _getTokenOrETHBalance(_strategy, DAI);
                _trade(_strategy, _sendToken, _sendQuantity, DAI, 1);
            }
            try
                ITradeIntegration(synthetix).trade(
                    _strategy,
                    DAI,
                    _getTokenOrETHBalance(_strategy, DAI).sub(reserveBalance),
                    _receiveToken,
                    _minReceiveQuantity
                )
            {
                return;
            } catch Error(string memory _err) {
                revert(string(abi.encodePacked('Failed midway in out synth', _err, ';')));
            }
        }
        // Go through UNIv3 first via WETH
        try
            ITradeIntegration(univ3).trade(
                _strategy,
                _sendToken,
                _sendQuantity,
                _receiveToken,
                _minReceiveQuantity,
                WETH
            )
        {
            console.log('UniV3 WETH');
            return;
        } catch Error(string memory _err) {
            error = string(
                abi.encodePacked(error, 'UniV3:', [_sendToken, WETH, _receiveToken].toTradePathString(), ':', _err, ';')
            );
        }

        // Try Curve through reserve assets
        address[3] memory reserves = [DAI, WETH, WBTC];
        for (uint256 i = 0; i < reserves.length; i++) {
            try
                this.SwapUniThenCurve(
                    reserves[i],
                    _strategy,
                    _sendToken,
                    _sendQuantity,
                    _receiveToken,
                    _minReceiveQuantity
                )
            {
                console.log('Uni -> Curve');
                return;
            } catch Error(string memory _err) {
                error = string(
                    abi.encodePacked(
                        error,
                        'Uni-Curve:',
                        [_sendToken, reserves[i], _receiveToken].toTradePathString(),
                        ':',
                        _err,
                        ';'
                    )
                );
            }
            try
                this.SwapCurveThenUni(
                    reserves[i],
                    _strategy,
                    _sendToken,
                    _sendQuantity,
                    _receiveToken,
                    _minReceiveQuantity
                )
            {
                console.log('Curve -> Uni');
                return;
            } catch Error(string memory _err) {
                error = string(
                    abi.encodePacked(
                        error,
                        'Curve-Uni:',
                        [_sendToken, reserves[i], _receiveToken].toTradePathString(),
                        ':',
                        _err,
                        ';'
                    )
                );
            }
        }

        // Update balance in case we tried some Curve paths but had to revert
        // TODO: Fix this. All failed attempts should be properly reverted
        uint256 sendBalanceLeft = _getTokenOrETHBalance(_strategy, _sendToken);
        _sendQuantity = _sendQuantity < sendBalanceLeft ? _sendQuantity : sendBalanceLeft;
        // Try Univ3 through DAI
        try
            ITradeIntegration(univ3).trade(
                _strategy,
                _sendToken,
                _sendQuantity,
                _receiveToken,
                _minReceiveQuantity,
                DAI
            )
        {
            console.log('UniV3 DAI');
            return;
        } catch Error(string memory _err) {
            error = string(
                abi.encodePacked(error, 'UniV3:', [_sendToken, DAI, _receiveToken].toTradePathString(), ':', _err, ';')
            );
        }
        // Try Univ3 through USDC
        try
            ITradeIntegration(univ3).trade(
                _strategy,
                _sendToken,
                _sendQuantity,
                _receiveToken,
                _minReceiveQuantity,
                USDC
            )
        {
            console.log('UniV3 USDC');
            return;
        } catch Error(string memory _err) {
            error = string(
                abi.encodePacked(error, 'UniV3:', [_sendToken, USDC, _receiveToken].toTradePathString(), ':', _err, ';')
            );
        }

        sendBalanceLeft = _getTokenOrETHBalance(_strategy, _sendToken);
        _sendQuantity = _sendQuantity < sendBalanceLeft ? _sendQuantity : sendBalanceLeft;

        if (_minReceiveQuantity > 1) {
            // Try on UniV2 through WETH
            try
                ITradeIntegration(univ2).trade(
                    _strategy,
                    _sendToken,
                    _sendQuantity,
                    _receiveToken,
                    _minReceiveQuantity,
                    WETH
                )
            {
                console.log('UniV2');
                return;
            } catch Error(string memory _err) {
                error = string(
                    abi.encodePacked(
                        error,
                        'UniV2:',
                        [_sendToken, WETH, _receiveToken].toTradePathString(),
                        ':',
                        _err,
                        ';'
                    )
                );
            }
        }
        console.log(string(abi.encodePacked('MasterSwapper:', error)));
        revert(string(abi.encodePacked('MasterSwapper:', error)));
    }

    function SwapUniThenCurve(
        address _reserve,
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) external {
        require(msg.sender == address(this), 'Nope');
        // Going through Curve but switching first to reserve
        uint256 reserveBalance = _getTokenOrETHBalance(_strategy, _reserve);
        ITradeIntegration(univ3).trade(_strategy, _sendToken, _sendQuantity, _reserve, 1);
        ITradeIntegration(curve).trade(
            _strategy,
            _reserve,
            _getTokenOrETHBalance(_strategy, _reserve).sub(reserveBalance),
            _receiveToken,
            _minReceiveQuantity
        );
    }

    function SwapCurveThenUni(
        address _reserve,
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) external {
        require(msg.sender == address(this), 'Nope');
        // Going through Curve to reserve asset and
        // then receive asset via Uni to reserve asset
        uint256 reserveBalance = _getTokenOrETHBalance(_strategy, _reserve);
        ITradeIntegration(curve).trade(_strategy, _sendToken, _sendQuantity, _reserve, 1);
        ITradeIntegration(curve).trade(
            _strategy,
            _reserve,
            _getTokenOrETHBalance(_strategy, _reserve).sub(reserveBalance),
            _receiveToken,
            _minReceiveQuantity
        );
    }

    function _findCurvePool(address _fromToken, address _toToken) private view returns (address) {
        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        address curvePool = curveRegistry.find_pool_for_coins(_fromToken, _toToken);
        if (curvePool == address(0) && _fromToken == WETH) {
            curvePool = curveRegistry.find_pool_for_coins(ETH_ADD_CURVE, _toToken);
        }
        if (curvePool == address(0) && _toToken == WETH) {
            curvePool = curveRegistry.find_pool_for_coins(_fromToken, ETH_ADD_CURVE);
        }
        return curvePool;
    }

    function _getSynth(address _token) private view returns (address) {
        ISynthetix snx = ISynthetix(ISnxProxy(SNX).target());
        try snx.synths(stringToBytes32(ERC20(_token).symbol())) returns (ISnxSynth _synth) {
            return address(_synth);
        } catch {
            return address(0);
        }
    }

    function stringToBytes32(string memory source) private pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
        assembly {
            result := mload(add(source, 32))
        }
    }
}
