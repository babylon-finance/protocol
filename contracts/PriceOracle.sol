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

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/SafeCast.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {ICToken} from './interfaces/external/compound/ICToken.sol';
import {ISnxExchangeRates} from './interfaces/external/synthetix/ISnxExchangeRates.sol';
import {ICurveAddressProvider} from './interfaces/external/curve/ICurveAddressProvider.sol';
import {ICurveRegistry} from './interfaces/external/curve/ICurveRegistry.sol';
import {ICurvePoolV3} from './interfaces/external/curve/ICurvePoolV3.sol';
import {IUniswapV2Router} from './interfaces/external/uniswap/IUniswapV2Router.sol';
import {ISnxSynth} from './interfaces/external/synthetix/ISnxSynth.sol';
import {ISnxProxy} from './interfaces/external/synthetix/ISnxProxy.sol';
import {IYearnRegistry} from './interfaces/external/yearn/IYearnRegistry.sol';
import {IYearnVault} from './interfaces/external/yearn/IYearnVault.sol';
import {IStETH} from './interfaces/external/lido/IStETH.sol';
import {IWstETH} from './interfaces/external/lido/IWstETH.sol';

import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';

/**
 * @title PriceOracle
 * @author Babylon Finance Protocol
 *
 * Uses Uniswap V3 to get a price of a token pair
 */
