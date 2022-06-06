const { expect } = require('chai');
const { deployments } = require('hardhat');
const { impersonateAddress } = require('lib/rpc');
const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const { getSigs } = require('lib/web3');
const { eth } = require('lib/helpers');
const { deploy } = deployments;

const TIMELOCK_ADDRESS = '0xe6Ed0eAcB79a6e457416E4df38ed778fd6C6D193';

const TEST_NAV = !!process.env.TEST_NAV;

export async function getContracts() {
  const { ethers } = hre;

  const owner = await impersonateAddress('0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e');
  const deployer = await impersonateAddress('0x040cC3AF8455F3c34D1df1D2a305e047a062BeBf');
  const keeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');
  const gov = await impersonateAddress(TIMELOCK_ADDRESS);
  const gnosis = await impersonateAddress('0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e');

  const controller = await ethers.getContractAt('BabController', '0xd4a5b5fcb561daf3adf86f8477555b92fba43b5f', gov);
  const distributor = await ethers.getContractAt(
    'RewardsDistributor',
    '0x40154ad8014df019a53440a60ed351dfba47574e',
    owner,
  );
  const strategyNft = await ethers.getContractAt('StrategyNFT', '0xdE7A3F8CcCcddbcB773e1656b41a9C2d4AC5454d', owner);
  const valuer = await ethers.getContractAt('IGardenValuer', await controller.gardenValuer(), owner);
  const priceOracle = await ethers.getContractAt('PriceOracle', await controller.priceOracle(), owner);
  const ishtarGate = await ethers.getContractAt('IshtarGate', '0x77d200eca7fd0a3db27e96d7b24cf7613b0a2a12', owner);
  const gardens = await controller.getGardens();

  return {
    gov,
    owner,
    deployer,
    keeper,
    controller,
    distributor,
    priceOracle,
    strategyNft,
    valuer,
    gardens,
    ishtarGate,
    gnosis,
  };
}

