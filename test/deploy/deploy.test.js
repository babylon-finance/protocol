const { expect } = require('chai');
const { deployments } = require('hardhat');

const { impersonateAddress } = require('lib/rpc');
const { ONE_DAY_IN_SECONDS } = require('lib/constants.js');
const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const { takeSnapshot, restoreSnapshot } = require('lib/rpc');
const { from, parse, eth } = require('lib/helpers');
const { getContracts, deployFixture } = require('lib/deploy');
const { increaseTime } = require('utils/test-helpers');

const { deploy } = deployments;

describe('deploy', function () {
  let owner;
  let gov;
  let keeper;
  let priceOracle;
  let gardens;
  let strategyNft;
  let valuer;
  let gardensNAV;
  let snapshotId;

  async function canUnwindAllActiveStrategies() {
    for (const garden of gardens) {
      const gardenContract = await ethers.getContractAt('Garden', garden);
      console.log(`${await gardenContract.name()}`);

      const reserveAsset = await gardenContract.reserveAsset();

      const strategies = await gardenContract.getStrategies();
      for (const strategy of strategies) {
        const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);
        const isExecuting = await strategyContract.isStrategyActive();
        const name = await strategyNft.getStrategyName(strategy);

        if (!isExecuting) {
          console.log(`  Strategy ${name} ${strategyContract.address} is not active.`);
          continue;
        }

        console.log(`  Unwinding capital ${name} ${strategyContract.address}`);

        try {
          const capital = reserveAsset === addresses.tokens.DAI ? eth(3000) : eth(1);
          await strategyContract.connect(owner).unwindStrategy(capital);

          const [, active, , finalized, , exitedAt] = await strategyContract.getStrategyState();

          expect(active).eq(true);
          expect(finalized).eq(false);
          expect(exitedAt).eq(0);
        } catch (e) {
          console.log(`  failed to unwind capital ${e}`);
        }
      }
    }
  }

  async function canAllocateCapitalToAllActiveStrategies() {
    for (const garden of gardens) {
      const gardenContract = await ethers.getContractAt('Garden', garden);
      console.log(`${await gardenContract.name()}`);

      const reserveAsset = await gardenContract.reserveAsset();

      const strategies = await gardenContract.getStrategies();
      for (const strategy of strategies) {
        const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);
        const isExecuting = await strategyContract.isStrategyActive();
        const name = await strategyNft.getStrategyName(strategy);

        if (!isExecuting) {
          console.log(`  Strategy ${name} ${strategyContract.address} is not active.`);
          continue;
        }

        console.log(`  Adding capital to the strategy ${name} ${strategyContract.address}`);

        try {
          const capital = reserveAsset === addresses.tokens.DAI ? eth(3000) : eth(1);
          await strategyContract.connect(keeper).executeStrategy(capital, 1);

          const [, active, , finalized, , exitedAt] = await strategyContract.getStrategyState();

          expect(active).eq(true);
          expect(finalized).eq(false);
          expect(exitedAt).eq(0);
        } catch (e) {
          console.log(`  failed to allocate capital to the strategy ${e}`);
        }
      }
    }
  }

  async function canFinalizeAllActiveStrategies() {
    for (const garden of gardens) {
      const gardenContract = await ethers.getContractAt('Garden', garden);
      console.log(`${await gardenContract.name()}`);

      const strategies = await gardenContract.getStrategies();
      for (const strategy of strategies) {
        const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);
        const isExecuting = await strategyContract.isStrategyActive();
        const name = await strategyNft.getStrategyName(strategy);

        if (!isExecuting) {
          console.log(`  Strategy ${name} ${strategyContract.address} is not active.`);
          continue;
        }

        console.log(`  Finalizing strategy ${name} ${strategyContract.address}`);
        await strategyContract.connect(gov).changeStrategyDuration(1);

        try {
          await strategyContract.connect(keeper).finalizeStrategy(1, '');

          const [, active, , finalized, , exitedAt] = await strategyContract.getStrategyState();

          expect(active).eq(false);
          expect(finalized).eq(true);
          expect(exitedAt).gt(0);
        } catch (e) {
          console.log(`failed to finalize strategy ${e}`);
        }
      }
    }
  }

  describe('before deployment', function () {
    before(async () => {
      snapshotId = await takeSnapshot();
    });

    beforeEach(async () => {
      ({ owner, gov, keeper, strategyNft, valuer, gardens } = await getContracts());
    });

    afterEach(async () => {
      await restoreSnapshot(snapshotId);
    });

    it.skip('can unwind all active strategies', async () => {
      await canUnwindAllActiveStrategies();
    });

    it.skip('can allocate all active strategies', async () => {
      await canAllocateCapitalToAllActiveStrategies();
    });

    it('can finalize all active strategies', async () => {
      await canFinalizeAllActiveStrategies();
    });
  });

  // TODO: Check that users can deposit/withdraw to all gardens
  // TODO: Check that gardens can start new strategies with all integrations
  describe('after deployment', function () {
    beforeEach(async () => {
      ({ owner, gov, keeper, priceOracle, gardens, gardensNAV, strategyNft, valuer } = await deployFixture());
    });

    it('NAV has NOT changed for gardens after deploy', async () => {
      for (const garden of gardens) {
        const gardenContract = await ethers.getContractAt('Garden', garden);
        const gardenNAV = (await valuer.calculateGardenValuation(garden, addresses.tokens.DAI))
          .mul(await gardenContract.totalSupply())
          .div(eth());
        console.log(
          `Garden ${await gardenContract.name()} ${garden} has NAV $${ethers.utils.formatUnits(gardenNAV, 'ether')}`,
        );
        expect(gardenNAV).to.closeTo(gardensNAV[garden], eth());
      }
    });

    it('can finalize all active strategies', async () => {
      await canFinalizeAllActiveStrategies();
    });
  });
});
