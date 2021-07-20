const { expect } = require('chai');
const { deployments } = require('hardhat');

const { impersonateAddress } = require('../../lib/rpc');
const { ONE_DAY_IN_SECONDS, GARDEN_PARAMS } = require('../../lib/constants.js');
const addresses = require('../../lib/addresses');
const { increaseTime } = require('../utils/test-helpers');
const { createStrategy, executeStrategy } = require('../fixtures/StrategyHelper.js');

const { deploy } = deployments;

const upgradeFixture = deployments.createFixture(async (hre, options) => {
  owner = await impersonateAddress('0xeA4E1d01Fad05465a84bAd319c93B73Fa12756fB');
  deployer = await impersonateAddress('0x040cC3AF8455F3c34D1df1D2a305e047a062BeBf');
  keeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');
  controller = await ethers.getContractAt('BabController', '0xd4a5b5fcb561daf3adf86f8477555b92fba43b5f', owner);

  const signers = await ethers.getSigners();
  const signer = signers[0];

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
      await controller.editIntegration(
        await (await ethers.getContractAt(contract, deployment.address)).getName(),
        deployment.address,
      );
    }
    if (type === 'operation') {
      await controller.setOperation(operation, deployment.address);
    }
  }

  const beacon = await ethers.getContractAt(
    'UpgradeableBeacon',
    '0x31946680978CEFB010e5f5Fa8b8134c058cba7dC',
    deployer,
  );

  const newImpl = await deploy('Strategy', {
    from: signer.address,
    args: [],
    log: true,
  });

  await beacon.connect(deployer).upgradeTo(newImpl.address);

  return { controller, owner, deployer, keeper };
});

describe.skip('v0.6.0', function () {
  let controller;
  let owner;
  let deployer;
  let keeper;

  beforeEach(async () => {
    ({ controller, owner, deployer, keeper } = await upgradeFixture());
  });

  describe('after upgrade', function () {
    describe('can finalizeStrategy', function () {
      it('leverageEthStrategy', async () => {
        const leverageEthStrategy = await ethers.getContractAt(
          'IStrategy',
          '0x49567812f97369a05e8D92462d744EFd00d7Ea42',
          owner,
        );

        await increaseTime(ONE_DAY_IN_SECONDS * 120);

        await leverageEthStrategy.connect(keeper).finalizeStrategy(0, '');
        const [
          address,
          active,
          dataSet,
          finalized,
          executedAt,
          exitedAt,
        ] = await leverageEthStrategy.getStrategyState();
        expect(active).equals(false);
        expect(finalized).equals(true);
      });

      it('Lend Eth Borrow DAI', async () => {
        const lendEthBorrowDaiInHarvestDai = await ethers.getContractAt(
          'IStrategy',
          '0xcd4fd2a8426c86067836d077eda7fa2a1df549dd',
          owner,
        );

        await increaseTime(ONE_DAY_IN_SECONDS * 120);

        await lendEthBorrowDaiInHarvestDai.connect(keeper).finalizeStrategy(0, '');

        const [
          address,
          active,
          dataSet,
          finalized,
          executedAt,
          exitedAt,
        ] = await lendEthBorrowDaiInHarvestDai.getStrategyState();
        expect(active).equals(false);
        expect(finalized).equals(true);
      });

      it('USDC-ETH Uniswap', async () => {
        const usdcEthUniswapLp = await ethers.getContractAt(
          'IStrategy',
          '0x13c0afb2d5ccdc5e515241de4447c6104d5bba7b',
          owner,
        );
        await increaseTime(ONE_DAY_IN_SECONDS * 120);

        await usdcEthUniswapLp.connect(keeper).finalizeStrategy(0, '');

        const [address, active, dataSet, finalized, executedAt, exitedAt] = await usdcEthUniswapLp.getStrategyState();
        expect(active).equals(false);
        expect(finalized).equals(true);
      });

      it('long WBTC', async () => {
        const longWBTC = await ethers.getContractAt('IStrategy', '0x7498decb12acdb1c70e17bdb8481a13000a01ed6', owner);

        await increaseTime(ONE_DAY_IN_SECONDS * 120);
        
        await longWBTC.connect(keeper).finalizeStrategy(0, '');

        const [address, active, dataSet, finalized, executedAt, exitedAt] = await longWBTC.getStrategyState();
        expect(active).equals(false);
        expect(finalized).equals(true);
      });
    });
  });
});
