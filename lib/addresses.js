module.exports = {
  zero: '0x0000000000000000000000000000000000000000',
  users: {
    hardhat1: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
    hardhat2: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
    hardhat3: '0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc',
  },
  aave: {
    lendingPool: '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9',
    dataProvider: '0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d',
  },
  compound: {
    Comptroller: '0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b',
    Governance: '0xc0da01a04c3f3e0be433606045bb7017a7323e38',
    Timelock: '0x6d903f6003cca6255d85cca4d3b5e5146dc33925',
    OpenOracle: '0x922018674c12a7f0d394ebeef9b58f186cde13c1',
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
    pools: {
      v3: {
        tricrypto: '0x331aF2E331bd619DefAa5DAc6c038f53FCF9F785',
        // tripool: '0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7',
        // aave: '0xDeBF20617708857ebe4F679508E7b7863a8A8EeE',
        // ankrETH: '0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2', Not supported
        // busd: '0xb6c057591E073249F2D9D88Ba59a46CFC9B59EdB',
        // compound: '0xeB21209ae4C2c9FF2a86ACA31E123764A3B6Bc06', Works but missing ctokens exchange
        // eurs: '0x0Ce6a5fF5217e38315f87032CF90686C96627CAA', Not supported. No liquidity
        // hbtc: '0x4CA9b3063Ec5866A4B82E437059D2C43d1be596F', Not supported. No liquidity
        // ironbank: '0x2dded6Da1BF5DBdF597C45fcFaa3194e53EcfeAF', Works but missing cream price
        // link: '0xf178c0b5bb7e7abf4e12a4838c7b7c5ba2c623c0', Missing synthetix link
        // pax: '0xA50cCc70b6a011CffDdf45057E39679379187287', works but need to wait for blocks
        // renbtc: '0x93054188d876f558f4a66B2EF1d97d16eDf0895B', works but not liquidity on eth with renbtc
        // reth: '0xF9440930043eb3997fc70e1339dBb11F341de7A8',
        // saave: '0xEB16Ae0052ed37f479f7fe63849198Df1765a733', Not supported
        // sbtc: '0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714', Missing synthetix synth btc
        // seth: '0xc5424B857f758E906013F3555Dad202e4bdB4567', Missing synth seth
        // steth: '0xDC24316b9AE028F1497c275EB9192a3Ea0f67022', ** This should be doable, the EEE thing
        // susd: '0xFCBa3E75865d2d561BE8D220616520c171F12851',
        // usdt: '0xac795D2c97e60DF6a99ff1c814727302fD747a80',
        // y: '0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3',
        // yv2: '0x8925D9d9B4569D737a48499DeF3f67BaA5a144b9',
      },
      metapools: {
        bbtc: '0xC45b2EEe6e09cA176Ca3bB5f7eEe7C47bF93c756',
        dusd: '0x61E10659fe3aa93d036d099405224E4Ac24996d0',
        gusd: '0x64448B78561690B70E17CBE8029a3e5c1bB7136e',
        husd: '0x09672362833d8f703D5395ef3252D4Bfa51c15ca',
        linkusd: '0x1de7f0866e2c4adAC7b457c58Cc25c8688CDa1f2',
        musd: '0x803A2B40c5a9BB2B86DD630B274Fa2A9202874C2',
        obtc: '0xd5BCf53e2C81e1991570f33Fa881c49EEa570C8D',
        pbtc: '0x11F419AdAbbFF8d595E7d5b223eee3863Bb3902C',
        rsv: '0xBE175115BF33E12348ff77CcfEE4726866A0Fbd5',
        tbtc: '0xaa82ca713D94bBA7A89CEAB55314F9EfFEdDc78c',
        usdk: '0xF1f85a74AD6c64315F85af52d3d46bF715236ADc',
        usdn: '0x094d12e5b541784701FD8d65F11fc0598FBC6332',
        usdp: '0x3c8cAee4E09296800f8D29A68Fa3837e2dae4940',
        ust: '0xB0a0716841F2Fc03fbA72A891B8Bb13584F52F2d',
      },
    },
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
      //daiwbtc: '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599', TODO: Check pair address
    },
  },
  yearn: {
    vaultRegistry: '0xE15461B18EE31b7379019Dc523231C57d1Cbc18c',
    vaults: {
      ydai: '0x19D3364A399d251E894aC732651be8B0E4e85001',
    },
  },
  harvest: {
    vaults: {
      fWETH: '0xFE09e53A81Fe2808bc493ea64319109B5bAa573e',
      fUSDC: '0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE',
      fDAI: '0xab7FA2B2985BCcfC13c6D86b1D5A17486ab1e04C',
      fWBTC: '0x5d9d25c7C457dD82fc8668FFC6B9746b674d4EcB',
    },
  },
  tokens: {
    DAI: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    CDAI: '0x5d3a536e4d6dbd6114cc1ead35777bab948e3643',
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
  },
  holders: {
    DAI: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    sUSD: '0x49BE88F0fcC3A8393a59d3688480d7D253C37D2A',
    WETH: '0x2f0b23f53734252bda2277357e97e1517d6b042a',
    USDC: '0xD1669Ac6044269b59Fa12c5822439F609Ca54F41',
    ETH: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
  },
  api: {
    oneinch: 'https://api.1inch.exchange/v2.0/',
  },
};
