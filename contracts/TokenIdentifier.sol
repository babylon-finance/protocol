// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IBabController} from './interfaces/IBabController.sol';
import {ICToken} from './interfaces/external/compound/ICToken.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ITokenIdentifier} from './interfaces/ITokenIdentifier.sol';
import {ICurveMetaRegistry} from './interfaces/ICurveMetaRegistry.sol';
import {ICurvePoolV3} from './interfaces/external/curve/ICurvePoolV3.sol';
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

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IStETH private constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH private constant wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    bytes32 private constant SUSHI_SYMBOL = keccak256(bytes('SLP'));
    bytes32 private constant UNI_SYMBOL = keccak256(bytes('UNI-V2'));

    // Token Types
    uint8 private constant COMP_TOKEN = 1;
    uint8 private constant AAVE_TOKEN = 2;
    uint8 private constant CREAM_TOKEN = 3;
    uint8 private constant SYNTH_TOKEN = 4;
    uint8 private constant CURVE_LP_TOKEN = 5;
    uint8 private constant YEARN_TOKEN = 6;
    uint8 private constant LIDO_TOKEN = 7;
    uint8 private constant SUSHI_LP_TOKEN = 8;
    uint8 private constant UNIV2_LP_TOKEN = 9;
    uint8 private constant ONEINCH_LP_TOKEN = 10;
    uint8 private constant HARVESTV3_LP_TOKEN = 11;
    uint8 private constant VISOR_LP_TOKEN = 12;

    /* ============ State Variables ============ */

    IBabController public controller;
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

    /* ============ Modifiers ============ */

    /* ============ Constructor ============ */

    constructor(IBabController _controller) {
        controller = _controller;

        cTokenToAsset[0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        cTokenToAsset[0x35A18000230DA775CAc24873d00Ff85BccdeD550] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        cTokenToAsset[0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5] = WETH; // ETH
        cTokenToAsset[0x39AA39c021dfbaE8faC545936693aC917d5E7563] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        cTokenToAsset[0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        cTokenToAsset[0xccF4429DB6322D5C611ee964527D42E5d685DD6a] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC2
        cTokenToAsset[0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4] = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP
        cTokenToAsset[0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF; // BAT
        cTokenToAsset[0xFAce851a4921ce59e912d19329929CE6da6EB0c7] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
        cTokenToAsset[0x158079Ee67Fce2f58472A96584A73C7Ab9AC95c1] = 0x221657776846890989a759BA2973e427DfF5C9bB; // REP
        cTokenToAsset[0xF5DCe57282A584D2746FaF1593d3121Fcac444dC] = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359; // SAI
        cTokenToAsset[0x12392F67bdf24faE0AF363c24aC620a2f67DAd86] = 0x0000000000085d4780B73119b644AE5ecd22b376; // TUSD
        cTokenToAsset[0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407] = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // ZRX
        cTokenToAsset[0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // aave
        cTokenToAsset[0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2; // MKR
        cTokenToAsset[0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7] = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2; // SUSHI
        cTokenToAsset[0x041171993284df560249B57358F931D9eB7b925D] = 0x8E870D67F660D95d5be530380D0eC0bd388289E1; // USDP
        cTokenToAsset[0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e; // YFI

        aTokenToAsset[0xFFC97d72E13E01096502Cb8Eb52dEe56f74DAD7B] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // aave
        aTokenToAsset[0x1E6bb68Acec8fefBD87D192bE09bb274170a0548] = 0xD46bA6D942050d489DBd938a2C909A5d5039A161; // AAMPL
        aTokenToAsset[0x272F97b7a56a387aE942350bBC7Df5700f8a4576] = 0xba100000625a3754423978a60c9317c58a424e3D; // bal
        aTokenToAsset[0x05Ec93c0365baAeAbF7AefFb0972ea7ECdD39CF1] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF; // bat
        aTokenToAsset[0xA361718326c15715591c299427c62086F69923D9] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53; // busd
        aTokenToAsset[0x8dAE6Cb04688C62d939ed9B68d32Bc62e49970b1] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // crv
        aTokenToAsset[0x028171bCA77440897B824Ca71D1c56caC55b68A3] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // dai
        aTokenToAsset[0xaC6Df26a590F08dcC95D5a4705ae8abbc88509Ef] = 0xF629cBd94d3791C9250152BD8dfBDF380E2a3B9c; // enj
        aTokenToAsset[0x683923dB55Fead99A79Fa01A27EeC3cB19679cC3] = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA; // fei
        aTokenToAsset[0xd4937682df3C8aEF4FE912A96A74121C0829E664] = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // frax
        aTokenToAsset[0xD37EE7e4f452C6638c96536e68090De8cBcdb583] = 0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd; // gusd
        aTokenToAsset[0x39C6b3e42d6A679d7D776778Fe880BC9487C2EDA] = 0xdd974D5C2e2928deA5F71b9825b8b646686BD200; // knc
        aTokenToAsset[0xa06bC25B5805d5F8d82847D191Cb4Af5A3e873E0] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // link
        aTokenToAsset[0xa685a61171bb30d4072B338c80Cb7b2c865c873E] = 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942; // mana
        aTokenToAsset[0xc713e5E149D5D0715DcD1c156a020976e7E56B88] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2; // mkr
        aTokenToAsset[0xc9BC48c72154ef3e5425641a3c747242112a46AF] = 0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919; // rai
        aTokenToAsset[0xCC12AbE4ff81c9378D670De1b57F8e0Dd228D77a] = 0x408e41876cCCDC0F92210600ef50372656052a38; // ren
        aTokenToAsset[0x514cd6756CCBe28772d4Cb81bC3156BA9d1744aa] = 0xD5147bc8e386d91Cc5DBE72099DAC6C9b99276F5; // renFIL
        aTokenToAsset[0x35f6B052C598d933D69A4EEC4D04c73A191fE6c2] = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F; // snx
        aTokenToAsset[0x6C5024Cd4F8A59110119C56f8933403A539555EB] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51; // susd
        aTokenToAsset[0x101cc05f4A51C0319f570d5E146a8C625198e636] = 0x0000000000085d4780B73119b644AE5ecd22b376; // tusd
        aTokenToAsset[0xB9D7CB55f463405CDfBe4E90a6D2Df01C2B92BF1] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // uni
        aTokenToAsset[0xBcca60bB61934080951369a648Fb03DF4F96263C] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // usdc
        aTokenToAsset[0x2e8F4bdbE3d47d7d7DE490437AeA9915D930F1A3] = 0x8E870D67F660D95d5be530380D0eC0bd388289E1; // usdp
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
        crTokenToAsset[0xC581b735A1688071A1746c968e0798D642EDE491] = 0xC581b735A1688071A1746c968e0798D642EDE491; // EURT
        crTokenToAsset[0xD7394428536F63d5659cc869EF69d10f9E66314B] = 0x8E870D67F660D95d5be530380D0eC0bd388289E1; // PAX
        crTokenToAsset[0x1241B10E7EA55b22f5b2d007e8fECDF73DCff999] = 0x45804880De22913dAFE09f4980848ECE6EcbAf78; // PAXG
        crTokenToAsset[0x2A867fd776B83e1bd4e13C6611AFd2F6af07EA6D] = 0x9BE89D2a4cd102D8Fecc6BF9dA793be995C22541; // BBTC
        crTokenToAsset[0x250Fb308199FE8C5220509C1bf83D21d60b7f74A] = 0x0000000000095413afC295d19EDeb1Ad7B71c952; // LON
        crTokenToAsset[0x4112a717edD051F77d834A6703a1eF5e3d73387F] = 0x25f8087EAD173b73D6e8B84329989A8eEA16CF73; // YGG
        crTokenToAsset[0xF04ce2e71D32D789a259428ddcD02D3C9F97fb4E] = 0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b; // AXS
        crTokenToAsset[0x89e42987c39f72e2EAd95a8a5bC92114323d5828] = 0x3845badAde8e6dFF049820680d1F14bD3903a5d0; // SAND
        crTokenToAsset[0x58DA9c9fC3eb30AbBcbBAb5DDabb1E6e2eF3d2EF] = 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942; // MANA

        synths[0x57Ab1ec28D129707052df4dF418D58a2D46d5f51] = true; // ProxyERC20sUSD
        synths[0xd2dF355C19471c8bd7D8A3aa27Ff4e26A21b4076] = true; // ProxysAAVE
        synths[0xe36E2D3c7c34281FA3bC737950a68571736880A1] = true; // ProxysADA
        synths[0xF48e200EAF9906362BB1442fca31e0835773b8B4] = true; // ProxysAUD
        synths[0xfE18be6b3Bd88A2D2A7f928d00292E7a9963CfC6] = true; // ProxysBTC
        synths[0x0F83287FF768D1c1e17a42F44d644D7F22e8ee1d] = true; // ProxysCHF
        synths[0xD38aEb759891882e78E957c80656572503D8c1B1] = true; // ProxysCRV
        synths[0xfE33ae95A9f0DA8A845aF33516EDc240DCD711d6] = true; // ProxysDEFI
        synths[0x1715AC0743102BF5Cd58EfBB6Cf2dC2685d967b6] = true; // ProxysDOT
        synths[0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb] = true; // ProxysETH
        synths[0x104eDF1da359506548BFc7c25bA1E28C16a70235] = true; // ProxysETHBTC
        synths[0xD71eCFF9342A5Ced620049e616c5035F1dB98620] = true; // ProxysEUR
        synths[0x97fe22E7341a0Cd8Db6F6C021A24Dc8f4DAD855F] = true; // ProxysGBP
        synths[0xF6b1C627e95BFc3c1b4c9B825a032Ff0fBf3e07d] = true; // ProxysJPY
        synths[0x269895a3dF4D73b077Fc823dD6dA1B95f72Aaf9B] = true; // ProxysKRW
        synths[0xbBC455cb4F1B9e4bFC4B73970d360c8f032EfEE6] = true; // ProxysLINK

        // Yearn vaults
        // https://medium.com/yearn-state-of-the-vaults/the-vaults-at-yearn-9237905ffed3
        vaults[0xc5bDdf9843308380375a611c18B50Fb9341f502A] = true; // veCRV-DAO yVault
        vaults[0x9d409a0A012CFbA9B15F6D4B36Ac57A46966Ab9a] = true; // Yearn Compounding veCRV yVault
        vaults[0xdb25cA703181E7484a155DD612b06f57E12Be5F0] = true; // YFI yVault
        vaults[0xF29AE508698bDeF169B89834F76704C3B205aedf] = true; // SNX yVault
        vaults[0x873fB544277FD7b977B196a826459a69E27eA4ea] = true; // RAI yVault
        vaults[0x671a912C10bba0CFA74Cfc2d6Fba9BA1ed9530B2] = true; // LINK yVault
        vaults[0xa5cA62D95D24A4a350983D5B8ac4EB8638887396] = true; // sUSD yVault
        vaults[0xB8C3B7A2A618C552C23B1E4701109a9E756Bab67] = true; // 1INCH yVault
        vaults[0xa258C4606Ca8206D8aA700cE2143D7db854D168c] = true; // WETH yVault
        vaults[0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9] = true; // USDC yVault
        vaults[0xdA816459F1AB5631232FE5e97a05BBBb94970c95] = true; // DAI yVault
        vaults[0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E] = true; // WBTC yVault
        vaults[0x7Da96a3891Add058AdA2E826306D812C638D87a7] = true; // USDT yVault
        vaults[0xFBEB78a723b8087fD2ea7Ef1afEc93d35E8Bed42] = true; // UNI yVault
        vaults[0xd9788f3931Ede4D5018184E198699dC6d66C1915] = true; // AAVE yVault
        vaults[0x4A3FE75762017DB0eD73a71C9A06db7768DB5e66] = true; // COMP yVault
        vaults[0x6d765CbE5bC922694afE112C140b8878b9FB0390] = true; // SUSHI yVault
        vaults[0xFD0877d9095789cAF24c98F7CCe092fa8E120775] = true; // TUSD yVault
        // Curve yearn vaults
        vaults[0xE537B5cc158EB71037D4125BDD7538421981E6AA] = true; // Curve 3Crypto Pool yVault
        vaults[0x6FAfCA7f49B4Fd9dC38117469cd31A1E5aec91F5] = true; // Curve USDM Pool yVault
        vaults[0x718AbE90777F5B778B52D553a5aBaa148DD0dc5D] = true; // Curve alETH Pool yVault
        vaults[0x8b9C0c24307344B6D7941ab654b2Aeee25347473] = true; // Curve EURN Pool yVault
        vaults[0xd8C620991b8E626C099eAaB29B1E3eEa279763bb] = true; // Curve MIM-UST
        vaults[0x0d4EA8536F9A13e4FBa16042a46c30f092b06aA5] = true; // Curve EURT Pool yVault
        vaults[0x2DfB14E32e2F8156ec15a2c21c3A6c053af52Be8] = true; // Curve MIM Pool yVault
        vaults[0x4560b99C904aAD03027B5178CCa81584744AC01f] = true; // Curve cvxCRV Pool yVault
        vaults[0x67e019bfbd5a67207755D04467D6A70c0B75bF60] = true; // Curve ibEUR Pool yVault
        vaults[0x528D50dC9a333f01544177a924893FA1F5b9F748] = true; // Curve ibKRW Pool yVault
        vaults[0x595a68a8c9D5C230001848B69b1947ee2A607164] = true; // Curve ibGBP Pool yVault
        vaults[0x1b905331F7dE2748F4D6a0678e1521E20347643F] = true; // Curve ibAUD Pool yVault
        vaults[0x490bD0886F221A5F79713D3E84404355A9293C50] = true; // Curve ibCHF Pool yVault
        vaults[0x59518884EeBFb03e90a18ADBAAAB770d4666471e] = true; // Curve ibJPY Pool yVault
        vaults[0x8cc94ccd0f3841a468184aCA3Cc478D2148E1757] = true; // Curve mUSD Pool yVault
        vaults[0x625b7DF2fa8aBe21B0A976736CDa4775523aeD1E] = true; // Curve HBTC Pool yVault
        vaults[0x3D27705c64213A5DcD9D26880c1BcFa72d5b6B0E] = true; // Curve USDK Pool yVault
        vaults[0x80bbeE2fa460dA291e796B9045e93d19eF948C6A] = true; // Curve Pax Pool yVault
        vaults[0xC116dF49c02c5fD147DE25Baa105322ebF26Bd97] = true; // Curve RSV Pool yVault
        vaults[0x28a5b95C101df3Ded0C0d9074DB80C438774B6a9] = true; // Curve USDT Pool yVault
        vaults[0x3D980E50508CFd41a13837A60149927a11c03731] = true; // Curve triCrypto Pool yVault
        vaults[0x25212Df29073FfFA7A67399AcEfC2dd75a831A1A] = true; // Curve EURS Pool yVault
        vaults[0x5a770DbD3Ee6bAF2802D29a901Ef11501C44797A] = true; // Curve sUSD Pool yVault
        vaults[0x39CAF13a104FF567f71fd2A4c68C026FDB6E740B] = true; // Curve Aave Pool yVault
        vaults[0x054AF22E1519b020516D72D749221c24756385C9] = true; // Curve HUSD Pool yVault
        vaults[0x3B96d491f067912D18563d56858Ba7d6EC67a6fa] = true; // Curve USDN Pool yVault
        vaults[0xBfedbcbe27171C418CDabC2477042554b1904857] = true; // Curve rETH Pool yVault
        vaults[0x132d8D2C76Db3812403431fAcB00F3453Fc42125] = true; // Curve ankrETH Pool yVault
        vaults[0xf2db9a7c0ACd427A680D640F02d90f6186E71725] = true; // Curve LINK Pool yVault
        vaults[0xA74d4B67b3368E83797a35382AFB776bAAE4F5C8] = true; // Curve alUSD Pool yVault
        vaults[0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417] = true; // Curve USDP Pool yVault
        vaults[0x1C6a9783F812b3Af3aBbf7de64c3cD7CC7D1af44] = true; // Curve UST Pool yVault
        vaults[0x30FCf7c6cDfC46eC237783D94Fc78553E79d4E9C] = true; // Curve DUSD Pool yVault
        vaults[0xf8768814b88281DE4F532a3beEfA5b85B69b9324] = true; // Curve TUSD Pool yVault
        vaults[0x4B5BfD52124784745c1071dcB244C6688d2533d3] = true; // Curve Y Pool yVault
        vaults[0x84E13785B5a27879921D6F685f041421C7F482dA] = true; // Curve 3pool yVault
        vaults[0x2a38B9B0201Ca39B17B460eD2f11e4929559071E] = true; // Curve GUSD Pool yVault
        vaults[0x27b7b1ad7288079A66d12350c828D3C00A6F07d7] = true; // Curve Iron Bank Pool yVault
        vaults[0x986b4AFF588a109c09B50A03f42E4110E29D353F] = true; // Curve sETH Pool yVault
        vaults[0xdCD90C7f6324cfa40d7169ef80b12031770B4325] = true; // Curve stETH Pool yVault
        vaults[0x8414Db07a7F743dEbaFb402070AB01a4E0d2E45e] = true; // Curve sBTC Pool yVault
        vaults[0x7047F90229a057C13BF847C0744D646CFb6c9E1A] = true; // Curve renBTC Pool yVault
        vaults[0xe9Dc63083c464d6EDcCFf23444fF3CFc6886f6FB] = true; // Curve oBTC Pool yVault
        vaults[0x3c5DF3077BcF800640B5DAE8c91106575a4826E6] = true; // Curve pBTC Pool yVault
        vaults[0x23D3D0f1c697247d5e0a9efB37d8b0ED0C464f7f] = true; // Curve tBTC Pool yVault
        vaults[0xB4AdA607B9d6b2c9Ee07A275e9616B84AC560139] = true; // Curve FRAX Pool yVault
        vaults[0x5fA5B62c8AF877CB37031e0a3B2f34A78e3C56A6] = true; // Curve LUSD Pool yVault
        vaults[0xb4D1Be44BfF40ad6e506edf43156577a3f8672eC] = true; // Curve SAAVE Pool yVault
        vaults[0x8fA3A9ecd9EFb07A8CE90A6eb014CF3c0E3B32Ef] = true; // Curve BBTC Pool yVault
        vaults[0x6Ede7F19df5df6EF23bD5B9CeDb651580Bdf56Ca] = true; // Curve BUSD Pool yVault
        vaults[0x2994529C0652D127b7842094103715ec5299bBed] = true; // yearn Curve.fi yDAI/yUSDC/yUSDT/yBUSD
        vaults[0xD6Ea40597Be05c201845c0bFd2e96A60bACde267] = true; // Curve Compound Pool yVault
    }

    /* ============ External Functions ============ */

    function updateYearnVault(address[] calldata _vaults, bool[] calldata _values) external override {
        controller.onlyGovernanceOrEmergency();
        for (uint256 i = 0; i < _vaults.length; i++) {
            vaults[_vaults[i]] = _values[i];
        }
    }

    function updateSynth(address[] calldata _synths, bool[] calldata _values) external override {
        controller.onlyGovernanceOrEmergency();
        for (uint256 i = 0; i < _synths.length; i++) {
            synths[_synths[i]] = _values[i];
        }
    }

    function updateCreamPair(address[] calldata _creamTokens, address[] calldata _underlyings) external override {
        controller.onlyGovernanceOrEmergency();
        for (uint256 i = 0; i < _creamTokens.length; i++) {
            crTokenToAsset[_creamTokens[i]] = _underlyings[i];
        }
    }

    function updateAavePair(address[] calldata _aaveTokens, address[] calldata _underlyings) external override {
        controller.onlyGovernanceOrEmergency();
        for (uint256 i = 0; i < _aaveTokens.length; i++) {
            aTokenToAsset[_aaveTokens[i]] = _underlyings[i];
        }
    }

    function updateCompoundPair(address[] calldata _cTokens, address[] calldata _underlyings) external override {
        controller.onlyGovernanceOrEmergency();
        for (uint256 i = 0; i < _cTokens.length; i++) {
            cTokenToAsset[_cTokens[i]] = _underlyings[i];
        }
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
        // Comp assets
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

        // crTokens Cream prices 0xde19f5a7cF029275Be9cEC538E81Aa298E297266
        // cTkens use same interface as compound
        if (crTokenToAsset[_tokenIn] != address(0)) {
            finalAssetIn = crTokenToAsset[_tokenIn];
            tokenInType = CREAM_TOKEN;
        }
        if (crTokenToAsset[_tokenOut] != address(0)) {
            finalAssetOut = crTokenToAsset[_tokenOut];
            tokenOutType = CREAM_TOKEN;
        }

        // Checks synthetix
        if (synths[_tokenIn]) {
            tokenInType = SYNTH_TOKEN;
        }

        if (synths[_tokenOut]) {
            tokenOutType = SYNTH_TOKEN;
        }

        // Curve LP Token
        address crvPool = _curveMetaRegistry.getPoolFromLpToken(_tokenIn);
        if (crvPool != address(0)) {
            tokenInType = CURVE_LP_TOKEN;
        }
        crvPool = _curveMetaRegistry.getPoolFromLpToken(_tokenOut);
        if (crvPool != address(0)) {
            tokenOutType = CURVE_LP_TOKEN;
        }

        // Yearn vaults
        if (_isYearnVault(_tokenIn)) {
            tokenInType = YEARN_TOKEN;
        }

        if (_isYearnVault(_tokenOut)) {
            tokenOutType = YEARN_TOKEN;
        }

        // Checks stETH && wstETH (Lido tokens)
        if (_tokenIn == address(stETH) || _tokenIn == address(wstETH)) {
            tokenInType = LIDO_TOKEN;
        }
        if (_tokenOut == address(stETH) || _tokenOut == address(wstETH)) {
            tokenOutType = LIDO_TOKEN;
        }

        // Check sushi pairs (univ2)
        string memory tokenInSymbol = ERC20(_tokenIn).symbol();
        string memory tokenOutSymbol = ERC20(_tokenOut).symbol();

        if (keccak256(bytes(tokenInSymbol)) == SUSHI_SYMBOL) {
            tokenInType = SUSHI_LP_TOKEN;
        }
        if (keccak256(bytes(tokenOutSymbol)) == SUSHI_SYMBOL) {
            tokenOutType = SUSHI_LP_TOKEN;
        }
        // Checks univ2
        if (keccak256(bytes(tokenInSymbol)) == UNI_SYMBOL) {
            tokenInType = UNIV2_LP_TOKEN;
        }
        if (keccak256(bytes(tokenOutSymbol)) == UNI_SYMBOL) {
            tokenOutType = UNIV2_LP_TOKEN;
        }

        try IMooniswap(_tokenIn).mooniswapFactoryGovernance() returns (address) {
            _tokenInType = ONEINCH_LP_TOKEN;
        } catch {}

        try IMooniswap(_tokenOut).mooniswapFactoryGovernance() returns (address) {
            tokenOutType = ONEINCH_LP_TOKEN;
        } catch {}

        // todo: pickle
        // todo: convex tokens
        // todo: Harvest v3 lp token
        // todo: Visor (univ3 lp token)

        return (tokenInType, tokenOutType, finalAssetIn, finalAssetOut);
    }

    /* ============ Internal Functions ============ */

    function _isYearnVault(address _token) private view returns (bool) {
        return vaults[_token];
    }
}
