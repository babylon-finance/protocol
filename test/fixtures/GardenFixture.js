const { deployments } = require('hardhat');
const { GARDEN_PARAMS } = require('lib/constants.js');
const addresses = require('lib/addresses');
const { impersonateAddress } = require('lib/rpc');
const { fund } = require('lib/whale');
const { createStrategy } = require('./StrategyHelper.js');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');

async function setUpFixture(
  { upgradesDeployer, deployments, getNamedAccounts, ethers },
  options,
  { gardenParams = GARDEN_PARAMS },
) {
  const signers = await ethers.getSigners();
  const [deployer, keeper, , signer1, signer2, signer3] = signers;

  await deployments.fixture();

  const babController = await getContract('BabController', 'BabControllerProxy');
  const bablToken = await getContract('BABLToken');
  const timeLockRegistry = await getContract('TimeLockRegistry');
  const ishtarGate = await getContract('IshtarGate');
  const mardukGate = await getContract('MardukGate');
  const priceOracle = await getContract('PriceOracle');
  const treasury = await getContract('Treasury');
  const gardenValuer = await getContract('GardenValuer');
  const gardenNFT = await getContract('GardenNFT');
  const strategyNFT = await getContract('StrategyNFT');
  const rewardsDistributor = await getContract('RewardsDistributor', 'RewardsDistributorProxy');
  const babViewer = await getContract('BabylonViewer');
  const timelockController = await getContract('TimelockController');
  const babGovernor = await getContract('BabylonGovernor');

  const uniswapV3TradeIntegration = await getContract('UniswapV3TradeIntegration');
  const balancerIntegration = await getContract('BalancerIntegration');
  const uniswapPoolIntegration = await getContract('UniswapPoolIntegration');
  const yearnVaultIntegration = await getContract('YearnVaultIntegration');
  const harvestVaultIntegration = await getContract('HarvestVaultIntegration');
  const harvestV3VaultIntegration = await getContract('HarvestPoolV3Integration');
  const sushiswapPoolIntegration = await getContract('SushiswapPoolIntegration');
  const curvePoolIntegration = await getContract('CurvePoolIntegration');
  const convexStakeIntegration = await getContract('ConvexStakeIntegration');
  const oneInchPoolIntegration = await getContract('OneInchPoolIntegration');
  const compoundLendIntegration = await getContract('CompoundLendIntegration');
  const aaveLendIntegration = await getContract('AaveLendIntegration');
  const aaveBorrowIntegration = await getContract('AaveBorrowIntegration');
  const compoundBorrowIntegration = await getContract('CompoundBorrowIntegration');
  const lidoIntegration = await getContract('LidoStakeIntegration');
  const curveTradeIntegration = await getContract('CurveTradeIntegration');
  const synthetixTradeIntegration = await getContract('SynthetixTradeIntegration');
  const univ2TradeIntegration = await getContract('UniswapV2TradeIntegration');
  const masterSwapper = await getContract('MasterSwapper');

  const buyOperation = await getContract('BuyOperation');
  const addLiquidityOperation = await getContract('AddLiquidityOperation');
  const depositVaultOperation = await getContract('DepositVaultOperation');
  const lendOperation = await getContract('LendOperation');
  const borrowOperation = await getContract('BorrowOperation');

  const dai = await getERC20(addresses.tokens.DAI);
  const usdc = await getERC20(addresses.tokens.USDC);
  const weth = await getERC20(addresses.tokens.WETH);
  const wbtc = await getERC20(addresses.tokens.WBTC);

  const owner = await impersonateAddress(timelockController.address);
  await fund([owner.address], { tokens: [addresses.tokens.ETH] });

  const TOKEN_MAP = {
    [addresses.tokens.WETH]: weth,
    [addresses.tokens.DAI]: dai,
    [addresses.tokens.USDC]: usdc,
    [addresses.tokens.WBTC]: wbtc,
  };

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
      ethers.utils.parseEther('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: ethers.utils.parseEther('1'),
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
      ethers.utils.parseEther('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: ethers.utils.parseEther('1'),
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
      ethers.utils.parseEther('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: ethers.utils.parseEther('1'),
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
      ethers.utils.parseEther('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: ethers.utils.parseEther('1'),
      },
    );

  const gardens = await babController.getGardens();

  const garden1 = await ethers.getContractAt('Garden', gardens[0]);

  const garden2 = await ethers.getContractAt('Garden', gardens[1]);

  const garden3 = await ethers.getContractAt('Garden', gardens[2]);

  const garden4 = await ethers.getContractAt('Garden', gardens[3]);

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
  const usdcWhaleSigner = await impersonateAddress('0x0a59649758aa4d66e25f08dd01271e891fe52199');
  const wethWhaleSigner = await impersonateAddress('0xC8dDA504356195ba5344E5a9826Ce07DfEaA97b6');
  const wbtcWhaleSigner = await impersonateAddress('0x9ff58f4ffb29fa2266ab25e75e2a8b3503311656');
  const nft = await impersonateAddress('0x26231A65EF80706307BbE71F032dc1e5Bf28ce43');
  console.log('end garden fixture');

  return {
    babController,
    bablToken,
    timeLockRegistry,
    treasury,
    rewardsDistributor,
    uniswapV3TradeIntegration,
    curveTradeIntegration,
    balancerIntegration,
    uniswapPoolIntegration,
    harvestVaultIntegration,
    yearnVaultIntegration,
    sushiswapPoolIntegration,
    curvePoolIntegration,
    convexStakeIntegration,
    oneInchPoolIntegration,
    compoundLendIntegration,
    compoundBorrowIntegration,
    synthetixTradeIntegration,
    univ2TradeIntegration,
    aaveLendIntegration,
    aaveBorrowIntegration,
    harvestV3VaultIntegration,
    lidoIntegration,
    babViewer,
    timelockController,
    babGovernor,
    masterSwapper,

    garden1,
    garden2,
    garden3,
    garden4,

    strategy11,
    strategy21,

    buyOperation,
    addLiquidityOperation,
    depositVaultOperation,
    lendOperation,
    borrowOperation,

    gardenValuer,
    priceOracle,
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
