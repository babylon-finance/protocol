const { expect } = require('chai');
const { deployments } = require('hardhat');

const { impersonateAddress } = require('../../lib/rpc');
const { ONE_DAY_IN_SECONDS, GARDEN_PARAMS } = require('../../lib/constants.js');
const addresses = require('../../lib/addresses');
const { increaseTime } = require('../utils/test-helpers');
const { createStrategy, executeStrategy } = require('../fixtures/StrategyHelper.js');

const { deploy } = deployments;

const upgradeFixture = deployments.createFixture(async (hre, options) => {
  const { network, upgradesDeployer, ethers } = hre;

  owner = await impersonateAddress('0xeA4E1d01Fad05465a84bAd319c93B73Fa12756fB');
  deployer = await impersonateAddress('0x040cC3AF8455F3c34D1df1D2a305e047a062BeBf');
  keeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');

  controller = await ethers.getContractAt('BabController', '0xd4a5b5fcb561daf3adf86f8477555b92fba43b5f', owner);
  distributor = await ethers.getContractAt('RewardsDistributor', '0x40154ad8014df019a53440a60ed351dfba47574e', owner);

  const signers = await ethers.getSigners();
  const signer = signers[0];

  // upgrade rewards distributor
  const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', owner);

  const distributorNewImpl = await deploy('RewardsDistributor', {
    from: signer.address,
  });

  await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address);

  // deploy new contracts
  for (const { contract, type, operation, args } of [
    { contract: 'UniswapPoolIntegration', type: 'integration', args: [controller.address, addresses.uniswap.router] },
    {
      contract: 'SushiswapPoolIntegration',
      type: 'integration',
      args: [controller.address, addresses.sushiswap.router],
    },
    {
      contract: 'OneInchPoolIntegration',
      type: 'integration',
      args: [controller.address, addresses.oneinch.factory],
    },

    { contract: 'AddLiquidityOperation', type: 'operation', operation: 1, args: ['lp', controller.address] },
    { contract: 'DepositVaultOperation', type: 'operation', operation: 2, args: ['vault', controller.address] },
    { contract: 'BorrowOperation', type: 'operation', operation: 4, args: ['borrow', controller.address] },
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

describe.only('v0.6.0', function () {
  let controller;
  let owner;
  let deployer;
  let keeper;

  beforeEach(async () => {
    ({ controller, owner, deployer, keeper } = await upgradeFixture());
  });

  describe('after upgrade', function () {
    describe('can finalizeStrategy', function () {
      for (const [name, strategy] of [
        ['leverageEthStrategy', '0x49567812f97369a05e8D92462d744EFd00d7Ea42'],
        ['Lend Eth Borrow DAI', '0xcd4fd2a8426c86067836d077eda7fa2a1df549dd'],
        ['long WBTC', '0x7498decb12acdb1c70e17bdb8481a13000a01ed6'],
        ['yearn farm0', '0xc34210736940279DcB67d5796715D24135b76Bfe'],
      ]) {
        it(name, async () => {
          const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);

          await increaseTime(ONE_DAY_IN_SECONDS * 120);

          await strategyContract.connect(keeper).finalizeStrategy(0, '');
          const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();
          expect(active).eq(false);
          expect(finalized).eq(true);
          expect(exitedAt).gt(0);
        });
      }
    });
  });
});
