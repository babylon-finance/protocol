const { deployments } = require('hardhat');
const { GARDEN_PARAMS } = require('../../lib/constants.js');
const addresses = require('../../lib/addresses');
const { impersonateAddress } = require('../../lib/rpc');
const { createStrategy } = require('./StrategyHelper.js');

async function setUpFixture({ deployments, getNamedAccounts, ethers }, options, gardenParams) {
  async function getContract(contractName, deploymentName) {
    return await ethers.getContractAt(contractName, (await deployments.get(deploymentName || contractName)).address);
  }

  await deployments.fixture();

  const [owner, signer1, signer2, signer3] = await ethers.getSigners();

  const babController = await getContract('BabController', 'BabControllerProxy');
  const bablToken = await getContract('BABLToken');
  const timeLockRegistry = await getContract('TimeLockRegistry');
  const ishtarGate = await getContract('IshtarGate');
  const priceOracle = await getContract('PriceOracle');
  const treasury = await getContract('Treasury');
  const gardenValuer = await getContract('GardenValuer');
  const rewardsDistributor = await getContract('RewardsDistributor');

  const kyberTradeIntegration = await getContract('KyberTradeIntegration');
  const oneInchTradeIntegration = await getContract('OneInchTradeIntegration');
  const balancerIntegration = await getContract('BalancerIntegration');
  const uniswapPoolIntegration = await getContract('UniswapPoolIntegration');
  const yearnVaultIntegration = await getContract('YearnVaultIntegration');
  const sushiswapPoolIntegration = await getContract('SushiswapPoolIntegration');
  const oneInchPoolIntegration = await getContract('OneInchPoolIntegration');
  const compoundLendIntegration = await getContract('CompoundLendIntegration');
  const aaveLendIntegration = await getContract('AaveLendIntegration');

  // Gives signer1 creator permissions
  await ishtarGate.connect(owner).setCreatorPermissions(owner.address, true, { gasPrice: 0 });
  await ishtarGate.connect(owner).setCreatorPermissions(signer1.address, true, { gasPrice: 0 });

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'Absolute ETH Return [beta]', 'EYFA', gardenParams, 'http...', {
      value: ethers.utils.parseEther('1'),
    });

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'ETH Yield Farm [a]', 'EYFB', gardenParams, 'http...', {
      value: ethers.utils.parseEther('1'),
    });

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'ETH Yield Farm [b]', 'EYFG', gardenParams, 'http...', {
      value: ethers.utils.parseEther('1'),
    });

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'ETH Yield Farm [d]', 'EYFG', gardenParams, 'http...', {
      value: ethers.utils.parseEther('1'),
    });

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
  // Create strategies
  const strategy11 = (
    await createStrategy('long', 'dataset', [signer1, signer2, signer3], kyberTradeIntegration.address, garden1)
  ).address;
  const strategy21 = (
    await createStrategy('long', 'deposit', [signer1, signer2, signer3], kyberTradeIntegration.address, garden2)
  ).address;

  await createStrategy('long', 'deposit', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);
  await createStrategy('long', 'dataset', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);

  console.log('Created and started garden', garden1.address);
  console.log('Created manual testing garden', garden3.address);

  const daiWhaleSigner = await impersonateAddress('0x6B175474E89094C44Da98b954EedeAC495271d0F');
  const wethWhaleSigner = await impersonateAddress('0xC8dDA504356195ba5344E5a9826Ce07DfEaA97b6');

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
    yearnVaultIntegration,
    sushiswapPoolIntegration,
    oneInchPoolIntegration,
    compoundLendIntegration,
    aaveLendIntegration,

    garden1,
    garden2,
    garden3,
    garden4,

    strategy11,
    strategy21,

    gardenValuer,
    priceOracle,
    ishtarGate,

    GARDEN_PARAMS,

    owner,
    signer1,
    signer2,
    signer3,
    daiWhaleSigner,
    wethWhaleSigner,
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
