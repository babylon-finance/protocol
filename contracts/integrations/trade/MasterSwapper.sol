// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import {BaseIntegration} from '../BaseIntegration.sol';

import {ICurveAddressProvider} from '../../interfaces/external/curve/ICurveAddressProvider.sol';
import {ICurveRegistry} from '../../interfaces/external/curve/ICurveRegistry.sol';
import {ITradeIntegration} from '../../interfaces/ITradeIntegration.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IMasterSwapper} from '../../interfaces/IMasterSwapper.sol';
import {IWETH} from '../../interfaces/external/weth/IWETH.sol';

import {String} from '../../lib/String.sol';
import {DeFiUtils} from '../../lib/DeFiUtils.sol';
import {AddressArrayUtils} from '../../lib/AddressArrayUtils.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {ControllerLib} from '../../lib/ControllerLib.sol';

import 'hardhat/console.sol';

/**
 * @title MasterSwapper
 * @author Babylon Finance Protocol
 *
 * Master class for integration with trading protocols
 */
contract MasterSwapper is BaseIntegration, ReentrancyGuard, IMasterSwapper {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;
    using PreciseUnitMath for uint256;
    using String for address;
    using String for bytes;
    using DeFiUtils for address[];
    using ControllerLib for IBabController;

    /* ============ Struct ============ */

    /* ============ Events ============ */

    /* ============ Constants ============ */

    IUniswapV3Factory internal constant uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    ICurveAddressProvider internal constant curveAddressProvider =
        ICurveAddressProvider(0x0000000022D53366457F9d5E68Ec105046FC4383);
    address private constant palStkAAVE = 0x24E79e946dEa5482212c38aaB2D0782F04cdB0E0;

    /* ============ State Variables ============ */

    ITradeIntegration public univ2;
    ITradeIntegration public univ3;
    ITradeIntegration public curve;
    ITradeIntegration public heartTradeIntegration;
    ITradeIntegration public paladinTradeIntegration;

    /* ============ Constructor ============ */

    /**
     * Creates the master swapper
     *
     * @param _controller             Address of the controller
     * @param _curve                  Address of curve trade integration
     * @param _univ3                  Address of univ3 trade integration
     * @param _univ2                  Address of univ2 trade integration
     * @param _hearttrade             Address of heart trade integration
     * @param _paladinTrade           Address of paladin trade integration
     */
    constructor(
        IBabController _controller,
        ITradeIntegration _curve,
        ITradeIntegration _univ3,
        ITradeIntegration _univ2,
        ITradeIntegration _hearttrade,
        ITradeIntegration _paladinTrade
    ) BaseIntegration('master_swapper_v3', _controller) {
        curve = _curve;
        univ3 = _univ3;
        univ2 = _univ2;
        heartTradeIntegration = _hearttrade;
        paladinTradeIntegration = _paladinTrade;
    }

    /* ============ External Functions ============ */

    /**
     * Executes a trade choosing the appropriate protocol for it
     * @dev
     *
     * @param _sendToken            Address of the token to be sent to the exchange
     * @param _sendQuantity         Units of reserve asset token sent to the exchange
     * @param _receiveToken         Address of the token that will be received from the exchange
     * @param _minReceiveQuantity   Min units of wanted token to be received from the exchange
     */
    function trade(
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity,
        IStrategy.TradeInfo memory _tradeInfo
    ) public override nonReentrant returns (uint256) {
        address strategy = msg.sender;
        console.log('trade');
        // deposit ETH to WETH if it is a send token
        if (_sendToken == address(0)) {
            console.log('wrap');
            IStrategy(strategy).invokeFromIntegration(
                WETH,
                _sendQuantity,
                abi.encodeWithSelector(IWETH.deposit.selector)
            );
        }

        console.log('_sendToken:', _sendToken);
        console.log('_sendQuantity:', _sendQuantity);
        console.log('_receiveToken:', _receiveToken);
        console.log('_minReceiveQuantity:', _minReceiveQuantity);
        // handle ETH<>WETH as a special case
        uint256 receivedQuantity =
            _trade(
                strategy,
                _sendToken == address(0) ? WETH : _sendToken,
                _sendQuantity,
                _receiveToken == address(0) ? WETH : _receiveToken,
                _minReceiveQuantity
            );

        console.log('receivedQuantity:', receivedQuantity);

        // unrwap WETH if ETH is a receive token
        if (_receiveToken == address(0)) {
            console.log('unwrap');
            IStrategy(strategy).invokeFromIntegration(
                WETH,
                0,
                abi.encodeWithSelector(IWETH.withdraw.selector, receivedQuantity)
            );
            console.log('strategy.balance:', strategy.balance);
        }

        return receivedQuantity;
    }

    /**
     * Function to update the internal mappings of the swapper
     * @param _index                   Index to update
     * @param _newAddress              New address
     */
    function updateTradeAddress(uint256 _index, address _newAddress) external {
        controller.onlyGovernanceOrEmergency();
        require(_newAddress != address(0), 'New address i not valid');
        if (_index == 0) {
            curve = ITradeIntegration(_newAddress);
        }
        if (_index == 1) {
            univ3 = ITradeIntegration(_newAddress);
        }
        if (_index == 3) {
            univ2 = ITradeIntegration(_newAddress);
        }
        if (_index == 4) {
            heartTradeIntegration = ITradeIntegration(_newAddress);
        }
        if (_index == 5) {
            paladinTradeIntegration = ITradeIntegration(_newAddress);
        }
    }

    function isTradeIntegration(address _integration) external view override returns (bool) {
        return
            _integration == address(this) ||
            _integration == address(curve) ||
            _integration == address(univ3) ||
            _integration == address(univ2) ||
            _integration == address(heartTradeIntegration) ||
            _integration == address(paladinTradeIntegration);
    }

    /* ============ Internal Functions ============ */

    function _trade(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) private returns (uint256) {
        require(_minReceiveQuantity > 0, 'minReceiveQuantity > 0');

        if (_sendToken == _receiveToken) {
            return _sendQuantity;
        }

        string memory error;
        uint256 receivedQuantity;

        // Palstake AAVE
        if (_receiveToken == palStkAAVE) {
            uint256 aaveTradeQuantity =
                _sendToken != AAVE
                    ? ITradeIntegration(univ3).trade(_strategy, _sendToken, _sendQuantity, AAVE, 1)
                    : _sendQuantity;
            try
                ITradeIntegration(paladinTradeIntegration).trade(
                    _strategy,
                    AAVE,
                    aaveTradeQuantity,
                    palStkAAVE,
                    _minReceiveQuantity
                )
            returns (uint256 receivedQuantity) {
                return receivedQuantity;
            } catch Error(string memory _err) {
                error = _formatError(error, _err, 'Paladin Trade Integration ', _sendToken, palStkAAVE);
            }
        }

        // Heart Direct
        if (controller.protocolWantedAssets(_sendToken)) {
            // If the heart wants it go through the heart and get WETH
            try ITradeIntegration(heartTradeIntegration).trade(_strategy, _sendToken, _sendQuantity, WETH, 1) returns (
                uint256 receivedQuantity
            ) {
                _sendToken = WETH;
                _sendQuantity = receivedQuantity;
                if (_receiveToken == WETH) {
                    return receivedQuantity;
                }
            } catch Error(string memory _err) {
                error = _formatError(error, _err, 'Heart Trade Integration ', _sendToken, WETH);
            }
        }

        // Curve Direct
        try
            ITradeIntegration(curve).trade(_strategy, _sendToken, _sendQuantity, _receiveToken, _minReceiveQuantity)
        returns (uint256 receivedQuantity) {
            return receivedQuantity;
        } catch Error(string memory _err) {
            error = _formatError(error, _err, 'Curve ', _sendToken, _receiveToken);
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
        returns (uint256 receivedQuantity) {
            return receivedQuantity;
        } catch Error(string memory _err) {
            error = _formatError(error, _err, 'UniV3 ', _sendToken, WETH, _receiveToken);
        }

        // Try Curve through reserve assets
        (error, receivedQuantity) = _swapCurveUni(
            _strategy,
            _sendToken,
            _sendQuantity,
            _receiveToken,
            _minReceiveQuantity,
            error
        );
        if (receivedQuantity > 0) {
            return receivedQuantity;
        }

        // Try Univ3 through DAI, USDC, WBTC, USDT
        address[4] memory reserves = [DAI, USDC, WBTC, USDT];
        for (uint256 i = 0; i < reserves.length; i++) {
            try
                ITradeIntegration(univ3).trade(
                    _strategy,
                    _sendToken,
                    _sendQuantity,
                    _receiveToken,
                    _minReceiveQuantity,
                    reserves[i]
                )
            returns (uint256 receivedQuantity) {
                return receivedQuantity;
            } catch Error(string memory _err) {
                error = _formatError(error, _err, 'UniV3 ', _sendToken, reserves[i], _receiveToken);
            }
        }

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
        returns (uint256 receivedQuantity) {
            return receivedQuantity;
        } catch Error(string memory _err) {
            error = _formatError(error, _err, 'UniV2 ', _sendToken, WETH, _receiveToken);
        }

        revert(string(abi.encodePacked('MasterSwapper:', error)));
    }

    function swapSwap(
        ITradeIntegration _one,
        ITradeIntegration _two,
        address _reserve,
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) external returns (uint256) {
        require(msg.sender == address(this), 'Nope');

        uint256 receivedQuantity = ITradeIntegration(_one).trade(_strategy, _sendToken, _sendQuantity, _reserve, 1);
        return ITradeIntegration(_two).trade(_strategy, _reserve, receivedQuantity, _receiveToken, _minReceiveQuantity);
    }

    function _swapCurveUni(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity,
        string memory error
    ) internal returns (string memory, uint256) {
        address[4] memory reserves = [DAI, WETH, WBTC, AAVE];
        for (uint256 i = 0; i < reserves.length; i++) {
            if (_sendToken != reserves[i] && _receiveToken != reserves[i]) {
                // Going through Curve but switching first to reserve
                try
                    this.swapSwap(
                        univ3,
                        curve,
                        reserves[i],
                        _strategy,
                        _sendToken,
                        _sendQuantity,
                        _receiveToken,
                        _minReceiveQuantity
                    )
                returns (uint256 receivedQuantity) {
                    return ('', receivedQuantity);
                } catch Error(string memory _err) {
                    error = _formatError(error, _err, 'Uni-Curve ', _sendToken, reserves[i], _receiveToken);
                }
                // Going through Curve to reserve asset and
                // then receive asset via Uni to reserve asset
                try
                    this.swapSwap(
                        curve,
                        univ3,
                        reserves[i],
                        _strategy,
                        _sendToken,
                        _sendQuantity,
                        _receiveToken,
                        _minReceiveQuantity
                    )
                returns (uint256 receivedQuantity) {
                    return ('', receivedQuantity);
                } catch Error(string memory _err) {
                    error = _formatError(error, _err, 'Curve-Uni ', _sendToken, reserves[i], _receiveToken);
                }
            }
        }
        return (error, 0);
    }

    function _swap(
        ITradeIntegration _integration,
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity,
        address _hop,
        string memory error
    ) internal returns (string memory, uint256) {
        try
            ITradeIntegration(_integration).trade(
                _strategy,
                _sendToken,
                _sendQuantity,
                _receiveToken,
                _minReceiveQuantity,
                _hop
            )
        returns (uint256 receivedQuantity) {
            return ('', receivedQuantity);
        } catch Error(string memory _err) {
            return (_formatError(error, _err, _integration.name(), _sendToken, _hop, _receiveToken), 0);
        }
    }

    function _formatError(
        string memory _blob,
        string memory _err,
        string memory _name,
        address _send,
        address _receive
    ) internal view returns (string memory) {
        return _formatError(_blob, _err, _name, _send, address(0), _receive);
    }

    function _formatError(
        string memory _blob,
        string memory _err,
        string memory _name,
        address _send,
        address _hop,
        address _receive
    ) internal view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    _blob,
                    _name,
                    (
                        _hop == address(0)
                            ? AddressArrayUtils.toDynamic(_send, _receive)
                            : AddressArrayUtils.toDynamic(_send, _hop, _receive)
                    )
                        .toTradePathString(),
                    ':',
                    _err,
                    ';'
                )
            );
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