contract PriceOracle is Ownable, IPriceOracle {
    using PreciseUnitMath for int256;
    using PreciseUnitMath for uint256;
    using SafeMath for uint256;

    /* ============ State Variables ============ */

    /* ============ Constants ============ */

    // Address of Uniswap factory
    IUniswapV3Factory internal constant factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    ISnxExchangeRates internal constant snxEchangeRates = ISnxExchangeRates(0xd69b189020EF614796578AfE4d10378c5e7e1138);
    // Address of Curve Registry
    ICurveAddressProvider internal constant curveAddressProvider =
        ICurveAddressProvider(0x0000000022D53366457F9d5E68Ec105046FC4383);
    IUniswapV2Router internal constant uniRouterV2 = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IYearnRegistry private constant yearnRegistry = IYearnRegistry(0xE15461B18EE31b7379019Dc523231C57d1Cbc18c);

    address internal constant ETH_ADD_CURVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    IStETH private constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH private constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    // the desired seconds agos array passed to the observe method
    uint32 private constant SECONDS_GRANULARITY = 30;
    uint256 private constant CURVE_SLIPPAGE = 3e16;

    uint24 private constant FEE_LOW = 500;
    uint24 private constant FEE_MEDIUM = 3000;
    uint24 private constant FEE_HIGH = 10000;
    int24 private constant maxTwapDeviation = 100;
    uint160 private constant maxLiquidityDeviationFactor = 50;
    int24 private constant baseThreshold = 1000;

    // Mapping of cToken addresses
    mapping(address => address) public cTokenToAsset;
    // Mapping of interest bearing aave tokens
    mapping(address => address) public aTokenToAsset;
    // Mapping of cream tokens
    mapping(address => address) public crTokenToAsset;
    // Mapping of synths
    mapping(address => bool) public synths;
    // Mapping of yearn vaults
    mapping(address => bool) public vaults;

    /* ============ Constructor ============ */

    constructor() {
        cTokenToAsset[0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        cTokenToAsset[0x35A18000230DA775CAc24873d00Ff85BccdeD550] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        cTokenToAsset[0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5] = WETH; // ETH
        cTokenToAsset[0x39AA39c021dfbaE8faC545936693aC917d5E7563] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        cTokenToAsset[0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        cTokenToAsset[0xccF4429DB6322D5C611ee964527D42E5d685DD6a] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        cTokenToAsset[0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4] = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP
        cTokenToAsset[0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF; // BAT
        cTokenToAsset[0xFAce851a4921ce59e912d19329929CE6da6EB0c7] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
        cTokenToAsset[0x158079Ee67Fce2f58472A96584A73C7Ab9AC95c1] = 0x1985365e9f78359a9B6AD760e32412f4a445E862; // REP
        cTokenToAsset[0xF5DCe57282A584D2746FaF1593d3121Fcac444dC] = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359; // SAI
        cTokenToAsset[0x12392F67bdf24faE0AF363c24aC620a2f67DAd86] = 0x0000000000085d4780B73119b644AE5ecd22b376; // TUSD
        cTokenToAsset[0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407] = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // ZRX

        aTokenToAsset[0xFFC97d72E13E01096502Cb8Eb52dEe56f74DAD7B] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // aave
        aTokenToAsset[0x272F97b7a56a387aE942350bBC7Df5700f8a4576] = 0xba100000625a3754423978a60c9317c58a424e3D; // bal
        aTokenToAsset[0x05Ec93c0365baAeAbF7AefFb0972ea7ECdD39CF1] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF; // bat
        aTokenToAsset[0xA361718326c15715591c299427c62086F69923D9] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53; // busd
        aTokenToAsset[0x8dAE6Cb04688C62d939ed9B68d32Bc62e49970b1] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // crv
        aTokenToAsset[0x028171bCA77440897B824Ca71D1c56caC55b68A3] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // dai
        aTokenToAsset[0xaC6Df26a590F08dcC95D5a4705ae8abbc88509Ef] = 0xF629cBd94d3791C9250152BD8dfBDF380E2a3B9c; // enj
        aTokenToAsset[0xD37EE7e4f452C6638c96536e68090De8cBcdb583] = 0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd; // gusd
        aTokenToAsset[0x39C6b3e42d6A679d7D776778Fe880BC9487C2EDA] = 0xdd974D5C2e2928deA5F71b9825b8b646686BD200; // knc
        aTokenToAsset[0xa06bC25B5805d5F8d82847D191Cb4Af5A3e873E0] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // link
        aTokenToAsset[0xa685a61171bb30d4072B338c80Cb7b2c865c873E] = 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942; // mana
        aTokenToAsset[0xc713e5E149D5D0715DcD1c156a020976e7E56B88] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2; // mkr
        aTokenToAsset[0xc9BC48c72154ef3e5425641a3c747242112a46AF] = 0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919; // rai
        aTokenToAsset[0xCC12AbE4ff81c9378D670De1b57F8e0Dd228D77a] = 0x408e41876cCCDC0F92210600ef50372656052a38; // ren
        aTokenToAsset[0x35f6B052C598d933D69A4EEC4D04c73A191fE6c2] = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F; // snx
        aTokenToAsset[0x6C5024Cd4F8A59110119C56f8933403A539555EB] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51; // susd
        aTokenToAsset[0x101cc05f4A51C0319f570d5E146a8C625198e636] = 0x0000000000085d4780B73119b644AE5ecd22b376; // tusd
        aTokenToAsset[0xB9D7CB55f463405CDfBe4E90a6D2Df01C2B92BF1] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // uni
        aTokenToAsset[0xBcca60bB61934080951369a648Fb03DF4F96263C] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // usdc
        aTokenToAsset[0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // usdt
        aTokenToAsset[0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // wbtc
        aTokenToAsset[0x030bA81f1c18d280636F32af80b9AAd02Cf0854e] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // weth
        aTokenToAsset[0xF256CC7847E919FAc9B808cC216cAc87CCF2f47a] = 0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272; // xsushi
        aTokenToAsset[0x5165d24277cD063F5ac44Efd447B27025e888f37] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e; // yfi
        aTokenToAsset[0xDf7FF54aAcAcbFf42dfe29DD6144A69b629f8C9e] = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // zrx

        crTokenToAsset[0xD06527D5e56A3495252A528C4987003b712860eE] = WETH;
        crTokenToAsset[0x797AAB1ce7c01eB727ab980762bA88e7133d2157] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        crTokenToAsset[0x44fbeBd2F576670a6C33f6Fc0B00aA8c5753b322] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        crTokenToAsset[0xCbaE0A83f4f9926997c8339545fb8eE32eDc6b76] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e; // YFI
        crTokenToAsset[0xcE4Fe9b4b8Ff61949DCfeB7e03bc9FAca59D2Eb3] = 0xba100000625a3754423978a60c9317c58a424e3D; // BAL
        crTokenToAsset[0x19D1666f543D42ef17F66E376944A22aEa1a8E46] = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP
        crTokenToAsset[0x9baF8a5236d44AC410c0186Fe39178d5AAD0Bb87] = 0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8; // YCRV
        crTokenToAsset[0x892B14321a4FCba80669aE30Bd0cd99a7ECF6aC0] = 0x2ba592F78dB6436527729929AAf6c908497cB200; // CREAM
        crTokenToAsset[0x697256CAA3cCaFD62BB6d3Aa1C7C5671786A5fD9] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
        crTokenToAsset[0x8B86e0598616a8d4F1fdAE8b59E55FB5Bc33D0d6] = 0x80fB784B7eD66730e8b1DBd9820aFD29931aab03; // LEND
        crTokenToAsset[0xc7Fd8Dcee4697ceef5a2fd4608a7BD6A94C77480] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV
        crTokenToAsset[0x17107f40d70f4470d20CB3f138a052cAE8EbD4bE] = 0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D; // RENBTC
        crTokenToAsset[0x1FF8CDB51219a8838b52E9cAc09b71e591BC998e] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53; // BUSD
        crTokenToAsset[0x3623387773010d9214B10C551d6e7fc375D31F58] = 0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2; // MTA
        crTokenToAsset[0x4EE15f44c6F0d8d1136c83EfD2e8E4AC768954c6] = 0x4EE15f44c6F0d8d1136c83EfD2e8E4AC768954c6; // YYCRV
        crTokenToAsset[0x338286C0BC081891A4Bda39C7667ae150bf5D206] = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2; // SUSHI
        crTokenToAsset[0x10FDBD1e48eE2fD9336a482D746138AE19e649Db] = 0x50D1c9771902476076eCFc8B2A83Ad6b9355a4c9; // FTT
        crTokenToAsset[0x01da76DEa59703578040012357b81ffE62015C2d] = 0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7; // YETH
        crTokenToAsset[0xef58b2d5A1b8D3cDE67b8aB054dC5C831E9Bc025] = 0x476c5E26a75bd202a9683ffD34359C0CC15be0fF; // SRM
        crTokenToAsset[0xe89a6D0509faF730BD707bf868d9A2A744a363C7] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        crTokenToAsset[0xeFF039C3c1D668f408d09dD7B63008622a77532C] = 0x0d438F3b5175Bebc262bF23753C1E53d03432bDE; // WNXM
        crTokenToAsset[0x22B243B96495C547598D9042B6f94B01C22B2e9E] = 0x87eDfFDe3E14c7a66c9b9724747a1C5696b742e6; // SWAG
        crTokenToAsset[0x8b3FF1ed4F36C2c2be675AFb13CC3AA5d73685a5] = 0xaaAEBE6Fe48E54f431b0C390CfaF0b017d09D42d; // CEL
        crTokenToAsset[0x2A537Fa9FFaea8C1A41D3C2B68a9cb791529366D] = 0x1494CA1F11D487c2bBe4543E90080AeBa4BA3C2b; // DPI
        crTokenToAsset[0x7ea9C63E216D5565c3940A2B3d150e59C2907Db3] = 0x9BE89D2a4cd102D8Fecc6BF9dA793be995C22541; // BBTC
        crTokenToAsset[0x3225E3C669B39C7c8B3e204a8614bB218c5e31BC] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // AAVE
        crTokenToAsset[0xf55BbE0255f7f4E70f63837Ff72A577fbDDbE924] = 0x0391D2021f89DC339F60Fff84546EA23E337750f; // BOND
        crTokenToAsset[0x903560b1CcE601794C584F58898dA8a8b789Fc5d] = 0x1cEB5cB57C4D4E2b2433641b95Dd330A33185A44; // KP3R
        crTokenToAsset[0x054B7ed3F45714d3091e82aAd64A1588dC4096Ed] = 0x0316EB71485b0Ab14103307bf65a021042c6d380; // HBTC
        crTokenToAsset[0xd5103AfcD0B3fA865997Ef2984C66742c51b2a8b] = 0x9AFb950948c2370975fb91a441F36FDC02737cD4; // HFIL
        crTokenToAsset[0xfd609a03B393F1A1cFcAcEdaBf068CAD09a924E2] = 0xcBc1065255cBc3aB41a6868c22d1f1C573AB89fd; // CRETH2
        crTokenToAsset[0xD692ac3245bb82319A31068D6B8412796eE85d2c] = 0xdF574c24545E5FfEcb9a659c229253D4111d87e1; // HUSD
        crTokenToAsset[0x92B767185fB3B04F881e3aC8e5B0662a027A1D9f] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        crTokenToAsset[0x10a3da2BB0Fae4D591476fd97D6636fd172923a8] = 0x584bC13c7D411c00c01A62e8019472dE68768430; // HEGIC
        crTokenToAsset[0x3C6C553A95910F9FC81c98784736bd628636D296] = 0x36F3FD68E7325a35EB768F1AedaAe9EA0689d723; // ESD
        crTokenToAsset[0x21011BC93d9E515B9511A817A1eD1D6d468f49Fc] = 0x4688a8b1F292FDaB17E9a90c8Bc379dC1DBd8713; // COVER
        crTokenToAsset[0x85759961b116f1D36fD697855c57A6ae40793D9B] = 0x111111111117dC0aa78b770fA6A738034120C302; // 1INCH
        crTokenToAsset[0x7Aaa323D7e398be4128c7042d197a2545f0f1fea] = 0xd26114cd6EE289AccF82350c8d8487fedB8A0C07; // OMG
        crTokenToAsset[0x011a014d5e8Eb4771E575bB1000318D509230Afa] = 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940; // UNI-V2-WBTC-ETH
        crTokenToAsset[0xE6C3120F38F56deb38B69b65cC7dcAF916373963] = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852; // UNI-V2-ETH-USDT
        crTokenToAsset[0x4Fe11BC316B6d7A345493127fBE298b95AdaAd85] = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc; // UNI-V2-USDC-ETH
        crTokenToAsset[0xcD22C4110c12AC41aCEfA0091c432ef44efaAFA0] = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11; // UNI-V2-DAI-ETH
        crTokenToAsset[0x228619CCa194Fbe3Ebeb2f835eC1eA5080DaFbb2] = 0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272; // XSUSHI
        crTokenToAsset[0x73f6cBA38922960b7092175c0aDD22Ab8d0e81fC] = 0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58; // SLP-WBTC-ETH
        crTokenToAsset[0x38f27c03d6609a86FF7716ad03038881320BE4Ad] = 0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f; // SLP-DAI-ETH
        crTokenToAsset[0x5EcaD8A75216CEa7DFF978525B2D523a251eEA92] = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0; // SLP-USDC-ETH
        crTokenToAsset[0x5C291bc83d15f71fB37805878161718eA4b6AEe9] = 0x06da0fd433C1A5d7a4faa01111c044910A184553; // SLP-ETH-USDT
        crTokenToAsset[0x6BA0C66C48641e220CF78177C144323b3838D375] = 0x795065dCc9f64b5614C407a6EFDC400DA6221FB0; // SLP-SUSHI-ETH
        crTokenToAsset[0xd532944df6DFd5Dd629E8772F03D4fC861873abF] = 0x088ee5007C98a9677165D78dD2109AE4a3D04d0C; // SLP-YFI-ETH
        crTokenToAsset[0x197070723CE0D3810a0E47F06E935c30a480D4Fc] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        crTokenToAsset[0xC25EAE724f189Ba9030B2556a1533E7c8A732E14] = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F; // SNX
        crTokenToAsset[0x25555933a8246Ab67cbf907CE3d1949884E82B55] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51; // SUSD
        crTokenToAsset[0xc68251421eDDa00a10815E273fA4b1191fAC651b] = 0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5; // PICKLE
        crTokenToAsset[0x65883978aDA0e707c3b2BE2A6825b1C4BDF76A90] = 0x8Ab7404063Ec4DBcfd4598215992DC3F8EC853d7; // AKRO
        crTokenToAsset[0x8B950f43fCAc4931D408F1fcdA55C6CB6cbF3096] = 0x19D97D8fA813EE2f51aD4B4e04EA08bAf4DFfC28; // BBADGER
        crTokenToAsset[0x59089279987DD76fC65Bf94Cb40E186b96e03cB3] = 0x8207c1FfC5B6804F6024322CcF34F29c3541Ae26; // OGN
        crTokenToAsset[0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6] = 0xfF20817765cB7f73d4bde2e66e067E58D11095C2; // AMP
        crTokenToAsset[0xb092b4601850E23903A42EaCBc9D8A0EeC26A4d5] = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX
        crTokenToAsset[0x1d0986Fb43985c88Ffa9aD959CC24e6a087C7e35] = 0xa1faa113cbE53436Df28FF0aEe54275c13B40975; // ALPHA
        crTokenToAsset[0x51F48b638F82e8765F7a26373A2Cb4CcB10C07af] = 0xa47c8bf37f92aBed4A126BDA807A7b7498661acD; // UST
        crTokenToAsset[0xc36080892c64821fa8e396bc1bD8678fA3b82b17] = 0x4E15361FD6b4BB609Fa63C81A2be19d873717870; // FTM
        crTokenToAsset[0x8379BAA817c5c5aB929b03ee8E3c48e45018Ae41] = 0x3155BA85D5F96b2d030a4966AF206230e46849cb; // RUNE
        crTokenToAsset[0x299e254A8a165bBeB76D9D69305013329Eea3a3B] = 0xbC396689893D065F41bc2C6EcbeE5e0085233447; // PERP
        crTokenToAsset[0xf8445C529D363cE114148662387eba5E62016e20] = 0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919; // RAI
        crTokenToAsset[0x7C3297cFB4c4bbd5f44b450c0872E0ADA5203112] = 0x967da4048cD07aB37855c090aAF366e4ce1b9F48; // OCEAN
        crTokenToAsset[0xA87e8e61dfAC8af5944D353Cd26B96B20d5f4D01] = 0x986b4AFF588a109c09B50A03f42E4110E29D353F; // YVECRV CHECK!
        crTokenToAsset[0x081FE64df6dc6fc70043aedF3713a3ce6F190a21] = 0xFca59Cd816aB1eaD66534D82bc21E7515cE441CF; // RARI
        crTokenToAsset[0x28526Bb33d7230E65E735dB64296413731C5402e] = 0xb753428af26E81097e7fD17f40c88aaA3E04902c; // SFI
        crTokenToAsset[0x45406ba53bB84Cd32A58e7098a2D4D1b11B107F6] = 0x27b7b1ad7288079A66d12350c828D3C00A6F07d7; // YVCurve-IB CHECK!
        crTokenToAsset[0x6d1B9e01aF17Dd08d6DEc08E210dfD5984FF1C20] = 0x986b4AFF588a109c09B50A03f42E4110E29D353F; // YVCurve-sETH
        crTokenToAsset[0x1F9b4756B008106C806c7E64322d7eD3B72cB284] = 0xdCD90C7f6324cfa40d7169ef80b12031770B4325; // YVCurve-stETH
        crTokenToAsset[0xab10586C918612BA440482db77549d26B7ABF8f7] = 0x1337DEF16F9B486fAEd0293eb623Dc8395dFE46a; // ARMOR
        crTokenToAsset[0xdFFf11DFe6436e42a17B86e7F419Ac8292990393] = 0x1337DEF18C680aF1f9f45cBcab6309562975b1dD; // ARNXM
        crTokenToAsset[0xDbb5e3081dEf4b6cdD8864aC2aeDA4cBf778feCf] = 0xec67005c4E498Ec7f55E092bd1d35cbC47C91892; // MLN
        crTokenToAsset[0x71cEFCd324B732d4E058AfAcBA040d908c441847] = 0x1b40183EFB4Dd766f11bDa7A7c3AD8982e998421; // VSP
        crTokenToAsset[0x1A122348B73B58eA39F822A89e6ec67950c2bBD0] = 0xbA4cFE5741b357FA371b506e5db0774aBFeCf8Fc; // VVSP
        crTokenToAsset[0x523EFFC8bFEfC2948211A05A905F761CBA5E8e9E] = 0x6810e776880C02933D47DB1b9fc05908e5386b96; // GNO
        crTokenToAsset[0x4202D97E00B9189936EdF37f8D01cfF88BDd81d4] = 0xa9fE4601811213c340e850ea305481afF02f5b28; // YVWETH
        crTokenToAsset[0x4BAa77013ccD6705ab0522853cB0E9d453579Dd4] = 0x4BAa77013ccD6705ab0522853cB0E9d453579Dd4; // YUSD
        crTokenToAsset[0x98E329eB5aae2125af273102f3440DE19094b77c] = 0xCC4304A31d09258b0029eA7FE63d032f52e44EFe; // SWAP
        crTokenToAsset[0x8C3B7a4320ba70f8239F83770c4015B5bc4e6F91] = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA; // FEI
        crTokenToAsset[0xE585c76573D7593ABF21537B607091F76c996E73] = 0x4691937a7508860F876c9c0a2a617E7d9E945D4B; // WOO
        crTokenToAsset[0x81E346729723C4D15d0FB1c5679b9f2926Ff13C6] = 0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C; // BNT

        synths[0x57Ab1ec28D129707052df4dF418D58a2D46d5f51] = true; // ProxyERC20sUSD
        synths[0x176C674Ee533C6139B0dc8b458D72A93dCB3e705] = true; // ProxyiAAVE
        synths[0x8A8079c7149B8A1611e5C5d978DCA3bE16545F83] = true; // ProxyiADA
        synths[0xAFD870F32CE54EfdBF677466B612bf8ad164454B] = true; // ProxyiBNB
        synths[0xD6014EA05BDe904448B743833dDF07c3C7837481] = true; // ProxyiBTC
        synths[0x336213e1DDFC69f4701Fc3F86F4ef4A160c1159d] = true; // ProxyiCEX
        synths[0x6345728B1ccE16E6f8C509950b5c84FFF88530d9] = true; // ProxyiCOMP
        synths[0xCB98f42221b2C251A4E74A1609722eE09f0cc08E] = true; // ProxyiDASH
        synths[0x14d10003807AC60d07BB0ba82cAeaC8d2087c157] = true; // ProxyiDEFI
        synths[0x46a97629C9C1F58De6EC18C7F536e7E6d6A6ecDe] = true; // ProxyiDOT
        synths[0xF4EebDD0704021eF2a6Bbe993fdf93030Cd784b4] = true; // ProxyiEOS
        synths[0xd50c1746D835d2770dDA3703B69187bFfeB14126] = true; // ProxyiETC
        synths[0xA9859874e1743A32409f75bB11549892138BBA1E] = true; // ProxyiETH
        synths[0x2d7aC061fc3db53c39fe1607fB8cec1B2C162B01] = true; // ProxyiLINK
        synths[0x79da1431150C9b82D2E5dfc1C68B33216846851e] = true; // ProxyiLTC
        synths[0xA5a5DF41883Cdc00c4cCC6E8097130535399d9a3] = true; // ProxyiOIL
        synths[0x0fEd38108bdb8e62ef7b5680E8E0726E2F29e0De] = true; // ProxyiREN
        synths[0xC5807183a9661A533CB08CbC297594a0B864dc12] = true; // ProxyiTRX
        synths[0x36A00FF9072570eF4B9292117850B8FE08d96cce] = true; // ProxyiUNI
        synths[0x4AdF728E2Df4945082cDD6053869f51278fae196] = true; // ProxyiXMR
        synths[0x27269b3e45A4D3E79A3D6BFeE0C8fB13d0D711A6] = true; // ProxyiXRP
        synths[0x8deef89058090ac5655A99EEB451a4f9183D1678] = true; // ProxyiXTZ
        synths[0x592244301CeA952d6daB2fdC1fE6bd9E53917306] = true; // ProxyiYFI
        synths[0xcD39b5434a0A92cf47D1F567a7dF84bE356814F0] = true; // Proxys1INCH
        synths[0x7537AAe01f3B218DAE75e10d952473823F961B87] = true; // ProxysAAPL
        synths[0xd2dF355C19471c8bd7D8A3aa27Ff4e26A21b4076] = true; // ProxysAAVE
        synths[0xe36E2D3c7c34281FA3bC737950a68571736880A1] = true; // ProxysADA
        synths[0x9CF7E61853ea30A41b02169391b393B901eac457] = true; // ProxysAMZN
        synths[0xF48e200EAF9906362BB1442fca31e0835773b8B4] = true; // ProxysAUD
        synths[0x617aeCB6137B5108D1E7D4918e3725C8cEbdB848] = true; // ProxysBNB
        synths[0xfE18be6b3Bd88A2D2A7f928d00292E7a9963CfC6] = true; // ProxysBTC
        synths[0xeABACD844A196D7Faf3CE596edeBF9900341B420] = true; // ProxysCEX
        synths[0x0F83287FF768D1c1e17a42F44d644D7F22e8ee1d] = true; // ProxysCHF
        synths[0x9EeF4CA7aB9fa8bc0650127341C2d3F707a40f8A] = true; // ProxysCOIN
        synths[0xEb029507d3e043DD6C87F2917C4E82B902c35618] = true; // ProxysCOMP
        synths[0xD38aEb759891882e78E957c80656572503D8c1B1] = true; // ProxysCRV
        synths[0xfE33ae95A9f0DA8A845aF33516EDc240DCD711d6] = true; // ProxysDEFI
        synths[0x1715AC0743102BF5Cd58EfBB6Cf2dC2685d967b6] = true; // ProxysDOT
        synths[0x88C8Cf3A212c0369698D13FE98Fcb76620389841] = true; // ProxysEOS
        synths[0x22602469d704BfFb0936c7A7cfcD18f7aA269375] = true; // ProxysETC
        synths[0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb] = true; // ProxysETH
        synths[0xD71eCFF9342A5Ced620049e616c5035F1dB98620] = true; // ProxysEUR
        synths[0xf50B5e535F62a56A9BD2d8e2434204E726c027Fa] = true; // ProxysFB
        synths[0x23348160D7f5aca21195dF2b70f28Fce2B0be9fC] = true; // ProxysFTSE
        synths[0x97fe22E7341a0Cd8Db6F6C021A24Dc8f4DAD855F] = true; // ProxysGBP
        synths[0xC63B8ECCE56aB9C46184eC6aB85e4771fEa4c8AD] = true; // ProxysGOOG
        synths[0xF6b1C627e95BFc3c1b4c9B825a032Ff0fBf3e07d] = true; // ProxysJPY
        synths[0x269895a3dF4D73b077Fc823dD6dA1B95f72Aaf9B] = true; // ProxysKRW
        synths[0xbBC455cb4F1B9e4bFC4B73970d360c8f032EfEE6] = true; // ProxysLINK
        synths[0xC14103C2141E842e228FBaC594579e798616ce7A] = true; // ProxysLTC
        synths[0x745a824D6aBBD236AA794b5530062778A6Ad7523] = true; // ProxysMSFT
        synths[0x5A7E3c07604EB515C16b36cd51906a65f021F609] = true; // ProxysNFLX
        synths[0x757de3ac6B830a931eF178C6634c5C551773155c] = true; // ProxysNIKKEI
        synths[0x6d16cF3EC5F763d4d99cB0B0b110eefD93B11B56] = true; // ProxysOIL
        synths[0xD31533E8d0f3DF62060e94B3F1318137bB6E3525] = true; // ProxysREN
        synths[0x0352557B007A4Aae1511C114409b932F06F9E2f4] = true; // ProxysRUNE
        synths[0xf2E08356588EC5cd9E437552Da87C0076b4970B0] = true; // ProxysTRX
        synths[0x918dA91Ccbc32B7a6A0cc4eCd5987bbab6E31e6D] = true; // ProxysTSLA
        synths[0x30635297E450b930f8693297eBa160D9e6c8eBcf] = true; // ProxysUNI
        synths[0x6A22e5e94388464181578Aa7A6B869e00fE27846] = true; // ProxysXAG
        synths[0x261EfCdD24CeA98652B9700800a13DfBca4103fF] = true; // ProxysXAU
        synths[0x5299d6F7472DCc137D7f3C4BcfBBB514BaBF341A] = true; // ProxysXMR
        synths[0xa2B0fDe6D710e201d0d608e924A484d1A5fEd57c] = true; // ProxysXRP
        synths[0x2e59005c5c0f0a4D77CcA82653d48b46322EE5Cd] = true; // ProxysXTZ
        synths[0x992058B7DB08F9734d84485bfbC243C4ee6954A7] = true; // ProxysYFI

        vaults[0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417] = true; // Curve USDP Pool yVault
        vaults[0x49b3E44e54b6220aF892DbA48ae45F1Ea6bC4aE9] = true; // TUSD yVault
        vaults[0x25212Df29073FfFA7A67399AcEfC2dd75a831A1A] = true; // Curve EURS Pool yVault
        vaults[0xDdb166C6CB38CEDe52d12c405b6e906c1fB6f9d7] = true; // crvRenWSBTC yVault
        vaults[0x32651dD149a6EC22734882F790cBEB21402663F9] = true; // USDT yVault
        vaults[0x1f6BDffBadD98e410F83C66D1278241375F5199f] = true; // WBTC yVault
        vaults[0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9] = true; // USDC yVault
        vaults[0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E] = true; // WBTC yVault
        vaults[0xE537B5cc158EB71037D4125BDD7538421981E6AA] = true; // Curve 3Crypto Pool yVault
        vaults[0xa5cA62D95D24A4a350983D5B8ac4EB8638887396] = true; // sUSD yVault
        vaults[0x4A3FE75762017DB0eD73a71C9A06db7768DB5e66] = true; // COMP yVault
        vaults[0x0FCDAeDFb8A7DfDa2e9838564c5A1665d856AFDF] = true; // yearn Curve.fi MUSD/3Crv
        vaults[0xd9788f3931Ede4D5018184E198699dC6d66C1915] = true; // AAVE yVault
        vaults[0x722f76f34cB5c3B008A50E0664e55A53F4F461AB] = true; // yvUSDT MetaVault
        vaults[0x27b7b1ad7288079A66d12350c828D3C00A6F07d7] = true; // Curve Iron Bank Pool yVault
        vaults[0x8ee57c05741aA9DB947A744E713C15d4d19D8822] = true; // Curve yBUSD Pool yVault
        vaults[0x32413274504908460f0c373C7f20F429Fb80ed3A] = true; // saCRV yVault
        vaults[0x8B58Aa42A4Aa222b684078459CE03Dd0A43342B1] = true; // USDP yVault
        vaults[0x5737022626C282a89D105fD2e89ed6928EbDAe93] = true; // eCRV yVault
        vaults[0x5dbcF33D8c2E976c6b560249878e6F1491Bca25c] = true; // yearn Curve.fi yDAI/yUSDC/yUSDT/yTUSD
        vaults[0x3149950258FbBcE1638d6C23ac93A692604Ef864] = true; // crvRenWBTC yVault
        vaults[0x8cc94ccd0f3841a468184aCA3Cc478D2148E1757] = true; // Curve mUSD Pool yVault
        vaults[0x3C90033684F2504D55eeb652720785F70FA692D4] = true; // crvCOMP
        vaults[0x0F6121fB28C7C42916d663171063c62684598f9F] = true; // HBTC yVault
        vaults[0x23D3D0f1c697247d5e0a9efB37d8b0ED0C464f7f] = true; // Curve tBTC Pool yVault
        vaults[0xcC7E70A958917cCe67B4B87a8C30E6297451aE98] = true; // yearn Curve.fi GUSD/3Crv
        vaults[0x8fA3A9ecd9EFb07A8CE90A6eb014CF3c0E3B32Ef] = true; // Curve BBTC Pool yVault
        vaults[0xdA816459F1AB5631232FE5e97a05BBBb94970c95] = true; // DAI yVault
        vaults[0x6D2F347DCFc55C6AC80e515a58344acd7FeF0B84] = true; // bCRV yVault
        vaults[0x0e880118C29F095143dDA28e64d95333A9e75A47] = true; // eCRV yVault
        vaults[0x80bbeE2fa460dA291e796B9045e93d19eF948C6A] = true; // Curve Pax Pool yVault
        vaults[0x03403154afc09Ce8e44C3B185C82C6aD5f86b9ab] = true; // yearn Curve.fi aDAI/aUSDC/aUSDT
        vaults[0xFe8A3837cFf919C800bdC5d1ac6136F84497d679] = true; // UNI yVault
        vaults[0x0ff3773a6984aD900f7FB23A9acbf07AC3aDFB06] = true; // Curve Y Pool yVault
        vaults[0xD6Ea40597Be05c201845c0bFd2e96A60bACde267] = true; // Curve Compound Pool yVault
        vaults[0x597aD1e0c13Bfe8025993D9e79C69E1c0233522e] = true; // yearn USD//C
        vaults[0xBacB69571323575C6a5A3b4F9EEde1DC7D31FBc1] = true; // yearn Curve.fi aDAI/aSUSD
        vaults[0xac333895ce1A73875CF7B4Ecdc5A743C12f3d82B] = true; // WETH yVault
        vaults[0x4962B6C40B5E9433E029c5c423F6b1ce7fF28b0f] = true; // sUSD yVault
        vaults[0x7158c1Bee7a0Fa5BD6AFFc77b2309991D7ADCdd4] = true; // USDC yVault
        vaults[0xAc1C90b9c76d56BA2e24F3995F7671c745f8f308] = true; // AAVE yVault
        vaults[0x8e6741b456a074F0Bc45B8b82A755d4aF7E965dF] = true; // yearn Curve.fi DUSD/3Crv
        vaults[0x3D980E50508CFd41a13837A60149927a11c03731] = true; // Curve triCrypto Pool yVault
        vaults[0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7] = true; // yearn Wrapped Ether
        vaults[0xFBEB78a723b8087fD2ea7Ef1afEc93d35E8Bed42] = true; // UNI yVault
        vaults[0xdb25cA703181E7484a155DD612b06f57E12Be5F0] = true; // YFI yVault
        vaults[0xFe39Ce91437C76178665D64d7a2694B0f6f17fE3] = true; // yearn Curve.fi USDN/3Crv
        vaults[0xe11ba472F74869176652C35D30dB89854b5ae84D] = true; // HEGIC yVault
        vaults[0xB4AdA607B9d6b2c9Ee07A275e9616B84AC560139] = true; // Curve FRAX Pool yVault
        vaults[0xa2619fDFB99ABeb533a1147461f3f1109c5ADe75] = true; // WETH yVault
        vaults[0x629c759D1E83eFbF63d84eb3868B564d9521C129] = true; // yearn Curve.fi cDAI/cUSDC
        vaults[0x1133b2E2F51becCF25b2f8d0cA48c1d93DD5ab12] = true; // OCEAN yVault
        vaults[0x1Ae8Ccd120A05080d9A01C3B4F627F865685D091] = true; // WBTC yVault
        vaults[0x7356f09C294Cb9c6428AC7327B24B0f29419C181] = true; // SNX yVault
        vaults[0x873fB544277FD7b977B196a826459a69E27eA4ea] = true; // RAI yVault
        vaults[0x2147935D9739da4E691b8Ae2e1437492A394eBf5] = true; // WETH ubiVault
        vaults[0x3D27705c64213A5DcD9D26880c1BcFa72d5b6B0E] = true; // Curve USDK Pool yVault
        vaults[0x4C4A6A22bCE915C724A66b82128577F1B24831eD] = true; // Curve EURT Pool yVault
        vaults[0xB98Df7163E61bf053564bde010985f67279BBCEC] = true; // DAI yVault
        vaults[0x5fA5B62c8AF877CB37031e0a3B2f34A78e3C56A6] = true; // Curve LUSD Pool yVault
        vaults[0x625b7DF2fa8aBe21B0A976736CDa4775523aeD1E] = true; // Curve HBTC Pool yVault
        vaults[0x5120FeaBd5C21883a4696dBCC5D123d6270637E9] = true; // WETH yVault
        vaults[0x30FCf7c6cDfC46eC237783D94Fc78553E79d4E9C] = true; // Curve DUSD Pool yVault
        vaults[0xf8768814b88281DE4F532a3beEfA5b85B69b9324] = true; // Curve TUSD Pool yVault
        vaults[0xF6C9E9AF314982A4b38366f4AbfAa00595C5A6fC] = true; // yearn Curve.fi UST/3Crv
        vaults[0xcE0F1Ef5aAAB82547acc699d3Ab93c069bb6e547] = true; // sUSD-hedging yVault
        vaults[0x96Ea6AF74Af09522fCB4c28C269C26F59a31ced6] = true; // yearn Curve.fi LINK/sLINK
        vaults[0xAaAee277F21Bb7D2Bf49E6b36d0d94DC229B0B25] = true; // LUSD yVault
        vaults[0x0d4EA8536F9A13e4FBa16042a46c30f092b06aA5] = true; // Curve EURT Pool yVault
        vaults[0x39CAF13a104FF567f71fd2A4c68C026FDB6E740B] = true; // Curve Aave Pool yVault
        vaults[0x671a912C10bba0CFA74Cfc2d6Fba9BA1ed9530B2] = true; // LINK yVault
        vaults[0xe9Dc63083c464d6EDcCFf23444fF3CFc6886f6FB] = true; // Curve oBTC Pool yVault
        vaults[0x7047F90229a057C13BF847C0744D646CFb6c9E1A] = true; // Curve renBTC Pool yVault
        vaults[0xb4D1Be44BfF40ad6e506edf43156577a3f8672eC] = true; // Curve sAave Pool yVault
        vaults[0x5B707472eeF1553646740a7e5BEcFD41B9B4Ef4C] = true; // COMP yVault
        vaults[0x9d409a0A012CFbA9B15F6D4B36Ac57A46966Ab9a] = true; // Yearn Compounding veCRV yVault
        vaults[0xa442BEB83baBC33D93c8Bec471070Ce59b88fb7d] = true; // WETH yVault
        vaults[0x9cA85572E6A3EbF24dEDd195623F188735A5179f] = true; // yearn Curve.fi DAI/USDC/USDT
        vaults[0x7Da96a3891Add058AdA2E826306D812C638D87a7] = true; // USDT yVault
        vaults[0x477faf103dADc5Fe5BAa40951cf7512dcBC18126] = true; // USDC yVault
        vaults[0x054AF22E1519b020516D72D749221c24756385C9] = true; // Curve HUSD Pool yVault
        vaults[0xBF7AA989192b020a8d3e1C65a558e123834325cA] = true; // HBTC yVault
        vaults[0x19D3364A399d251E894aC732651be8B0E4e85001] = true; // DAI yVault
        vaults[0x3466c90017F82DDA939B01E8DBd9b0f97AEF8DfC] = true; // sUSD yVault
        vaults[0xB8C3B7A2A618C552C23B1E4701109a9E756Bab67] = true; // 1INCH yVault
        vaults[0x7F83935EcFe4729c4Ea592Ab2bC1A32588409797] = true; // yearn Curve.fi oBTC/sbtcCRV
        vaults[0x3408324Dbb537886CADc180f6FfCf674eE215F67] = true; // "renBTC yVault"
        vaults[0x3c5DF3077BcF800640B5DAE8c91106575a4826E6] = true; // Curve pBTC Pool yVault
        vaults[0x0e8A7717A4FD7694682E7005957dD5d7598bF14A] = true; // yExperimentalWBTC
        vaults[0xD2C65E20C3fDE3F18097e7414e65596e0C83B1a9] = true; // ICE yVault
        vaults[0x7Ff566E1d69DEfF32a7b244aE7276b9f90e9D0f6] = true; // yearn Curve.fi renBTC/wBTC/sBTC
        vaults[0x4856A7EFBbFcaE92AB13c5e2e322Fc77647bB856] = true; // RAI yVault
        vaults[0x5533ed0a3b83F70c3c4a1f69Ef5546D3D4713E44] = true; // yearn Curve.fi DAI/USDC/USDT/sUSD
        vaults[0xbD65955F752B2eF093B34B05e5FFb439AE8e5049] = true; // COMP yVault
        vaults[0xa9fE4601811213c340e850ea305481afF02f5b28] = true; // WETH yVault
        vaults[0x71955515ADF20cBDC699B8bC556Fc7Fd726B31B0] = true; // USDC yVault
        vaults[0x6d765CbE5bC922694afE112C140b8878b9FB0390] = true; // SUSHI yVault
        vaults[0x497590d2d57f05cf8B42A36062fA53eBAe283498] = true; // SUSHI yVault
        vaults[0x2DfB14E32e2F8156ec15a2c21c3A6c053af52Be8] = true; // Curve MIM Pool yVault
        vaults[0xED0244B688cF059f32f45E38A6ac6E479D6755f6] = true; // WETH yVault
        vaults[0x4B5BfD52124784745c1071dcB244C6688d2533d3] = true; // Curve Y Pool yVault
        vaults[0x2f08119C6f07c006695E079AAFc638b8789FAf18] = true; // yearn Tether USD
        vaults[0x46AFc2dfBd1ea0c0760CAD8262A5838e803A37e5] = true; // yearn Curve.fi hBTC/wBTC
        vaults[0x123964EbE096A920dae00Fb795FFBfA0c9Ff4675] = true; // yearn Curve.fi pBTC/sbtcCRV
        vaults[0x03c31f3444357087d5f568d24AE17f9177c8AA84] = true; // LINK yVault
        vaults[0xC116dF49c02c5fD147DE25Baa105322ebF26Bd97] = true; // Curve RSV Pool yVault
        vaults[0x2F194Da57aa855CAa02Ea3Ab991fa5d38178B9e6] = true; // UNI yVault
        vaults[0x98B058b2CBacF5E99bC7012DF757ea7CFEbd35BC] = true; // yearn Curve.fi EURS/sEUR
        vaults[0x07FB4756f67bD46B748b16119E802F1f880fb2CC] = true; // yearn Curve.fi tBTC/sbtcCrv
        vaults[0x3B96d491f067912D18563d56858Ba7d6EC67a6fa] = true; // Curve USDN Pool yVault
        vaults[0x39546945695DCb1c037C836925B355262f551f55] = true; // yearn Curve.fi HUSD/3Crv
        vaults[0xBfedbcbe27171C418CDabC2477042554b1904857] = true; // Curve rETH Pool yVault
        vaults[0x37d19d1c4E1fa9DC47bD1eA12f742a0887eDa74a] = true; // yearn TrueUSD
        vaults[0x8472E9914C0813C4b465927f82E213EA34839173] = true; // sBTC yVault
        vaults[0xFD0877d9095789cAF24c98F7CCe092fa8E120775] = true; // TUSD yVault
        vaults[0xF11b141BE4D1985E41c3AEa99417e27603F67c4c] = true; // wAAVE
        vaults[0xA8B1Cb4ed612ee179BDeA16CCa6Ba596321AE52D] = true; // yearn Curve.fi bBTC/sbtcCRV
        vaults[0xcB550A6D4C8e3517A939BC79d0c7093eb7cF56B5] = true; // WBTC yVault
        vaults[0x6Ede7F19df5df6EF23bD5B9CeDb651580Bdf56Ca] = true; // Curve BUSD Pool yVault
        vaults[0x881b06da56BB5675c54E4Ed311c21E54C5025298] = true; // yearn ChainLink Token
        vaults[0x79fF6c5A23B492619661F7c5b73a961114A4C940] = true; // AAVE yVault
        vaults[0x986b4AFF588a109c09B50A03f42E4110E29D353F] = true; // Curve sETH Pool yVault
        vaults[0xf4fDbc7C66Dc9832D672Ffe6242B6A386CeAd5DE] = true; // sUSD yVault
        vaults[0xdCD90C7f6324cfa40d7169ef80b12031770B4325] = true; // Curve stETH Pool yVault
        vaults[0x132d8D2C76Db3812403431fAcB00F3453Fc42125] = true; // Curve ankrETH Pool yVault
        vaults[0xF962B098Ecc4352aA2AD1d4164BD2b8367fd94c3] = true; // LINK yVault
        vaults[0xbda3A6CB2aaef41805F6317841d7B8654eC8b124] = true; // crvRenWBTC yVault
        vaults[0xACd43E627e64355f1861cEC6d3a6688B31a6F952] = true; // yearn Dai Stablecoin
        vaults[0x75A3f32ba5e60A094729257EE44841F9552baFb9] = true; // AAVE yVault
        vaults[0x84E13785B5a27879921D6F685f041421C7F482dA] = true; // Curve 3pool yVault
        vaults[0xf2db9a7c0ACd427A680D640F02d90f6186E71725] = true; // Curve LINK Pool yVault
        vaults[0x19b8Bc5CcF9700e16f2780bEA152F01C449f45D0] = true; // ALCX yVault
        vaults[0xF29AE508698bDeF169B89834F76704C3B205aedf] = true; // SNX yVault
        vaults[0x63859212aa05d60295a2F18a9e0C707040605BAd] = true; // DAI ubiVault
        vaults[0x1B5eb1173D2Bf770e50F10410C9a96F7a8eB6e75] = true; // yearn Curve.fi USDP/3Crv
        vaults[0x2994529C0652D127b7842094103715ec5299bBed] = true; // yearn Curve.fi yDAI/yUSDC/yUSDT/yBUSD
        vaults[0xdf5110EF6bc751cBaf76D35B8A3f312b581B5173] = true; // DAI ubiVault
        vaults[0x1C6a9783F812b3Af3aBbf7de64c3cD7CC7D1af44] = true; // Curve UST Pool yVault
        vaults[0x56A5Fd5104a4956898753dfb060ff32882Ae0eb4] = true; // ALCX yVault
        vaults[0x5a770DbD3Ee6bAF2802D29a901Ef11501C44797A] = true; // Curve sUSD Pool yVault
        vaults[0xb32747B4045479B77a8b8Eb44029ba12580214F8] = true; // SUSHI yVault
        vaults[0xE14d13d8B3b85aF791b2AADD661cDBd5E6097Db1] = true; // YFI yVault
        vaults[0xE625F5923303f1CE7A43ACFEFd11fd12f30DbcA4] = true; // yearn Curve.fi ETH/aETH
        vaults[0x29E240CFD7946BA20895a7a02eDb25C210f9f324] = true; // yearn Aave Interest bearing LINK
        vaults[0x2a38B9B0201Ca39B17B460eD2f11e4929559071E] = true; // Curve GUSD Pool yVault
        vaults[0x28a5b95C101df3Ded0C0d9074DB80C438774B6a9] = true; // Curve USDT Pool yVault
        vaults[0x8414Db07a7F743dEbaFb402070AB01a4E0d2E45e] = true; // Curve sBTC Pool yVault
        vaults[0xAf322a2eDf31490250fdEb0D712621484b09aBB6] = true; // USDT yVault
        vaults[0xBA2E7Fed597fd0E3e70f5130BcDbbFE06bB94fe1] = true; // yearn yearn.finance
        vaults[0x5b189D92983E941273b26e3b46e5a16206c08827] = true; // eCRV yVault
        vaults[0xa258C4606Ca8206D8aA700cE2143D7db854D168c] = true; // WETH yVault
        vaults[0xA74d4B67b3368E83797a35382AFB776bAAE4F5C8] = true; // Curve alUSD Pool yVault
        vaults[0x63739d137EEfAB1001245A8Bd1F3895ef3e186E7] = true; // DAI yVault
        vaults[0x5334e150B938dd2b6bd040D9c4a03Cff0cED3765] = true; // yearn Curve.fi renBTC/wBTC
        vaults[0xE0db48B4F71752C4bEf16De1DBD042B82976b8C7] = true; // yearn mStable USD
    }

    /* ============ External Functions ============ */

    /**
     * Returns the amount out corresponding to the amount in for a given token
     * @param _tokenIn              Address of the first token
     * @param _tokenOut             Address of the second token
     * @return price                Price of the pair
     */
    function getPriceNAV(address _tokenIn, address _tokenOut) public view override returns (uint256 price) {
        return _getPrice(_tokenIn, _tokenOut, true);
    }

    /**
     * Returns the amount out corresponding to the amount in for a given token
     * @param _tokenIn              Address of the first token
     * @param _tokenOut             Address of the second token
     * @return price                Price of the pair
     */
    function getPrice(address _tokenIn, address _tokenOut) public view virtual override returns (uint256 price) {
        return _getPrice(_tokenIn, _tokenOut, false);
    }

    /**
     * Returns the amount out corresponding to the amount in for a given token
     * @param _tokenIn              Address of the first token
     * @param _tokenOut             Address of the second token
     * @param _forNAV               Whether it is just for display purposes
     * @return price                Price of the pair
     */
    function _getPrice(
        address _tokenIn,
        address _tokenOut,
        bool _forNAV
    ) public view returns (uint256 price) {
        // Same asset. Returns base unit
        if (_tokenIn == _tokenOut) {
            return 10**18;
        }
        uint256 exchangeRate;
        // Comp assets
        if (cTokenToAsset[_tokenIn] != address(0)) {
            exchangeRate = getCompoundExchangeRate(_tokenIn);
            return getPrice(cTokenToAsset[_tokenIn], _tokenOut).preciseMul(exchangeRate);
        }
        if (cTokenToAsset[_tokenOut] != address(0)) {
            exchangeRate = getCompoundExchangeRate(_tokenOut);
            return getPrice(_tokenIn, cTokenToAsset[_tokenOut]).preciseDiv(exchangeRate);
        }

        // aave tokens. 1 to 1 with underlying
        if (aTokenToAsset[_tokenIn] != address(0)) {
            return getPrice(aTokenToAsset[_tokenIn], _tokenOut);
        }
        if (aTokenToAsset[_tokenOut] != address(0)) {
            return getPrice(_tokenIn, aTokenToAsset[_tokenOut]);
        }

        // crTokens Cream prices 0xde19f5a7cF029275Be9cEC538E81Aa298E297266
        // cTkens use same interface as compound
        if (crTokenToAsset[_tokenIn] != address(0)) {
            exchangeRate = getCreamExchangeRate(_tokenIn);
            return getPrice(crTokenToAsset[_tokenIn], _tokenOut).preciseMul(exchangeRate);
        }
        if (crTokenToAsset[_tokenOut] != address(0)) {
            exchangeRate = getCreamExchangeRate(_tokenOut);
            return getPrice(_tokenIn, crTokenToAsset[_tokenOut]).preciseDiv(exchangeRate);
        }

        // Checks synthetix
        if (synths[_tokenIn]) {
            address targetImpl = ISnxProxy(_tokenIn).target();
            exchangeRate = snxEchangeRates.rateForCurrency(ISnxSynth(targetImpl).currencyKey());
            return getPrice(USDC, _tokenOut).preciseMul(exchangeRate);
        }

        if (synths[_tokenOut]) {
            address targetImpl = ISnxProxy(_tokenOut).target();
            exchangeRate = snxEchangeRates.rateForCurrency(ISnxSynth(targetImpl).currencyKey());
            return getPrice(_tokenIn, USDC).preciseDiv(exchangeRate);
        }

        // Checks stETH && wstETH (Lido tokens)
        if (_tokenIn == address(stETH) || _tokenIn == address(wstETH)) {
            uint256 shares = 1e18;
            if (_tokenIn == address(wstETH)) {
                shares = wstETH.getStETHByWstETH(shares);
            }
            return getPrice(WETH, _tokenOut).preciseMul(stETH.getPooledEthByShares(shares));
        }
        if (_tokenOut == address(stETH) || _tokenOut == address(wstETH)) {
            uint256 shares = 1e18;
            if (_tokenOut == address(wstETH)) {
                shares = wstETH.getStETHByWstETH(shares);
            }
            return getPrice(_tokenIn, WETH).preciseDiv(stETH.getSharesByPooledEth(shares));
        }

        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        // Direct curve pair
        price = _checkPairThroughCurve(_tokenIn, _tokenOut);

        if (price != 0) {
            return price;
        }

        // Curve LP tokens
        if (curveRegistry.get_pool_from_lp_token(_tokenIn) != address(0)) {
            return curveRegistry.get_virtual_price_from_lp_token(_tokenIn).preciseMul(getPrice(USDC, _tokenOut));
        }
        if (curveRegistry.get_pool_from_lp_token(_tokenOut) != address(0)) {
            return getPrice(_tokenIn, USDC).preciseDiv(curveRegistry.get_virtual_price_from_lp_token(_tokenOut));
        }

        // Yearn vaults
        if (_isYearnVault(_tokenIn)) {
            return IYearnVault(_tokenIn).pricePerShare().preciseDiv(getPrice(IYearnVault(_tokenIn).token(), _tokenOut));
        }

        if (_isYearnVault(_tokenOut)) {
            return
                getPrice(_tokenIn, IYearnVault(_tokenOut).token()).preciseMul(IYearnVault(_tokenOut).pricePerShare());
        }

        uint256 uniPrice = 0;
        // Curve Pair through WBTC
        if (_tokenIn != WBTC && _tokenOut != WBTC) {
            price = _checkPairThroughCurve(WBTC, _tokenOut);
            if (price != 0) {
                uniPrice = _getUNIV3Price(_tokenIn, WBTC);
                if (uniPrice != 0) {
                    return uniPrice.preciseMul(price);
                }
            }
            price = _checkPairThroughCurve(_tokenIn, WBTC);
            if (price != 0) {
                uniPrice = _getUNIV3Price(WBTC, _tokenOut);
                if (uniPrice != 0) {
                    return price.preciseMul(uniPrice);
                }
            }
        }
        // Curve pair through DAI
        if (_tokenIn != DAI && _tokenOut != DAI) {
            price = _checkPairThroughCurve(DAI, _tokenOut);
            if (price != 0) {
                uniPrice = _getUNIV3Price(_tokenIn, DAI);
                if (uniPrice != 0) {
                    return uniPrice.preciseMul(price);
                }
            }
            price = _checkPairThroughCurve(_tokenIn, DAI);
            if (price != 0) {
                uniPrice = _getUNIV3Price(DAI, _tokenOut);
                if (uniPrice != 0) {
                    return price.preciseMul(uniPrice);
                }
            }
        }
        // Curve pair through WETH
        if (_tokenIn != WETH && _tokenOut != WETH) {
            price = _checkPairThroughCurve(WETH, _tokenOut);
            if (price != 0) {
                uniPrice = _getUNIV3Price(_tokenIn, WETH);
                if (uniPrice != 0) {
                    return uniPrice.preciseMul(price);
                }
            }
            price = _checkPairThroughCurve(_tokenIn, WETH);
            if (price != 0) {
                uniPrice = _getUNIV3Price(WETH, _tokenOut);
                if (uniPrice != 0) {
                    return price.preciseMul(uniPrice);
                }
            }
        }
        // Direct UNI3
        price = _getUNIV3Price(_tokenIn, _tokenOut);
        if (price != 0) {
            return price;
        }
        // UniV3 through WETH
        if (_tokenIn != WETH && _tokenOut != WETH) {
            uint256 divisor = _getUNIV3Price(_tokenOut, WETH);
            if (divisor != 0) {
                return _getUNIV3Price(_tokenIn, WETH).preciseDiv(divisor);
            }
        }
        // UniV3 through DAI
        if (_tokenIn != DAI && _tokenOut != DAI) {
            uint256 divisor = _getUNIV3Price(_tokenOut, DAI);
            if (divisor != 0) {
                return _getUNIV3Price(_tokenIn, DAI).preciseDiv(divisor);
            }
        }
        // Use only univ2 for UI
        if (_forNAV) {
            price = _getUNIV2Price(_tokenIn, _tokenOut);
        }
        // No valid price
        require(price != 0, 'Price not found');
        return price;
    }

    /* ============ Internal Functions ============ */

    // Susceptible to flash loans.
    // Only use for UI and getNAV
    function _getUNIV2Price(address _tokenIn, address _tokenOut) internal view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        return uniRouterV2.getAmountsOut(ERC20(_tokenIn).decimals(), path)[1];
    }

    function _getUNIV3Price(address _tokenIn, address _tokenOut) internal view returns (uint256) {
        bool found;
        int24 tick;
        IUniswapV3Pool pool;
        // We try the low pool first
        (found, pool, tick) = _checkPool(_tokenIn, _tokenOut);
        if (!found) {
            return 0;
        }
        return
            OracleLibrary
                .getQuoteAtTick(
                tick,
                // because we use 1e18 as a precision unit
                uint128(uint256(1e18).mul(10**(uint256(18).sub(ERC20(_tokenOut).decimals())))),
                _tokenIn,
                _tokenOut
            )
                .div(10**(uint256(18).sub(ERC20(_tokenIn).decimals())));
    }

    function _checkPool(address _tokenIn, address _tokenOut)
        internal
        view
        returns (
            bool,
            IUniswapV3Pool,
            int24
        )
    {
        int24 tick;
        IUniswapV3Pool pool = _getUniswapPoolWithHighestLiquidity(_tokenIn, _tokenOut);
        if (address(pool) != address(0)) {
            uint256 poolLiquidity = uint256(pool.liquidity());
            if (poolLiquidity > 0) {
                (, tick, , , , , ) = pool.slot0();
                return (_checkPrice(tick, pool), pool, tick);
            }
        }
        return (false, IUniswapV3Pool(0), 0);
    }

    function _getUniswapPoolWithHighestLiquidity(address sendToken, address receiveToken)
        private
        view
        returns (IUniswapV3Pool pool)
    {
        IUniswapV3Pool poolLow = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_LOW));
        IUniswapV3Pool poolMedium = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_MEDIUM));
        IUniswapV3Pool poolHigh = IUniswapV3Pool(factory.getPool(sendToken, receiveToken, FEE_HIGH));

        uint128 liquidityLow = address(poolLow) != address(0) ? poolLow.liquidity() : 0;
        uint128 liquidityMedium = address(poolMedium) != address(0) ? poolMedium.liquidity() : 0;
        uint128 liquidityHigh = address(poolHigh) != address(0) ? poolHigh.liquidity() : 0;
        if (liquidityLow >= liquidityMedium && liquidityLow >= liquidityHigh) {
            return poolLow;
        }
        if (liquidityMedium >= liquidityLow && liquidityMedium >= liquidityHigh) {
            return poolMedium;
        }
        return poolHigh;
    }

    /// @dev Revert if current price is too close to min or max ticks allowed
    /// by Uniswap, or if it deviates too much from the TWAP. Should be called
    /// whenever base and limit ranges are updated. In practice, prices should
    /// only become this extreme if there's no liquidity in the Uniswap pool.
    function _checkPrice(int24 mid, IUniswapV3Pool _pool) internal view returns (bool) {
        int24 tickSpacing = _pool.tickSpacing();
        // TODO: Add the other param from charm
        if (mid < TickMath.MIN_TICK + baseThreshold + tickSpacing) {
            // "price too low"
            return false;
        }
        if (mid > TickMath.MAX_TICK - baseThreshold - tickSpacing) {
            // "price too high"
            return false;
        }

        // Check TWAP deviation. This check prevents price manipulation before
        // the rebalance and also avoids rebalancing when price has just spiked.
        int56 twap = _getTwap(_pool);

        int56 deviation = mid > twap ? mid - twap : twap - mid;
        // Fail twap check
        return deviation < maxTwapDeviation;
    }

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    function _getTwap(IUniswapV3Pool _pool) private view returns (int56 twap) {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = SECONDS_GRANULARITY;
        secondsAgo[1] = 0;
        // observe fails if the pair has no observations
        try _pool.observe(secondsAgo) returns (
            int56[] memory tickCumulatives,
            uint160[] memory /* secondsPerLiquidityCumulativeX128s */
        ) {
            return (tickCumulatives[1] - tickCumulatives[0]) / SECONDS_GRANULARITY;
        } catch {
            return 0;
        }
    }

    function getCompoundExchangeRate(address _asset) public view override returns (uint256) {
        uint256 exchangeRateNormalized = ICToken(_asset).exchangeRateStored();
        if (ERC20(cTokenToAsset[_asset]).decimals() > 8) {
            exchangeRateNormalized = exchangeRateNormalized.div(10**(ERC20(cTokenToAsset[_asset]).decimals() - 8));
        } else {
            exchangeRateNormalized = exchangeRateNormalized.mul(10**(8 - ERC20(cTokenToAsset[_asset]).decimals()));
        }
        return exchangeRateNormalized;
    }

    function getCreamExchangeRate(address _asset) public view override returns (uint256) {
        uint256 exchangeRateNormalized = ICToken(_asset).exchangeRateStored();
        if (ERC20(crTokenToAsset[_asset]).decimals() > 8) {
            exchangeRateNormalized = exchangeRateNormalized.div(10**(ERC20(crTokenToAsset[_asset]).decimals() - 8));
        } else {
            exchangeRateNormalized = exchangeRateNormalized.mul(10**(8 - ERC20(crTokenToAsset[_asset]).decimals()));
        }
        return exchangeRateNormalized;
    }

    function _getPriceThroughCurve(
        address _curvePool,
        address _tokenIn,
        address _tokenOut
    ) private view returns (uint256) {
        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        (int128 i, int128 j, ) = curveRegistry.get_coin_indices(_curvePool, _tokenIn, _tokenOut);
        uint256 price = 0;
        if (_curvePool == 0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5) {
            price = ICurvePoolV3(_curvePool).get_dy(
                uint256(i),
                uint256(j),
                10**(_tokenIn == ETH_ADD_CURVE ? 18 : ERC20(_tokenIn).decimals())
            );
        } else {
            price = ICurvePoolV3(_curvePool).get_dy(
                i,
                j,
                10**(_tokenIn == ETH_ADD_CURVE ? 18 : ERC20(_tokenIn).decimals())
            );
        }
        price = price.mul(10**(18 - (_tokenOut == ETH_ADD_CURVE ? 18 : ERC20(_tokenOut).decimals())));
        uint256 delta = price.preciseMul(CURVE_SLIPPAGE);
        if (price < price.add(delta) && price > price.sub(delta)) {
            return price;
        }
        return 0;
    }

    function _checkPairThroughCurve(address _tokenIn, address _tokenOut) private view returns (uint256) {
        ICurveRegistry curveRegistry = ICurveRegistry(curveAddressProvider.get_registry());
        address curvePool = curveRegistry.find_pool_for_coins(_tokenIn, _tokenOut);
        if (_tokenIn == WETH && curvePool == address(0)) {
            _tokenIn = ETH_ADD_CURVE;
            curvePool = curveRegistry.find_pool_for_coins(ETH_ADD_CURVE, _tokenOut);
        }
        if (_tokenOut == WETH && curvePool == address(0)) {
            _tokenOut = ETH_ADD_CURVE;
            curvePool = curveRegistry.find_pool_for_coins(_tokenIn, ETH_ADD_CURVE);
        }
        if (curvePool != address(0)) {
            uint256 price = _getPriceThroughCurve(curvePool, _tokenIn, _tokenOut);
            return price;
        }
        return 0;
    }

    function _isYearnVault(address _token) private view returns (bool) {
        return vaults[_token];
    }
}
