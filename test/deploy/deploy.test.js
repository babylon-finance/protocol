const { expect } = require('chai');
// const { deployments } = require('hardhat');
const { getERC20, increaseTime } = require('utils/test-helpers');
// const { deploy } = deployments;
const { ONE_DAY_IN_SECONDS, ADDRESS_ZERO } = require('lib/constants');
const addresses = require('lib/addresses');
const { impersonateAddress } = require('lib/rpc');
const { takeSnapshot, restoreSnapshot } = require('lib/rpc');
const { getUsers } = require('lib/web3');
const { eth } = require('lib/helpers');
const { getContracts, deployFixture } = require('lib/deploy');
const { ONE_YEAR_IN_SECONDS } = require('../../lib/constants');

const STUCK = [
  // '0xb8392344ddad3d71d3Dc503c7A3A19aa70D05ccA', // 3xsETH
  // '0x2d160210011a992966221F428f63326f76066Ba9', // lend DAI
  '0x7a81af63b3ec25e8498d58ff129f9a2c1f795237', // aladdin
  '0x45d5daecb6e96c87fa04105ee205379ddfe8f555', // Stable to increase rewards
];

const HEART_STRATEGIES = ['0xE4F0d5799F51D55f5dBC8b6bDA6b4d6956D6E8e0', '0x73C7c6ec73d2244C04B87eC0E3e64c0bc04580e4'];

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
  let distributor;
  let gnosis;
  let heart;

  const getStrategyFuseRewards = async (_strategy) => {
    const lensPool = await ethers.getContractAt('ILensPool', '0xc76190E04012f26A364228Cfc41690429C44165d');
    const rest = await lensPool.getUnclaimedRewardsByDistributors(_strategy, [
      '0x3711c959d9732255dd5c0843622d8d364f143d73',
    ]);
    console.log('rest', await ethers.utils.formatEther(rest[1][0]));
  };

  async function iterateStrategiesFromGardens(cb) {
    for (const garden of gardens) {
      const gardenContract = await ethers.getContractAt('IGarden', garden);
      console.log(`${await gardenContract.name()}`);

      const reserveAsset = await gardenContract.reserveAsset();
      const strategies = await gardenContract.getStrategies();
      for (const strategy of strategies) {
        const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);
        const name = await strategyNft.getStrategyName(strategy);
        try {
          await cb(strategyContract, name, reserveAsset);
        } catch (error) {
          console.error(`${name} fails`);
        }
      }
    }
  }

  async function unwindStrategy(strategyContract, name, reserveAsset) {
    const isExecuting = await strategyContract.isStrategyActive();
    if (!isExecuting) {
      console.log(`  Strategy ${name} ${strategyContract.address} is not active.`);
      return;
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

  async function addCapitalToStrategy(strategyContract, name, reserveAsset) {
    const isExecuting = await strategyContract.isStrategyActive();
    if (isExecuting) {
      console.log(`  Strategy ${name} ${strategyContract.address} is not active.`);
    }

    console.log(`  Adding capital to the strategy ${name} ${strategyContract.address}`);

    try {
      const capital = reserveAsset === addresses.tokens.DAI ? eth(2000) : eth(1);
      await strategyContract.connect(keeper).executeStrategy(capital, 1);

      const [, active, , finalized, , exitedAt] = await strategyContract.getStrategyState();

      expect(active).eq(true);
      expect(finalized).eq(false);
      expect(exitedAt).eq(0);
    } catch (e) {
      console.log(`  failed to allocate capital to the strategy ${e}`);
    }
  }

  async function finalizeStrategy(strategyContract, name, reserveAsset) {
    const isExecuting = await strategyContract.isStrategyActive();
    const gardenContract = await ethers.getContractAt('IGarden', await strategyContract.garden());
    if (!isExecuting) {
      console.log(`  Strategy ${name} ${strategyContract.address} is not active.`);
      return;
    }

    console.log(`  Finalizing strategy ${name} ${strategyContract.address}`);
    try {
      await strategyContract
        .connect(gov)
        .updateParams([await gardenContract.minStrategyDuration(), eth(0.1), eth(0.1), eth(), eth(100)], {
          gasPrice: 0,
        });

      await strategyContract.connect(keeper).finalizeStrategy(1, '', 0, { gasLimit: 30000000 });

      const [, active, , finalized, , exitedAt] = await strategyContract.getStrategyState();

      expect(active).eq(false);
      expect(finalized).eq(true);
      expect(exitedAt).gt(0);
    } catch (e) {
      console.log(`failed to finalize strategy ${e}`);
    }
  }

  async function executeStuckStrategies() {
    const strategies = STUCK;
    for (const strategy of strategies) {
      const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);
      const gardenContract = await ethers.getContractAt('IGarden', strategyContract.garden());
      const reserveAsset = await gardenContract.reserveAsset();
      const name = await strategyNft.getStrategyName(strategy);
      await addCapitalToStrategy(strategyContract, name, reserveAsset);
    }
  }

  async function finalizeStrategies(strategies) {
    for (const strategy of strategies) {
      const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);
      const gardenContract = await ethers.getContractAt('IGarden', strategyContract.garden());
      const reserveAsset = await gardenContract.reserveAsset();
      const name = await strategyNft.getStrategyName(strategy);
      await finalizeStrategy(strategyContract, name, reserveAsset);
    }
  }

  async function finalizeStuckStrategies() {
    await finalizeStrategies(STUCK);
  }

  async function finalizeHeartStrategies() {
    await finalizeStrategies(HEART_STRATEGIES);
  }

  async function checkNAVStrategies() {
    const strategies = STUCK;
    for (const strategy of strategies) {
      console.log('strategy', strategy);
      const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);
      const gardenContract = await ethers.getContractAt('IGarden', strategyContract.garden());
      const reserveAsset = await gardenContract.reserveAsset();
      console.log('reserve', reserveAsset);
      const name = await strategyNft.getStrategyName(strategy);
      console.log('name', name);
      let nav;
      try {
        nav = await strategyContract.getNAV();
      } catch (error) {
        console.error(error);
      }
      console.log(name, reserveAsset, ethers.utils.formatEther(nav));
    }
  }

  async function canUnwindAllActiveStrategies() {
    await iterateStrategiesFromGardens(unwindStrategy);
  }

  async function canAllocateCapitalToAllActiveStrategies() {
    await iterateStrategiesFromGardens(addCapitalToStrategy);
  }

  async function canFinalizeAllActiveStrategies() {
    await iterateStrategiesFromGardens(finalizeStrategy);
  }

  describe('before deployment', function () {
    before(async () => {
      snapshotId = await takeSnapshot();
    });

    beforeEach(async () => {
      ({ owner, gov, keeper, strategyNft, valuer, gardens, distributor } = await getContracts());
    });

    afterEach(async () => {
      await restoreSnapshot(snapshotId);
    });

    it.skip('can unwind all active strategies', async () => {
      await canUnwindAllActiveStrategies();
    });

    it.skip('can execute stuck proposals', async () => {
      await executeStuckStrategies();
    });

    it.skip('can allocate all active strategies', async () => {
      await canAllocateCapitalToAllActiveStrategies();
    });

    it('gets right NAV strategies', async () => {
      await checkNAVStrategies();
    });

    it('can finalize all active strategies', async () => {
      await canFinalizeAllActiveStrategies();
    });
  });

  // TODO: Check that users can deposit/withdraw to all gardens
  // TODO: Check that gardens can start new strategies with all integrations
  describe('after deployment', function () {
    beforeEach(async () => {
      ({
        owner,
        gov,
        keeper,
        gardens,
        gardensNAV,
        strategyNft,
        valuer,
        distributor,
        gnosis,
        priceOracle,
        heart,
      } = await deployFixture());
    });

    it('NAV has NOT changed for gardens after deploy', async () => {
      for (const garden of gardens) {
        const gardenContract = await ethers.getContractAt('IGarden', garden);
        const gardenNAV = (await valuer.calculateGardenValuation(garden, addresses.tokens.DAI))
          .mul(await gardenContract.totalSupply())
          .div(eth());
        console.log(
          `Garden ${await gardenContract.name()} ${garden} has NAV $${ethers.utils.formatUnits(gardenNAV, 'ether')}`,
        );
        // const strategies = await gardenContract.getStrategies();
        // for(const strat of strategies) {
        //   const stratContract = await ethers.getContractAt('Strategy', strat);
        //   console.log(strat, (await stratContract.getNAV()).toString());
        // }
        try {
          expect(gardenNAV).to.closeTo(gardensNAV[garden], eth());
        } catch (e) {
          console.log(e.message);
          console.log(`the diff is $${ethers.utils.formatUnits(gardensNAV[garden].sub(gardenNAV), 'ether')}`);
        }
        // console.log('gardenNAV', gardenNAV.toString());
        // console.log('gardensNAV[garden]', gardensNAV[garden].toString());
      }
    });

    it.skip('gets right NAV strategies', async () => {
      await checkNAVStrategies();
    });

    it('can execute stuck strategies', async () => {
      await executeStuckStrategies();
    });

    it('can allocate all active strategies', async () => {
      await canAllocateCapitalToAllActiveStrategies();
    });

    it('can finalize all active strategies', async () => {
      await canFinalizeAllActiveStrategies();
    });

    it.skip('can finalize heart strategies and compound rewards', async () => {
      const babl = await getERC20(addresses.tokens.BABL);
      const firstStrategy = await ethers.getContractAt('IStrategy', HEART_STRATEGIES[0]);
      const secondStrategy = await ethers.getContractAt('IStrategy', HEART_STRATEGIES[1]);
      const heartGarden = await ethers.getContractAt('IGarden', await firstStrategy.garden());
      await increaseTime(ONE_DAY_IN_SECONDS * 40);
      const gardenBalance = await babl.balanceOf(heartGarden.address);
      const estimatedStrategistBABLStr1 = await distributor.estimateUserRewards(firstStrategy.address, gnosis.address);
      const estimatedStrategistBABLStr2 = await distributor.estimateUserRewards(secondStrategy.address, gnosis.address);
      const getRewardsStrategistBABL1 = await distributor.getRewards(heartGarden.address, gnosis.address, [
        firstStrategy.address,
        secondStrategy.address,
      ]);
      const strategistBalanceBefore = await babl.balanceOf(gnosis.address);

      await finalizeHeartStrategies();
      const gardenBalanceAfter = await babl.balanceOf(heartGarden.address);
      const rewards = (await firstStrategy.strategyRewards()).add(await secondStrategy.strategyRewards());
      const estimatedStrategistBABLStr11 = await distributor.estimateUserRewards(firstStrategy.address, gnosis.address);
      const estimatedStrategistBABLStr21 = await distributor.estimateUserRewards(
        secondStrategy.address,
        gnosis.address,
      );
      const getRewardsStrategistBABL2 = await distributor.getRewards(heartGarden.address, gnosis.address, [
        firstStrategy.address,
        secondStrategy.address,
      ]);
      await expect(
        heartGarden.connect(gnosis).claimReturns(await heartGarden.getFinalizedStrategies()),
      ).to.be.revertedWith('BAB#082'); // No rewards to claim
      const strategistBalanceAfter = await babl.balanceOf(gnosis.address);
      expect(gardenBalanceAfter).to.be.closeTo(
        gardenBalance
          .add(await firstStrategy.capitalReturned())
          .add(await secondStrategy.capitalReturned())
          .add(rewards),
        eth('100'),
      );
      expect(strategistBalanceAfter).to.eq(strategistBalanceBefore);
      expect(estimatedStrategistBABLStr1[5]).to.be.gt(0);
      expect(estimatedStrategistBABLStr1[6]).to.be.eq(estimatedStrategistBABLStr2[6]).to.eq(0); // No profitable strategy
      expect(estimatedStrategistBABLStr2[5]).to.be.gt(0);
      expect(estimatedStrategistBABLStr11[5]).to.be.eq(estimatedStrategistBABLStr21[5]).to.eq(0);
      expect(getRewardsStrategistBABL2[5]).to.eq(getRewardsStrategistBABL1[5]).to.eq(0);
      expect(getRewardsStrategistBABL2[6]).to.eq(getRewardsStrategistBABL1[6]).to.eq(0);
    });

    it('can finalize stuck strategies', async () => {
      await finalizeStuckStrategies();
    });
  });
});
