module.exports = {
  zero: '0x0000000000000000000000000000000000000000',
  users: {
    hardhat1: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    hardhat2: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
    hardhat3: '0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc',
  },
  paladin: {
    palStkAAVE: '0x24E79e946dEa5482212c38aaB2D0782F04cdB0E0',
  },
  lido: {
    steth: '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84',
    wsteth: '0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0',
  },
  stakewise: {
    seth2: '0xFe2e637202056d30016725477c5da089Ab0A043A',
    reth2: '0x20BC832ca081b91433ff6c17f85701B6e92486c5',
  },
  synthetix: {
    exchangeRates: '0xd69b189020EF614796578AfE4d10378c5e7e1138',
    synths: [
      { synth: '0x57Ab1ec28D129707052df4dF418D58a2D46d5f51' }, // ProxyERC20sUSD
      { synth: '0xd2dF355C19471c8bd7D8A3aa27Ff4e26A21b4076' }, // ProxysAAVE
      { synth: '0xe36E2D3c7c34281FA3bC737950a68571736880A1' }, // ProxysADA
      { synth: '0xF48e200EAF9906362BB1442fca31e0835773b8B4' }, // ProxysAUD
      { synth: '0xfE18be6b3Bd88A2D2A7f928d00292E7a9963CfC6' }, // ProxysBTC
      { synth: '0x0F83287FF768D1c1e17a42F44d644D7F22e8ee1d' }, // ProxysCHF
      { synth: '0xD38aEb759891882e78E957c80656572503D8c1B1' }, // ProxysCRV
      { synth: '0xfE33ae95A9f0DA8A845aF33516EDc240DCD711d6' }, // ProxysDEFI
      { synth: '0x1715AC0743102BF5Cd58EfBB6Cf2dC2685d967b6' }, // ProxysDOT
      { synth: '0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb' }, // ProxysETH
      { synth: '0x104eDF1da359506548BFc7c25bA1E28C16a70235' }, // ProxysETHBTC
      { synth: '0xD71eCFF9342A5Ced620049e616c5035F1dB98620' }, // ProxysEUR
      { synth: '0x97fe22E7341a0Cd8Db6F6C021A24Dc8f4DAD855F' }, // ProxysGBP
      { synth: '0xF6b1C627e95BFc3c1b4c9B825a032Ff0fBf3e07d' }, // ProxysJPY
      { synth: '0x269895a3dF4D73b077Fc823dD6dA1B95f72Aaf9B' }, // ProxysKRW
      { synth: '0xbBC455cb4F1B9e4bFC4B73970d360c8f032EfEE6' }, // ProxysLINK
    ],
  },
  aave: {
    lendingPool: '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9',
    dataProvider: '0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d',
    atokens: [
      { atoken: '0xFFC97d72E13E01096502Cb8Eb52dEe56f74DAD7B', token: '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9' }, // aave
      { atoken: '0x1E6bb68Acec8fefBD87D192bE09bb274170a0548', token: '0xD46bA6D942050d489DBd938a2C909A5d5039A161' }, // AAMPL
      { atoken: '0x272F97b7a56a387aE942350bBC7Df5700f8a4576', token: '0xba100000625a3754423978a60c9317c58a424e3D' }, // bal
      { atoken: '0x05Ec93c0365baAeAbF7AefFb0972ea7ECdD39CF1', token: '0x0D8775F648430679A709E98d2b0Cb6250d2887EF' }, // bat
      { atoken: '0xA361718326c15715591c299427c62086F69923D9', token: '0x4Fabb145d64652a948d72533023f6E7A623C7C53' }, // busd
      { atoken: '0x8dAE6Cb04688C62d939ed9B68d32Bc62e49970b1', token: '0xD533a949740bb3306d119CC777fa900bA034cd52' }, // crv
      { atoken: '0x028171bCA77440897B824Ca71D1c56caC55b68A3', token: '0x6B175474E89094C44Da98b954EedeAC495271d0F' }, // dai
      { atoken: '0xaC6Df26a590F08dcC95D5a4705ae8abbc88509Ef', token: '0xF629cBd94d3791C9250152BD8dfBDF380E2a3B9c' }, // enj
      { atoken: '0x683923dB55Fead99A79Fa01A27EeC3cB19679cC3', token: '0x956F47F50A910163D8BF957Cf5846D573E7f87CA' }, // fei
      { atoken: '0xd4937682df3C8aEF4FE912A96A74121C0829E664', token: '0x853d955aCEf822Db058eb8505911ED77F175b99e' }, // frax
      { atoken: '0xD37EE7e4f452C6638c96536e68090De8cBcdb583', token: '0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd' }, // gusd
      { atoken: '0x39C6b3e42d6A679d7D776778Fe880BC9487C2EDA', token: '0xdd974D5C2e2928deA5F71b9825b8b646686BD200' }, // knc
      { atoken: '0xa06bC25B5805d5F8d82847D191Cb4Af5A3e873E0', token: '0x514910771AF9Ca656af840dff83E8264EcF986CA' }, // link
      { atoken: '0xa685a61171bb30d4072B338c80Cb7b2c865c873E', token: '0x0F5D2fB29fb7d3CFeE444a200298f468908cC942' }, // mana
      { atoken: '0xc713e5E149D5D0715DcD1c156a020976e7E56B88', token: '0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2' }, // mkr
      { atoken: '0xc9BC48c72154ef3e5425641a3c747242112a46AF', token: '0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919' }, // rai
      { atoken: '0xCC12AbE4ff81c9378D670De1b57F8e0Dd228D77a', token: '0x408e41876cCCDC0F92210600ef50372656052a38' }, // ren
      // { atoken: '0x514cd6756CCBe28772d4Cb81bC3156BA9d1744aa', token: '0xD5147bc8e386d91Cc5DBE72099DAC6C9b99276F5' }, // renFIL
      { atoken: '0x35f6B052C598d933D69A4EEC4D04c73A191fE6c2', token: '0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F' }, // snx
      { atoken: '0x6C5024Cd4F8A59110119C56f8933403A539555EB', token: '0x57Ab1ec28D129707052df4dF418D58a2D46d5f51' }, // susd
      { atoken: '0x101cc05f4A51C0319f570d5E146a8C625198e636', token: '0x0000000000085d4780B73119b644AE5ecd22b376' }, // tusd
      { atoken: '0xB9D7CB55f463405CDfBe4E90a6D2Df01C2B92BF1', token: '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984' }, // uni
      { atoken: '0xBcca60bB61934080951369a648Fb03DF4F96263C', token: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48' }, // usdc
      { atoken: '0x2e8F4bdbE3d47d7d7DE490437AeA9915D930F1A3', token: '0x8E870D67F660D95d5be530380D0eC0bd388289E1' }, // usdp
      { atoken: '0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811', token: '0xdAC17F958D2ee523a2206206994597C13D831ec7' }, // usdt
      { atoken: '0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656', token: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599' }, // wbtc
      { atoken: '0x030bA81f1c18d280636F32af80b9AAd02Cf0854e', token: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2' }, // weth
      { atoken: '0xF256CC7847E919FAc9B808cC216cAc87CCF2f47a', token: '0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272' }, // xsushi
      { atoken: '0x5165d24277cD063F5ac44Efd447B27025e888f37', token: '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e' }, // yfi
      { atoken: '0xDf7FF54aAcAcbFf42dfe29DD6144A69b629f8C9e', token: '0xE41d2489571d322189246DaFA5ebDe1F4699F498' }, // zrx
    ],
  },
  compound: {
    Comptroller: '0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b',
    Governance: '0xc0da01a04c3f3e0be433606045bb7017a7323e38',
    Timelock: '0x6d903f6003cca6255d85cca4d3b5e5146dc33925',
    OpenOracle: '0x922018674c12a7f0d394ebeef9b58f186cde13c1',
    ctokens: [
      { ctoken: '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643', token: '0x6B175474E89094C44Da98b954EedeAC495271d0F' },
      { ctoken: '0x35A18000230DA775CAc24873d00Ff85BccdeD550', token: '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984' },
      { ctoken: '0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5', token: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2' },
      { ctoken: '0x39AA39c021dfbaE8faC545936693aC917d5E7563', token: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48' },
      { ctoken: '0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9', token: '0xdAC17F958D2ee523a2206206994597C13D831ec7' },
      { ctoken: '0xccF4429DB6322D5C611ee964527D42E5d685DD6a', token: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599' },
      { ctoken: '0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4', token: '0xc00e94Cb662C3520282E6f5717214004A7f26888' },
      { ctoken: '0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E', token: '0x0D8775F648430679A709E98d2b0Cb6250d2887EF' },
      { ctoken: '0xFAce851a4921ce59e912d19329929CE6da6EB0c7', token: '0x514910771AF9Ca656af840dff83E8264EcF986CA' },
      { ctoken: '0x158079Ee67Fce2f58472A96584A73C7Ab9AC95c1', token: '0x221657776846890989a759ba2973e427dff5c9bb' },
      { ctoken: '0xF5DCe57282A584D2746FaF1593d3121Fcac444dC', token: '0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359' },
      { ctoken: '0x12392F67bdf24faE0AF363c24aC620a2f67DAd86', token: '0x0000000000085d4780B73119b644AE5ecd22b376' },
      { ctoken: '0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407', token: '0xE41d2489571d322189246DaFA5ebDe1F4699F498' },
      { ctoken: '0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c', token: '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9' },
      { ctoken: '0x95b4ef2869ebd94beb4eee400a99824bf5dc325b', token: '0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2' },
      { ctoken: '0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7', token: '0x6B3595068778DD592e39A122f4f5a5cF09C90fE2' },
      { ctoken: '0x041171993284df560249b57358f931d9eb7b925d', token: '0x8E870D67F660D95d5be530380D0eC0bd388289E1' },
      { ctoken: '0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946', token: '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e' },
    ],
  },
  cream: {
    crtokens: [
      { ctoken: '0xD06527D5e56A3495252A528C4987003b712860eE', token: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2' }, // WETH
      { ctoken: '0x797AAB1ce7c01eB727ab980762bA88e7133d2157', token: '0xdAC17F958D2ee523a2206206994597C13D831ec7' }, // USDT
      { ctoken: '0x44fbeBd2F576670a6C33f6Fc0B00aA8c5753b322', token: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48' }, // USDC
      { ctoken: '0xCbaE0A83f4f9926997c8339545fb8eE32eDc6b76', token: '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e' }, // YFI
      { ctoken: '0xcE4Fe9b4b8Ff61949DCfeB7e03bc9FAca59D2Eb3', token: '0xba100000625a3754423978a60c9317c58a424e3D' }, // BAL
      { ctoken: '0x19D1666f543D42ef17F66E376944A22aEa1a8E46', token: '0xc00e94Cb662C3520282E6f5717214004A7f26888' }, // COMP
      { ctoken: '0x9baF8a5236d44AC410c0186Fe39178d5AAD0Bb87', token: '0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8' }, // YCRV
      { ctoken: '0x892B14321a4FCba80669aE30Bd0cd99a7ECF6aC0', token: '0x2ba592F78dB6436527729929AAf6c908497cB200' }, // CREAM
      { ctoken: '0x697256CAA3cCaFD62BB6d3Aa1C7C5671786A5fD9', token: '0x514910771AF9Ca656af840dff83E8264EcF986CA' }, // LINK
      { ctoken: '0x8B86e0598616a8d4F1fdAE8b59E55FB5Bc33D0d6', token: '0x80fB784B7eD66730e8b1DBd9820aFD29931aab03' }, // LEND
      { ctoken: '0xc7Fd8Dcee4697ceef5a2fd4608a7BD6A94C77480', token: '0xD533a949740bb3306d119CC777fa900bA034cd52' }, // CRV
      { ctoken: '0x17107f40d70f4470d20CB3f138a052cAE8EbD4bE', token: '0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D' }, // RENBTC
      { ctoken: '0x1FF8CDB51219a8838b52E9cAc09b71e591BC998e', token: '0x4Fabb145d64652a948d72533023f6E7A623C7C53' }, // BUSD
      { ctoken: '0x3623387773010d9214B10C551d6e7fc375D31F58', token: '0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2' }, // MTA
      { ctoken: '0x4EE15f44c6F0d8d1136c83EfD2e8E4AC768954c6', token: '0x4EE15f44c6F0d8d1136c83EfD2e8E4AC768954c6' }, // YYCRV
      { ctoken: '0x338286C0BC081891A4Bda39C7667ae150bf5D206', token: '0x6B3595068778DD592e39A122f4f5a5cF09C90fE2' }, // SUSHI
      { ctoken: '0x10FDBD1e48eE2fD9336a482D746138AE19e649Db', token: '0x50D1c9771902476076eCFc8B2A83Ad6b9355a4c9' }, // FTT
      { ctoken: '0x01da76DEa59703578040012357b81ffE62015C2d', token: '0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7' }, // YETH
      { ctoken: '0xef58b2d5A1b8D3cDE67b8aB054dC5C831E9Bc025', token: '0x476c5E26a75bd202a9683ffD34359C0CC15be0fF' }, // SRM
      { ctoken: '0xe89a6D0509faF730BD707bf868d9A2A744a363C7', token: '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984' }, // UNI
      { ctoken: '0xeFF039C3c1D668f408d09dD7B63008622a77532C', token: '0x0d438F3b5175Bebc262bF23753C1E53d03432bDE' }, // WNXM
      { ctoken: '0x22B243B96495C547598D9042B6f94B01C22B2e9E', token: '0x87eDfFDe3E14c7a66c9b9724747a1C5696b742e6' }, // SWAG
      { ctoken: '0x8b3FF1ed4F36C2c2be675AFb13CC3AA5d73685a5', token: '0xaaAEBE6Fe48E54f431b0C390CfaF0b017d09D42d' }, // CEL
      { ctoken: '0x2A537Fa9FFaea8C1A41D3C2B68a9cb791529366D', token: '0x1494CA1F11D487c2bBe4543E90080AeBa4BA3C2b' }, // DPI
      { ctoken: '0x7ea9C63E216D5565c3940A2B3d150e59C2907Db3', token: '0x9BE89D2a4cd102D8Fecc6BF9dA793be995C22541' }, // BBTC
      { ctoken: '0x3225E3C669B39C7c8B3e204a8614bB218c5e31BC', token: '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9' }, // AAVE
      { ctoken: '0xf55BbE0255f7f4E70f63837Ff72A577fbDDbE924', token: '0x0391D2021f89DC339F60Fff84546EA23E337750f' }, // BOND
      { ctoken: '0x903560b1CcE601794C584F58898dA8a8b789Fc5d', token: '0x1cEB5cB57C4D4E2b2433641b95Dd330A33185A44' }, // KP3R
      { ctoken: '0x054B7ed3F45714d3091e82aAd64A1588dC4096Ed', token: '0x0316EB71485b0Ab14103307bf65a021042c6d380' }, // HBTC
      { ctoken: '0xd5103AfcD0B3fA865997Ef2984C66742c51b2a8b', token: '0x9AFb950948c2370975fb91a441F36FDC02737cD4' }, // HFIL
      { ctoken: '0xfd609a03B393F1A1cFcAcEdaBf068CAD09a924E2', token: '0xcBc1065255cBc3aB41a6868c22d1f1C573AB89fd' }, // CRETH2
      { ctoken: '0xD692ac3245bb82319A31068D6B8412796eE85d2c', token: '0xdF574c24545E5FfEcb9a659c229253D4111d87e1' }, // HUSD
      { ctoken: '0x92B767185fB3B04F881e3aC8e5B0662a027A1D9f', token: '0x6B175474E89094C44Da98b954EedeAC495271d0F' }, // DAI
      { ctoken: '0x10a3da2BB0Fae4D591476fd97D6636fd172923a8', token: '0x584bC13c7D411c00c01A62e8019472dE68768430' }, // HEGIC
      { ctoken: '0x3C6C553A95910F9FC81c98784736bd628636D296', token: '0x36F3FD68E7325a35EB768F1AedaAe9EA0689d723' }, // ESD
      { ctoken: '0x85759961b116f1D36fD697855c57A6ae40793D9B', token: '0x111111111117dC0aa78b770fA6A738034120C302' }, // 1INCH
      { ctoken: '0x7Aaa323D7e398be4128c7042d197a2545f0f1fea', token: '0xd26114cd6EE289AccF82350c8d8487fedB8A0C07' }, // OMG
      { ctoken: '0x011a014d5e8Eb4771E575bB1000318D509230Afa', token: '0xBb2b8038a1640196FbE3e38816F3e67Cba72D940' }, // UNI-V2-WBTC-ETH
      { ctoken: '0xE6C3120F38F56deb38B69b65cC7dcAF916373963', token: '0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852' }, // UNI-V2-ETH-USDT
      { ctoken: '0x4Fe11BC316B6d7A345493127fBE298b95AdaAd85', token: '0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc' }, // UNI-V2-USDC-ETH
      { ctoken: '0xcD22C4110c12AC41aCEfA0091c432ef44efaAFA0', token: '0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11' }, // UNI-V2-DAI-ETH
      { ctoken: '0x228619CCa194Fbe3Ebeb2f835eC1eA5080DaFbb2', token: '0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272' }, // XSUSHI
      { ctoken: '0x73f6cBA38922960b7092175c0aDD22Ab8d0e81fC', token: '0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58' }, // SLP-WBTC-ETH
      { ctoken: '0x38f27c03d6609a86FF7716ad03038881320BE4Ad', token: '0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f' }, // SLP-DAI-ETH
      { ctoken: '0x5EcaD8A75216CEa7DFF978525B2D523a251eEA92', token: '0x397FF1542f962076d0BFE58eA045FfA2d347ACa0' }, // SLP-USDC-ETH
      { ctoken: '0x5C291bc83d15f71fB37805878161718eA4b6AEe9', token: '0x06da0fd433C1A5d7a4faa01111c044910A184553' }, // SLP-ETH-USDT
      { ctoken: '0x6BA0C66C48641e220CF78177C144323b3838D375', token: '0x795065dCc9f64b5614C407a6EFDC400DA6221FB0' }, // SLP-SUSHI-ETH
      { ctoken: '0xd532944df6DFd5Dd629E8772F03D4fC861873abF', token: '0x088ee5007C98a9677165D78dD2109AE4a3D04d0C' }, // SLP-YFI-ETH
      { ctoken: '0x197070723CE0D3810a0E47F06E935c30a480D4Fc', token: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599' }, // WBTC
      { ctoken: '0xC25EAE724f189Ba9030B2556a1533E7c8A732E14', token: '0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F' }, // SNX
      { ctoken: '0x25555933a8246Ab67cbf907CE3d1949884E82B55', token: '0x57Ab1ec28D129707052df4dF418D58a2D46d5f51' }, // SUSD
      { ctoken: '0xc68251421eDDa00a10815E273fA4b1191fAC651b', token: '0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5' }, // PICKLE
      { ctoken: '0x65883978aDA0e707c3b2BE2A6825b1C4BDF76A90', token: '0x8Ab7404063Ec4DBcfd4598215992DC3F8EC853d7' }, // AKRO
      { ctoken: '0x8B950f43fCAc4931D408F1fcdA55C6CB6cbF3096', token: '0x19D97D8fA813EE2f51aD4B4e04EA08bAf4DFfC28' }, // BBADGER
      { ctoken: '0x59089279987DD76fC65Bf94Cb40E186b96e03cB3', token: '0x8207c1FfC5B6804F6024322CcF34F29c3541Ae26' }, // OGN
      { ctoken: '0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6', token: '0xfF20817765cB7f73d4bde2e66e067E58D11095C2' }, // AMP
      { ctoken: '0xb092b4601850E23903A42EaCBc9D8A0EeC26A4d5', token: '0x853d955aCEf822Db058eb8505911ED77F175b99e' }, // FRAX
      { ctoken: '0x1d0986Fb43985c88Ffa9aD959CC24e6a087C7e35', token: '0xa1faa113cbE53436Df28FF0aEe54275c13B40975' }, // ALPHA
      { ctoken: '0x51F48b638F82e8765F7a26373A2Cb4CcB10C07af', token: '0xa47c8bf37f92aBed4A126BDA807A7b7498661acD' }, // UST
      { ctoken: '0xc36080892c64821fa8e396bc1bD8678fA3b82b17', token: '0x4E15361FD6b4BB609Fa63C81A2be19d873717870' }, // FTM
      { ctoken: '0x8379BAA817c5c5aB929b03ee8E3c48e45018Ae41', token: '0x3155BA85D5F96b2d030a4966AF206230e46849cb' }, // RUNE
      { ctoken: '0x299e254A8a165bBeB76D9D69305013329Eea3a3B', token: '0xbC396689893D065F41bc2C6EcbeE5e0085233447' }, // PERP
      { ctoken: '0xf8445C529D363cE114148662387eba5E62016e20', token: '0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919' }, // RAI
      { ctoken: '0x7C3297cFB4c4bbd5f44b450c0872E0ADA5203112', token: '0x967da4048cD07aB37855c090aAF366e4ce1b9F48' }, // OCEAN
      { ctoken: '0x081FE64df6dc6fc70043aedF3713a3ce6F190a21', token: '0xFca59Cd816aB1eaD66534D82bc21E7515cE441CF' }, // RARI
      { ctoken: '0x28526Bb33d7230E65E735dB64296413731C5402e', token: '0xb753428af26E81097e7fD17f40c88aaA3E04902c' }, // SFI
      { ctoken: '0x45406ba53bB84Cd32A58e7098a2D4D1b11B107F6', token: '0x27b7b1ad7288079A66d12350c828D3C00A6F07d7' }, // YVCurve-IB CHECK!
      { ctoken: '0x6d1B9e01aF17Dd08d6DEc08E210dfD5984FF1C20', token: '0x986b4AFF588a109c09B50A03f42E4110E29D353F' }, // YVCurve-sETH
      { ctoken: '0x1F9b4756B008106C806c7E64322d7eD3B72cB284', token: '0xdCD90C7f6324cfa40d7169ef80b12031770B4325' }, // YVCurve-stETH
      { ctoken: '0xab10586C918612BA440482db77549d26B7ABF8f7', token: '0x1337DEF16F9B486fAEd0293eb623Dc8395dFE46a' }, // ARMOR
      { ctoken: '0xdFFf11DFe6436e42a17B86e7F419Ac8292990393', token: '0x1337DEF18C680aF1f9f45cBcab6309562975b1dD' }, // ARNXM
      { ctoken: '0xDbb5e3081dEf4b6cdD8864aC2aeDA4cBf778feCf', token: '0xec67005c4E498Ec7f55E092bd1d35cbC47C91892' }, // MLN
      { ctoken: '0x71cEFCd324B732d4E058AfAcBA040d908c441847', token: '0x1b40183EFB4Dd766f11bDa7A7c3AD8982e998421' }, // VSP
      { ctoken: '0x1A122348B73B58eA39F822A89e6ec67950c2bBD0', token: '0xbA4cFE5741b357FA371b506e5db0774aBFeCf8Fc' }, // VVSP
      { ctoken: '0x523EFFC8bFEfC2948211A05A905F761CBA5E8e9E', token: '0x6810e776880C02933D47DB1b9fc05908e5386b96' }, // GNO
      { ctoken: '0x4202D97E00B9189936EdF37f8D01cfF88BDd81d4', token: '0xa9fE4601811213c340e850ea305481afF02f5b28' }, // YVWETH
      { ctoken: '0x4BAa77013ccD6705ab0522853cB0E9d453579Dd4', token: '0x4BAa77013ccD6705ab0522853cB0E9d453579Dd4' }, // YUSD
      { ctoken: '0x98E329eB5aae2125af273102f3440DE19094b77c', token: '0xCC4304A31d09258b0029eA7FE63d032f52e44EFe' }, // SWAP
      { ctoken: '0x8C3B7a4320ba70f8239F83770c4015B5bc4e6F91', token: '0x956F47F50A910163D8BF957Cf5846D573E7f87CA' }, // FEI
      { ctoken: '0xE585c76573D7593ABF21537B607091F76c996E73', token: '0x4691937a7508860F876c9c0a2a617E7d9E945D4B' }, // WOO
      { ctoken: '0x81E346729723C4D15d0FB1c5679b9f2926Ff13C6', token: '0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C' }, // BNT
      { ctoken: '0xC581b735A1688071A1746c968e0798D642EDE491', token: '0xC581b735A1688071A1746c968e0798D642EDE491' }, // EURT
      { ctoken: '0xD7394428536F63d5659cc869EF69d10f9E66314B', token: '0x8E870D67F660D95d5be530380D0eC0bd388289E1' }, // PAX
      { ctoken: '0x1241B10E7EA55b22f5b2d007e8fECDF73DCff999', token: '0x45804880De22913dAFE09f4980848ECE6EcbAf78' }, // PAXG
      { ctoken: '0x2A867fd776B83e1bd4e13C6611AFd2F6af07EA6D', token: '0x9BE89D2a4cd102D8Fecc6BF9dA793be995C22541' }, // BBTC
      { ctoken: '0x250Fb308199FE8C5220509C1bf83D21d60b7f74A', token: '0x0000000000095413afC295d19EDeb1Ad7B71c952' }, // LON
      { ctoken: '0x4112a717edD051F77d834A6703a1eF5e3d73387F', token: '0x25f8087EAD173b73D6e8B84329989A8eEA16CF73' }, // YGG
      { ctoken: '0xF04ce2e71D32D789a259428ddcD02D3C9F97fb4E', token: '0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b' }, // AXS
      { ctoken: '0x89e42987c39f72e2EAd95a8a5bC92114323d5828', token: '0x3845badAde8e6dFF049820680d1F14bD3903a5d0' }, // SAND
      { ctoken: '0x58DA9c9fC3eb30AbBcbBAb5DDabb1E6e2eF3d2EF', token: '0x0F5D2fB29fb7d3CFeE444a200298f468908cC942' }, // MANA
    ],
  },
  kyber: {
    proxy: '0x9AAb3f75489902f3a48495025729a0AF77d4b11e',
  },
  oneinch: {
    exchange: '0xC586BeF4a0992C495Cf22e1aeEE4E446CECDee0E',
    factory: '0xbAF9A5d4b0052359326A6CDAb54BABAa3a3A9643',
    pools: {
      wethdai: '0x7566126f2fd0f2dddae01bb8a6ea49b760383d5a',
      wethusdc: '0xb4db55a20e0624edd82a0cf356e3488b4669bd27',
      wethwbtc: '0x6a11f3e5a01d129e566d783a7b6e8862bfd66cca',
      daiusdc: '0x05d7bc2a5ec390743edec5aa9f9fe35aa87efa43',
    },
  },
  balancer: {
    factory: '0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd',
    pools: {
      wethdai: '0x8b6e6e7b5b3801fed2cafd4b22b8a16c2f2db21a',
    },
  },
  curve: {
    addressProvider: '0x0000000022D53366457F9d5E68Ec105046FC4383',
    pools: {
      v3: {
        tripool: '0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7',
        aave: '0xDeBF20617708857ebe4F679508E7b7863a8A8EeE',
        aeth: '0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2',
        busd: '0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27',
        compound: '0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56',
        hbtc: '0x4CA9b3063Ec5866A4B82E437059D2C43d1be596F',
        ib: '0x2dded6Da1BF5DBdF597C45fcFaa3194e53EcfeAF',
        pax: '0x06364f10B501e868329afBc005b3492902d6C763',
        ren: '0x93054188d876f558f4a66B2EF1d97d16eDf0895B',
        saave: '0xEB16Ae0052ed37f479f7fe63849198Df1765a733',
        steth: '0xDC24316b9AE028F1497c275EB9192a3Ea0f67022',
        susd: '0xA5407eAE9Ba41422680e2e00537571bcC53efBfD',
        usdt: '0x52EA46506B9CC5Ef470C5bf89f17Dc28bB35D85C',
        y: '0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51',
        dusd: '0x8038C01A0390a8c547446a0b2c18fc9aEFEcc10c',
        gusd: '0x4f062658EaAF2C1ccf8C8e36D6824CDf41167956',
        husd: '0x3eF6A01A0f81D6046290f3e2A8c5b843e738E604',
        musd: '0x8474DdbE98F5aA3179B3B3F5942D724aFcdec9f6',
        rsv: '0xC18cC39da8b11dA8c3541C598eE022258F9744da',
        usdk: '0x3E01dD8a5E1fb3481F0F589056b428Fc308AF0Fb',
        usdn: '0x0f9cb53Ebe405d49A0bbdBD291A65Ff571bC83e1',
        usdp: '0x42d7025938bEc20B69cBae5A77421082407f053A',
        ust: '0x890f4e345B1dAED0367A877a1612f86A1f86985f',
        tusd: '0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1',
        busdv2: '0x4807862AA8b2bF68830e4C8dc86D0e9A998e085a',
        lusd: '0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA',
        frax: '0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B',
        alusd: '0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c',
        mim: '0x5a6A4D54456819380173272A5E8E9B9904BdF41B',
        bbtc: '0x071c661B4DeefB59E2a3DdB20Db036821eeE8F4b',
        obtc: '0xd81dA8D904b52208541Bade1bD6595D8a251F8dd',
        pbtc: '0x7F55DDe206dbAD629C080068923b36fe9D6bDBeF',
        tbtc: '0xC25099792E9349C7DD09759744ea681C7de2cb66',
        // Broken
        // rai: '0x618788357D0EBd8A37e763ADab3bc575D54c2C7d',
        // reth: '0xF9440930043eb3997fc70e1339dBb11F341de7A8',
        // linkusd: '0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171',
        // sbtc: '0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714',
        // seth: '0xc5424B857f758E906013F3555Dad202e4bdB4567',
        // eurt: '0xFD5dB7463a3aB53fD211b4af195c5BCCC1A03890',
        // eurs: '0x0Ce6a5fF5217e38315f87032CF90686C96627CAA',
        // link: '0xF178C0b5Bb7e7aBF4e12A4838C7b7c5bA2C623c0',
        // tricrypto: '0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5', //deprecated
      },
      crypto: {
        tricrypto2: '0xD51a44d3FaE010294C616388b506AcdA1bfAAE46',
        crveth: '0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511',
        cvxeth: '0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4',
        spell: '0x98638FAcf9a3865cd033F36548713183f6996122',
        t: '0x752eBeb79963cf0732E9c0fec72a49FD1DEfAEAC',
        // Broken
        // xaut3crv: '0xAdCFcf9894335dC340f6Cd182aFA45999F45Fc44',
        // eurtusd: '0x9838eCcC42659FA8AA7daF2aD134b53984c9427b',
        // eursusd: '0x98a7F18d4E56Cfe84E3D081B40001B3d5bD3eB8B',
      },
      factory: {
        wormhole: '0xCEAF7747579696A2F0bb206a14210e3c9e6fB269', // 53
        d3pool: '0xBaaa1F5DbA42C3389bDbc2c9D2dE134F5cD0Dc89', // 57
        mimust: '0x55A8a39bc9694714E2874c1ce77aa1E599461E18', // 48
        feimetapool: '0x06cb22615BA53E60D67Bf6C341a0fD5E718E1655', // 11
        cvxcrv: '0x9D0464996170c6B9e75eED71c68B99dDEDf279e8', // 22
        origindollar: '0x87650D7bbfC3A9F10587d7778206671719d9910D', // 9
        ibbtc: '0xFbdCA68601f835b27790D98bbb8eC7f05FDEaA9B', // 60
        usdm: '0x5B3b5DF2BF2B6543f78e053bD91C4Bdd820929f1', // 23
        // Broken
        // talcx: '0x9001a452d39A8710D27ED5c2E10431C13F5Fba74', // 94 No price
        // aleth: '0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e', // 38 No price
        // reth: '0x447Ddd4960d9fdBF6af9a790560d0AF76795CB08', // 89 No price
        // tokemetapool: '0x961226B64AD373275130234145b96D100Dc0b655', // 95 No price
        // trieurpool: '0xb9446c4Ef5EBE66268dA6700D26f96273DE3d571', // 66
        // ibeur: '0x19b080FE1ffA0553469D20Ca36219F17Fcf03859', // 3
        // bean: '0x3a70DfA7d2262988064A2D051dd47521E43c9BdD', // 81 Hacked
      },
      cryptofactory: {
        palstkaave: '0x48536EC5233297C367fd0b6979B75d9270bB6B15', // 9
        yfieth: '0xC26b89A667578ec7b3f11b2F98d6Fd15C07C54ba', // 8
        btflyeth: '0xF43b15Ab692fDe1F9c24a9FCE700AdCC809D5391', // 17
        badgerwbtc: '0x50f3752289e1456BfA505afd37B241bca23e685d', // 4
        stgusdc: '0x3211C6cBeF1429da3D0d58494938299C92Ad5860', // 37
        // Broken
        // cvxfxs: '0xd658A338613198204DCa1143Ac3F01A722b5d94A', // 18
        // keep3reth: 'find', // 39
        // stasiseurs: '0x98a7F18d4E56Cfe84E3D081B40001B3d5bD3eB8B',
      },
    },
  },
  gamma: {
    visors: [
      { name: 'BABL-ETH', address: '0x705b3aCaF102404CfDd5e4A60535E4e70091273C' },
      // They need to enable them
      // { name: 'GAMMA-ETH', address: '0xf6eeCA73646ea6A5c878814e6508e87facC7927C' },
      // { name: 'FLOAT-ETH', address: '0xc86B1e7FA86834CaC1468937cdd53ba3cCbC1153' },
    ],
  },
  // Lists all potential assets to be bonded. Get actual discounts from on-chain
  bonds: [
    {
      name: 'BABL-ETH',
      address: '0x705b3aCaF102404CfDd5e4A60535E4e70091273C',
      link: 'https://app.gammastrategies.org/dashboard',
    },
    {
      name: 'fDAI',
      address: '0xa6c25548df506d84afd237225b5b34f2feb1aa07',
      link: 'https://app.rari.capital/fuse/pool/144',
    },
    {
      name: 'fFRAX',
      address: '0xa54c548d11792b3d26ad74f5f899e12cdfd64fd6',
      link: 'https://app.rari.capital/fuse/pool/144',
    },
    {
      name: 'fBABL',
      address: '0x812eedc9eba9c428434fd3ce56156b4e23012ebc',
      link: 'https://app.rari.capital/fuse/pool/144',
    },
    {
      name: 'fWETH',
      address: '0x7dbc3af9251756561ce755fcc11c754184af71f7',
      link: 'https://app.rari.capital/fuse/pool/144',
    },
    {
      name: 'fFEI',
      address: '0x3a2804ec0ff521374af654d8d0daa1d1ae1ee900',
      link: 'https://app.rari.capital/fuse/pool/144',
    },
  ],
  pickle: {
    // https://github.com/pickle-finance/contracts
    jars: [
      {
        name: 'pCurve sCRV Jar',
        address: '0x68d14d66B2B0d6E157c06Dc8Fefa3D8ba0e66a89',
        needs: '0xC25a3A3b969415c80451098fa907EC722572917F',
        crvpool: '0xA5407eAE9Ba41422680e2e00537571bcC53efBfD',
        nogauge: true,
      },
      { name: 'USDC Jar', address: '0xEB801AB73E9A2A482aA48CaCA13B1954028F4c94', nogauge: true }, // it has a gauge but gauge don't have decimals and it messes stuff up
      {
        name: 'pCurve REN/BTC Jar',
        address: '0x2E35392F4c36EBa7eCAFE4de34199b2373Af22ec',
        needs: '0x49849C98ae39Fff122806C06791Fa73784FB3675',
        crvpool: '0x93054188d876f558f4a66B2EF1d97d16eDf0895B',
        nogauge: true,
      },
      {
        name: 'pCurve 3pool Jar',
        address: '0x1BB74b5DdC1f4fC91D6f9E7906cf68bc93538e33',
        needs: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
        crvpool: '0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7',
      },
      {
        name: 'pCurve ETH/stETH Jar',
        address: '0x77C8A58D940a322Aea02dBc8EE4A30350D4239AD',
        needs: '0x06325440D014e39736583c165C2963BA99fAf14E',
        crvpool: '0xDC24316b9AE028F1497c275EB9192a3Ea0f67022',
      },
      {
        name: 'Sushi DAI/ETH Jar',
        address: '0x55282dA27a3a02ffe599f6D11314D239dAC89135',
        needs: '0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f',
        sushi: '0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f',
      },
      {
        name: 'Sushi USDC/ETH Jar',
        address: '0x8c2D16B7F6D3F989eb4878EcF13D695A7d504E43',
        needs: '0x397FF1542f962076d0BFE58eA045FfA2d347ACa0',
        sushi: '0x397FF1542f962076d0BFE58eA045FfA2d347ACa0',
      },
      {
        name: 'Sushi USDT/ETH Jar',
        address: '0xa7a37aE5Cb163a3147DE83F15e15D8E5f94D6bCE',
        needs: '0x06da0fd433C1A5d7a4faa01111c044910A184553',
        sushi: '0x06da0fd433C1A5d7a4faa01111c044910A184553',
      },
      {
        name: 'Sushi WBTC/ETH Jar',
        address: '0xde74b6c547bd574c3527316a2eE30cd8F6041525',
        needs: '0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58',
        sushi: '0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58',
      },
      {
        name: 'Sushi YFI/ETH Jar',
        address: '0x3261D9408604CC8607b687980D40135aFA26FfED',
        needs: '0x088ee5007C98a9677165D78dD2109AE4a3D04d0C',
        sushi: '0x088ee5007C98a9677165D78dD2109AE4a3D04d0C',
      },
      {
        name: 'Sushi CVX/ETH Jar',
        address: '0xDCfAE44244B3fABb5b351b01Dc9f050E589cF24F',
        needs: '0x05767d9EF41dC40689678fFca0608878fb3dE906',
        sushi: '0x05767d9EF41dC40689678fFca0608878fb3dE906',
      },
      {
        name: 'Yearn USDC Jar',
        address: '0xEB801AB73E9A2A482aA48CaCA13B1954028F4c94',
        needs: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        nogauge: true, // it has a gauge but the decimals issue. Gauge don't have decimals()
      },
      {
        name: 'pYearn LUSD/3CRV Jar',
        address: '0x4fFe73Cf2EEf5E8C8E0E10160bCe440a029166D2',
        needs: '0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA',
        crvpool: '0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA',
      },
      {
        name: 'pYearn FRAX/3CRV Jar',
        address: '0x729C6248f9B1Ce62B3d5e31D4eE7EE95cAB32dfD',
        needs: '0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B',
        crvpool: '0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B',
      },
      {
        name: 'pYearn Ironbank Jar',
        address: '0x4E9806345fb39FFebd70A01f177A675805019ba8',
        needs: '0x5282a4ef67d9c33135340fb3289cc1711c13638c',
        crvpool: '0x2dded6Da1BF5DBdF597C45fcFaa3194e53EcfeAF',
      },
      {
        name: 'pCurve MIM/3CRV Jar',
        address: '0x1Bf62aCb8603Ef7F3A0DFAF79b25202fe1FAEE06',
        needs: '0x5a6A4D54456819380173272A5E8E9B9904BdF41B',
        crvpool: '0x5a6A4D54456819380173272A5E8E9B9904BdF41B',
      },
      {
        name: 'pSushi SPELL/ETH Jar',
        address: '0xdB84a6A48881545E8595218b7a2A3c9bd28498aE',
        needs: '0xb5De0C3753b6E1B4dBA616Db82767F17513E6d4E',
        sushi: '0xb5De0C3753b6E1B4dBA616Db82767F17513E6d4E',
      },
      {
        name: 'pSushi MIM/ETH Jar',
        address: '0x993f35FaF4AEA39e1dfF28f45098429E0c87126C',
        needs: '0x07D5695a24904CC1B6e3bd57cC7780B90618e3c4',
        sushi: '0x07D5695a24904CC1B6e3bd57cC7780B90618e3c4',
      },
      {
        name: 'pCurve cvxCRV/CRV Jar',
        address: '0xF1478A8387C449c55708a3ec11c143c35daf5E74',
        needs: '0x9D0464996170c6B9e75eED71c68B99dDEDf279e8',
        crvpool: '0x9D0464996170c6B9e75eED71c68B99dDEDf279e8',
      },
      {
        name: 'pCurve CRV/ETH Jar',
        address: '0x1c5Dbb5d9864738e84c126782460C18828859648',
        needs: '0xEd4064f376cB8d68F770FB1Ff088a3d0F3FF5c4d',
        crvpool: '0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511',
      },
      {
        name: 'pCurve CVX/ETH Jar',
        address: '0xc97f3fd224d90609831a2B74b46642aC43afE5ee',
        needs: '0x3A283D9c08E8b55966afb64C515f5143cf907611',
        crvpool: '0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4',
      },
      {
        name: 'pLOOKS Jar',
        address: '0xb4EBc2C371182DeEa04B2264B9ff5AC4F0159C69',
        needs: '0xf4d2888d29D722226FafA5d9B24F9164c092421E',
      },
      {
        name: 'pUniv3 USDC/ETH 0.05% Jar',
        address: '0x8CA1D047541FE183aE7b5d80766eC6d5cEeb942A',
        needs: '0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640',
      },
      {
        name: 'pUniv3 LOOKS/ETH 0.3% Jar',
        address: '0x0A3a5764945E29E38408637bC659981f0172b961',
        needs: '0x4b5Ab61593A2401B1075b90c04cBCDD3F87CE011',
      },
      {
        name: 'pUniv3 USDC/USDT 0.01% Jar',
        address: '0x563c77b40c7f08bA735426393Cf5f0e527D16C10',
        needs: '0x3416cF6C708Da44DB2624D63ea0AAef7113527C6',
      },
      {
        name: 'pUniv3 WBTC/ETH 0.05% Jar',
        address: '0xAaCDaAad9a9425bE2d666d08F741bE4F081C7ab1',
        needs: '0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0',
      },
      {
        name: 'pUniv3 COW/ETH Jar',
        address: '0xf0Fb82757B9f8A3A3AE3524e385E2E9039633948',
        needs: '0xFCfDFC98062d13a11cec48c44E4613eB26a34293',
      },
      {
        name: 'pUniv3 APE/ETH Jar',
        address: '0x49ED0e6B438430CEEdDa8C6d06B6A2797aFA81cA',
        needs: '0xAc4b3DacB91461209Ae9d41EC517c2B9Cb1B7DAF',
      },
      {
        name: 'pUniv3 FRAX/DAI Jar',
        address: '0xe7b69a17B3531d01FCEAd66FaF7d9f7655469267',
        needs: '0x97e7d56A0408570bA1a7852De36350f7713906ec',
      },
      // Not sure why it doesn't exit. Investigate
      // {
      //   name: 'pUniv3 FRAX/USDC Jar',
      //   address: '0x7f3514CBC6825410Ca3fA4deA41d46964a953Afb',
      //   needs: '0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52',
      // },
      // No swap param
      // {
      //   name: 'pUniv3 RBN/ETH Jar',
      //   address: '0x506748d736b77f51c5b490e4aC6c26B8c3975b14',
      //   needs: '0x94981F69F7483AF3ae218CbfE65233cC3c60d93a',
      // },
      // Not enough liquidity in univ3
      // {
      //   name: 'pUniv3 PICKLE/ETH 1% Jar',
      //   address: '0x575a9E386c33732880DEF8BE1BAD9dbc5dDDf7D7',
      //   needs: '0x11c4D3b9cd07807F455371d56B3899bBaE662788',
      // },
      // {
      //   name: 'pSTARGATE USDC Jar',
      //   address: '0x81740AAc02ae2F3c61D5a0c012b3e18f9dc02b5c',
      //   needs: '0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56',
      // },
      // {
      //   name: 'pSTARGATE USDT Jar',
      //   address: '0x363e7CD14AEcf4f7d0e66Ae1DEff830343D760a7',
      //   needs: '0x38EA452219524Bb87e18dE1C24D3bB59510BD783',
      // },
      // No rewards
      // {
      //   name: 'pUniv2 LOOKS/ETH Jar',
      //   address: '0x69CC22B240bdcDf4A33c7B3D04a660D4cF714370',
      //   needs: '0xDC00bA87Cc2D99468f7f34BC04CBf72E111A32f7',
      //   uni: '0xDC00bA87Cc2D99468f7f34BC04CBf72E111A32f7',
      // },
      // Do not work
      // cant get cvxcrv
      // {
      //   name: 'pCurve cvxCRV Jar',
      //   address: '0xB245280Fd1795f5068DEf8E8f32DB7846b030b2B',
      //   needs: '0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7',
      // },
      // Do not work
      // cant get cvxFXSFXS
      // {
      //   name: 'pCurve cvxFXSFXS Jar',
      //   address: '0x5Da34d322a4b29488e711419Fea36dA0d0114d5C',
      //   needs: '0xF3A43307DcAFa93275993862Aae628fCB50dC768',
      // },
      // No liquidity for tribe
      // {
      //   name: 'Univ2 FEI/TRIBE Jar',
      //   address: '0xC1513C1b0B359Bc5aCF7b772100061217838768B',
      //   needs: '0x9928e4046d7c6513326cCeA028cD3e7a91c7590A',
      //   uni: '0x9928e4046d7c6513326cCeA028cD3e7a91c7590A',
      // },
      // No Supply
      // {
      //   name: 'pUniv3 USDC/ETH 0.3% Jar',
      //   address: '0x3b79f29d7979D7DE22A0d09098e898157ea32dD5',
      //   needs: '0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8',
      // },
      // Pickle has no liquidity
      // {
      //   name: 'pUniv3 PICKLE/ETH 1% Jar',
      //   address: '0x575a9E386c33732880DEF8BE1BAD9dbc5dDDf7D7',
      //   needs: '0x11c4D3b9cd07807F455371d56B3899bBaE662788',
      // },
      // No liquidity for ALCX
      // {
      //   name: 'Sushi ALCX/ETH Jar',
      //   address: '0x9eb0aAd5Bb943D3b2F7603Deb772faa35f60aDF9',
      //   needs: '0xC3f279090a47e80990Fe3a9c30d24Cb117EF91a8',
      //   sushi: '0xC3f279090a47e80990Fe3a9c30d24Cb117EF91a8',
      // },
      // Not enough volume on univ3 for Sushi
      // {
      //   name: 'Sushi SUSHI/ETH Jar',
      //   address: '0xECb520217DccC712448338B0BB9b08Ce75AD61AE',
      //   needs: '0x795065dCc9f64b5614C407a6EFDC400DA6221FB0',
      //   sushi: '0x795065dCc9f64b5614C407a6EFDC400DA6221FB0',
      // },
      // Crazy slippage
      // {
      //   name: 'pSushi TRU/ETH Jar',
      //   address: '0x1d92e1702D7054f74eAC3a9569AeB87FC93e101D',
      //   needs: '0xfCEAAf9792139BF714a694f868A215493461446D',
      //   sushi: '0xfCEAAf9792139BF714a694f868A215493461446D',
      // },
      // Slippage
      // {
      //   name: 'pLQTY Jar',
      //   address: '0x65B2532474f717D5A8ba38078B78106D56118bbb',
      //   needs: '0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D',
      // },
      // No price for NEWO
      // {
      //   name: 'pSushi NEWO/USDC Jar',
      //   address: '0xBc57294Fc20bD23983dB598fa6B3f306aA1a414f',
      //   needs: '0xB264dC9D22ece51aAa6028C5CBf2738B684560D6',
      //   sushi: '0xB264dC9D22ece51aAa6028C5CBf2738B684560D6',
      // },
    ],
  },
  convex: {
    pools: [
      {
        name: 'compound',
        crvpool: '0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56',
        cvxpool: '0x32512Bee3848bfcBb7bEAf647aa697a100f3b706',
      },
      {
        name: 'usdt',
        crvpool: '0x52EA46506B9CC5Ef470C5bf89f17Dc28bB35D85C',
        cvxpool: '0xA1c3492b71938E144ad8bE4c2fB6810b01A43dD8',
      },
      {
        name: 'y',
        crvpool: '0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51',
        cvxpool: '0x0928F6753880A03628eB0be07b77992c8af37874',
      },
      {
        name: 'busd',
        crvpool: '0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27',
        cvxpool: '0x59bB786F222d3f0f00B0dA31B799Fff80D552940',
      },
      {
        name: 'susd',
        crvpool: '0xA5407eAE9Ba41422680e2e00537571bcC53efBfD',
        cvxpool: '0x11D200ef1409cecA8D6d23e6496550f707772F11',
      },
      {
        name: 'pax',
        crvpool: '0x06364f10B501e868329afBc005b3492902d6C763',
        cvxpool: '0x2eA94b0d3349A284488ACF2934E494b2f58ef647',
      },
      {
        name: 'ren',
        crvpool: '0x93054188d876f558f4a66B2EF1d97d16eDf0895B',
        cvxpool: '0x74b79021Ea6De3f0D1731fb8BdfF6eE7DF10b8Ae',
      },
      {
        name: 'hbtc',
        crvpool: '0x4CA9b3063Ec5866A4B82E437059D2C43d1be596F',
        cvxpool: '0x33c00bF8CFDf42929E0884d230A55F963221f8f3',
      },
      {
        name: 'tripool',
        crvpool: '0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7',
        cvxpool: '0x30D9410ED1D5DA1F6C8391af5338C93ab8d4035C',
      },
      {
        name: 'gusd',
        crvpool: '0x4f062658EaAF2C1ccf8C8e36D6824CDf41167956',
        cvxpool: '0x15c2471ef46Fa721990730cfa526BcFb45574576',
      },
      {
        name: 'husd',
        crvpool: '0x3eF6A01A0f81D6046290f3e2A8c5b843e738E604',
        cvxpool: '0xe4de776C0eA0974bfA39B8cbB9491091C8cDc1ff',
      },
      {
        name: 'usdk',
        crvpool: '0x3E01dD8a5E1fb3481F0F589056b428Fc308AF0Fb',
        cvxpool: '0x47941F99F4371CC26637CaEdBbd8Ba5F4bfE5149',
      },
      {
        name: 'usdn',
        crvpool: '0x0f9cb53Ebe405d49A0bbdBD291A65Ff571bC83e1',
        cvxpool: '0x3689f325E88c2363274E5F3d44b6DaB8f9e1f524',
      },
      {
        name: 'musd',
        crvpool: '0x8474DdbE98F5aA3179B3B3F5942D724aFcdec9f6',
        cvxpool: '0xd34d466233c5195193dF712936049729140DBBd7',
      },
      {
        name: 'rsv',
        crvpool: '0xC18cC39da8b11dA8c3541C598eE022258F9744da',
        cvxpool: '0x8b876C2C02B1f2Ac6Ec207B7f2f06034A4316A87',
      },
      {
        name: 'dusd',
        crvpool: '0x8038C01A0390a8c547446a0b2c18fc9aEFEcc10c',
        cvxpool: '0x06f4fFa5C3636AaA5C30B3DB97bfd1cd9Ac24A19',
      },
      {
        name: 'ust',
        crvpool: '0x890f4e345B1dAED0367A877a1612f86A1f86985f',
        cvxpool: '0x67c4f788FEB82FAb27E3007daa3d7b90959D5b89',
      },
      {
        name: 'aave',
        crvpool: '0xDeBF20617708857ebe4F679508E7b7863a8A8EeE',
        cvxpool: '0x23F224C37C3A69A058d86a54D3f561295A93d542',
      },
      {
        name: 'steth',
        crvpool: '0xDC24316b9AE028F1497c275EB9192a3Ea0f67022',
        cvxpool: '0x9518c9063eB0262D791f38d8d6Eb0aca33c63ed0',
      },
      {
        name: 'saave',
        crvpool: '0xEB16Ae0052ed37f479f7fe63849198Df1765a733',
        cvxpool: '0x09CCD0892b696AB21436e51588a7a7f8b649733d',
      },
      {
        name: 'aeth',
        crvpool: '0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2',
        cvxpool: '0x7E96955b66c89B931BBDAf187740Cc0fF2602F21',
      },
      {
        name: 'usdp',
        crvpool: '0x42d7025938bEc20B69cBae5A77421082407f053A',
        cvxpool: '0x7a5dC1FA2e1B10194bD2e2e9F1A224971A681444',
      },
      {
        name: 'ib',
        crvpool: '0x2dded6Da1BF5DBdF597C45fcFaa3194e53EcfeAF',
        cvxpool: '0x912EC00eaEbf3820a9B0AC7a5E15F381A1C91f22',
      },
      {
        name: 'tusd',
        crvpool: '0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1',
        cvxpool: '0x0A2eA49EB5F9e23058deffD509D13DDd553c2A19',
      },
      {
        name: 'frax',
        crvpool: '0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B',
        cvxpool: '0xbE0F6478E0E4894CFb14f32855603A083A57c7dA',
      },
      {
        name: 'lusd',
        crvpool: '0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA',
        cvxpool: '0xFB9B2f06FDb404Fd3E2278E9A9edc8f252F273d0',
      },
      {
        name: 'busdv2',
        crvpool: '0x4807862AA8b2bF68830e4C8dc86D0e9A998e085a',
        cvxpool: '0x02D784f98A312aF3e2771297Feff1Da8273e4F29',
      },
      {
        name: 'alusd',
        crvpool: '0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c',
        cvxpool: '0xCA3D9F45FfA69ED454E66539298709cb2dB8cA61',
      },
      {
        name: 'mim',
        crvpool: '0x5a6A4D54456819380173272A5E8E9B9904BdF41B',
        cvxpool: '0xabB54222c2b77158CC975a2b715a3d703c256F05',
      },
      {
        name: 'cvxcrv',
        crvpool: '0x9D0464996170c6B9e75eED71c68B99dDEDf279e8',
        cvxpool: '0x8FDF7cabfEc73d5FfD1447867834b4cf39B745B7',
      },
      {
        name: 'mimust',
        crvpool: '0x55A8a39bc9694714E2874c1ce77aa1E599461E18',
        cvxpool: '0x766A8D4DE01D3eD575CdEf0587Eaf615eCB46726',
      },
      {
        name: 'd3pool',
        crvpool: '0xBaaa1F5DbA42C3389bDbc2c9D2dE134F5cD0Dc89',
        cvxpool: '0x88c82d9767CC8AF564Da81dDD10741fa9D875682',
      },
      {
        name: 'wormhole',
        crvpool: '0xCEAF7747579696A2F0bb206a14210e3c9e6fB269',
        cvxpool: '0x2d2006135e682984a8a2eB74F5C87c2251cC71E9',
      },
      {
        name: 'tricrypto2',
        crvpool: '0xD51a44d3FaE010294C616388b506AcdA1bfAAE46',
        cvxpool: '0x903C9974aAA431A765e60bC07aF45f0A1B3b61fb',
      },
      {
        name: 'crveth',
        crvpool: '0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511',
        cvxpool: '0x0Fb8dcdD95e4C48D3dD0eFA4086512f6F8FD4565',
      },
      {
        name: 'cvxeth',
        crvpool: '0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4',
        cvxpool: '0x0bC857f97c0554d1d0D602b56F2EEcE682016fBA',
      },
      {
        name: 'spell',
        crvpool: '0x98638FAcf9a3865cd033F36548713183f6996122',
        cvxpool: '0xe87f447ef9B76905A25ab8160c7EF66864f4984A',
      },
      {
        name: 'feimetapool',
        crvpool: '0x06cb22615BA53E60D67Bf6C341a0fD5E718E1655',
        cvxpool: '0x6b35abd7612270E09244aFdbE3e5cf67f3B4E09F',
      },
      {
        name: 'badgerwbtc',
        crvpool: '0x50f3752289e1456BfA505afd37B241bca23e685d',
        cvxpool: '0xe7f50e96e0FE8285D3B27B3b9A464a2102C9708c',
      },
      {
        name: 'btflyeth',
        crvpool: '0xF43b15Ab692fDe1F9c24a9FCE700AdCC809D5391',
        cvxpool: '0x6b45b93B4505B5c134262c3985d776D71a20D601',
      },
      // Don't work
      // {
      //   name: 'seth',
      //   crvpool: '0xc5424B857f758E906013F3555Dad202e4bdB4567',
      //   cvxpool: '0xAF1d4C576bF55f6aE493AEebAcC3a227675e5B98',
      // },
    ],
  },
  uniswap: {
    router: '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
    factory: '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f',
    pairs: {
      wethdai: '0xa478c2975ab1ea89e8196811f51a7b7ade33eb11',
      wethusdc: '0xb4e16d0168e52d35cacd2c6185b44281ec28c9dc',
      wethwbtc: '0xbb2b8038a1640196fbe3e38816f3e67cba72d940',
      wethrenBTC: '0x81fbef4704776cc5bba0a5df3a90056d2c6900b3',
      daiusdc: '0xae461ca67b15dc8dc81ce7615e0320da1a9ab8d5',
      daiwbtc: '0x231b7589426ffe1b75405526fc32ac09d44364c4',
    },
    v3: {
      factory: '0x1F98431c8aD98523631AE4a59f267346ea31F984',
    },
  },
  sushiswap: {
    router: '0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F',
    factory: '0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac',
    pairs: {
      wethdai: '0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f',
      wethusdc: '0x397FF1542f962076d0BFE58eA045FfA2d347ACa0',
      wethwbtc: '0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58',
      wethrenBTC: '0x0289B9CD5859476Ce325aCa04309D36adDCEbDAA',
      daiusdc: '0xAaF5110db6e744ff70fB339DE037B990A20bdace',
      ethsushi: '0x795065dCc9f64b5614C407a6EFDC400DA6221FB0',
      // daiwbtc: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599', TODO: Check pair address
    },
  },
  // https://vaults.yearn.finance/ethereum/defi-tokens
  yearn: {
    vaultRegistry: '0xE15461B18EE31b7379019Dc523231C57d1Cbc18c',
    daiVault: '0xdA816459F1AB5631232FE5e97a05BBBb94970c95',
    vaults: [
      {
        vault: '0x7Da96a3891Add058AdA2E826306D812C638D87a7',
        curve: false,
        name: 'USDT vault',
        needs: '0x7Da96a3891Add058AdA2E826306D812C638D87a7',
      },
      // {
      //   vault: '0xa5cA62D95D24A4a350983D5B8ac4EB8638887396',
      //   curve: false,
      //   name: 'sUSD vault',
      //   needs: '0x57ab1ec28d129707052df4df418d58a2d46d5f51',
      // },
      {
        vault: '0xdA816459F1AB5631232FE5e97a05BBBb94970c95',
        curve: false,
        name: 'DAI vault',
        needs: '0x6b175474e89094c44da98b954eedeac495271d0f',
      },
      {
        vault: '0xFD0877d9095789cAF24c98F7CCe092fa8E120775',
        curve: false,
        name: 'TUSD vault',
        needs: '0x0000000000085d4780B73119b644AE5ecd22b376',
      },
      {
        vault: '0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE',
        curve: false,
        name: 'USDC vault',
        needs: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
      },
      {
        vault: '0x378cb52b00F9D0921cb46dFc099CFf73b42419dC',
        curve: false,
        name: 'LUSD vault',
        needs: '0x5f98805A4E8be255a32880FDeC7F6728C6568bA0',
      },
      // { vault: '0xc5bDdf9843308380375a611c18B50Fb9341f502A', curve: true }, // NO veCRV-DAO yVault N/A weird vault. Is the asset of the vault below
      // { vault: '0x9d409a0A012CFbA9B15F6D4B36Ac57A46966Ab9a', curve: true }, // NO yvBOOST
      // {
      //   vault: '0xe11ba472F74869176652C35D30dB89854b5ae84D',
      //   curve: false,
      //   name: 'HEGIC vault',
      //   needs: '0x584bC13c7D411c00c01A62e8019472dE68768430',
      // },
      { vault: '0xB8C3B7A2A618C552C23B1E4701109a9E756Bab67', curve: false, name: '1INCH yVault', skipTest: true }, // twap issue on this block
      {
        vault: '0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E',
        curve: false,
        name: 'WBTC vault',
        needs: '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599',
      },
      {
        vault: '0xFBEB78a723b8087fD2ea7Ef1afEc93d35E8Bed42',
        curve: false,
        name: 'UNI vault',
        needs: '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984',
      },
      {
        vault: '0xF29AE508698bDeF169B89834F76704C3B205aedf',
        curve: false,
        name: 'SNX yVault',
        needs: '0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F',
      },
      {
        vault: '0x671a912C10bba0CFA74Cfc2d6Fba9BA1ed9530B2',
        curve: false,
        name: 'LINK yVault',
        needs: '0x514910771AF9Ca656af840dff83E8264EcF986CA',
      },
      // {
      //   vault: '0x873fB544277FD7b977B196a826459a69E27eA4ea',
      //   curve: false,
      //   name: 'RAI yVault',
      //   needs: '0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919',
      // },
      {
        vault: '0xa258C4606Ca8206D8aA700cE2143D7db854D168c',
        curve: false,
        name: 'WETH yVault',
        needs: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2',
      },
      {
        vault: '0xd9788f3931Ede4D5018184E198699dC6d66C1915',
        curve: false,
        name: 'AAVE yVault',
        needs: '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9',
      },
      {
        vault: '0x4A3FE75762017DB0eD73a71C9A06db7768DB5e66',
        curve: false,
        name: 'COMP yVault',
        needs: '0xc00e94cb662c3520282e6f5717214004a7f26888',
      },
      { vault: '0x6d765CbE5bC922694afE112C140b8878b9FB0390', curve: false, name: 'SUSHI yVault', skipTest: true },
      {
        vault: '0xdb25cA703181E7484a155DD612b06f57E12Be5F0',
        curve: false,
        name: 'YFI yVault',
        needs: '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e',
      },
      // Curve ones
      {
        vault: '0xE537B5cc158EB71037D4125BDD7538421981E6AA',
        curve: true,
        name: 'Curve 3Crypto Pool yVault',
        needs: '0xc4AD29ba4B3c580e6D59105FFf484999997675Ff',
        crvpool: '0xD51a44d3FaE010294C616388b506AcdA1bfAAE46',
      },
      {
        vault: '0x4560b99C904aAD03027B5178CCa81584744AC01f',
        curve: true,
        name: 'Curve cvxCRV Pool yVault',
        needs: '0x9D0464996170c6B9e75eED71c68B99dDEDf279e8',
        crvpool: '0x9D0464996170c6B9e75eED71c68B99dDEDf279e8',
      },
      {
        vault: '0x625b7DF2fa8aBe21B0A976736CDa4775523aeD1E',
        curve: true,
        name: 'Curve HBTC Pool yVault',
        needs: '0xb19059ebb43466C323583928285a49f558E572Fd',
        crvpool: '0x4CA9b3063Ec5866A4B82E437059D2C43d1be596F',
      },
      {
        vault: '0x3D27705c64213A5DcD9D26880c1BcFa72d5b6B0E',
        curve: true,
        name: 'Curve USDK Pool yVault',
        needs: '0x97E2768e8E73511cA874545DC5Ff8067eB19B787',
        crvpool: '0x3E01dD8a5E1fb3481F0F589056b428Fc308AF0Fb',
      },
      {
        vault: '0x80bbeE2fa460dA291e796B9045e93d19eF948C6A',
        curve: true,
        name: 'Curve Pax Pool yVault',
        needs: '0xD905e2eaeBe188fc92179b6350807D8bd91Db0D8',
        crvpool: '0x06364f10B501e868329afBc005b3492902d6C763',
      },
      {
        vault: '0x39CAF13a104FF567f71fd2A4c68C026FDB6E740B',
        curve: true,
        name: 'Curve Aave Pool yVault',
        needs: '0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900',
        crvpool: '0xDeBF20617708857ebe4F679508E7b7863a8A8EeE',
      },
      {
        vault: '0x28a5b95C101df3Ded0C0d9074DB80C438774B6a9',
        curve: true,
        name: 'Curve USDT Pool yVault',
        needs: '0x9fC689CCaDa600B6DF723D9E47D84d76664a1F23',
        crvpool: '0x52EA46506B9CC5Ef470C5bf89f17Dc28bB35D85C',
      },
      {
        vault: '0x8cc94ccd0f3841a468184aCA3Cc478D2148E1757',
        curve: true,
        name: 'Curve mUSD Pool yVault',
        needs: '0x1AEf73d49Dedc4b1778d0706583995958Dc862e6',
        crvpool: '0x8474DdbE98F5aA3179B3B3F5942D724aFcdec9f6',
      },
      {
        vault: '0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417',
        curve: true,
        name: 'Curve USDP Pool yVault',
        needs: '0x7Eb40E450b9655f4B3cC4259BCC731c63ff55ae6',
        crvpool: '0x42d7025938bEc20B69cBae5A77421082407f053A',
      },
      {
        vault: '0x2DfB14E32e2F8156ec15a2c21c3A6c053af52Be8',
        curve: true,
        name: 'Curve MIM Pool yVault',
        needs: '0x5a6A4D54456819380173272A5E8E9B9904BdF41B',
        crvpool: '0x5a6A4D54456819380173272A5E8E9B9904BdF41B',
      },
      {
        vault: '0xC116dF49c02c5fD147DE25Baa105322ebF26Bd97',
        curve: true,
        name: 'Curve RSV Pool yVault',
        needs: '0xC2Ee6b0334C261ED60C72f6054450b61B8f18E35',
        crvpool: '0xC18cC39da8b11dA8c3541C598eE022258F9744da',
      },
      {
        vault: '0x84E13785B5a27879921D6F685f041421C7F482dA',
        curve: true,
        name: 'Curve 3pool yVault',
        needs: '0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490',
        crvpool: '0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7',
      },
      {
        vault: '0x27b7b1ad7288079A66d12350c828D3C00A6F07d7',
        curve: true,
        name: 'Curve Iron Bank Pool yVault',
        needs: '0x5282a4eF67D9C33135340fB3289cc1711c13638C',
        crvpool: '0x2dded6Da1BF5DBdF597C45fcFaa3194e53EcfeAF',
      },
      {
        vault: '0x2a38B9B0201Ca39B17B460eD2f11e4929559071E',
        curve: true,
        name: 'Curve GUSD Pool yVault',
        needs: '0xD2967f45c4f384DEEa880F807Be904762a3DeA07',
        crvpool: '0x4f062658EaAF2C1ccf8C8e36D6824CDf41167956',
      },
      {
        vault: '0xdCD90C7f6324cfa40d7169ef80b12031770B4325',
        curve: true,
        name: 'Curve stETH Pool yVault',
        needs: '0x06325440D014e39736583c165C2963BA99fAf14E',
        crvpool: '0xDC24316b9AE028F1497c275EB9192a3Ea0f67022',
      },
      {
        vault: '0x4B5BfD52124784745c1071dcB244C6688d2533d3',
        curve: true,
        name: 'Curve Y Pool yVault',
        needs: '0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8',
        crvpool: '0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51',
      },
      {
        vault: '0x7047F90229a057C13BF847C0744D646CFb6c9E1A',
        curve: true,
        name: 'Curve renBTC Pool yVault',
        needs: '0x49849C98ae39Fff122806C06791Fa73784FB3675',
        crvpool: '0x93054188d876f558f4a66B2EF1d97d16eDf0895B',
      },
      {
        vault: '0x5fA5B62c8AF877CB37031e0a3B2f34A78e3C56A6',
        curve: true,
        name: 'Curve LUSD Pool yVault',
        needs: '0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA',
        crvpool: '0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA',
      },
      // {
      //   vault: '0x986b4AFF588a109c09B50A03f42E4110E29D353F',
      //   curve: true,
      //   name: 'Curve sETH Pool yVault',
      //   needs: '0xA3D87FffcE63B53E0d54fAa1cc983B7eB0b74A9c',
      //   crvpool: '0xc5424B857f758E906013F3555Dad202e4bdB4567',
      // },
      // {
      //   vault: '0x054AF22E1519b020516D72D749221c24756385C9',
      //   curve: true,
      //   name: 'Curve HUSD Pool yVault',
      //   needs: '0x5B5CFE992AdAC0C9D48E05854B2d91C73a003858',
      //   crvpool: '0x3eF6A01A0f81D6046290f3e2A8c5b843e738E604',
      // },
      {
        vault: '0xA74d4B67b3368E83797a35382AFB776bAAE4F5C8',
        curve: true,
        name: 'Curve alUSD Pool yVault',
        needs: '0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c',
        crvpool: '0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c',
      },
      {
        vault: '0xb4D1Be44BfF40ad6e506edf43156577a3f8672eC',
        curve: true,
        name: 'Curve SAAVE Pool yVault',
        needs: '0x02d341CcB60fAaf662bC0554d13778015d1b285C',
        crvpool: '0xEB16Ae0052ed37f479f7fe63849198Df1765a733',
      },
      {
        vault: '0x3B96d491f067912D18563d56858Ba7d6EC67a6fa',
        curve: true,
        name: 'Curve USDN Pool yVault',
        needs: '0x4f3E8F405CF5aFC05D68142F3783bDfE13811522',
        crvpool: '0x0f9cb53Ebe405d49A0bbdBD291A65Ff571bC83e1',
      },
      {
        vault: '0xB4AdA607B9d6b2c9Ee07A275e9616B84AC560139',
        curve: true,
        name: 'Curve FRAX Pool yVault',
        needs: '0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B',
        crvpool: '0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B',
      },
      {
        vault: '0xf8768814b88281DE4F532a3beEfA5b85B69b9324',
        curve: true,
        name: 'Curve TUSD Pool yVault',
        needs: '0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1',
        crvpool: '0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1',
      },
      {
        vault: '0xD6Ea40597Be05c201845c0bFd2e96A60bACde267',
        curve: true,
        name: 'Curve Compound Pool yVault',
        needs: '0x845838DF265Dcd2c412A1Dc9e959c7d08537f8a2',
        crvpool: '0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56',
      },
      {
        vault: '0x30FCf7c6cDfC46eC237783D94Fc78553E79d4E9C',
        curve: true,
        name: 'Curve DUSD Pool yVault',
        needs: '0x3a664Ab939FD8482048609f652f9a0B0677337B9',
        crvpool: '0x8038C01A0390a8c547446a0b2c18fc9aEFEcc10c',
      },
      {
        vault: '0x6Ede7F19df5df6EF23bD5B9CeDb651580Bdf56Ca',
        curve: true,
        name: 'Curve BUSD Pool yVault',
        needs: '0x4807862AA8b2bF68830e4C8dc86D0e9A998e085a',
        crvpool: '0x4807862AA8b2bF68830e4C8dc86D0e9A998e085a',
      },
      // {
      //   vault: '0x1C6a9783F812b3Af3aBbf7de64c3cD7CC7D1af44',
      //   curve: true,
      //   name: 'Curve UST Pool yVault',
      //   needs: '0x94e131324b6054c0D789b190b2dAC504e4361b53',
      //   crvpool: '0x890f4e345B1dAED0367A877a1612f86A1f86985f',
      // },
      // {
      //   vault: '0x718AbE90777F5B778B52D553a5aBaa148DD0dc5D',
      //   curve: true,
      //   name: 'Curve alETH Pool yVault',
      //   needs: '0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e',
      //   crvpool: '0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e',
      // },
      {
        vault: '0xd8C620991b8E626C099eAaB29B1E3eEa279763bb',
        curve: true,
        name: 'Curve MIM-UST',
        needs: '0x55A8a39bc9694714E2874c1ce77aa1E599461E18',
        crvpool: '0x55A8a39bc9694714E2874c1ce77aa1E599461E18',
      },
      {
        vault: '0xF59D66c1d593Fb10e2f8c2a6fD2C958792434B9c',
        curve: true,
        name: 'Curve oUSD yvVault',
        needs: '0x87650D7bbfC3A9F10587d7778206671719d9910D',
        crvpool: '0x87650D7bbfC3A9F10587d7778206671719d9910D',
      },
      {
        vault: '0x5e69e8b51B71C8596817fD442849BD44219bb095',
        curve: true,
        name: 'Curve ibBTC yvVault',
        needs: '0xFbdCA68601f835b27790D98bbb8eC7f05FDEaA9B',
        crvpool: '0xFbdCA68601f835b27790D98bbb8eC7f05FDEaA9B',
      },
      // Look into why
      // {
      //   vault: '0x6FAfCA7f49B4Fd9dC38117469cd31A1E5aec91F5',
      //   curve: true,
      //   name: 'Curve USDM yvVault',
      //   needs: '0x5B3b5DF2BF2B6543f78e053bD91C4Bdd820929f1',
      //   crvpool: '0x5B3b5DF2BF2B6543f78e053bD91C4Bdd820929f1',
      // },
      {
        vault: '0x790a60024bC3aea28385b60480f15a0771f26D09',
        curve: true,
        name: 'Curve YFI/ETH yvVault',
        needs: '0xC26b89A667578ec7b3f11b2F98d6Fd15C07C54ba',
        crvpool: '0xC26b89A667578ec7b3f11b2F98d6Fd15C07C54ba',
      },
      // {
      //   vault: '0x2994529C0652D127b7842094103715ec5299bBed',
      //   curve: true,
      //   name: 'yearn Curve.fi yDAI/yUSDC/yUSDT/yBUSD',
      //   needs: '0x3B3Ac5386837Dc563660FB6a0937DFAa5924333B',
      //   crvpool: '0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27',
      // },
      {
        vault: '0x132d8D2C76Db3812403431fAcB00F3453Fc42125',
        curve: true,
        skipTest: true,
        name: 'Curve ankrETH Pool yVault',
        needs: '0xaA17A236F2bAdc98DDc0Cf999AbB47D47Fc0A6Cf',
        crvpool: '0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2',
      },
      {
        vault: '0x23D3D0f1c697247d5e0a9efB37d8b0ED0C464f7f',
        curve: true,
        name: 'Curve tBTC Pool yVault',
        needs: '0x64eda51d3Ad40D56b9dFc5554E06F94e1Dd786Fd',
        crvpool: '0xC25099792E9349C7DD09759744ea681C7de2cb66',
      },
      {
        vault: '0x8fA3A9ecd9EFb07A8CE90A6eb014CF3c0E3B32Ef',
        curve: true,
        skipTest: true,
        name: 'Curve BBTC Pool yVault',
        needs: '0x410e3E86ef427e30B9235497143881f717d93c2A',
        crvpool: '0x071c661B4DeefB59E2a3DdB20Db036821eeE8F4b',
      },
      {
        vault: '0xe9Dc63083c464d6EDcCFf23444fF3CFc6886f6FB',
        curve: true,
        name: 'Curve oBTC Pool yVault',
        needs: '0x2fE94ea3d5d4a175184081439753DE15AeF9d614',
        crvpool: '0xd81dA8D904b52208541Bade1bD6595D8a251F8dd',
      },
      {
        vault: '0x3c5DF3077BcF800640B5DAE8c91106575a4826E6',
        curve: true,
        name: 'Curve pBTC Pool yVault',
        needs: '0xDE5331AC4B3630f94853Ff322B66407e0D6331E8',
        crvpool: '0x7F55DDe206dbAD629C080068923b36fe9D6bDBeF',
      },
      {
        vault: '0x6A5468752f8DB94134B6508dAbAC54D3b45efCE6',
        curve: true,
        name: 'Curve crvETH Pool yVault',
        needs: '0xed4064f376cb8d68f770fb1ff088a3d0f3ff5c4d',
        crvpool: '0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511',
      },
      {
        vault: '0x1635b506a88fBF428465Ad65d00e8d6B6E5846C3',
        curve: true,
        name: 'Curve cvxETH Pool yVault',
        needs: '0x3a283d9c08e8b55966afb64c515f5143cf907611',
        crvpool: '0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4',
      },
      // {
      //   vault: '0x8414Db07a7F743dEbaFb402070AB01a4E0d2E45e',
      //   curve: true,
      //   name: 'Curve sBTC Pool yVault',
      //   needs: '0x075b1bb99792c9E1041bA13afEf80C91a1e70fB3',
      //   crvpool: '0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714',
      // },
      {
        vault: '0x5a770DbD3Ee6bAF2802D29a901Ef11501C44797A',
        curve: true,
        name: 'Curve sUSD Pool yVault',
        needs: '0xC25a3A3b969415c80451098fa907EC722572917F',
        crvpool: '0xA5407eAE9Ba41422680e2e00537571bcC53efBfD',
      },
      // {
      //   vault: '0xBfedbcbe27171C418CDabC2477042554b1904857',
      //   curve: true,
      //   name: 'Curve rETH Pool yVault',
      //   needs: '0x53a901d48795C58f485cBB38df08FA96a24669D5',
      //   crvpool: '0xF9440930043eb3997fc70e1339dBb11F341de7A8',
      // },
      // {
      //   vault: '0xf2db9a7c0ACd427A680D640F02d90f6186E71725',
      //   curve: true,
      //   name: 'Curve LINK Pool yVault',
      //   needs: '0xcee60cFa923170e4f8204AE08B4fA6A3F5656F3a',
      //   crvpool: '0xF178C0b5Bb7e7aBF4e12A4838C7b7c5bA2C623c0',
      // },
      // {
      //   vault: '0x25212Df29073FfFA7A67399AcEfC2dd75a831A1A',
      //   curve: true,
      //   name: 'Curve EURS Pool yVault',
      //   needs: '0x194eBd173F6cDacE046C53eACcE9B953F28411d1',
      //   crvpool: '0x0Ce6a5fF5217e38315f87032CF90686C96627CAA',
      // },
      // {
      //   vault: '0x0d4EA8536F9A13e4FBa16042a46c30f092b06aA5',
      //   curve: true,
      //   name: 'Curve EURT Pool yVault',
      //   needs: '0xFD5dB7463a3aB53fD211b4af195c5BCCC1A03890',
      //   crvpool: '0xFD5dB7463a3aB53fD211b4af195c5BCCC1A03890',
      // },
      // {
      //   vault: '0x3D980E50508CFd41a13837A60149927a11c03731',
      //   curve: true,
      //   name: 'Curve triCrypto Pool yVault',
      //   needs: '0xcA3d75aC011BF5aD07a98d02f18225F9bD9A6BDF',
      //   crvpool: '0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5',
      // },
      // { vault: "0x8b9C0c24307344B6D7941ab654b2Aeee25347473", curve: true, name: "Curve EURN Pool yVault", needs: "0x3Fb78e61784C9c637D560eDE23Ad57CA1294c14a", crvpool: "0x0000000000000000000000000000000000000000"},
      // { vault: "0x528D50dC9a333f01544177a924893FA1F5b9F748", curve: true, name: "Curve ibKRW Pool yVault", needs: "0x8461A004b50d321CB22B7d034969cE6803911899", crvpool: "0x0000000000000000000000000000000000000000"},
      // { vault: "0x1b905331F7dE2748F4D6a0678e1521E20347643F", curve: true, name: "Curve ibAUD Pool yVault", needs: "0x3F1B0278A9ee595635B61817630cC19DE792f506", crvpool: "0x0000000000000000000000000000000000000000"},
      // { vault: "0x490bD0886F221A5F79713D3E84404355A9293C50", curve: true, name: "Curve ibCHF Pool yVault", needs: "0x9c2C8910F113181783c249d8F6Aa41b51Cde0f0c", crvpool: "0x0000000000000000000000000000000000000000"},
      // { vault: "0x595a68a8c9D5C230001848B69b1947ee2A607164", curve: true, name: "Curve ibGBP Pool yVault", needs: "0xD6Ac1CB9019137a896343Da59dDE6d097F710538", crvpool: "0x0000000000000000000000000000000000000000"},
      // { vault: "0x67e019bfbd5a67207755D04467D6A70c0B75bF60", curve: true, name: "Curve ibEUR Pool yVault", needs: "0x19b080FE1ffA0553469D20Ca36219F17Fcf03859", crvpool: "0x0000000000000000000000000000000000000000"},
      // { vault: "0x59518884EeBFb03e90a18ADBAAAB770d4666471e", curve: true, name: "Curve ibJPY Pool yVault", needs: "0x8818a9bb44Fbf33502bE7c15c500d0C783B73067", crvpool: "0x0000000000000000000000000000000000000000"},
    ],
  },
  harvest: {
    vaults: {
      fWETH: '0xFE09e53A81Fe2808bc493ea64319109B5bAa573e',
      fUSDC: '0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE',
      fDAI: '0xab7FA2B2985BCcfC13c6D86b1D5A17486ab1e04C',
      fWBTC: '0x5d9d25c7C457dD82fc8668FFC6B9746b674d4EcB',
      fETHSUSHI: '0x5aDe382F38A09A1F8759D06fFE2067992ab5c78e',
    },
    v3vaults: {
      fBablWeth: '0xadb16df01b9474347e8fffd6032360d3b54627fb',
      // fWethUsdt: '0xc53DaB6fDD18AF6CD5cF37fDE7C941d368f8664f',
      // fWethUsdt2: '0xEA46CfcB43D5274991344cF6F56765e39A7Eae1a',
      // fDaiWeth: '0x503Ea79B73995Cf0C8d323C17782047ED5cC72B2',
      // fDaiWeth2: '0x8137ac6dF358fe2D0DFbB1b5aA87C110950A16Cd',
      // fUsdcWeth: '0x3b2ED6013f961404AbA5a030e20A2AceB486832d',
      // fUsdcWeth2: '0xC74075F5c9aD58C655a6160bA955B4aCD5dE8d0B',
      // fWethSeth: '0x65383Abd40f9f831018dF243287F7AE3612c62AC', Seth disappeared
      // fCNGWeth: '0xc3426599Ec933FbF657ee44b53e7f01d83Be1f63', No liquidity
      // fUstUsdt: '0x1851A8fA2ca4d8Fb8B5c56EAC1813Fd890998EFc', No liquidity
      // fDonWeth: '0x25642078C595A7078f150e5E0486364077aE9eBB', DON doesn't have liquidity
      // fWbtcWeth: '0x2357685B07469eE80A389819C7A41edCD70cd88C', Weird Pool. Doesn't work
    },
    v3ToRewardPool: {
      '0xadb16df01b9474347e8fffd6032360d3b54627fb': '0x3e6397E309f68805FA8Ef66A6216bD2010DdAF19', // fBablWeth
      '0x65383Abd40f9f831018dF243287F7AE3612c62AC': '0x11301B7C82Cd953734440aaF0D5Dd0B36E2aB1d8', // fWethSeth
      '0xc53DaB6fDD18AF6CD5cF37fDE7C941d368f8664f': '0x6055d7f2E84e334176889f6d8c3F84580cA4F507', // fWethUsdt 3-4.5k
      '0xEA46CfcB43D5274991344cF6F56765e39A7Eae1a': '0xFd1121b2292eBD475791Ee2d646ccC8451c9F7Ae', // fWethUsdt 4.2-5.5k
      '0x503Ea79B73995Cf0C8d323C17782047ED5cC72B2': '0xEFb78d1E3BA4272E7D806b9dC88e239e08e4082D', // fDaiWeth 3-4.5k
      '0x8137ac6dF358fe2D0DFbB1b5aA87C110950A16Cd': '0x35De0D0F9448B35a09e1E884C7d23A00027fbD8f', // fDaiWeth 4.2-5.5k
      '0x3b2ED6013f961404AbA5a030e20A2AceB486832d': '0x7931D6263798f99A082Caf1416b2457605628e2D', // fUsdcWeth 3-4.5k
      '0xC74075F5c9aD58C655a6160bA955B4aCD5dE8d0B': '0xe9D5571a741AF8201e6ca11241aF4d2D635D6c85', // fUsdcWeth 4.2-5.5k;
    },
  },
  tokens: {
    DAI: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    FRAX: '0x853d955aCEf822Db058eb8505911ED77F175b99e',
    FEI: '0x956F47F50A910163D8BF957Cf5846D573E7f87CA',
    DPI: '0x1494ca1f11d487c2bbe4543e90080aeba4ba3c2b',
    AAVE: '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9',
    CDAI: '0x5d3a536e4d6dbd6114cc1ead35777bab948e3643',
    TUSD: '0x0000000000085d4780B73119b644AE5ecd22b376',
    bUSD: '0x4fabb145d64652a948d72533023f6e7a623c7c53',
    ETH1: '0x0000000000000000000000000000000000000000',
    ETH2: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
    hBTC: '0x0316EB71485b0Ab14103307bf65a021042c6d380',
    renBTC: '0xeb4c2781e4eba804ce9a9803c67d0893436bb27d',
    sBTC: '0xfe18be6b3bd88a2d2a7f928d00292e7a9963cfc6',
    aETHC: '0xE95A203B1a91a908F9B9CE46459d101078c2c3cb',
    rETH: '0x9559aaa82d9649c7a7b220e7c461d2e74c9a3593',
    sETH: '0x5e74c9036fb86bd7ecdcb084a0673efc32ea31cb',
    stETH: '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84',
    wstETH: '0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0',
    WETH: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
    CETH: '0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5',
    USDC: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    CUSDC: '0x39aa39c021dfbae8fac545936693ac917d5e7563',
    USDT: '0xdac17f958d2ee523a2206206994597c13d831ec7',
    CUSDT: '0xf650c3d88d12db855b8bf7d11be6c55a4e07dcc9',
    WBTC: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
    CWBTC: '0xc11b1268c1a384e55c48c2391d8d480264a3a7f4',
    COMP: '0xc00e94cb662c3520282e6f5717214004a7f26888',
    CCOMP: '0x70e36f6bf80a52b3b46b3af8e106cc0ed743e8e4',
    YFI: '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e',
    SNX: '0xc011a73ee8576fb46f5e1c5751ca3b9fe0af2a6f',
    sUSD: '0x57Ab1ec28D129707052df4dF418D58a2D46d5f51',
    sAAVE: '0xd2dF355C19471c8bd7D8A3aa27Ff4e26A21b4076',
    BABL: '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74',
    hBABL: '0xaA2D49A1d66A58B8DD0687E730FefC2823649791',
    CRV: '0xD533a949740bb3306d119CC777fa900bA034cd52',
    CVX: '0x4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b',
  },
  holders: {
    DAI: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    sUSD: '0x49BE88F0fcC3A8393a59d3688480d7D253C37D2A',
    WETH: '0x2f0b23f53734252bda2277357e97e1517d6b042a',
    USDC: '0xD1669Ac6044269b59Fa12c5822439F609Ca54F41',
    BABL: '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74',
    ETH: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
  },
};
