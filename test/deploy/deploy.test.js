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
    // for (const garden of gardens) {
    // const gardenContract = await ethers.getContractAt('Garden', garden);
    // console.log(`${await gardenContract.name()}`);
    // Fixes: 0x69ef15D3a4910EDc47145f6A88Ae60548F5AbC2C

    const strategies = [
      // '0x69ef15D3a4910EDc47145f6A88Ae60548F5AbC2C',
      '0xcd9498b4160568DeEAb0fE3A0De739EbF152CB48',
      // '0x3FeaD42999D537477CE39335aA7b4951e8e78233',
      // '0x9D78319EDA31663B487204F0CA88A046e742eE16',
      // '0x4f85dD417d19058cA81564f41572fb90D2F7e935',
      // '0xFDeA6F30F3dadD60382bAA07252923Ff6007c35d',
      // '0xc38E5828c1c84F4687f2080c0C8d2e4a89695A11',
      // '0x9f794DD83E2C815158Fc290c3c2b20f8B6605746',
    ];
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

      const strategyC = await impersonateAddress(strategy);
      const rewards = await ethers.getContractAt('IBasicRewards', '0x0A760466E1B4621579a82a39CB56Dda2F4E70f03', owner);
      const booster = await ethers.getContractAt('IBooster', '0xf403c135812408bfbe8713b5a23a04b3d48aae31', owner);
      await rewards.connect(strategyC).withdrawAll(true, { gasPrice: 0 });
      await booster.connect(strategyC).withdrawAll(25, { gasPrice: 0 });
      //
      // await strategyContract.connect(keeper).finalizeStrategy(0, '');
      // const [, active, , finalized, , exitedAt] = await strategyContract.getStrategyState();
      // expect(active).eq(false);
      // expect(finalized).eq(true);
      // expect(exitedAt).gt(0);
    }
    // }
  }

  describe('before deployment', function () {
    beforeEach(async () => {
      ({ owner, keeper, strategyNft, valuer, gardens } = await getContracts());
    });

    it.skip('can finalize all active strategies', async () => {
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

    it.only('can finalize all active strategies', async () => {
      await canFinalizeAllActiveStrategies();
    });
  });
});
