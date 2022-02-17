import { isConstructSignatureDeclaration } from 'typescript';
import { increaseBlock } from '../test/utils/test-helpers';

const { expect } = require('chai');
const { deployments } = require('hardhat');

const { impersonateAddress } = require('lib/rpc');
const { ONE_DAY_IN_SECONDS } = require('lib/constants.js');
const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const { getSigs } = require('lib/web3');
const { from, parse, eth } = require('lib/helpers');
const { getGasPrice } = require('lib/gasnow');
const { increaseTime, getContract } = require('utils/test-helpers');

const { deploy } = deployments;

const TIMELOCK_ADDRESS = '0xe6Ed0eAcB79a6e457416E4df38ed778fd6C6D193';

export async function getContracts() {
  const { ethers } = hre;

  const owner = await impersonateAddress('0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e');
  const deployer = await impersonateAddress('0x040cC3AF8455F3c34D1df1D2a305e047a062BeBf');
  const ownerV2 = await impersonateAddress('0x0B892EbC6a4bF484CDDb7253c6BD5261490163b9');
  const keeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');
  const gov = await impersonateAddress(TIMELOCK_ADDRESS);
  const governor = await impersonateAddress('0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24');
  const gnosis = await impersonateAddress('0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e');
  const tokenIdentifier = await ethers.getContractAt(
    'TokenIdentifier',
    '0x17a7c092E0009aF48c8e08af473DFC4b472e2852',
    owner,
  );

  const controller = await ethers.getContractAt('BabController', '0xD4a5b5fcB561dAF3aDF86F8477555B92FBa43b5F', gov);
  const distributor = await ethers.getContractAt(
    'RewardsDistributor',
    '0x40154ad8014df019a53440a60ed351dfba47574e',
    owner,
  );

  const strategyNft = await ethers.getContractAt('StrategyNFT', '0xdE7A3F8CcCcddbcB773e1656b41a9C2d4AC5454d', owner);
  const valuer = await ethers.getContractAt('GardenValuer', await controller.gardenValuer(), owner);
  const ishtarGate = await ethers.getContractAt('IshtarGate', '0x77d200eca7fd0a3db27e96d7b24cf7613b0a2a12', ownerV2);
  const gardens = await controller.getGardens();
  const heart = await ethers.getContractAt('Heart', '0x51e6775b7bE2eA1d20cA02cFEeB04453366e72C8');
  const heartGarden = await ethers.getContractAt('Garden', '0xaA2D49A1d66A58B8DD0687E730FefC2823649791');

  return {
    gov,
    owner,
    ownerV2,
    deployer,
    keeper,
    controller,
    distributor,
    strategyNft,
    valuer,
    gardens,
    ishtarGate,
    gnosis,
    tokenIdentifier,
    heart,
    heartGarden,
    governor,
  };
}

