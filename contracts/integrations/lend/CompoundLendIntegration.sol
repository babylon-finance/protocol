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
        assetToCToken[address(0)] = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5; // ETH
        assetToCToken[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 0x39AA39c021dfbaE8faC545936693aC917d5E7563; // USDC
        assetToCToken[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9; // USDT
        assetToCToken[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599] = 0xccF4429DB6322D5C611ee964527D42E5d685DD6a; // WBTC
        assetToCToken[0xc00e94Cb662C3520282E6f5717214004A7f26888] = 0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4; // COMP
        assetToCToken[0x0D8775F648430679A709E98d2b0Cb6250d2887EF] = 0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E; // BAT
        assetToCToken[0x514910771AF9Ca656af840dff83E8264EcF986CA] = 0xFAce851a4921ce59e912d19329929CE6da6EB0c7; // LINK
        assetToCToken[0x1985365e9f78359a9B6AD760e32412f4a445E862] = 0x158079Ee67Fce2f58472A96584A73C7Ab9AC95c1; // REP
        assetToCToken[0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359] = 0xF5DCe57282A584D2746FaF1593d3121Fcac444dC; // SAI
        assetToCToken[0x0000000000085d4780B73119b644AE5ecd22b376] = 0x12392F67bdf24faE0AF363c24aC620a2f67DAd86; // TUSD
        assetToCToken[0xE41d2489571d322189246DaFA5ebDe1F4699F498] = 0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407; // ZRX
    }

    /* ============ External Functions ============ */

    // Governance function
    function updateCTokenMapping(address _assetAddress, address _cTokenAddress) external onlyGovernance {
        assetToCToken[_assetAddress] = _cTokenAddress;
    }

    function getInvestmentTokenAmount(address _address, address _assetToken) public view override returns (uint256) {
        ICToken ctoken = ICToken(_getInvestmentToken(_assetToken));
        return ctoken.balanceOf(_address).mul(ctoken.exchangeRateStored()).div(10**18);
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
        uint8 assetDecimals = _assetToken == address(0) ? 18 : ERC20(_assetToken).decimals();
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
        bytes memory methodData;
        if (assetToCToken[_assetToken] == cETH) {
          methodData = abi.encodeWithSignature('mint()');
        } else {
          methodData = abi.encodeWithSignature('mint(uint256)', _numTokensToSupply);
        }
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
