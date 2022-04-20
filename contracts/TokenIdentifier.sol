// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;
import {IBabController} from './interfaces/IBabController.sol';
import {ICToken} from './interfaces/external/compound/ICToken.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ITokenIdentifier} from './interfaces/ITokenIdentifier.sol';
import {IProtocolDataProvider} from './interfaces/external/aave/IProtocolDataProvider.sol';
import {AaveToken} from './interfaces/external/aave/AaveToken.sol';
import {IComptroller} from './interfaces/external/compound/IComptroller.sol';
import {ICurveMetaRegistry} from './interfaces/ICurveMetaRegistry.sol';
import {IPickleJarRegistry} from './interfaces/IPickleJarRegistry.sol';
import {IYearnVaultRegistry} from './interfaces/IYearnVaultRegistry.sol';
import {ICurvePoolV3} from './interfaces/external/curve/ICurvePoolV3.sol';
import {IMooniswap} from './interfaces/external/1inch/IMooniswap.sol';
import {IYearnVault} from './interfaces/external/yearn/IYearnVault.sol';
import {IStETH} from './interfaces/external/lido/IStETH.sol';
import {IWstETH} from './interfaces/external/lido/IWstETH.sol';

import {ControllerLib} from './lib/ControllerLib.sol';

/**
 * @title TokenIdentifier
 * @author Babylon Finance Protocol
 *
 * Returns the type of the asset
 */
