const { expect } = require('chai');
const { deployments } = require('hardhat');

const { impersonateAddress } = require('lib/rpc');
const { ONE_DAY_IN_SECONDS } = require('lib/constants.js');
const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const { from, parse, eth } = require('lib/helpers');
const { getContracts, deployFixture } = require('lib/deploy');
const { increaseTime } = require('utils/test-helpers');

const { deploy } = deployments;

describe('deploy', function () {
  let owner;
  let keeper;
  let priceOracle;
  let gardens;
  let strategyNft;
  let valuer;
  let gardensNAV;

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
          console.log(`Strategy ${name} ${strategyContract.address} is not active.`);
          continue;
        }

        console.log(`Finalizing strategy ${name} ${strategyContract.address}`);

        await increaseTime(ONE_DAY_IN_SECONDS * 360);

        try {
          await strategyContract.connect(keeper).finalizeStrategy(0, '');

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
    beforeEach(async () => {
      ({ owner, keeper, strategyNft, valuer, gardens } = await getContracts());
    });

    it.only('can finalize all active strategies', async () => {
      await canFinalizeAllActiveStrategies();
    });
  });

  // TODO: Check that NAV is not changed after deploy
  // TODO: Check that users can deposit/withdraw to all gardens
  // TODO: Check that gardens can start new strategies with all integrations
  describe('after deployment', function () {
    beforeEach(async () => {
      ({ owner, keeper, priceOracle, gardens, gardensNAV, strategyNft, valuer } = await deployFixture());
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

    it.skip('can finalize all active strategies', async () => {
      await canFinalizeAllActiveStrategies();
    });
  });
});
