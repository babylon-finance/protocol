

pragma solidity 0.8.9;

import {IBaseIntegration} from '../interfaces/IBaseIntegration.sol';

/**
 * @title ITrade
 * @author Babylon Finance
 *
 * Interface for trading protocol integrations
 */
interface ITradeIntegration is IBaseIntegration {
    function trade(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity
    ) external;

    function trade(
        address _strategy,
        address _sendToken,
        uint256 _sendQuantity,
        address _receiveToken,
        uint256 _minReceiveQuantity,
        address _hopToken
    ) external;
}