const deployFixture = deployments.createFixture(async (hre, options) => {
  const { ethers } = hre;

  const {
    owner,
    gov,
    deployer,
    keeper,
    controller,
    distributor,
    strategyNft,
    valuer,
    gardens,
    ishtarGate,
    gnosis,
  } = await getContracts();

  await fund([owner.address, deployer.address, TIMELOCK_ADDRESS, gnosis.address], {
    tokens: [addresses.tokens.ETH],
  });

  const signers = await ethers.getSigners();
  const signer = signers[0];

  // get NAV of all gardens before deploy
  const gardensNAV = {};

  if (TEST_NAV) {
    for (const garden of gardens) {
      const gardenContract = await ethers.getContractAt('IGarden', garden);
      const reserveAsset = await ethers.getContractAt(
        '@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20',
        await gardenContract.reserveAsset(),
      );
      const decimals = await reserveAsset.decimals();
      const decimalsDiff = 18 - decimals;
      const gardenNAV = (await valuer.calculateGardenValuation(garden, addresses.tokens.DAI))
        .mul(await gardenContract.totalSupply())
        .mul(10 ** decimalsDiff)
        .div(eth());
      gardensNAV[garden] = gardenNAV;
      console.log('Garden NAV', gardenContract.address, gardenNAV.toString());
    }
  }

  // upgrade controller
  const proxyAdmin = await ethers.getContractAt(
    '@openzeppelin/contracts/proxy/ProxyAdmin.sol:ProxyAdmin',
    '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC',
    gnosis,
  );

  const controllerNewImpl = await deploy('BabController', {
    from: signer.address,
  });

  await proxyAdmin.upgrade(controller.address, controllerNewImpl.address);

  // upgrade rewards distributor
  const distributorNewImpl = await deploy('RewardsDistributor', {
    from: signer.address,
  });

  await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address);

  const curveMetaRegistry = await deploy('CurveMetaRegistry', {
    from: signer.address,
    args: [controller.address],
  });
  // const curveMetaRegistry = await ethers.getContractAt('CurveMetaRegistry', '0x6897E6A2ABaD74738E51832ca85b1a9E3e3e4C08');

  /*  const pickleJarRegistry = await deploy('PickleJarRegistry', {
    from: signer.address,
    args: [controller.address],
  }); */
  const pickleJarRegistry = await ethers.getContractAt(
    'PickleJarRegistry',
    '0xB3fE136A9Cc0c0Bc37e31E21f681E7Cff8FcCE80',
  );
  const yearnVaultRegistry = await ethers.getContractAt(
    'YearnVaultRegistry',
    '0x61c733fE0Eb89b75440A21cD658C4011ec512EB8',
  );
  const convexRegistry = await ethers.getContractAt('ConvexRegistry', '0xB95d213cdDBd256D3B9ae98b21CC6B9D8a1818ef');

  /* const yearnVaultRegistry = await deploy('YearnVaultRegistry', {
    from: signer.address,
    args: [controller.address],
  });
  const convexRegistry = await deploy('ConvexRegistry', {
    from: signer.address,
    args: [controller.address],
  }); */

  const tokenIdentifier = await deploy('TokenIdentifier', {
    from: signer.address,
    args: [
      controller.address,
      pickleJarRegistry.address,
      yearnVaultRegistry.address,
      curveMetaRegistry.address,
      convexRegistry.address,
    ],
  });

  // deploy new contracts
  // TODO: Deploy all integrations and tests adding new strategies with them
  for (const { contract, type, operation, args } of [
    // MasterSwapper deps
    {
      contract: 'CurveTradeIntegration',
      type: 'integration',
      args: [controller.address, curveMetaRegistry.address],
    },
    {
      contract: 'CurvePoolIntegration',
      type: 'integration',
      args: [controller.address, curveMetaRegistry.address],
    },
    {
      contract: 'CurveGaugeIntegration',
      type: 'integration',
      args: [controller.address, curveMetaRegistry.address],
    },
    // {
    //   contract: 'ConvexStakeIntegration',
    //   type: 'integration',
    //   args: [controller.address, convexRegistry.address],
    // },
    // { contract: 'UniswapV3TradeIntegration', type: 'integration', args: [controller.address] },
    // { contract: 'UniswapV2TradeIntegration', type: 'integration', args: [controller.address] },
    // { contract: 'SynthetixTradeIntegration', type: 'integration', args: [controller.address] },
    // { contract: 'HeartTradeIntegration', type: 'integration', args: [controller.address] },
    // { contract: 'PaladinTradeIntegration', type: 'integration', args: [controller.address] },
    // {
    //   contract: 'FuseLendIntegration',
    //   type: 'integration',
    //   args: [controller.address, '0xC7125E3A2925877C7371d579D29dAe4729Ac9033'],
    // },
    //
    // { contract: 'BuyOperation', type: 'operation', operation: 0, args: ['swap', controller.address] },
    // { contract: 'AddLiquidityOperation', type: 'operation', operation: 1, args: ['lp', controller.address] },
    // { contract: 'DepositVaultOperation', type: 'operation', operation: 2, args: ['vault', controller.address] },
    // { contract: 'LendOperation', type: 'operation', operation: 3, args: ['lend', controller.address] },
    // { contract: 'BorrowOperation', type: 'operation', operation: 4, args: ['borrow', controller.address] },
  ]) {
    const deployment = await deploy(contract, {
      from: signer.address,
      args,
    });
    console.log('deployed', contract, deployment.address);
    if (type === 'operation') {
      await controller.setOperation(operation, deployment.address);
    }
  }
  // deploy PriceOracle
  const priceOracle = await deploy('PriceOracle', {
    from: signer.address,
    args: [tokenIdentifier.address, controller.address],
  });
  await controller.editPriceOracle(priceOracle.address);

  const priceOracleInstance = await ethers.getContractAt('PriceOracle', priceOracle.address);

  // deploy MasterSwapper
  /* const masterSwapper = await deploy('MasterSwapper', {
    from: signer.address,
    args: [
      controller.address,
      (await deployments.get('CurveTradeIntegration')).address,
      (await deployments.get('UniswapV3TradeIntegration')).address,
      (await deployments.get('SynthetixTradeIntegration')).address,
      (await deployments.get('UniswapV2TradeIntegration')).address,
      (await deployments.get('HeartTradeIntegration')).address,
      (await deployments.get('PaladinTradeIntegration')).address,
    ],
  });

  await controller.setMasterSwapper(masterSwapper.address); */
  const masterSwapper = await ethers.getContractAt('MasterSwapper', '0x55a2e7237C43C6Ef2873a2c07e3f3C9cD1fB9387');
  await masterSwapper.connect(gov).updateTradeAddress(0, (await deployments.get('CurveTradeIntegration')).address);

  // upgrade strategy
  const strategyBeacon = await ethers.getContractAt(
    'UpgradeableBeacon',
    '0x31946680978CEFB010e5f5Fa8b8134c058cba7dC',
    gnosis,
  );

  const strategyNewImpl = await deploy('Strategy', {
    from: signer.address,
    args: [],
    log: true,
  });

  await strategyBeacon.connect(gnosis).upgradeTo(strategyNewImpl.address);

  // upgrade garden
  const gardenBeacon = await ethers.getContractAt(
    'UpgradeableBeacon',
    '0xc8f44C560efe396a6e57e48fF07205bD28AF5E75',
    gnosis,
  );

  const gardenNewImpl = await deploy('Garden', {
    from: signer.address,
    args: ['0xaaacb63ab80969af93b811deb81ddeb4c8710591', '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74'],
    log: true,
  });

  await gardenBeacon.connect(gnosis).upgradeTo(gardenNewImpl.address);

  // update garden module
  const vTableBeacon = await ethers.getContractAt('VTableBeacon', '0xaaacb63ab80969af93b811deb81ddeb4c8710591', gnosis);

  const strategyGardenModule = await deploy('StrategyGardenModule', {
    from: signer.address,
    args: [],
    log: true,
  });

  const strategyGardenModuleContract = await ethers.getContractAt(
    'StrategyGardenModule',
    strategyGardenModule.address,
    signer,
  );

  const adminGardenModule = await deploy('AdminGardenModule', {
    from: signer.address,
    args: [],
    log: true,
  });

  const adminGardenModuleContract = await ethers.getContractAt('AdminGardenModule', adminGardenModule.address, signer);

  // set garden modules on the beacon
  await vTableBeacon.updateVTable([
    [adminGardenModuleContract.address, getSigs(adminGardenModuleContract)],
    [strategyGardenModuleContract.address, getSigs(strategyGardenModuleContract)],
  ]);

  return {
    controller,
    distributor,
    owner,
    gov,
    deployer,
    priceOracle: priceOracleInstance,
    keeper,
    gardens,
    gardensNAV,
    strategyNft,
    valuer,
    ishtarGate,
    gnosis,
  };
});

module.exports = {
  getContracts,
  deployFixture,
};
