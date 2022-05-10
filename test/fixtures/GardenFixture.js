const { deployments } = require('hardhat');
const { GARDEN_PARAMS, BABL_GARDEN_PARAMS } = require('lib/constants.js');
const addresses = require('lib/addresses');
const { impersonateAddress } = require('lib/rpc');
const { fund } = require('lib/whale');
const { createStrategy } = require('./StrategyHelper.js');
const { getERC20, getContract, eth } = require('utils/test-helpers');

async function setUpFixture(
  { upgradesDeployer, deployments, getNamedAccounts, ethers },
  options,
  { gardenParams = GARDEN_PARAMS },
) {
  const [deployer, keeper, , signer1, signer2, signer3, signer4] = await ethers.getSigners();

  await deployments.fixture();

  const babController = await getContract('BabController', 'BabControllerProxy');
  const heart = await getContract('Heart', 'HeartProxy');
  const bablToken = await getContract('BABLToken');
  const timeLockRegistry = await getContract('TimeLockRegistry');
  const ishtarGate = await getContract('IshtarGate');
  const mardukGate = await getContract('MardukGate');
  const priceOracle = await getContract('PriceOracle');
  const curveMetaRegistry = await getContract('CurveMetaRegistry');
  const convexRegistry = await getContract('ConvexRegistry');
  const yearnVaultRegistry = await getContract('YearnVaultRegistry');
  const tokenIdentifier = await getContract('TokenIdentifier');
  const treasury = await getContract('Treasury');
  const gardenValuer = await getContract('GardenValuer');
  const gardenNFT = await getContract('GardenNFT');
  const strategyNFT = await getContract('StrategyNFT');
  const rewardsDistributor = await getContract('RewardsDistributor', 'RewardsDistributorProxy');
  const viewer = await getContract('IViewer', 'Viewer');
  const timelockController = await getContract('TimelockController');
  const babGovernor = await getContract('BabylonGovernor');

  const uniswapV3TradeIntegration = await getContract('UniswapV3TradeIntegration');
  const balancerIntegration = await getContract('BalancerIntegration');
  const pickleJarIntegration = await getContract('PickleJarIntegration');
  const pickleFarmIntegration = await getContract('PickleFarmIntegration');
  const gammaIntegration = await getContract('GammaIntegration');
  const uniswapPoolIntegration = await getContract('UniswapPoolIntegration');
  const yearnVaultIntegration = await getContract('YearnVaultIntegration');
  const harvestVaultIntegration = await getContract('HarvestVaultIntegration');
  const harvestV3VaultIntegration = await getContract('HarvestPoolV3Integration');
  const harvestV3StakeIntegration = await getContract('HarvestV3StakeIntegration');
  const sushiswapPoolIntegration = await getContract('SushiswapPoolIntegration');
  const curvePoolIntegration = await getContract('CurvePoolIntegration');
  const convexStakeIntegration = await getContract('ConvexStakeIntegration');
  const curveGaugeIntegration = await getContract('CurveGaugeIntegration');
  const stakewiseIntegration = await getContract('StakewiseIntegration');
  const oneInchPoolIntegration = await getContract('OneInchPoolIntegration');
  const compoundLendIntegration = await getContract('CompoundLendIntegration');
  const fuseLendIntegration = await getContract('FuseLendIntegration');
  const aaveLendIntegration = await getContract('AaveLendIntegration');
  const aaveBorrowIntegration = await getContract('AaveBorrowIntegration');
  const compoundBorrowIntegration = await getContract('CompoundBorrowIntegration');
  const fuseBorrowIntegration = await getContract('FuseBorrowIntegration');
  const lidoIntegration = await getContract('LidoStakeIntegration');
  const curveTradeIntegration = await getContract('CurveTradeIntegration');
  const synthetixTradeIntegration = await getContract('SynthetixTradeIntegration');
  const univ2TradeIntegration = await getContract('UniswapV2TradeIntegration');
  const heartTradeIntegration = await getContract('HeartTradeIntegration');
  const paladinTradeIntegration = await getContract('PaladinTradeIntegration');
  const masterSwapper = await getContract('MasterSwapper');

  const buyOperation = await getContract('BuyOperation');
  const addLiquidityOperation = await getContract('AddLiquidityOperation');
  const depositVaultOperation = await getContract('DepositVaultOperation');
  const lendOperation = await getContract('LendOperation');
  const borrowOperation = await getContract('BorrowOperation');
  const customOperation = await getContract('CustomOperation');

  const dai = await getERC20(addresses.tokens.DAI);
  const usdc = await getERC20(addresses.tokens.USDC);
  const weth = await getERC20(addresses.tokens.WETH);
  const wbtc = await getERC20(addresses.tokens.WBTC);
  const babl = await getERC20(addresses.tokens.BABL);
  const aave = await getERC20(addresses.tokens.AAVE);

  const owner = await impersonateAddress(timelockController.address);
  await signer4.sendTransaction({ to: owner.address, value: ethers.utils.parseEther('5') });

  console.log('before funds');
  await fund([owner.address, signer1.address, signer2.address, signer3.address], {
    tokens: [
      addresses.tokens.USDC,
      addresses.tokens.DAI,
      addresses.tokens.WETH,
      addresses.tokens.BABL,
      addresses.tokens.WBTC,
      addresses.tokens.FEI,
      addresses.tokens.FRAX,
      addresses.tokens.AAVE,
    ],
  });

  // fund with local hardhat BABL Token created to create a Test Heart Garden of local BABL reserveAsset
  const treasurySigner = await impersonateAddress(treasury.address);
  await bablToken.connect(owner).enableTokensTransfers();
  const amount = eth('1000');
  await bablToken.connect(treasurySigner).transfer(signer1.address, amount, { gasPrice: 0 });
  await bablToken.connect(signer1).approve(babController.address, amount, { gasPrice: 0 });

  const TOKEN_MAP = {
    [addresses.tokens.WETH]: weth,
    [addresses.tokens.DAI]: dai,
    [addresses.tokens.USDC]: usdc,
    [addresses.tokens.WBTC]: wbtc,
    [addresses.tokens.BABL]: babl,
    [addresses.tokens.AAVE]: aave,
  };

  console.log('creating gardens');
  [dai, weth, wbtc, babl, usdc, aave].forEach(async (erc20) => {
    await erc20.connect(signer1).approve(babController.address, eth('20'), {
      gasPrice: 0,
    });
  });

  // Gives signer1 creator permissions
  await ishtarGate.connect(owner).setCreatorPermissions(signer1.address, true, { gasPrice: 0 });
  await mardukGate.connect(owner).setCreatorPermissions(owner.address, true, { gasPrice: 0 });
  await mardukGate.connect(owner).setCreatorPermissions(signer1.address, true, { gasPrice: 0 });
  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'Absolute ETH Return [beta]',
      'EYFA',
      'http...',
      0,
      gardenParams,
      eth('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: eth('1'),
      },
    );
  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'ETH Yield Farm [a]',
      'EYFB',
      'http...',
      1,
      gardenParams,
      eth('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: eth('1'),
      },
    );

  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'ETH Yield Farm [b]',
      'EYFG',
      'http...',
      2,
      gardenParams,
      eth('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: eth('1'),
      },
    );

  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'ETH Yield Farm [d]',
      'EYFG',
      'http...',
      3,
      gardenParams,
      eth('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: eth('1'),
      },
    );

  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.BABL,
      'The Heart of Babylon',
      'hBABL',
      'http...',
      5,
      BABL_GARDEN_PARAMS,
      eth('20'),
      [false, false, false],
      [0, 0, 0],
      {},
    );

  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.AAVE,
      'AAVE Paladin Garden',
      'PALA',
      'http...',
      5,
      BABL_GARDEN_PARAMS,
      eth('20'),
      [false, false, false],
      [0, 0, 0],
      {},
    );

  await babController
    .connect(signer1)
    .createGarden(
      bablToken.address,
      'The Test Heart of Babylon',
      'hBABL',
      'http...',
      5,
      BABL_GARDEN_PARAMS,
      eth('200'),
      [true, false, false],
      [0, 0, 0],
      {},
    );

  const gardens = await babController.getGardens();

  const garden1 = await ethers.getContractAt('IGarden', gardens[0]);

  const garden2 = await ethers.getContractAt('IGarden', gardens[1]);

  const garden3 = await ethers.getContractAt('IGarden', gardens[2]);

  const garden4 = await ethers.getContractAt('IGarden', gardens[3]);

  const heartGarden = await ethers.getContractAt('IGarden', gardens[4]);

  const aaveGarden = await ethers.getContractAt('IGarden', gardens[5]);

  const heartTestGarden = await ethers.getContractAt('IGarden', gardens[6]);

  console.log('heart garden', heartGarden.address);

  // Set the heart garden
  await heart.connect(owner).setHeartGardenAddress(heartGarden.address, { gasPrice: 0 });

  // Grants community access
  for (let i = 0; i < gardens.length; i += 1) {
    await ishtarGate
      .connect(signer1)
      .grantGardenAccessBatch(gardens[i], [signer1.address, signer2.address, signer3.address], [3, 3, 3], {
        gasPrice: 0,
      });
  }
  const strategy10 = (
    await createStrategy('buy', 'dataset', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden1)
  ).address;
  // Create strategies
  const strategy11 = (
    await createStrategy('buy', 'dataset', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden1)
  ).address;

  const strategy21 = (
    await createStrategy('buy', 'deposit', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden2)
  ).address;

  await createStrategy('buy', 'deposit', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden3);
  await createStrategy('buy', 'dataset', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden3);

  console.log('Created and started garden', garden1.address);
  console.log('Created manual testing garden', garden3.address);

  const daiWhaleSigner = await impersonateAddress('0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7');
  const wethWhaleSigner = await impersonateAddress('0xC8dDA504356195ba5344E5a9826Ce07DfEaA97b6');
  const nft = await impersonateAddress('0x26231A65EF80706307BbE71F032dc1e5Bf28ce43');
  console.log('end garden fixture');

  return {
    babController,
    bablToken,
    timeLockRegistry,
    treasury,
    heart,
    rewardsDistributor,
    pickleJarIntegration,
    gammaIntegration,
    uniswapV3TradeIntegration,
    curveTradeIntegration,
    balancerIntegration,
    uniswapPoolIntegration,
    harvestVaultIntegration,
    pickleFarmIntegration,
    yearnVaultIntegration,
    sushiswapPoolIntegration,
    curvePoolIntegration,
    curveGaugeIntegration,
    convexStakeIntegration,
    oneInchPoolIntegration,
    compoundLendIntegration,
    compoundBorrowIntegration,
    curveMetaRegistry,
    synthetixTradeIntegration,
    univ2TradeIntegration,
    aaveLendIntegration,
    aaveBorrowIntegration,
    heartTradeIntegration,
    harvestV3VaultIntegration,
    harvestV3StakeIntegration,
    paladinTradeIntegration,
    fuseLendIntegration,
    fuseBorrowIntegration,
    lidoIntegration,
    stakewiseIntegration,
    convexRegistry,
    yearnVaultRegistry,
    timelockController,
    babGovernor,
    masterSwapper,
    viewer,

    garden1,
    garden2,
    garden3,
    garden4,
    heartGarden,
    aaveGarden,
    heartTestGarden,

    strategy11,
    strategy21,

    buyOperation,
    addLiquidityOperation,
    depositVaultOperation,
    lendOperation,
    borrowOperation,
    customOperation,

    gardenValuer,
    priceOracle,
    tokenIdentifier,
    ishtarGate,
    mardukGate,

    gardenNFT,
    strategyNFT,

    GARDEN_PARAMS,

    deployer,
    keeper,
    owner,
    signer1,
    signer2,
    signer3,

    daiWhaleSigner,
    wethWhaleSigner,

    deployments,
    upgradesDeployer,

    dai,
    usdc,
    weth,
    wbtc,
    babl,

    TOKEN_MAP,

    nft,
  };
}

const fixtureCache = {};

module.exports = {
  setupTests: (params = {}) => {
    const key = JSON.stringify(params);
    if (!fixtureCache[key]) {
      fixtureCache[key] = deployments.createFixture((hre, options) => setUpFixture(hre, options, params));
    }
    return fixtureCache[key];
  },
};
