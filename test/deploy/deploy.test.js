const { expect } = require('chai');
// const { deployments } = require('hardhat');
const { getERC20, increaseTime, from } = require('utils/test-helpers');
// const { deploy } = deployments;
const { ONE_DAY_IN_SECONDS } = require('lib/constants');
const addresses = require('lib/addresses');
const { impersonateAddress } = require('lib/rpc');
const { takeSnapshot, restoreSnapshot } = require('lib/rpc');
const { eth } = require('lib/helpers');
const { getContracts, deployFixture } = require('lib/deploy');
const { ADDRESS_ZERO } = require('../../lib/constants');

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
  // '0x69B9a89083E2324079922e01557cAfb87cd90B09',
  // '0x22de22A50b00333159C54BFc1b9C0507e4759487',
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
      ({ owner, gov, keeper, priceOracle, strategyNft, valuer, gardens, distributor } = await getContracts());
    });

    afterEach(async () => {
      await restoreSnapshot(snapshotId);
    });

    it.skip('can unwind all active strategies', async () => {
      await canUnwindAllActiveStrategies();
    });

    it('can execute stuck proposals', async () => {
      await executeStuckStrategies();
    });

    it.skip('can allocate all active strategies', async () => {
      await canAllocateCapitalToAllActiveStrategies();
    });

    it('gets right NAV strategies', async () => {
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
      ({ owner, gov, keeper, gardens, gardensNAV, strategyNft, valuer, distributor, gnosis } = await deployFixture());
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

    it('gets right NAV strategies', async () => {
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

    it('can finalize heart strategies and compound rewards', async () => {
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
    it.only('getPastEvents for prophets staking', async () => {
      const provider = new ethers.providers.JsonRpcProvider();
      const abi = ['Stake(address indexed _owner, address indexed _target, uint256 _tokenId)'];
      const prophets = '0x26231A65EF80706307BbE71F032dc1e5Bf28ce43';
      const owner = await impersonateAddress('0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e');
      const prophetsContract = await ethers.getContractAt('IProphets', prophets, owner);
      let eventFilter = prophetsContract.filters.Stake();
      let events = await prophetsContract.queryFilter(eventFilter, 0, 13757641);
      // Dec 7th 2021 1638864000
      // Block Number 13757640 (Dec-07-2021 09:00:31 AM +UTC)
      const users = [];
      const prophetsid = [];
      const targets = [];
      const blockNumbers = []; 
      // Users left
      const usersLeft = [];
      const usersSoldProphet = [];
      const usersCancelStake = [];
      // console.log('events length', events.length.toString());
      // console.log('users', events[0]);
      for (let i = 0; i < events.length; i++) {
        // console.log('user %s', i, events[i].args._owner);
        let reStaked = false;
        const user = events[i].args._owner;
        const target = await ethers.getContractAt('IGarden', events[i].args._target, owner);
        const prophet = events[i].args._tokenId;
        const balance1 = await target.balanceOf(user);
        let balance2 = from(0);
        const prophetsAttr = await prophetsContract.getStakedProphetAttrs(user, target.address);
        if (prophetsAttr[6].gt(1638864000)) {
          // console.log('stake not valid - event after deadline Dec 7th', prophetsAttr[6].toString(), '1638864000', user);
          continue;
        }
        // check if still the owner 
        const newOwner = await prophetsContract.ownerOf(prophet);
        if (events[i].args._owner !== newOwner) {
          // User sold its prophet, such Stake event is not longer valid for original user
          usersSoldProphet.push(events[i].args._owner);
          continue;
        }
        const newTarget = await ethers.getContractAt('IGarden', await prophetsContract.targetOf(prophet), owner);
        if (newTarget.address === ADDRESS_ZERO) {
          // console.log('user re-staked into ZERO ADDRESS');
          usersCancelStake.push(events[i].args._owner);
          continue;
        }
        if (newTarget.address !== target.address) {
          // console.log('user re-staked prophet targets', target.address, newTarget.address);
          balance2 = await newTarget.balanceOf(user);
          // console.log('user re-staked prophet balances', balance1.toString(), balance2.toString());
          reStaked = true;
        }
        if (balance1.lte(eth(0.05)) && balance2.lte(eth(0.05))) {
          // console.log('user to be removed', user, balance1.toString(), balance2.toString());
          usersLeft.push(events[i].args._owner);
          continue;
        }
        console.log('%s block %s user %s id %s restaked? %s garden %s bal1 %s bal2 %s', i, events[i].blockNumber, events[i].args._owner, prophet, reStaked, reStaked ? newTarget.address : target.address, balance1.toString(), balance2.toString());
        users.push(events[i].args._owner);
        prophetsid.push(prophet);
        targets.push(reStaked ? newTarget.address : target.address);
        blockNumbers.push(events[i].blockNumber);
      }
      console.log('users staking prophet correctly', ...users);
      console.log('prophets staked correctly', prophetsid.toString());
      console.log('targets of correct staking', targets);
      console.log('blockNumbers', blockNumbers.toString());
      console.log('');
      console.log('users left withdrawing all balance', usersLeft);
      console.log('');
      console.log('users sold prophet', usersSoldProphet);
      console.log('');
      console.log('users cancel stake (address(0))', usersCancelStake);
    });
  });
});
