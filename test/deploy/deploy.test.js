const { expect } = require('chai');
// const { deployments } = require('hardhat');
// const { increaseTime } = require('utils/test-helpers');
// const { deploy } = deployments;
const addresses = require('lib/addresses');
const { impersonateAddress } = require('lib/rpc');
const { takeSnapshot, restoreSnapshot } = require('lib/rpc');
const { eth } = require('lib/helpers');
const { getContracts, deployFixture } = require('lib/deploy');

const STUCK = [
  // '0x69ef15D3a4910EDc47145f6A88Ae60548F5AbC2C',
  // '0xcd9498b4160568DeEAb0fE3A0De739EbF152CB48',
  // '0xE064ad71dc506130A4C1C85Fb137606BaaCDe9c0', // Long BED
  // '0x702c284Cd32F842bE450f5e5C9DE48f14303F1C8', // Long TOKE. Reason: Error: execution reverted: BAB#098
  // '0x5fF64AB324806aBDb8902Ff690B90a078D36CCe1', // Long wbtc, borrow DAI, long CDT. Reason: Error: execution reverted: Master swapper could not swap

  // '0x81b1C6A04599b910e33b1AB549DE4a19E5701838', // Lend wbtc, borrow dai, yield yearn dai. Reason: Error: execution reverted: Curve Swap failed midway
  // '0xc38E5828c1c84F4687f2080c0C8d2e4a89695A11', // Long eth, borrow dai, steth crv convex. Reason: Error: execution reverted: The garden did not receive the investment tokens
  // '0x3be1008317F3aAC19Bf7a0b370465fbEF884F4ED', // ✅ Not Enough Capital or other keeper logic. ICELong
  // '0x6F854a988577Ce994926a8979881E6a18E6a70dF', // ✅ Not Enough Capital or other keeper logic. lend wbtc, borrow dai, long LDO. Reason: Error: execution reverted: Curve Swap failed midway
  // '0x19C54aDcfAB5a3608540130418580176d325c1F9', // ✅ Eth 3x. Reason: Error: execution reverted: Address: low-level call with value failed -> No liquidity
  // '0x628c3134915D3d8c5073Ed8F618BCE1631b82416', // ETH + AXS
  // '0xfd6B47DE3E02A6f3264EE5d274010b9f9CfB1BC5', // IB Curve
  // '0xc24827322127Ae48e8893EE3041C668a94fBcDA8'  // IB Forever
  // '0xE064ad71dc506130A4C1C85Fb137606BaaCDe9c0', // Long BED Red Pill
  // '0xfd6b47de3e02a6f3264ee5d274010b9f9cfb1bc5', // Iron Bank Curve Pool
  '0x69B9a89083E2324079922e01557cAfb87cd90B09',
];

describe('deploy', function () {
  let owner;
  let gov;
  let keeper;
  let gardens;
  let strategyNft;
  let valuer;
  let gardensNAV;
  let snapshotId;

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

      await strategyContract.connect(keeper).finalizeStrategy(1, '', 0);

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

  async function finalizeStuckStrategies() {
    const strategies = STUCK;
    for (const strategy of strategies) {
      const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);
      const gardenContract = await ethers.getContractAt('IGarden', strategyContract.garden());
      const reserveAsset = await gardenContract.reserveAsset();
      const name = await strategyNft.getStrategyName(strategy);
      await finalizeStrategy(strategyContract, name, reserveAsset);
    }
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
      ({ owner, gov, keeper, strategyNft, valuer, gardens } = await getContracts());
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

    it.only('gets right NAV strategies', async () => {
      await getStrategyFuseRewards('0x69B9a89083E2324079922e01557cAfb87cd90B09');
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
      ({ owner, gov, keeper, gardens, gardensNAV, strategyNft, valuer } = await deployFixture());
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

    it.only('gets right NAV strategies', async () => {
      await getStrategyFuseRewards('0x69B9a89083E2324079922e01557cAfb87cd90B09');
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

    it('can finalize stuck strategies', async () => {
      await finalizeStuckStrategies();
    });
  });
});
