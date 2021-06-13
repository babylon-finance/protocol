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
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {ICToken} from '../../interfaces/external/compound/ICToken.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {LendIntegration} from './LendIntegration.sol';

/**
 * @title CompoundLendIntegration
 * @author Babylon Finance Protocol
 *
 * Compound lend integration.
 */
contract CompoundLendIntegration is LendIntegration {
    using SafeMath for uint256;
    using SafeCast for uint256;

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyGovernance() {
        require(msg.sender == controller.owner(), 'Only governance can call this');
        _;
    }

    /* ============ Constant ============ */

    address internal constant CompoundComptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address internal constant cETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    // Mapping of asset addresses to cToken addresses
    mapping(address => address) public assetToCToken;

    /* ============ Struct ============ */

    /* ============ Events ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     */
    constructor(IBabController _controller, address _weth) LendIntegration('compoundlend', _weth, _controller) {
        assetToCToken[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643; // DAI
        assetToCToken[0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984] = 0x35A18000230DA775CAc24873d00Ff85BccdeD550; // UNI
        assetToCToken[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5; // WETH
        assetToCToken[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 0x39AA39c021dfbaE8faC545936693aC917d5E7563; // USDC
        assetToCToken[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9; // USDT
        assetToCToken[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599] = 0xC11b1268C1A384e55C48c2391d8d480264A3A7F4; // WBTC
        assetToCToken[0xc00e94Cb662C3520282E6f5717214004A7f26888] = 0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4; // COMP
    }

    /* ============ External Functions ============ */

    // Governance function
    function updateCTokenMapping(address _assetAddress, address _cTokenAddress) external onlyGovernance {
        assetToCToken[_assetAddress] = _cTokenAddress;
    }

    /* ============ Internal Functions ============ */

    function _isInvestment(address _assetToken) internal view override returns (bool) {
        return assetToCToken[_assetToken] != address(0);
    }

    function _getExpectedShares(address _assetToken, uint256 _numTokensToSupply)
        internal
        view
        override
        returns (uint256)
    {
        uint256 oneCTokenInUderlying = _getExchangeRatePerToken(_assetToken);
        return oneCTokenInUderlying.mul(_numTokensToSupply).div(10**18);
    }

    // TODO: Test this
    function _getExchangeRatePerToken(address _assetToken) internal view override returns (uint256) {
        address cToken = assetToCToken[_assetToken];
        uint256 exchangeRateCurrent = ICToken(cToken).exchangeRateStored();
        // TODO: exchangeRateCurrent reverts wit no reason. Super strange.
        // uint256 exchangeRateCurrent = ICToken(cToken).exchangeRateCurrent();
        uint8 assetDecimals = ERC20(_assetToken).decimals();
        // cTokens always have 8 decimals.
        if (assetDecimals < 8) {
            uint256 mantissa = 8 - assetDecimals;
            return exchangeRateCurrent.mul(10**mantissa);
        } else {
            uint256 mantissa = assetDecimals - 8;
            return exchangeRateCurrent.div(10**mantissa);
        }
    }

    function _getRedeemCalldata(
        address, /* _strategy */
        address _assetToken,
        uint256 _numTokensToSupply
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
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('redeemUnderlying(uint256)', _numTokensToSupply);

        return (assetToCToken[_assetToken], 0, methodData);
    }

    /**
     * Returns calldata for supplying tokens.
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getSupplyCalldata(
        address, /* _strategy */
        address _assetToken,
        uint256 _numTokensToSupply
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
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('mint(uint256)', _numTokensToSupply);
        // If it is ETH, send the value
        return (assetToCToken[_assetToken], assetToCToken[_assetToken] == cETH ? _numTokensToSupply : 0, methodData);
    }

    /**
     * Return pre action calldata
     *
     * @param  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * @param  _borrowOp                Type of Borrow op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address _asset,
        uint256, /* _amount */
        uint256 _borrowOp
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
        if (_borrowOp == 0) {
            // Encode method data for Garden to invoke
            address[] memory markets = new address[](1);
            markets[0] = assetToCToken[_asset];
            bytes memory methodData = abi.encodeWithSignature('enterMarkets(address[])', markets);
            return (CompoundComptrollerAddress, 0, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    function _getSpender(address _assetToken) internal view override returns (address) {
        return assetToCToken[_assetToken];
    }

    function _getInvestmentToken(address _assetToken) internal view override returns (address) {
        return assetToCToken[_assetToken];
    }
}
