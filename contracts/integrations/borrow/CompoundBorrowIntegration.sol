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

pragma solidity >=0.7.0 <0.9.0;

import 'hardhat/console.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ICToken} from '../../interfaces/external/compound/ICToken.sol';
import {ICEther} from '../../interfaces/external/compound/ICEther.sol';
import {ICompoundPriceOracle} from '../../interfaces/external/compound/ICompoundPriceOracle.sol';
import {IComptroller} from '../../interfaces/external/compound/IComptroller.sol';
import {IWETH} from '../../interfaces/external/weth/IWETH.sol';
import {BorrowIntegration} from './BorrowIntegration.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {IGarden} from '../../interfaces/IGarden.sol';

/**
 * @title CompoundBorrowIntegration
 * @author Babylon Finance
 *
 * Abstract class that houses compound borring logic.
 */
contract CompoundBorrowIntegration is BorrowIntegration {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyGovernance() {
        require(msg.sender == controller.owner(), 'Only governance can call this');
        _;
    }

    /* ============ State Variables ============ */

    address constant CompoundComptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address constant CEtherAddress = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    // Mapping of asset addresses to cToken addresses
    mapping(address => address) public assetToCToken;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     * @param _maxCollateralFactor    Max collateral factor allowed
     */
    constructor(
        IBabController _controller,
        address _weth,
        uint256 _maxCollateralFactor
    ) BorrowIntegration('compoundborrow', _weth, _controller, _maxCollateralFactor) {
        assetToCToken[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643; // DAI
        assetToCToken[0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984] = 0x35A18000230DA775CAc24873d00Ff85BccdeD550; // UNI
        assetToCToken[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5; // WETH
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

    /**
     * Get the amount of borrowed debt that needs to be repaid
     * @param asset   The underlying asset
     *
     */
    function getBorrowBalance(address _strategy, address asset) public view override returns (uint256) {
        address cToken = assetToCToken[asset];
        (
            ,
            ,
            // err
            // cTokenBalance
            uint256 borrowBalance,

        ) = ICToken(cToken).getAccountSnapshot(_strategy);
        return borrowBalance;
    }

    /**
     * Get the amount of collateral depposited
     * @param asset   The collateral to check
     *
     */
    function getCollateralBalance(address _strategy, address asset) external view override returns (uint256) {
        address cToken = assetToCToken[asset];
        (
            ,
            // err
            uint256 cTokenBalance, // borrow balance
            ,
            uint256 exchangeRateMantissa
        ) = ICToken(cToken).getAccountSnapshot(_strategy);

        // Source: balanceOfUnderlying from any ctoken
        return cTokenBalance.mul(exchangeRateMantissa).div(10**ERC20(asset).decimals());
    }

    /**
     * Get the remaining liquidity available to borrow
     *
     */
    function getRemainingLiquidity(address _strategy) public view override returns (uint256) {
        IComptroller comptroller = IComptroller(CompoundComptrollerAddress);
        (
            ,
            /* error */
            uint256 liquidity, /* shortfall */

        ) = comptroller.getAccountLiquidity(_strategy);
        return liquidity;
    }

    /* ============ Overriden Functions ============ */

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

    /**
     * Return borrow token calldata
     *
     * hparam  _strategy                 Address of the strategy executing it
     * @param  _asset                    Address of the asset to deposit
     * @param  _amount                   Amount of the token to deposit
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getBorrowCalldata(
        address, /* _strategy */
        address _asset,
        uint256 _amount
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
        bytes memory methodData = abi.encodeWithSignature('borrow(uint256)', _amount);

        return (assetToCToken[_asset], 0, methodData);
    }

    /**
     * Return repay borrowed asset calldata
     *
     * hparam  _strategy                 Address of the strategy executing it
     * @param  _asset                    Address of the asset to deposit
     * @param  _amount                   Amount of the token to deposit
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getRepayCalldata(
        address, /* _strategy */
        address _asset,
        uint256 _amount
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
        bytes memory methodData = abi.encodeWithSignature('repayBorrow(uint256)', _amount);
        return (assetToCToken[_asset], 0, methodData);
    }

    /* ============ Internal Functions ============ */

    function _getCollateralAsset(
        address _asset,
        uint8 /* _borrowOp */
    ) internal view override returns (address) {
        // TODO: check this
        return assetToCToken[_asset];
    }

    function _getSpender(address _asset) internal view override returns (address) {
        return assetToCToken[_asset];
    }
}