contract TokenIdentifier is ITokenIdentifier {
    using ControllerLib for IBabController;

    /* ============ Constants ============ */

    IComptroller private constant COMP_COMPTROLLER = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
    IProtocolDataProvider private constant AAVE_PROVIDER =
        IProtocolDataProvider(address(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d)); // Aave Mainnet

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IStETH private constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH private constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    bytes32 private constant SUSHI_SYMBOL = keccak256(bytes('SLP'));
    bytes32 private constant UNI_SYMBOL = keccak256(bytes('UNI-V2'));

    // Token Types
    uint8 private constant COMP_TOKEN = 1;
    uint8 private constant AAVE_TOKEN = 2;
    uint8 private constant CREAM_TOKEN = 3; // deprecated but keep
    uint8 private constant SYNTH_TOKEN = 4; // deprecated but keep. may enable later
    uint8 private constant CURVE_LP_TOKEN = 5;
    uint8 private constant YEARN_TOKEN = 6;
    uint8 private constant LIDO_TOKEN = 7;
    uint8 private constant SUSHI_LP_TOKEN = 8;
    uint8 private constant UNIV2_LP_TOKEN = 9;
    uint8 private constant ONEINCH_LP_TOKEN = 10;
    uint8 private constant HARVESTV3_LP_TOKEN = 11;
    uint8 private constant VISOR_LP_TOKEN = 12;
    uint8 private constant PICKLE_JAR_TOKEN = 13;

    /* ============ State Variables ============ */

    IBabController public immutable controller;
    IPickleJarRegistry public jarRegistry;
    IYearnVaultRegistry public vaultRegistry;
    ICurveMetaRegistry public curveMetaRegistry;

    // Mapping of interest bearing aave tokens
    mapping(address => address) public aTokenToAsset;
    // Mapping of interest bearing compound tokens
    mapping(address => address) public cTokenToAsset;
    // Mapping of yearn vaults
    mapping(address => bool) public vaults;
    // Mapping of gamma visors
    mapping(address => bool) public visors;
    // Mapping of pickle jars
    mapping(address => bool) public jars;

    /* ============ Modifiers ============ */

    /* ============ Constructor ============ */

    constructor(
        IBabController _controller,
        IPickleJarRegistry _jarRegistry,
        IYearnVaultRegistry _vaultRegistry,
        ICurveMetaRegistry _curveMetaRegistry
    ) {
        controller = _controller;
        jarRegistry = _jarRegistry;
        vaultRegistry = _vaultRegistry;
        curveMetaRegistry = _curveMetaRegistry;

        // Fetches and copies data for faster & cheaper reads
        _refreshAAveReserves();
        _refreshCompoundTokens();
        _updateYearnVaults();
        _updatePickleJars();

        visors[0x705b3aCaF102404CfDd5e4A60535E4e70091273C] = true; // BABL-ETH Visor
        visors[0xf6eeCA73646ea6A5c878814e6508e87facC7927C] = true; // GAMMA-ETH Visor
        visors[0xc86B1e7FA86834CaC1468937cdd53ba3cCbC1153] = true; // FLOAT-ETH Visor
        visors[0x705b3aCaF102404CfDd5e4A60535E4e70091273C] = true; // BABL-ETH Visor
        visors[0xf6eeCA73646ea6A5c878814e6508e87facC7927C] = true; // GAMMA-ETH Visor
        visors[0xc86B1e7FA86834CaC1468937cdd53ba3cCbC1153] = true; // FLOAT-ETH Visor
    }

    /* ============ External Functions ============ */

    /**
     * Refreshes all aave mappings from protocol data provider on mainnetx
     */
    function refreshAAveReserves() external override {
        controller.onlyGovernanceOrEmergency();
        _refreshAAveReserves();
    }

    /**
     * Refreshes all ctoken mappings from compound comptroller
     */
    function refreshCompoundTokens() external override {
        controller.onlyGovernanceOrEmergency();
        _refreshCompoundTokens();
    }

    /**
     * Refreshes all yearn vaults from our registry
     */
    function updateYearnVaults() external override {
        controller.onlyGovernanceOrEmergency();
        _updateYearnVaults();
    }

    /**
     * Refreshes all pickle jars from our registry
     */
    function updatePickleJars() external override {
        controller.onlyGovernanceOrEmergency();
        _updatePickleJars();
    }

    /**
     * Adds/deletes visor vaults
     */
    function updateVisor(address[] calldata _visors, bool[] calldata _values) external override {
        controller.onlyGovernanceOrEmergency();
        _updateVisor(_visors, _values);
    }

    /**
     * Returns the types of the two tokens
     * @param _tokenIn              Address of the first token
     * @param _tokenOut             Address of the second token
     * @return (uint8,uint8)        Types of both tokens
     */
    function identifyTokens(
        address _tokenIn,
        address _tokenOut,
        ICurveMetaRegistry _curveMetaRegistry
    )
        external
        view
        override
        returns (
            uint8,
            uint8,
            address,
            address
        )
    {
        uint8 tokenInType;
        uint8 tokenOutType;
        address finalAssetIn;
        address finalAssetOut;

        // Compound
        if (cTokenToAsset[_tokenIn] != address(0)) {
            tokenInType = COMP_TOKEN;
            finalAssetIn = cTokenToAsset[_tokenIn];
        }
        if (cTokenToAsset[_tokenOut] != address(0)) {
            tokenOutType = COMP_TOKEN;
            finalAssetOut = cTokenToAsset[_tokenOut];
        }

        // aave tokens. 1 to 1 with underlying
        if (aTokenToAsset[_tokenIn] != address(0)) {
            tokenInType = AAVE_TOKEN;
            finalAssetIn = aTokenToAsset[_tokenIn];
        }
        if (aTokenToAsset[_tokenOut] != address(0)) {
            tokenOutType = AAVE_TOKEN;
            finalAssetOut = aTokenToAsset[_tokenOut];
        }

        // Checks visor
        if (visors[_tokenIn]) {
            tokenInType = VISOR_LP_TOKEN;
        }

        if (visors[_tokenOut]) {
            tokenOutType = VISOR_LP_TOKEN;
        }

        // Early exit
        if (tokenInType > 0 && tokenOutType > 0) {
            return (tokenInType, tokenOutType, finalAssetIn, finalAssetOut);
        }

        if (tokenInType == 0) {
            // Curve LP Token
            address crvPool = _curveMetaRegistry.getPoolFromLpToken(_tokenIn);
            if (crvPool != address(0)) {
                tokenInType = CURVE_LP_TOKEN;
            }
        }

        if (tokenOutType == 0) {
            address crvPool = _curveMetaRegistry.getPoolFromLpToken(_tokenOut);
            if (crvPool != address(0)) {
                tokenOutType = CURVE_LP_TOKEN;
            }
        }

        // Yearn vaults
        if (vaults[_tokenIn]) {
            tokenInType = YEARN_TOKEN;
        }

        if (vaults[_tokenOut]) {
            tokenOutType = YEARN_TOKEN;
        }

        // Pickle jars
        if (jars[_tokenIn]) {
            tokenInType = PICKLE_JAR_TOKEN;
        }

        if (jars[_tokenOut]) {
            tokenOutType = PICKLE_JAR_TOKEN;
        }

        // Checks stETH && wstETH (Lido tokens)
        if (_tokenIn == address(stETH) || _tokenIn == address(wstETH)) {
            tokenInType = LIDO_TOKEN;
        }
        if (_tokenOut == address(stETH) || _tokenOut == address(wstETH)) {
            tokenOutType = LIDO_TOKEN;
        }

        // Early exit
        if (tokenInType > 0 && tokenOutType > 0) {
            return (tokenInType, tokenOutType, finalAssetIn, finalAssetOut);
        }

        // Check sushi pairs (univ2)
        if (tokenInType == 0) {
            string memory tokenInSymbol = ERC20(_tokenIn).symbol();
            if (keccak256(bytes(tokenInSymbol)) == SUSHI_SYMBOL) {
                tokenInType = SUSHI_LP_TOKEN;
            }
            // Checks univ2
            if (keccak256(bytes(tokenInSymbol)) == UNI_SYMBOL) {
                tokenInType = UNIV2_LP_TOKEN;
            }
        }
        if (tokenOutType == 0) {
            string memory tokenOutSymbol = ERC20(_tokenOut).symbol();
            if (keccak256(bytes(tokenOutSymbol)) == SUSHI_SYMBOL) {
                tokenOutType = SUSHI_LP_TOKEN;
            }
            if (keccak256(bytes(tokenOutSymbol)) == UNI_SYMBOL) {
                tokenOutType = UNIV2_LP_TOKEN;
            }
        }

        // todo: convex tokens 1 to 1

        return (tokenInType, tokenOutType, finalAssetIn, finalAssetOut);
    }

    /* ============ Internal Functions ============ */

    function _refreshAAveReserves() private {
        IProtocolDataProvider.TokenData[] memory atokens = AAVE_PROVIDER.getAllATokens();
        for (uint256 i = 0; i < atokens.length; i++) {
            aTokenToAsset[atokens[i].tokenAddress] = AaveToken(atokens[i].tokenAddress).underlyingAssetAddress();
        }
    }

    /**
     * Refreshes all ctoken mappings from compound comptroller
     */
    function _refreshCompoundTokens() private {
        address[] memory markets = COMP_COMPTROLLER.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            cTokenToAsset[markets[i]] = ICToken(markets[i]).underlying();
        }
    }

    /**
     * Refreshes all yearn vaults from our registry
     */
    function _updateYearnVaults() private {
        address[] memory yvaults = vaultRegistry.getAllVaults();
        for (uint256 i = 0; i < yvaults.length; i++) {
            vaults[yvaults[i]] = true;
        }
    }

    /**
     * Refreshes all pickle jars from our registry
     */
    function _updatePickleJars() private {
        address[] memory pjars = jarRegistry.getAllJars();
        for (uint256 i = 0; i < pjars.length; i++) {
            jars[pjars[i]] = true;
        }
    }

    /**
     * Adds/deletes visor vaults
     */
    function _updateVisor(address[] calldata _visors, bool[] calldata _values) private {
        for (uint256 i = 0; i < _visors.length; i++) {
            visors[_visors[i]] = _values[i];
        }
    }
}
