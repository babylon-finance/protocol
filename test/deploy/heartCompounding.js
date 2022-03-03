const { expect } = require('chai');
const addresses = require('lib/addresses');
const { impersonateAddress } = require('lib/rpc');
const { takeSnapshot, restoreSnapshot } = require('lib/rpc');
const { fund } = require('lib/whale');
const { eth } = require('lib/helpers');
const { getContracts, deployFixture } = require('lib/deploy');
const { increaseTime, getERC20 } = require('../utils/test-helpers');
const {
  createStrategy,
  executeStrategy,
  injectFakeProfits,
  finalizeStrategyAfterQuarter,
} = require('fixtures/StrategyHelper.js');
const { ONE_DAY_IN_SECONDS } = require('../../lib/constants');

describe('Heart Compounding', function () {
  let owner;
  let gov;
  let keeper;
  let distributor;
  let gardens;
  let heartGarden;
  let masterSwapper;
  let strategyNft;
  let gardensNAV;
  let snapshotId;
  let gnosis;
  let ramon;
  let raul;
  let bablToken;
  let valuer;

  async function createStrategies(strategies) {
    const retVal = [];
    for (let i = 0; i < strategies.length; i++) {
      const strategy = await createStrategy(
        'buy',
        'vote',
        [gnosis, ramon, raul],
        masterSwapper.address,
        strategies[i].garden,
        keeper,
      );
      retVal.push(strategy);
    }
    return retVal;
  }

  describe.only('heart compounding after deployment', function () {
    beforeEach(async () => {
      ({
        owner,
        gov,
        keeper,
        distributor,
        gardens,
        strategyNft,
        heartGarden,
        masterSwapper,
        gnosis,
        valuer,
      } = await deployFixture());

      ramon = await impersonateAddress('0xc31c4549356d46c37021393eeeb6f704b38061ec');
      raul = await impersonateAddress('0x166D00d97AF29F7F6a8cD725F601023b843ade66');
      bablToken = await getERC20('0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74');

      await fund([ramon.address, raul.address], {
        tokens: [addresses.tokens.BABL],
      });
    });

    it('can NOT claim rewards in Heart Garden (they are zero per user)', async () => {
      const [long1] = await createStrategies([{ garden: heartGarden }]);
      await executeStrategy(long1, { amount: eth(), executedBy: keeper });
      increaseTime(ONE_DAY_IN_SECONDS * 55);
      await injectFakeProfits(long1, eth().mul(200));
      const estimatedGnosisBABL1 = await distributor.estimateUserRewards(long1.address, gnosis.address);
      const getRewardsGnosisBABL1 = await distributor.getRewards(heartGarden.address, gnosis.address, [long1.address]);
      const estimatedRamonBABL1 = await distributor.estimateUserRewards(long1.address, ramon.address);
      const getRewardsRamonBABL1 = await distributor.getRewards(heartGarden.address, ramon.address, [long1.address]);
      await finalizeStrategyAfterQuarter(long1, { keeper });
      const estimatedGnosisBABL2 = await distributor.estimateUserRewards(long1.address, gnosis.address);
      const getRewardsGnosisBABL2 = await distributor.getRewards(heartGarden.address, gnosis.address, [long1.address]);
      const estimatedRamonBABL2 = await distributor.estimateUserRewards(long1.address, ramon.address);
      const getRewardsRamonBABL2 = await distributor.getRewards(heartGarden.address, ramon.address, [long1.address]);
      expect(estimatedGnosisBABL1[0]).to.be.gt(0);
      expect(estimatedGnosisBABL1[1]).to.be.gt(0);
      expect(estimatedGnosisBABL1[2]).to.be.gt(0);
      expect(estimatedGnosisBABL1[3]).to.be.gt(0);
      expect(estimatedGnosisBABL1[4]).to.be.gt(0);
      expect(estimatedGnosisBABL1[5]).to.be.gt(0);
      expect(estimatedGnosisBABL1[6]).to.be.gt(0);
      expect(estimatedGnosisBABL1[7]).to.be.gt(0);
      expect(getRewardsGnosisBABL1[0]).to.be.eq(0);
      expect(getRewardsGnosisBABL1[1]).to.be.eq(0);
      expect(getRewardsGnosisBABL1[2]).to.be.eq(0);
      expect(getRewardsGnosisBABL1[3]).to.be.eq(0);
      expect(getRewardsGnosisBABL1[4]).to.be.eq(0);
      expect(getRewardsGnosisBABL1[5]).to.be.eq(0);
      expect(getRewardsGnosisBABL1[6]).to.be.eq(0);
      expect(getRewardsGnosisBABL1[7]).to.be.eq(0);
      // After finishing the strategy
      expect(estimatedGnosisBABL2[0]).to.be.eq(0);
      expect(estimatedGnosisBABL2[1]).to.be.eq(0);
      expect(estimatedGnosisBABL2[2]).to.be.eq(0);
      expect(estimatedGnosisBABL2[3]).to.be.eq(0);
      expect(estimatedGnosisBABL2[4]).to.be.eq(0);
      expect(estimatedGnosisBABL2[5]).to.be.eq(0);
      expect(estimatedGnosisBABL2[6]).to.be.eq(0);
      expect(estimatedGnosisBABL2[7]).to.be.eq(0);
      expect(getRewardsGnosisBABL2[0]).to.be.eq(0);
      expect(getRewardsGnosisBABL2[1]).to.be.eq(0);
      expect(getRewardsGnosisBABL2[2]).to.be.eq(0);
      expect(getRewardsGnosisBABL2[3]).to.be.eq(0);
      expect(getRewardsGnosisBABL2[4]).to.be.eq(0);
      expect(getRewardsGnosisBABL2[5]).to.be.eq(0);
      expect(getRewardsGnosisBABL2[6]).to.be.eq(0);
      expect(getRewardsGnosisBABL2[7]).to.be.eq(0);
      // Ramon
      expect(estimatedRamonBABL1[0]).to.be.eq(0); // No strategist BABL
      expect(estimatedRamonBABL1[1]).to.be.eq(0); // No strategist profits
      expect(estimatedRamonBABL1[2]).to.be.gt(0);
      expect(estimatedRamonBABL1[3]).to.be.gt(0);
      expect(estimatedRamonBABL1[4]).to.be.gt(0);
      expect(estimatedRamonBABL1[5]).to.be.gt(0);
      expect(estimatedRamonBABL1[6]).to.be.gt(0);
      expect(estimatedRamonBABL1[7]).to.be.eq(0); // No garden creator BABL bonus
      expect(getRewardsRamonBABL1[0]).to.be.eq(0);
      expect(getRewardsRamonBABL1[1]).to.be.eq(0);
      expect(getRewardsRamonBABL1[2]).to.be.eq(0);
      expect(getRewardsRamonBABL1[3]).to.be.eq(0);
      expect(getRewardsRamonBABL1[4]).to.be.eq(0);
      expect(getRewardsRamonBABL1[5]).to.be.eq(0);
      expect(getRewardsRamonBABL1[6]).to.be.eq(0);
      expect(getRewardsRamonBABL1[7]).to.be.eq(0);
      // After finishing strategy -> equals 0
      expect(estimatedRamonBABL2[0]).to.be.eq(0);
      expect(estimatedRamonBABL2[1]).to.be.eq(0);
      expect(estimatedRamonBABL2[2]).to.be.eq(0);
      expect(estimatedRamonBABL2[3]).to.be.eq(0);
      expect(estimatedRamonBABL2[4]).to.be.eq(0);
      expect(estimatedRamonBABL2[5]).to.be.eq(0);
      expect(estimatedRamonBABL2[6]).to.be.eq(0);
      expect(estimatedRamonBABL2[7]).to.be.eq(0);
      expect(getRewardsRamonBABL2[0]).to.be.eq(0);
      expect(getRewardsRamonBABL2[1]).to.be.eq(0);
      expect(getRewardsRamonBABL2[2]).to.be.eq(0);
      expect(getRewardsRamonBABL2[3]).to.be.eq(0);
      expect(getRewardsRamonBABL2[4]).to.be.eq(0);
      expect(getRewardsRamonBABL2[5]).to.be.eq(0);
      expect(getRewardsRamonBABL2[6]).to.be.eq(0);
      expect(getRewardsRamonBABL2[7]).to.be.eq(0);
    });
    it('all rewards (BABL profit and BABL mining) are auto-compounded in the heart garden', async () => {
      const [long1] = await createStrategies([{ garden: heartGarden }]);
      const hBABLSupply1 = await heartGarden.totalSupply();
      const gardenNAV1 = await valuer.calculateGardenValuation(heartGarden.address, addresses.tokens.BABL);
      await executeStrategy(long1, { amount: eth(100), executedBy: keeper });
      const hBABLSupply2 = await heartGarden.totalSupply();
      const gardenNAV2 = await valuer.calculateGardenValuation(heartGarden.address, addresses.tokens.BABL);
      increaseTime(ONE_DAY_IN_SECONDS * 55);
      await injectFakeProfits(long1, eth().mul(200));
      const gardenBalanceInReserve3 = await bablToken.balanceOf(heartGarden.address);
      const hBABLSupply3 = await heartGarden.totalSupply();
      const gardenNAV3 = await valuer.calculateGardenValuation(heartGarden.address, addresses.tokens.BABL);
      await finalizeStrategyAfterQuarter(long1, { keeper });
      const capitalReturnedLong4 = await long1.capitalReturned();
      const hBABLSupply4 = await heartGarden.totalSupply();
      const gardenBalanceInReserve4 = await bablToken.balanceOf(heartGarden.address);
      const strategyRewards = await long1.strategyRewards();
      const reserveAssetRewardsSetAsideLong1 = await heartGarden.reserveAssetRewardsSetAside();
      const gardenNAV4 = await valuer.calculateGardenValuation(heartGarden.address, addresses.tokens.BABL);
      expect(gardenBalanceInReserve4).to.be.closeTo(
        gardenBalanceInReserve3.add(capitalReturnedLong4).add(strategyRewards),
        gardenBalanceInReserve3.div(100),
      );
      expect(reserveAssetRewardsSetAsideLong1).to.eq(0);
      expect(gardenNAV2).to.be.gt(gardenNAV1);
      expect(gardenNAV3).to.be.gt(gardenNAV2).to.be.gt(gardenNAV1);
      expect(gardenNAV4).to.be.gt(gardenNAV3).to.be.gt(gardenNAV2).to.be.gt(gardenNAV1);
      expect(hBABLSupply4).to.be.eq(hBABLSupply3).to.be.eq(hBABLSupply2).to.be.eq(hBABLSupply1);
    });
  });
});
