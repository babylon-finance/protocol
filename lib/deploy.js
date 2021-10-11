const { expect } = require('chai');
const { deployments } = require('hardhat');

const { impersonateAddress } = require('lib/rpc');
const { ONE_DAY_IN_SECONDS } = require('lib/constants.js');
const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const { from, parse, eth } = require('lib/helpers');
const { increaseTime } = require('utils/test-helpers');

const { deploy } = deployments;

export async function getContracts() {
  const { ethers } = hre;

  const owner = await impersonateAddress('0x0B892EbC6a4bF484CDDb7253c6BD5261490163b9');
  const deployer = await impersonateAddress('0x040cC3AF8455F3c34D1df1D2a305e047a062BeBf');
  const keeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');

  let controller = await ethers.getContractAt('BabController', '0xd4a5b5fcb561daf3adf86f8477555b92fba43b5f', owner);
  const distributor = await ethers.getContractAt(
    'RewardsDistributor',
    '0x40154ad8014df019a53440a60ed351dfba47574e',
    owner,
  );

  const strategyNft = await ethers.getContractAt('StrategyNFT', '0xdE7A3F8CcCcddbcB773e1656b41a9C2d4AC5454d', owner);
  const valuer = await ethers.getContractAt('GardenValuer', await controller.gardenValuer(), owner);

  const gardens = await controller.getGardens();

  return { owner, deployer, keeper, controller, distributor, strategyNft, valuer, gardens };
}

const deployFixture = deployments.createFixture(async (hre, options) => {
  const { ethers } = hre;

  const { owner, deployer, keeper, controller, distributor, strategyNft, valuer, gardens } = await getContracts();

  await fund([owner.address, deployer.address], {
    tokens: [addresses.tokens.ETH],
  });

  const signers = await ethers.getSigners();
  const signer = signers[0];

  // get NAV of all gardens before deploy
  const gardensNAV = {};
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('Garden', garden);
    const gardenNAV = (await valuer.calculateGardenValuation(garden, addresses.tokens.DAI))
      .mul(await gardenContract.totalSupply())
      .div(eth());
    gardensNAV[garden] = gardenNAV;
  }

  // upgrade controller
  const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', owner);

  const controllerNewImpl = await deploy('BabController', {
    from: signer.address,
  });

  await proxyAdmin.upgrade(controller.address, controllerNewImpl.address);

  // upgrade rewards distributor
  const distributorNewImpl = await deploy('RewardsDistributor', {
    from: signer.address,
  });

  await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address);

  // deploy new contracts
  // TODO: Deploy all integrations and tests adding new strategies with them
  for (const { contract, type, operation, args } of [
    // MasterSwapper deps
    { contract: 'CurveTradeIntegration', type: 'integration', args: [controller.address] },
    { contract: 'ConvexStakeIntegration', type: 'integration', args: [controller.address] },
    { contract: 'UniswapV3TradeIntegration', type: 'integration', args: [controller.address] },
    { contract: 'UniswapV2TradeIntegration', type: 'integration', args: [controller.address] },
    { contract: 'SynthetixTradeIntegration', type: 'integration', args: [controller.address] },

    { contract: 'AddLiquidityOperation', type: 'operation', operation: 1, args: ['lp', controller.address] },
    { contract: 'DepositVaultOperation', type: 'operation', operation: 2, args: ['vault', controller.address] },
    { contract: 'LendOperation', type: 'operation', operation: 3, args: ['lend', controller.address] },
    { contract: 'BuyOperation', type: 'operation', operation: 0, args: ['buy', controller.address] },
  ]) {
    const deployment = await deploy(contract, {
      from: signer.address,
      args,
    });
    console.log('deploying', contract, deployment.address);
    if (type === 'operation') {
      await controller.setOperation(operation, deployment.address);
    }
  }

  // deploy PriceOracle
  const priceOracle = await deploy('PriceOracle', {
    from: signer.address,
    args: [],
  });
  await controller.editPriceOracle(priceOracle.address);

  // deploy MasterSwapper
  const masterSwapper = await deploy('MasterSwapper', {
    from: signer.address,
    args: [
      controller.address,
      (await deployments.get('CurveTradeIntegration')).address,
      (await deployments.get('UniswapV3TradeIntegration')).address,
      (await deployments.get('SynthetixTradeIntegration')).address,
      (await deployments.get('UniswapV2TradeIntegration')).address,
    ],
  });
  await controller.setMasterSwapper(masterSwapper.address);

  // upgrade strategy
  const strategyBeacon = await ethers.getContractAt(
    'UpgradeableBeacon',
    '0x31946680978CEFB010e5f5Fa8b8134c058cba7dC',
    owner,
  );

  const strategyNewImpl = await deploy('Strategy', {
    from: signer.address,
    args: [],
    log: true,
  });

  await strategyBeacon.connect(owner).upgradeTo(strategyNewImpl.address);

  // upgrade garden
  const gardenBeacon = await ethers.getContractAt(
    'UpgradeableBeacon',
    '0xc8f44C560efe396a6e57e48fF07205bD28AF5E75',
    owner,
  );

  const gardenNewImpl = await deploy('Garden', {
    from: signer.address,
    args: [],
    log: true,
  });

  await gardenBeacon.connect(owner).upgradeTo(gardenNewImpl.address);

  return { controller, distributor, owner, deployer, keeper, gardens, gardensNAV, strategyNft, valuer };
});

module.exports = {
  getContracts,
  deployFixture,
};