const deployFixture = deployments.createFixture(async (hre, options) => {
  const { ethers } = hre;
  const { maxPriorityFeePerGas } = await getGasPrice();

  const {
    owner,
    ownerV2,
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
    tokenIdentifier,
    heart,
    heartGarden,
    governor,
  } = await getContracts();

  await fund([owner.address, deployer.address, TIMELOCK_ADDRESS, gnosis.address], {
    tokens: [addresses.tokens.ETH],
  });
  const signers = await ethers.getSigners();
  const signer = signers[0];

  // get NAV of all gardens before deploy
  /* const gardensNAV = {};
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('IGarden', garden);
    const gardenNAV = (await valuer.calculateGardenValuation(garden, addresses.tokens.DAI))
      .mul(await gardenContract.totalSupply())
      .div(eth());
    gardensNAV[garden] = gardenNAV;
  } */

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

  // We update Rewards Distributor at Rewards Assistant

  const distributorAssistant = await deploy('RewardsAssistant', {
    from: signer.address,
    args: [controller.address],
    log: true,
    maxPriorityFeePerGas,
  });

  // We then set the Rewards Assistant in RD
  await distributor.connect(gnosis).setRewardsAssistant(distributorAssistant.address, { maxPriorityFeePerGas });
  // For rewards we need a heart garden using the same BABL Token than RD in tests
  // Set the test heart garden into rewards distributor
  await distributor.connect(gnosis).setHeartGarden(heartGarden.address, { gasPrice: 0 });

  // const babViewer = await ethers.getContractAt('BabylonViewer', '0x796af8955e2e0eb81ad72a77df9aa515d92226e0');

  /* const heartViewerDeployment = await deploy('HeartViewer', {
    from: signer.address,
    args: [controller.address, governor.address, heart.address],
    log: true,
    maxPriorityFeePerGas,
  });
  const heartViewer = await ethers.getContractAt('HeartViewer', heartViewerDeployment.address); */

  // deploy new contracts
  // TODO: Deploy all integrations and tests adding new strategies with them
  /*   for (const { contract, type, operation, args } of [
    // MasterSwapper deps
    { contract: 'CurveTradeIntegration', type: 'integration', args: [controller.address] },
    { contract: 'ConvexStakeIntegration', type: 'integration', args: [controller.address] },
    { contract: 'UniswapV3TradeIntegration', type: 'integration', args: [controller.address] },
    { contract: 'UniswapV2TradeIntegration', type: 'integration', args: [controller.address] },
    { contract: 'SynthetixTradeIntegration', type: 'integration', args: [controller.address] },

    { contract: 'BalancerIntegration', type: 'integration', args: [controller.address, addresses.balancer.factory] },
    { contract: 'HarvestVaultIntegration', type: 'integration', args: [controller.address] },
    { contract: 'YearnVaultIntegration', type: 'integration', args: [controller.address] },
    { contract: 'UniswapPoolIntegration', type: 'integration', args: [controller.address, addresses.uniswap.router] },
    { contract: 'OneInchPoolIntegration', type: 'integration', args: [controller.address, addresses.oneinch.factory] },
    {
      contract: 'SushiswapPoolIntegration',
      type: 'integration',
      args: [controller.address, addresses.sushiswap.router],
    },
    {
      contract: 'CompoundLendIntegration',
      type: 'integration',
      args: ['compoundlend', controller.address, '0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b'],
    },
    {
      contract: 'CompoundBorrowIntegration',
      type: 'integration',
      args: [
        'compoundborrow',
        controller.address,
        ethers.utils.parseEther('0.30'),
        '0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b',
      ],
    },
    {
      contract: 'FuseLendIntegration',
      type: 'integration',
      args: [controller.address, '0xC7125E3A2925877C7371d579D29dAe4729Ac9033'],
    },
    {
      contract: 'FuseBorrowIntegration',
      type: 'integration',
      args: [controller.address, ethers.utils.parseEther('0.35'), '0xC7125E3A2925877C7371d579D29dAe4729Ac9033'],
    },
    { contract: 'AaveLendIntegration', type: 'integration', args: [controller.address] },
    {
      contract: 'AaveBorrowIntegration',
      type: 'integration',
      args: [controller.address, ethers.utils.parseEther('0.30')],
    },
    // { contract: 'LidoStakeIntegration', type: 'integration', args: [controller.address] },
    // { contract: 'CurvePoolIntegration', type: 'integration', args: [controller.address] },
    // { contract: 'HarvestPoolV3Integration', type: 'integration', args: [controller.address] },
    // { contract: 'HarvestV3StakeIntegration', type: 'integration', args: [controller.addres] },

    { contract: 'AddLiquidityOperation', type: 'operation', operation: 1, args: ['lp', controller.address] },
    { contract: 'DepositVaultOperation', type: 'operation', operation: 2, args: ['vault', controller.address] },
    { contract: 'LendOperation', type: 'operation', operation: 3, args: ['lend', controller.address] },
    { contract: 'BorrowOperation', type: 'operation', operation: 4, args: ['borrow', controller.address] },
    { contract: 'BuyOperation', type: 'operation', operation: 0, args: ['buy', controller.address] },
  ]) {
    const deployment = await deploy(contract, {
      from: signer.address,
      args,
    });
    console.log('deployment', contract, deployment.address);
    if (type === 'operation') {
      await controller.setOperation(operation, deployment.address);
    }
  } */

  // deploy PriceOracle
  /* const priceOracle = await deploy('PriceOracle', {
    from: signer.address,
    args: [tokenIdentifier.address, controller.address],
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

  await controller.setMasterSwapper(masterSwapper.address); */

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
    args: ['0xaaacb63ab80969af93b811deb81ddeb4c8710591'],
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
    distributorAssistant,
    owner,
    ownerV2,
    gov,
    deployer,
    keeper,
    gardens,
    // gardensNAV,
    strategyNft,
    valuer,
    ishtarGate,
    gnosis,
    heartGarden,
    heart,
    governor,
    // heartViewer,
    // babViewer,
  };
});

module.exports = {
  getContracts,
  deployFixture,
};
