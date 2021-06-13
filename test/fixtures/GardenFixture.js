const { deployments } = require('hardhat');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../../lib/system.js');
const { GARDEN_PARAMS } = require('../../lib/constants.js');
const addresses = require('../../lib/addresses');
const { getAssetWhale } = require('../../lib/whale.js');
const { impersonateAddress } = require('../../lib/rpc');
const { createStrategy } = require('./StrategyHelper.js');
const { getContract } = require('../utils/test-helpers');

async function setUpFixture({ upgradesDeployer, deployments, getNamedAccounts, ethers }, options, gardenParams) {
  const signers = await ethers.getSigners();
  const [deployer, keeper, owner, signer1, signer2, signer3] = signers;

  await deployments.fixture();

  const babController = await getContract('BabController', 'BabControllerProxy');
  const bablToken = await getContract('BABLToken');
  const timeLockRegistry = await getContract('TimeLockRegistry');
  const ishtarGate = await getContract('IshtarGate');
  const priceOracle = await getContract('PriceOracle');
  const treasury = await getContract('Treasury');
  const gardenValuer = await getContract('GardenValuer');
  const gardenNFT = await getContract('GardenNFT');
  const strategyNFT = await getContract('StrategyNFT');
  const rewardsDistributor = await getContract('RewardsDistributor', 'RewardsDistributorProxy');

  const kyberTradeIntegration = await getContract('KyberTradeIntegration');
  const oneInchTradeIntegration = await getContract('OneInchTradeIntegration');
  const balancerIntegration = await getContract('BalancerIntegration');
  const uniswapPoolIntegration = await getContract('UniswapPoolIntegration');
  const yearnVaultIntegration = await getContract('YearnVaultIntegration');
  const harvestVaultIntegration = await getContract('HarvestVaultIntegration');
  const sushiswapPoolIntegration = await getContract('SushiswapPoolIntegration');
  const oneInchPoolIntegration = await getContract('OneInchPoolIntegration');
  const compoundLendIntegration = await getContract('CompoundLendIntegration');
  const aaveLendIntegration = await getContract('AaveLendIntegration');

  const buyOperation = await getContract('BuyOperation');
  const addLiquidityOperation = await getContract('AddLiquidityOperation');
  const depositVaultOperation = await getContract('DepositVaultOperation');
  const lendOperation = await getContract('LendOperation');

  // deploy uniswap v2 adapter for tests
  await deployments.deploy('UniswapTWAP', {
    from: deployer.address,
    args: [babController.address, addresses.uniswap.factory, TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY],
    log: true,
  });
  const univ2 = await getContract('UniswapTWAP');

  // Gives signer1 creator permissions
  await ishtarGate.connect(owner).setCreatorPermissions(owner.address, true, { gasPrice: 0 });
  await ishtarGate.connect(owner).setCreatorPermissions(signer1.address, true, { gasPrice: 0 });

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
      .grantGardenAccessBatch(
        gardens[i],
        [owner.address, signer1.address, signer2.address, signer3.address],
        [3, 3, 3, 3],
        {
          gasPrice: 0,
        },
      );
  }
  console.log('create strategies');
  // Create strategies
  const strategy11 = (
    await createStrategy('buy', 'dataset', [signer1, signer2, signer3], kyberTradeIntegration.address, garden1)
  ).address;
  const strategy21 = (
    await createStrategy('buy', 'deposit', [signer1, signer2, signer3], kyberTradeIntegration.address, garden2)
  ).address;

  await createStrategy('buy', 'deposit', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);
  await createStrategy('buy', 'dataset', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);

  console.log('Created and started garden', garden1.address);
  console.log('Created manual testing garden', garden3.address);

  const dai = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
  const usdc = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
  const weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  wbtc = await ethers.getContractAt('IERC20', addresses.tokens.WBTC);

  const usdcWhaleAddress = getAssetWhale(addresses.tokens.USDC); // Has USDC

  const daiWhaleSigner = await impersonateAddress('0x6b175474e89094c44da98b954eedeac495271d0f');
  const usdcWhaleSigner = await impersonateAddress(usdcWhaleAddress);
  const wethWhaleSigner = await impersonateAddress('0xC8dDA504356195ba5344E5a9826Ce07DfEaA97b6');
  const wbtcWhaleSigner = await impersonateAddress('0x2260fac5e5542a773aa44fbcfedf7c193bc2c599');

  const thousandUSDC = ethers.BigNumber.from(1000 * 1000000);
  console.log('signers', signers.length);
  for (const signer of signers.slice(3, 10)) {
    await dai.connect(daiWhaleSigner).transfer(signer.address, ethers.utils.parseEther('10000'), {
      gasPrice: 0,
    });
    await usdc.connect(usdcWhaleSigner).transfer(signer.address, thousandUSDC, {
      gasPrice: 0,
    });
    await weth.connect(wethWhaleSigner).transfer(signer.address, ethers.utils.parseEther('5'), {
      gasPrice: 0,
    });

    await wbtc.connect(wbtcWhaleSigner).transfer(signer.address, 1e8, {
      gasPrice: 0,
    });
    console.log('wbtc balance', (await wbtc.balanceOf(signer.address)).toString());
  }

  return {
    babController,
    bablToken,
    timeLockRegistry,
    treasury,
    rewardsDistributor,
    kyberTradeIntegration,
    oneInchTradeIntegration,
    balancerIntegration,
    uniswapPoolIntegration,
    harvestVaultIntegration,
    yearnVaultIntegration,
    sushiswapPoolIntegration,
    oneInchPoolIntegration,
    compoundLendIntegration,
    aaveLendIntegration,
    univ2,

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

    gardenValuer,
    priceOracle,
    ishtarGate,

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
  };
}

const fixtureCache = {};

module.exports = {
  setupTests: (gardenParams = GARDEN_PARAMS) => {
    const key = JSON.stringify(gardenParams);
    if (!fixtureCache[key]) {
      fixtureCache[key] = deployments.createFixture((hre, options) => setUpFixture(hre, options, gardenParams));
    }
    return fixtureCache[key];
  },
};
