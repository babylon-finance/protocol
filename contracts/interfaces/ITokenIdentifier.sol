

pragma solidity 0.8.9;

import {ICurveMetaRegistry} from './ICurveMetaRegistry.sol';

/**
 * @title IPriceOracle
 * @author Babylon Finance
 *
 * Interface for interacting with PriceOracle
 */
interface ITokenIdentifier {
    /* ============ Functions ============ */

    function identifyTokens(
        address _tokenIn,
        address _tokenOut,
        ICurveMetaRegistry _curveMetaRegistry
    )
        external
        view
        returns (
            uint8,
            uint8,
            address,
            address
        );

    function updateYearnVault(address[] calldata _vaults, bool[] calldata _values) external;

    function updateSynth(address[] calldata _synths, bool[] calldata _values) external;

    function updateCreamPair(address[] calldata _creamTokens, address[] calldata _underlyings) external;

    function updateAavePair(address[] calldata _aaveTokens, address[] calldata _underlyings) external;

    function updateCompoundPair(address[] calldata _cTokens, address[] calldata _underlyings) external;
}
