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
import {IntegerUtils} from '../../lib/IntegerUtils.sol';
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

    struct TradeArgs {
        address strategy;
        address sendToken;
        uint256 sendQuantity;
        address receiveToken;
        uint256 minReceiveQuantity;
    }

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
    address[] curveUniHopTokens;
    address[] uniV3HopTokens;

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

        curveUniHopTokens = [DAI, WETH, WBTC, AAVE];
        uniV3HopTokens = [DAI, USDC, WBTC, USDT];
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
    ) public override nonReentrant returns (uint256, IStrategy.TradeProtocol[] memory, address[] memory) {
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
        (uint256 receivedQuantity,,) =
            _trade(
                strategy,
                _sendToken == address(0) ? WETH : _sendToken,
                _sendQuantity,
                _receiveToken == address(0) ? WETH : _receiveToken,
                _minReceiveQuantity,
                _tradeInfo
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

        return (receivedQuantity, new IStrategy.TradeProtocol[](0), new address[](0));
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
        uint256 _minReceiveQuantity,
        IStrategy.TradeInfo memory _tradeInfo
    ) private returns (uint256, IStrategy.TradeProtocol[] memory, address[] memory) {
        require(_minReceiveQuantity > 0, 'minReceiveQuantity > 0');

        if (_sendToken == _receiveToken) {
            return (_sendQuantity, new IStrategy.TradeProtocol[](0), new address[](0));
        }

        console.log('_tradeInfo.path.length :', _tradeInfo.path.length );

        if (_tradeInfo.path.length > 0) {
            return (_tradeExecute(
                _strategy,
                _sendToken,
                _sendQuantity,
                _receiveToken,
                _minReceiveQuantity,
                _tradeInfo
            ), new IStrategy.TradeProtocol[](0), new address[](0));
        } else {
            return _tradeSearch(TradeArgs(
                _strategy,
                _sendToken,
                _sendQuantity,
                _receiveToken,
                _minReceiveQuantity
            ));
        }

    }

    function _tradeExecute(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity,
        IStrategy.TradeInfo memory _tradeInfo
    ) private returns (uint256) {
        for (uint256 index = 0; index < _tradeInfo.path.length; index++) {
            bool isLast = index == _tradeInfo.path.length - 1;
            IStrategy.TradeProtocol protocol = _tradeInfo.path[index];
            if (protocol == IStrategy.TradeProtocol.Paladin) {
                // Palstake AAVE
                if (_receiveToken == palStkAAVE) {
                    uint256 aaveTradeQuantity = _sendToken != AAVE ? ITradeIntegration(univ3).trade(_strategy, _sendToken, _sendQuantity, AAVE, 1) : _sendQuantity;
                    return ITradeIntegration(paladinTradeIntegration).trade(
                        _strategy,
                        AAVE,
                        aaveTradeQuantity,
                        palStkAAVE,
                        isLast ? _minReceiveQuantity : 1
                    );
                }
            }
        }
    }

    function _tradeSearch(TradeArgs memory _args) private returns (uint256, IStrategy.TradeProtocol[] memory, address[] memory) {
        TradeArgs memory args = _args;
        string memory error;
        uint256 receivedQuantity;
        IStrategy.TradeProtocol[] memory path;
        address[] memory hops;
        // Palstake AAVE
        if (args.receiveToken == palStkAAVE) {
            uint256 aaveTradeQuantity =
                args.sendToken != AAVE
                    ? ITradeIntegration(univ3).trade(args.strategy, args.sendToken, args.sendQuantity, AAVE, 1)
                    : args.sendQuantity;
            try
                ITradeIntegration(paladinTradeIntegration).trade(
                    args.strategy,
                    AAVE,
                    aaveTradeQuantity,
                    palStkAAVE,
                    args.minReceiveQuantity
                )
            returns (uint256 receivedQuantity) {
                return (receivedQuantity, IntegerUtils.toDynamic(IStrategy.TradeProtocol.Paladin), AddressArrayUtils.toDynamic(address(0)));
            } catch Error(string memory _err) {
                error = _formatError(error, _err, 'Paladin Trade Integration ',
                                     args.sendToken, palStkAAVE);
            }
        }

        // Heart Direct
        if (controller.protocolWantedAssets(args.sendToken)) {
            // If the heart wants it go through the heart and get WETH
            try ITradeIntegration(heartTradeIntegration).trade(args.strategy,
                                                               args.sendToken,
                                                               args.sendQuantity, WETH, 1) returns (
                uint256 receivedQuantity
            ) {
                args.sendToken = WETH;
                args.sendQuantity = receivedQuantity;
                if (args.receiveToken == WETH) {
                    return (receivedQuantity, IntegerUtils.toDynamic(IStrategy.TradeProtocol.Heart), AddressArrayUtils.toDynamic(address(0)));
                }
            } catch Error(string memory _err) {
                error = _formatError(error, _err, 'Heart Trade Integration ',
                                     args.sendToken, WETH);
            }
        }

        // Curve Direct
        try
            ITradeIntegration(curve).trade(args.strategy, args.sendToken,
                                           args.sendQuantity, args.receiveToken,
                                           args.minReceiveQuantity)
        returns (uint256 receivedQuantity) {
            return (receivedQuantity,
                    IntegerUtils.toDynamic(IStrategy.TradeProtocol.Curve), AddressArrayUtils.toDynamic(address(0)));
        } catch Error(string memory _err) {
            error = _formatError(error, _err, 'Curve ', args.sendToken, args.receiveToken);
        }

        // Go through UNIv3 first via WETH
        try
            ITradeIntegration(univ3).trade(
                args.strategy,
                args.sendToken,
                args.sendQuantity,
                args.receiveToken,
                args.minReceiveQuantity,
                WETH
            )
        returns (uint256 receivedQuantity) {
            return (receivedQuantity, IntegerUtils.toDynamic(IStrategy.TradeProtocol.UniV3), AddressArrayUtils.toDynamic(WETH));
        } catch Error(string memory _err) {
            error = _formatError(error, _err, 'UniV3 ', args.sendToken, WETH,
                                 args.receiveToken);
        }

        // Try Curve-Uni through reserve assets
        for (uint256 i = 0; i < curveUniHopTokens.length; i++) {
            if (args.sendToken != curveUniHopTokens[i] && args.receiveToken !=
                curveUniHopTokens[i]) {
                // Going through Curve but switching first to reserve
                try
                    this.swapSwap(
                        univ3,
                        curve,
                        curveUniHopTokens[i],
                        args.strategy,
                        args.sendToken,
                        args.sendQuantity,
                        args.receiveToken,
                        args.minReceiveQuantity
                    )
                returns (uint256 receivedQuantity) {
                    return (receivedQuantity, IntegerUtils.toDynamic(IStrategy.TradeProtocol.UniV3, IStrategy.TradeProtocol.Curve), AddressArrayUtils.toDynamic(address(0), address(0)));
                } catch Error(string memory _err) {
                    error = _formatError(error, _err, 'Uni-Curve ',
                                         args.sendToken, curveUniHopTokens[i],
                                         args.receiveToken);
                }
                // Going through Curve to reserve asset and
                // then receive asset via Uni to reserve asset
                try
                    this.swapSwap(
                        curve,
                        univ3,
                        curveUniHopTokens[i],
                        args.strategy,
                        args.sendToken,
                        args.sendQuantity,
                        args.receiveToken,
                        args.minReceiveQuantity
                    )
                returns (uint256 receivedQuantity) {
                    return (receivedQuantity, IntegerUtils.toDynamic(IStrategy.TradeProtocol.Curve, IStrategy.TradeProtocol.UniV3), AddressArrayUtils.toDynamic(address(0), address(0)));
                } catch Error(string memory _err) {
                    error = _formatError(error, _err, 'Curve-Uni ',
                                         args.sendToken, curveUniHopTokens[i],
                                         args.receiveToken);
                }
            }
        }

        // Try Univ3 through uniV3HopTokens
        for (uint256 i = 0; i < uniV3HopTokens.length; i++) {
            try
                ITradeIntegration(univ3).trade(
                    args.strategy,
                    args.sendToken,
                    args.sendQuantity,
                    args.receiveToken,
                    args.minReceiveQuantity,
                    uniV3HopTokens[i]
                )
            returns (uint256 receivedQuantity) {
                return (receivedQuantity, IntegerUtils.toDynamic(IStrategy.TradeProtocol.UniV3), AddressArrayUtils.toDynamic(uniV3HopTokens[i]));
            } catch Error(string memory _err) {
                error = _formatError(error, _err, 'UniV3 ', args.sendToken,
                                     uniV3HopTokens[i], args.receiveToken);
            }
        }

        // Try on UniV2 through WETH
        try
            ITradeIntegration(univ2).trade(
                args.strategy,
                args.sendToken,
                args.sendQuantity,
                args.receiveToken,
                args.minReceiveQuantity,
                WETH
            )
        returns (uint256 receivedQuantity) {
            return (receivedQuantity, IntegerUtils.toDynamic(IStrategy.TradeProtocol.UniV2), AddressArrayUtils.toDynamic(WETH));
        } catch Error(string memory _err) {
            error = _formatError(error, _err, 'UniV2 ', args.sendToken, WETH,
                                 args.receiveToken);
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
}
