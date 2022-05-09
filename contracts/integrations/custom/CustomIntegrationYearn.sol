// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IYearnVaultRegistry} from '../../interfaces/IYearnVaultRegistry.sol';
import {IYearnVault} from '../../interfaces/external/yearn/IYearnVault.sol';
import {CustomIntegration} from './CustomIntegration.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {ControllerLib} from '../../lib/ControllerLib.sol';

/**
 * @title CustomIntegrationYearn
 * @author Babylon Finance Protocol
 *
 * Example of how to use custom integration to connect with yearn
 */
contract CustomIntegrationYearn is CustomIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using BytesLib for uint256;
    using ControllerLib for IBabController;

    /* ============ State Variables ============ */

    /* Add State variables here if any. Pass to the constructor */
    IYearnVaultRegistry private immutable yearnVaultRegistry;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     */
    constructor(IBabController _controller, IYearnVaultRegistry _yearnVaultRegistry)
        CustomIntegration('custom_yearn_sample', _controller)
    {
        require(address(_controller) != address(0), 'invalid address');
        yearnVaultRegistry = _yearnVaultRegistry;
    }

    /* =============== Internal Functions ============== */

    /**
     * Whether or not the data provided is valid
     *
     * @param  _data                     Data provided
     * @return bool                      True if the data is correct
     */
    function _isValid(bytes memory _data) internal view override returns (bool) {
        // Check the yearn vault registry to see if it is a valid vault
        return yearnVaultRegistry.vaults(BytesLib.decodeOpDataAddressAssembly(_data, 12));
    }

    /**
     * Which address needs to be approved (IERC-20) for the input tokens.
     *
     * hparam  _data                     Data provided
     * hparam  _opType                   O for enter, 1 for exit
     * @return address                   Address to approve the tokens to
     */
    function _getSpender(
        bytes calldata _data,
        uint8 /* _opType */
    ) internal pure override returns (address) {
        // Vault is passed as a param
        return BytesLib.decodeOpDataAddress(_data);
    }

    /**
     * The address of the IERC-20 token obtained after entering this operation
     *
     * @param  _param                     Address provided as param
     * @return address                    Address of the resulting lp token
     */
    function _getResultToken(address _param) internal pure override returns (address) {
        // The result token after investing in the vault is the vault itself
        return _param;
    }

    /**
     * Return enter custom calldata
     *
     * hparam  _strategy                 Address of the strategy
     * hparam  _data                     OpData e.g. Address of the pool
     * hparam  _resultTokensOut          Amount of result tokens to send
     * hparam  _tokensIn                 Addresses of tokens to send to spender to enter
     * hparam  _maxAmountsIn             Amounts of tokens to send to spender
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getEnterCalldata(
        address, /* _strategy */
        bytes calldata _data,
        uint256, /* _resultTokensOut */
        address[] calldata tokensIn,
        uint256[] calldata _maxAmountsIn
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address vault = BytesLib.decodeOpDataAddress(_data);
        require(tokensIn.length == 1 && _maxAmountsIn.length == 1, 'Wrong amount of tokens provided');
        require(yearnVaultRegistry.vaults(vault), 'Yearn vault is not valid');
        bytes memory methodData = abi.encodeWithSelector(IYearnVault.deposit.selector, _maxAmountsIn[0]);

        return (vault, 0, methodData);
    }

    /**
     * Return exit custom calldata
     *
     * hparam  _strategy                 Address of the strategy
     * hparam  _data                     OpData e.g. Address of the pool
     * hparam  _resultTokensIn           Amount of result tokens to send
     * hparam  _tokensOut                Addresses of tokens to receive
     * hparam  _minAmountsOut            Amounts of input tokens to receive
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getExitCalldata(
        address, /* _strategy */
        bytes calldata _data,
        uint256 _resultTokensIn,
        address[] calldata, /* _tokensOut */
        uint256[] calldata /* _minAmountsOut */
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address vault = BytesLib.decodeOpDataAddress(_data);
        bytes memory methodData = abi.encodeWithSelector(IYearnVault.withdraw.selector, _resultTokensIn);

        return (vault, 0, methodData);
    }

    /**
     * The list of addresses of the IERC-20 tokens mined as rewards during the strategy
     *
     * hparam  _data                      Address provided as param
     * @return address[]                  List of reward token addresses
     */
    function _getRewardTokens(
        address /* _data */
    ) internal pure override returns (address[] memory) {
        // No extra rewards. All get consolidated to the vault input token on exit
        return new address[](1);
    }

    /* ============ External Functions ============ */

    /**
     * The tokens to be purchased by the strategy on enter according to the weights.
     * Weights must add up to 1e18 (100%)
     *
     * hparam  _data                      Address provided as param
     * @return _inputTokens               List of input tokens to buy
     * @return _inputWeights              List of weights for the tokens to buy
     */
    function getInputTokensAndWeights(bytes calldata _data)
        external
        view
        override
        returns (address[] memory _inputTokens, uint256[] memory _inputWeights)
    {
        // Vault takes 100% in the vault token
        address vault = BytesLib.decodeOpDataAddress(_data);
        address[] memory inputTokens = new address[](1);
        inputTokens[0] = IYearnVault(vault).token();
        uint256[] memory inputWeights = new uint256[](1);
        inputWeights[0] = 1e18; // 100%
        return (inputTokens, inputWeights);
    }

    /**
     * The tokens to be received on exit.
     *
     * hparam  _data                      Bytes data
     * hparam  _liquidity                 Number with the amount of result tokens to exit
     * @return _exitTokens                List of output tokens to receive on exit
     * @return _minAmountsOut             List of min amounts for the output tokens to receive
     */
    function getOutputTokensAndMinAmountOut(bytes calldata _data, uint256 _liquidity)
        external
        view
        override
        returns (address[] memory _exitTokens, uint256[] memory _minAmountsOut)
    {
        // Vault exits 100% in the vault token
        address vault = BytesLib.decodeOpDataAddress(_data);
        address[] memory outputTokens = new address[](1);
        outputTokens[0] = IYearnVault(vault).token();
        uint256[] memory outpoutAmounts = new uint256[](1);
        outpoutAmounts[0] = _getPrice(vault, IYearnVault(vault).token()).preciseMul(_liquidity);
        return (outputTokens, outpoutAmounts);
    }

    /**
     * The price of the result token based on the asset received on enter
     *
     * hparam  _data                      Bytes data
     * hparam  _tokenDenominator          Token we receive the capital in
     * @return uint256                    Amount of result tokens to receive
     */
    function getPriceResultToken(bytes calldata _data, address _tokenAddress) external view override returns (uint256) {
        address vault = BytesLib.decodeOpDataAddress(_data);
        // We get the price of the input token in the vault token
        // Not needed in this case because Bbaylon already knows how to get the price of a vault token.
        // Implemented to showcase how it would be done.
        return _getPrice(IYearnVault(vault).token(), _tokenAddress);
    }
}
