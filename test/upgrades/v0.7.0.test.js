const { expect } = require('chai');
const { deployments } = require('hardhat');

const { impersonateAddress } = require('lib/rpc');
const { ONE_DAY_IN_SECONDS } = require('lib/constants.js');
const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const { increaseTime } = require('../utils/test-helpers');

const { deploy } = deployments;

const upgradeFixture = deployments.createFixture(async (hre, options) => {
  const { ethers } = hre;

  const owner = await impersonateAddress('0xeA4E1d01Fad05465a84bAd319c93B73Fa12756fB');
  const deployer = await impersonateAddress('0x040cC3AF8455F3c34D1df1D2a305e047a062BeBf');
  const keeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');

  let controller = await ethers.getContractAt('BabController', '0xd4a5b5fcb561daf3adf86f8477555b92fba43b5f', owner);
  const distributor = await ethers.getContractAt(
    'RewardsDistributor',
    '0x40154ad8014df019a53440a60ed351dfba47574e',
    owner,
  );

  await fund([owner.address, deployer.address], {
    tokens: [addresses.tokens.ETH],
  });

  const signers = await ethers.getSigners();
  const signer = signers[0];
  //
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
  for (const { contract, type, operation, args } of [
    {
      contract: 'ConvexStakeIntegration',
      type: 'integration',
      args: [controller.address],
    },
    {
      contract: 'CurvePoolIntegration',
      type: 'integration',
      args: [controller.address],
    },
    {
      contract: 'CurveTradeIntegration',
      type: 'integration',
      args: [controller.address],
    },
    {
      contract: 'SynthetixTradeIntegration',
      type: 'integration',
      args: [controller.address],
    },
    {
      contract: 'UniswapV2TradeIntegration',
      type: 'integration',
      args: [controller.address],
    },
    {
      contract: 'UniswapV3TradeIntegration',
      type: 'integration',
      args: [controller.address],
    },

    { contract: 'AddLiquidityOperation', type: 'operation', operation: 1, args: ['lp', controller.address] },
    { contract: 'DepositVaultOperation', type: 'operation', operation: 2, args: ['vault', controller.address] },
    { contract: 'LendOperation', type: 'operation', operation: 3, args: ['lend', controller.address] },
    { contract: 'BuyOperation', type: 'operation', operation: 0, args: ['buy', controller.address] },
  ]) {
    const deployment = await deploy(contract, {
      from: signer.address,
      args,
    });
    if (type === 'integration') {
    }
    if (type === 'operation') {
      await controller.setOperation(operation, deployment.address);
    }
  }

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

  // deploy PriceOracle
  const priceOracle = await deploy('PriceOracle', {
    from: signer.address,
    args: [],
  });

  await controller.setMasterSwapper(masterSwapper.address);
  await controller.editPriceOracle(priceOracle.address);

  // upgrade strategy
  const strategBeacon = await ethers.getContractAt(
    'UpgradeableBeacon',
    '0x31946680978CEFB010e5f5Fa8b8134c058cba7dC',
    deployer,
  );

  const strategyNewImpl = await deploy('Strategy', {
    from: signer.address,
    args: [],
    log: true,
  });

  await strategBeacon.connect(deployer).upgradeTo(strategyNewImpl.address);

  // upgrade garden
  const gardenBeacon = await ethers.getContractAt(
    'UpgradeableBeacon',
    '0xc8f44C560efe396a6e57e48fF07205bD28AF5E75',
    deployer,
  );

  const gardenNewImpl = await deploy('Garden', {
    from: signer.address,
    args: [],
    log: true,
  });

  await gardenBeacon.connect(deployer).upgradeTo(gardenNewImpl.address);

  return { controller, owner, deployer, keeper };
});

describe.only('v0.7.0', function () {
  let owner;
  let keeper;

  beforeEach(async () => {
    ({ owner, keeper } = await upgradeFixture());
  });

  describe('after upgrade', function () {
    describe('can finalizeStrategy', function () {
      for (const [name, strategy] of [
        ['Leverage long ETH', '0x49567812f97369a05e8D92462d744EFd00d7Ea42'],
        ['lend eth, borrow dai, harvest dai', '0xcd4fD2a8426c86067836d077eDA7FA2A1dF549dD'],
        ['Leverage BED', '0x0f4b1585ed506986d3a14436034D1D52704e5b56'],
        ['Stake ETH - Lido', '0xD8BAdcC27Ecb72F1e88b95172E7DeeeF921883C8'],
        ['Yearn USDC Vault', '0xa29b722f9D021FE435475b344355521Fa580940F'],
        ['Lend DAI on Aave', '0x4C449D3C878A6CabaD3f606A4978837Ac5196D5B'],
        ['Stake ETH', '0x07DEbD22bCa7d010E53fc8ec23E8ADc3a516eC08'],
        ['end eth, borrow dai, yearn da', '0x27cdbC334cF2dc7Aa720241e9a98Adbc8cc41254'],
        ['Stable Coin Farm Strategy', '0x40A561a3457F6EFDb8f80cDe3D55D280cce45f3a'],
        ['ETH-LINK LP', '0xc80C2f1c170fBD793845e67c58e2469569174EA2'],
        ['WETH-LINK', '0xe3bBF21574E18363733255ba56862E721CD2F3a4'],
        ['Long BED', '0xE064ad71dc506130A4C1C85Fb137606BaaCDe9c0'],
        ['Lend weth, borrow dai, farm yearn dai', '0xFDeA6F30F3dadD60382bAA07252923Ff6007c35d'],
        ['Lend wbtc, borrow dai, yield yearn dai', '0x81b1C6A04599b910e33b1AB549DE4a19E5701838'],
        ['Yearn - DAI Vault', '0x23E6E7B35E9E117176799cEF885B9D4a97D42df9'],
        ['ETHficient Stables', '0x3d4c6303E8E6ad9F4697a5c3deAe9827217439Ae'],
        ['long DAI', '0xB0147911b9d584618eB8F3BF63AD1AB858085101'],
        // ['RAI/ETH UNI LP', '0x884957Fd342993A748c82aC608043859F1482126'],
      ]) {
        it(name, async () => {
          const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);

          await increaseTime(ONE_DAY_IN_SECONDS * 360);

          await strategyContract.connect(keeper).finalizeStrategy(0, '');
          const [, active, , finalized, , exitedAt] = await strategyContract.getStrategyState();

          expect(active).eq(false);
          expect(finalized).eq(true);
          expect(exitedAt).gt(0);
        });
      }
    });
  });
});
