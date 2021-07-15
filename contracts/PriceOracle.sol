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

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // the desired seconds agos array passed to the observe method
    uint32 private constant SECONDS_GRANULARITY = 30;

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
        aTokenToAsset[0x39C6b3e42d6A679d7D776778Fe880BC9487C2EDA] = 0x39C6b3e42d6A679d7D776778Fe880BC9487C2EDA; // knc
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
        crTokenToAsset[0x797AAB1ce7c01eB727ab980762bA88e7133d2157] = USDT;
        crTokenToAsset[0x44fbebd2f576670a6c33f6fc0b00aa8c5753b322] = USDC;
        crTokenToAsset[0xCbaE0A83f4f9926997c8339545fb8eE32eDc6b76] = YFI;
        crTokenToAsset[0xcE4Fe9b4b8Ff61949DCfeB7e03bc9FAca59D2Eb3] = BAL;
        crTokenToAsset[0x19D1666f543D42ef17F66E376944A22aEa1a8E46] = COMP;
        crTokenToAsset[0x9baF8a5236d44AC410c0186Fe39178d5AAD0Bb87] = YCRV;
        crTokenToAsset[0x892B14321a4FCba80669aE30Bd0cd99a7ECF6aC0] = CREAM;
        crTokenToAsset[0x697256CAA3cCaFD62BB6d3Aa1C7C5671786A5fD9] = LINK;
        crTokenToAsset[0x8B86e0598616a8d4F1fdAE8b59E55FB5Bc33D0d6] = LEND;
        crTokenToAsset[0xc7Fd8Dcee4697ceef5a2fd4608a7BD6A94C77480] = CRV;
        crTokenToAsset[0x17107f40d70f4470d20CB3f138a052cAE8EbD4bE] = RENBTC;
        crTokenToAsset[0x1FF8CDB51219a8838b52E9cAc09b71e591BC998e] = BUSD;
        crTokenToAsset[0x3623387773010d9214B10C551d6e7fc375D31F58] = MTA;
        crTokenToAsset[0x4EE15f44c6F0d8d1136c83EfD2e8E4AC768954c6] = YYCRV;
        crTokenToAsset[0x338286C0BC081891A4Bda39C7667ae150bf5D206] = SUSHI;
        crTokenToAsset[0x10FDBD1e48eE2fD9336a482D746138AE19e649Db] = FTT;
        crTokenToAsset[0x01da76DEa59703578040012357b81ffE62015C2d] = YETH;
        crTokenToAsset[0xef58b2d5A1b8D3cDE67b8aB054dC5C831E9Bc025] = SRM;
        crTokenToAsset[0xe89a6D0509faF730BD707bf868d9A2A744a363C7] = UNI;
        crTokenToAsset[0xeFF039C3c1D668f408d09dD7B63008622a77532C] = WNXM;
        crTokenToAsset[0x22B243B96495C547598D9042B6f94B01C22B2e9E] = SWAG;
        crTokenToAsset[0x8b3FF1ed4F36C2c2be675AFb13CC3AA5d73685a5] = CEL;
        crTokenToAsset[0x2A537Fa9FFaea8C1A41D3C2B68a9cb791529366D] = DPI;
        crTokenToAsset[0x7ea9C63E216D5565c3940A2B3d150e59C2907Db3] = BBTC;
        crTokenToAsset[0x3225E3C669B39C7c8B3e204a8614bB218c5e31BC] = AAVE;
        crTokenToAsset[0xf55BbE0255f7f4E70f63837Ff72A577fbDDbE924] = BOND;
        crTokenToAsset[0x903560b1CcE601794C584F58898dA8a8b789Fc5d] = KP3R;
        crTokenToAsset[0x054B7ed3F45714d3091e82aAd64A1588dC4096Ed] = HBTC;
        crTokenToAsset[0xd5103AfcD0B3fA865997Ef2984C66742c51b2a8b] = HFIL;
        crTokenToAsset[0xfd609a03B393F1A1cFcAcEdaBf068CAD09a924E2] = CRETH2;
        crTokenToAsset[0xD692ac3245bb82319A31068D6B8412796eE85d2c] = HUSD;
        crTokenToAsset[0x92B767185fB3B04F881e3aC8e5B0662a027A1D9f] = DAI;
        crTokenToAsset[0x10a3da2BB0Fae4D591476fd97D6636fd172923a8] = HEGIC;
        crTokenToAsset[0x3C6C553A95910F9FC81c98784736bd628636D296] = ESD;
        crTokenToAsset[0x21011bc93d9e515b9511a817a1ed1d6d468f49fc] = COVER;
        crTokenToAsset[0x85759961b116f1D36fD697855c57A6ae40793D9B] = 1INCH;
        crTokenToAsset[0x7Aaa323D7e398be4128c7042d197a2545f0f1fea] = OMG;
        crTokenToAsset[0x011a014d5e8Eb4771E575bB1000318D509230Afa] = UNI-V2-WBTC-ETH;
        crTokenToAsset[0xE6C3120F38F56deb38B69b65cC7dcAF916373963] = UNI-V2-ETH-USDT;
        crTokenToAsset[0x4Fe11BC316B6d7A345493127fBE298b95AdaAd85] = UNI-V2-USDC-ETH;
        crTokenToAsset[0xcD22C4110c12AC41aCEfA0091c432ef44efaAFA0] = UNI-V2-DAI-ETH;
        crTokenToAsset[0x228619CCa194Fbe3Ebeb2f835eC1eA5080DaFbb2] = XSUSHI;
        crTokenToAsset[0x73f6cBA38922960b7092175c0aDD22Ab8d0e81fC] = SLP-WBTC-ETH;
        crTokenToAsset[0x38f27c03d6609a86FF7716ad03038881320BE4Ad] = SLP-DAI-ETH;
        crTokenToAsset[0x5EcaD8A75216CEa7DFF978525B2D523a251eEA92] = SLP-USDC-ETH;
        crTokenToAsset[0x5C291bc83d15f71fB37805878161718eA4b6AEe9] = SLP-ETH-USDT;
        crTokenToAsset[0x6BA0C66C48641e220CF78177C144323b3838D375] = SLP-SUSHI-ETH;
        crTokenToAsset[0xd532944df6DFd5Dd629E8772F03D4fC861873abF] = SLP-YFI-ETH;
        crTokenToAsset[0x197070723CE0D3810a0E47F06E935c30a480D4Fc] = WBTC;
        crTokenToAsset[0xC25EAE724f189Ba9030B2556a1533E7c8A732E14] = SNX;
        crTokenToAsset[0x25555933a8246Ab67cbf907CE3d1949884E82B55] = SUSD;
        crTokenToAsset[0xc68251421edda00a10815e273fa4b1191fac651b] = PICKLE;
        crTokenToAsset[0x65883978aDA0e707c3b2BE2A6825b1C4BDF76A90] = AKRO;
        crTokenToAsset[0x8B950f43fCAc4931D408F1fcdA55C6CB6cbF3096] = BBADGER;
        crTokenToAsset[0x59089279987DD76fC65Bf94Cb40E186b96e03cB3] = OGN;
        crTokenToAsset[0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6] = AMP;
        crTokenToAsset[0xb092b4601850E23903A42EaCBc9D8A0EeC26A4d5] = FRAX;
        crTokenToAsset[0x1d0986Fb43985c88Ffa9aD959CC24e6a087C7e35] = ALPHA;
        crTokenToAsset[0x51F48b638F82e8765F7a26373A2Cb4CcB10C07af] = UST;
        crTokenToAsset[0xc36080892c64821fa8e396bc1bD8678fA3b82b17] = FTM;
        crTokenToAsset[0x8379BAA817c5c5aB929b03ee8E3c48e45018Ae41] = RUNE;
        crTokenToAsset[0x299e254A8a165bBeB76D9D69305013329Eea3a3B] = PERP;
        crTokenToAsset[0xf8445C529D363cE114148662387eba5E62016e20] = RAI;
        crTokenToAsset[0x7C3297cFB4c4bbd5f44b450c0872E0ADA5203112] = OCEAN;
        crTokenToAsset[0xA87e8e61dfAC8af5944D353Cd26B96B20d5f4D01] = YVECRV;
        crTokenToAsset[0x1bcaFA2C1b3a522E41bAa60C2E318981Ea8D1eb5] = YVSTECRV;
        crTokenToAsset[0xf7c5314806bb349744Cf5E721F4d3395259B8531] = YVCurve-IB;
        crTokenToAsset[0x081FE64df6dc6fc70043aedF3713a3ce6F190a21] = RARI;
        crTokenToAsset[0x28526Bb33d7230E65E735dB64296413731C5402e] = SFI;
        crTokenToAsset[0x45406ba53bB84Cd32A58e7098a2D4D1b11B107F6] = YVCurve-IB;
        crTokenToAsset[0x6d1B9e01aF17Dd08d6DEc08E210dfD5984FF1C20] = YVCurve-sETH;
        crTokenToAsset[0x1F9b4756B008106C806c7E64322d7eD3B72cB284] = YVCurve-stETH;
        crTokenToAsset[0xab10586C918612BA440482db77549d26B7ABF8f7] = ARMOR;
        crTokenToAsset[0xdFFf11DFe6436e42a17B86e7F419Ac8292990393] = ARNXM;
        crTokenToAsset[0xDbb5e3081dEf4b6cdD8864aC2aeDA4cBf778feCf] = MLN;
        crTokenToAsset[0x71cEFCd324B732d4E058AfAcBA040d908c441847] = VSP;
        crTokenToAsset[0x1A122348B73B58eA39F822A89e6ec67950c2bBD0] = VVSP;
        crTokenToAsset[0x523EFFC8bFEfC2948211A05A905F761CBA5E8e9E] = GNO;
        crTokenToAsset[0x4202D97E00B9189936EdF37f8D01cfF88BDd81d4] = YVWETH;
        crTokenToAsset[0x4BAa77013ccD6705ab0522853cB0E9d453579Dd4] = YUSD;
        crTokenToAsset[0x98E329eB5aae2125af273102f3440DE19094b77c] = SWAP;
        crTokenToAsset[0x8C3B7a4320ba70f8239F83770c4015B5bc4e6F91] = FEI;
        crTokenToAsset[0xE585c76573D7593ABF21537B607091F76c996E73] = WOO;
        crTokenToAsset[0x81E346729723C4D15d0FB1c5679b9f2926Ff13C6] = BNT;
        
        ATokenToAsset[0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F] = true; // proxy SNX
        ATokenToAsset[0x57Ab1ec28D129707052df4dF418D58a2D46d5f51] = true; // ProxyERC20sUSD
        ATokenToAsset[0xb440DD674e1243644791a4AdfE3A2AbB0A92d309] = true; // ProxyFeePool
        ATokenToAsset[0x176C674Ee533C6139B0dc8b458D72A93dCB3e705] = true; // ProxyiAAVE
        ATokenToAsset[0x8A8079c7149B8A1611e5C5d978DCA3bE16545F83] = true; // ProxyiADA
        ATokenToAsset[0xAFD870F32CE54EfdBF677466B612bf8ad164454B] = true; // ProxyiBNB
        ATokenToAsset[0xD6014EA05BDe904448B743833dDF07c3C7837481] = true; // ProxyiBTC
        ATokenToAsset[0x336213e1DDFC69f4701Fc3F86F4ef4A160c1159d] = true; // ProxyiCEX
        ATokenToAsset[0x6345728B1ccE16E6f8C509950b5c84FFF88530d9] = true; // ProxyiCOMP
        ATokenToAsset[0xCB98f42221b2C251A4E74A1609722eE09f0cc08E] = true; // ProxyiDASH
        ATokenToAsset[0x14d10003807AC60d07BB0ba82cAeaC8d2087c157] = true; // ProxyiDEFI
        ATokenToAsset[0x46a97629C9C1F58De6EC18C7F536e7E6d6A6ecDe] = true; // ProxyiDOT
        ATokenToAsset[0xF4EebDD0704021eF2a6Bbe993fdf93030Cd784b4] = true; // ProxyiEOS
        ATokenToAsset[0xd50c1746D835d2770dDA3703B69187bFfeB14126] = true; // ProxyiETC
        ATokenToAsset[0xA9859874e1743A32409f75bB11549892138BBA1E] = true; // ProxyiETH
        ATokenToAsset[0x2d7aC061fc3db53c39fe1607fB8cec1B2C162B01] = true; // ProxyiLINK
        ATokenToAsset[0x79da1431150C9b82D2E5dfc1C68B33216846851e] = true; // ProxyiLTC
        ATokenToAsset[0xA5a5DF41883Cdc00c4cCC6E8097130535399d9a3] = true; // ProxyiOIL
        ATokenToAsset[0x0fEd38108bdb8e62ef7b5680E8E0726E2F29e0De] = true; // ProxyiREN
        ATokenToAsset[0xC5807183a9661A533CB08CbC297594a0B864dc12] = true; // ProxyiTRX
        ATokenToAsset[0x36A00FF9072570eF4B9292117850B8FE08d96cce] = true; // ProxyiUNI
        ATokenToAsset[0x4AdF728E2Df4945082cDD6053869f51278fae196] = true; // ProxyiXMR
        ATokenToAsset[0x27269b3e45A4D3E79A3D6BFeE0C8fB13d0D711A6] = true; // ProxyiXRP	
        ATokenToAsset[0x8deef89058090ac5655A99EEB451a4f9183D1678] = true; // ProxyiXTZ
        ATokenToAsset[0x592244301CeA952d6daB2fdC1fE6bd9E53917306] = true; // ProxyiYFI
        ATokenToAsset[0xcD39b5434a0A92cf47D1F567a7dF84bE356814F0] = true; // Proxys1INCH
        ATokenToAsset[0x7537AAe01f3B218DAE75e10d952473823F961B87] = true; // ProxysAAPL
        ATokenToAsset[0xd2dF355C19471c8bd7D8A3aa27Ff4e26A21b4076] = true; // ProxysAAVE
        ATokenToAsset[0xe36E2D3c7c34281FA3bC737950a68571736880A1] = true; // ProxysADA
        ATokenToAsset[0x9CF7E61853ea30A41b02169391b393B901eac457] = true; // ProxysAMZN
        ATokenToAsset[0xF48e200EAF9906362BB1442fca31e0835773b8B4] = true; // ProxysAUD
        ATokenToAsset[0x617aeCB6137B5108D1E7D4918e3725C8cEbdB848] = true; // ProxysBNB
        ATokenToAsset[0xfE18be6b3Bd88A2D2A7f928d00292E7a9963CfC6] = true; // ProxysBTC
        ATokenToAsset[0xeABACD844A196D7Faf3CE596edeBF9900341B420] = true; // ProxysCEX
        ATokenToAsset[0x0F83287FF768D1c1e17a42F44d644D7F22e8ee1d] = true; // ProxysCHF
        ATokenToAsset[0x9EeF4CA7aB9fa8bc0650127341C2d3F707a40f8A] = true; // ProxysCOIN
        ATokenToAsset[0xEb029507d3e043DD6C87F2917C4E82B902c35618] = true; // ProxysCOMP
        ATokenToAsset[0xD38aEb759891882e78E957c80656572503D8c1B1] = true; // ProxysCRV
        ATokenToAsset[0xfE33ae95A9f0DA8A845aF33516EDc240DCD711d6] = true; // ProxysDEFI
        ATokenToAsset[0x1715AC0743102BF5Cd58EfBB6Cf2dC2685d967b6] = true; // ProxysDOT
        ATokenToAsset[0x88C8Cf3A212c0369698D13FE98Fcb76620389841] = true; // ProxysEOS
        ATokenToAsset[0x22602469d704BfFb0936c7A7cfcD18f7aA269375] = true; // ProxysETC
        ATokenToAsset[0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb] = true; // ProxysETH
        ATokenToAsset[0xD71eCFF9342A5Ced620049e616c5035F1dB98620] = true; // ProxysEUR
        ATokenToAsset[0xf50B5e535F62a56A9BD2d8e2434204E726c027Fa] = true; // ProxysFB
        ATokenToAsset[0x23348160D7f5aca21195dF2b70f28Fce2B0be9fC] = true; // ProxysFTSE
        ATokenToAsset[0x97fe22E7341a0Cd8Db6F6C021A24Dc8f4DAD855F] = true; // ProxysGBP
        ATokenToAsset[0xC63B8ECCE56aB9C46184eC6aB85e4771fEa4c8AD] = true; // ProxysGOOG
        ATokenToAsset[0xF6b1C627e95BFc3c1b4c9B825a032Ff0fBf3e07d] = true; // ProxysJPY
        ATokenToAsset[0x269895a3dF4D73b077Fc823dD6dA1B95f72Aaf9B] = true; // ProxysKRW
        ATokenToAsset[0xbBC455cb4F1B9e4bFC4B73970d360c8f032EfEE6] = true; // ProxysLINK
        ATokenToAsset[0xC14103C2141E842e228FBaC594579e798616ce7A] = true; // ProxysLTC
        ATokenToAsset[0x745a824D6aBBD236AA794b5530062778A6Ad7523] = true; // ProxysMSFT
        ATokenToAsset[0x5A7E3c07604EB515C16b36cd51906a65f021F609] = true; // ProxysNFLX
        ATokenToAsset[0x757de3ac6B830a931eF178C6634c5C551773155c] = true; // ProxysNIKKEI
        ATokenToAsset[0x6d16cF3EC5F763d4d99cB0B0b110eefD93B11B56] = true; // ProxysOIL
        ATokenToAsset[0xD31533E8d0f3DF62060e94B3F1318137bB6E3525] = true; // ProxysREN
        ATokenToAsset[0x0352557B007A4Aae1511C114409b932F06F9E2f4] = true; // ProxysRUNE
        ATokenToAsset[0xf2E08356588EC5cd9E437552Da87C0076b4970B0] = true; // ProxysTSLA
        ATokenToAsset[0x30635297E450b930f8693297eBa160D9e6c8eBcf] = true; // ProxysUNI
        ATokenToAsset[0x6A22e5e94388464181578Aa7A6B869e00fE27846] = true; // ProxysXAG
        ATokenToAsset[0x261EfCdD24CeA98652B9700800a13DfBca4103fF] = true; // ProxysXAU
        ATokenToAsset[0x5299d6F7472DCc137D7f3C4BcfBBB514BaBF341A] = true; // ProxysXMR
        ATokenToAsset[0xa2B0fDe6D710e201d0d608e924A484d1A5fEd57c] = true; // ProxysXRP
        ATokenToAsset[0x2e59005c5c0f0a4D77CcA82653d48b46322EE5Cd] = true; // ProxysXTZ
        ATokenToAsset[0x992058B7DB08F9734d84485bfbC243C4ee6954A7] = true; // ProxysYFI 
    }

    /* ============ External Functions ============ */

    /**
     * Returns the amount out corresponding to the amount in for a given token
     * @param _tokenIn              Address of the first token
     * @param _tokenOut             Address of the second token
     * @return price                Price of the pair
     */
    function getPrice(address _tokenIn, address _tokenOut) public view override returns (uint256 price) {
        bool found;
        uint256 price;
        int24 tick;
        IUniswapV3Pool pool;

        // Same asset. Returns base unit
        if (_tokenIn == _tokenOut) {
            return 10**18;
        }

        // Comp assets
        if (cTokenToAsset[_tokenIn] != address(0)) {
            uint256 exchangeRateNormalized = getCompoundExchangeRate(_tokenIn);
            return getPrice(cTokenToAsset[_tokenIn], _tokenOut).preciseMul(exchangeRateNormalized);
        }
        if (cTokenToAsset[_tokenOut] != address(0)) {
            uint256 exchangeRateNormalized = getCompoundExchangeRate(_tokenOut);
            return getPrice(_tokenIn, cTokenToAsset[_tokenOut]).preciseDiv(exchangeRateNormalized);
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
            uint256 exchangeRate = getCreamExchangeRate(_tokenIn);
            return getPrice(crTokenToAsset[_tokenIn], _tokenOut).preciseMul(exchangeRate);
        }
        if (crTokenToAsset[_tokenOut] != address(0)) {
            uint256 exchangeRate = getCreamExchangeRate(_tokenOut);
            return getPrice(_tokenIn, crTokenToAsset[_tokenOut]).preciseDiv(exchangeRate);
        }

        // TODOs
        // Check Synths & integrate synths
        // Integrate lido

        // other btcs, change pairs & change path in uniswap trade
        // other stables, change pair & change path in uniswap trade

        if (_tokenIn != WETH && _tokenOut != WETH) {
            return getPrice(_tokenIn, WETH).preciseDiv(getPrice(_tokenOut, WETH));
        }
        // We try the low pool first
        (found, pool, tick) = checkPool(_tokenIn, _tokenOut, FEE_LOW);
        if (!found) {
            (found, pool, tick) = checkPool(_tokenIn, _tokenOut, FEE_MEDIUM);
        }
        if (!found) {
            (found, pool, tick) = checkPool(_tokenIn, _tokenOut, FEE_HIGH);
        }
        // No valid price
        require(found, 'Price not found');

        price = OracleLibrary
            .getQuoteAtTick(
            tick,
            // because we use 1e18 as a precision unit
            uint128(uint256(1e18).mul(10**(uint256(18).sub(ERC20(_tokenOut).decimals())))),
            _tokenIn,
            _tokenOut
        )
            .div(10**(uint256(18).sub(ERC20(_tokenIn).decimals())));
        return price;
    }

    function checkPool(
        address _tokenIn,
        address _tokenOut,
        uint24 fee
    )
        internal
        view
        returns (
            bool,
            IUniswapV3Pool,
            int24
        )
    {
        int24 tick;
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(_tokenIn, _tokenOut, fee));
        if (address(pool) != address(0)) {
            (, tick, , , , , ) = pool.slot0();
            return (_checkPrice(tick, pool), pool, tick);
        }
        return (false, IUniswapV3Pool(0), 0);
    }

    /* ============ Internal Functions ============ */

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
            uint160[] memory secondsPerLiquidityCumulativeX128s
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
}
