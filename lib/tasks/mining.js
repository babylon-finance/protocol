const chalk = require('chalk');
const { task } = require('hardhat/config');
const { from, eth, formatNumber } = require('../helpers');
const { ONE_DAY_IN_SECONDS } = require('lib/constants');

function normalizeToken(amount) {
  return amount.div(ethers.utils.parseEther('0.001')).toNumber() / 1000;
  // return amount;
}

/* async function getEstimateBaselineRewards(strategy, distributor, rewards) {
    const returned = await strategy.getNAV();
    const allocated = await strategy.capitalAllocated();
    let ratio;
    const [, , , , executedAt, ,] = await strategy.getStrategyState();
    const block = await ethers.provider.getBlock();
    const now = block.timestamp;
    const timeDiff = now - executedAt;
    const timedAPY = ethers.BigNumber.from(ONE_DAY_IN_SECONDS * 365).div(ethers.BigNumber.from(timeDiff));
    let returnedAPY;
    if (returned >= allocated) {
      // profit
      returnedAPY = ethers.BigNumber.from(allocated).add(
        ethers.BigNumber.from(returned).sub(ethers.BigNumber.from(allocated)).mul(ethers.BigNumber.from(timedAPY)),
      );
    } else {
      returnedAPY = ethers.BigNumber.from(allocated)
        .sub(ethers.BigNumber.from(returned))
        .mul(ethers.BigNumber.from(timedAPY));
      returnedAPY =
        BigInt(returnedAPY) < BigInt(allocated)
          ? ethers.BigNumber.from(allocated).sub(ethers.BigNumber.from(returnedAPY))
          : 0;
    }

    const profit = ethers.BigNumber.from(returnedAPY)
      .mul(eth())
      .mul(eth())
      .div(ethers.BigNumber.from(allocated))
      .div(eth());
    const realProfit = ethers.BigNumber.from(returned)
      .mul(eth())
      .mul(eth())
      .div(ethers.BigNumber.from(allocated))
      .div(eth());
    const benchmark = await distributor.checkMining(1, strategy.address);

    if (BigInt(profit) < BigInt(benchmark[12])) {
      // Segment 1 : very bad strategies
      ratio = from(benchmark[14]);
    } else if (BigInt(profit) < BigInt(benchmark[13])) {
      // Segment 2: not cool strategies
      ratio = from(benchmark[15]);
    } else {
      // Segment 3: cool strategies
      ratio = from(benchmark[16]);
    }
    // return [ratio, realProfit];
  
    return rewards.div(benchmark[11].add(benchmark[12].mul(ratio).mul(realProfit)));
  } */

task('mining').setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
  const [deployer, owner] = await ethers.getSigners();

  const block = await ethers.provider.getBlock();
  const now = block.timestamp;
  // console.log('now', now);

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const distributor = await getContract('RewardsDistributor', 'RewardsDistributorProxy', owner);
  const strategyNft = await getContract('StrategyNFT', 'StrategyNFT', deployer);

  const gardens = await babController.getGardens();

  let totalRewards = from(0);
  let totalUnclaimedRewards = from(0);
  let totalEstimateRewards = from(0);
  let totalRealUnclaimedRewards = from(0); // We do not count strategist's if negative profit
  let totalRealEstimateRewards = from(0); // We do not count strategist's if negative profit
  let totalRealRewards = from(0); // We do not count strategist's if negative profit

  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('Garden', garden);
    const strategies = await gardenContract.getStrategies();
    const finalizedStrategies = await gardenContract.getFinalizedStrategies();
    /* console.log(strategies);
    console.log('');
    console.log(finalizedStrategies); */
    let gardenBABLRewards = from(0);
    let unclaimedRewards = from(0);
    let estimateRewards = from(0);
    let realGardenBABLRewards = from(0);
    let realUnclaimedRewards = from(0);
    let realEstimateRewards = from(0);
    for (const strategy of finalizedStrategies) {
      const strategyContract = await ethers.getContractAt('Strategy', strategy);
      const capitalAllocated = await strategyContract.capitalAllocated();
      const strategyNAV = await strategyContract.getNAV();
      const strategyReturned = await strategyContract.capitalReturned();
      const [, , , finalized, , ,] = await strategyContract.getStrategyState();
      const totalNegativeVotes = await strategyContract.totalNegativeVotes();
      const strategyName = await strategyNft.getStrategyName(strategy);
      if (finalized) {
        // Just check that we only get finalized strategies
        const strategist = await strategyContract.strategist();
        const creator = await gardenContract.creator();
        let rewards = await strategyContract.strategyRewards();
        unclaimedRewards = unclaimedRewards.add(rewards);
        if (BigInt(strategyReturned) >= BigInt(capitalAllocated)) {
          realUnclaimedRewards = realUnclaimedRewards.add(rewards);
        } else {
          if (BigInt(totalNegativeVotes) > 0) {
            // We do not sum the strategist 10% if negative profits
            // Stewards voting against the strategy will receive their 10% BABL for stewards
            rewards = rewards.mul(90).div(100);
            realUnclaimedRewards = realUnclaimedRewards.add(rewards);
          } else {
            // We do not sum the strategist 10% if negative profits
            // We also do not deliver stewards 10%, as there were not stewards voting against the strategy
            rewards = rewards.mul(80).div(100);
            realUnclaimedRewards = realUnclaimedRewards.add(rewards);
          }
        }
        // console.log('Unclaimed', strategyName, rewards.toString());
      }
    }

    for (const strategy of strategies) {
      const strategyContract = await ethers.getContractAt('Strategy', strategy);
      const capitalAllocated = await strategyContract.capitalAllocated();
      const strategyNAV = await strategyContract.getNAV();
      const strategyReturned = await strategyContract.capitalReturned();
      const [, , , finalized, , ,] = await strategyContract.getStrategyState();
      const totalNegativeVotes = await strategyContract.totalNegativeVotes();
      if (!finalized) {
        // Just check that we only get live strategies
        const strategist = await strategyContract.strategist();
        const creator = await gardenContract.creator();
        let strategyEstimateRewards = await distributor.estimateStrategyRewards(strategy);
        const strategyName = await strategyNft.getStrategyName(strategy);
        // const baselineRewards = await getEstimateBaselineRewards(strategy, distributor, strategyEstimateRewards);
        // console.log(strategyEstimateRewards.toString());
        // console.log(baselineRewards.toString());
        //console.log('strategy estimate rewards',strategyName, strategyEstimateRewards.toString());
        estimateRewards = estimateRewards.add(strategyEstimateRewards);
        if (BigInt(strategyNAV) >= BigInt(capitalAllocated)) {
          // console.log('positive profit', strategyNAV >= capitalAllocated, strategyNAV.toString(), capitalAllocated.toString());
          realEstimateRewards = realEstimateRewards.add(strategyEstimateRewards);
        } else {
          if (BigInt(totalNegativeVotes) > 0) {
            // We do not sum the strategist 10% if negative profits
            // Stewards voting against the strategy will receive their 10% BABL for stewards
            // console.log('negative profit + negative voters', strategyEstimateRewards.toString(), strategyEstimateRewards.mul(90).div(100).toString());
            strategyEstimateRewards = strategyEstimateRewards.mul(90).div(100);
            realEstimateRewards = realEstimateRewards.add(strategyEstimateRewards);
          } else {
            // We do not sum the strategist 10% if negative profits
            // We also do not deliver stewards 10%, as there were not stewards voting against the strategy
            // console.log('negative profit + all positive voters', strategyEstimateRewards.toString(), strategyEstimateRewards.mul(80).div(100).toString());
            strategyEstimateRewards = strategyEstimateRewards.mul(80).div(100);
            realEstimateRewards = realEstimateRewards.add(strategyEstimateRewards);
          }
        }
        // console.log('Estimate',strategyName, strategyEstimateRewards.toString());
        //console.log(strategyEstimateRewards.toString());
        // console.log('realEstimateRewards', realEstimateRewards.toString());
      }
    }
    // Total garden data
    console.log(`${await gardenContract.name()}`);
    console.log('  Potential rewards');
    console.log(`    Garden BABL unclaimed Rewards: ${chalk.green(normalizeToken(unclaimedRewards))} BABL`);
    console.log(`    Garden BABL estimated Rewards: ${chalk.cyan(normalizeToken(estimateRewards))} BABL`);

    gardenBABLRewards = unclaimedRewards.add(estimateRewards);
    realGardenBABLRewards = realUnclaimedRewards.add(realEstimateRewards);
    // Baseline rewards
    totalRewards = totalRewards.add(gardenBABLRewards);
    totalEstimateRewards = totalEstimateRewards.add(estimateRewards);
    totalUnclaimedRewards = totalUnclaimedRewards.add(unclaimedRewards);
    // Real rewards
    totalRealRewards = totalRealRewards.add(realGardenBABLRewards);
    totalRealEstimateRewards = totalRealEstimateRewards.add(realEstimateRewards);
    totalRealUnclaimedRewards = totalRealUnclaimedRewards.add(realUnclaimedRewards);

    console.log(`    Garden total BABL Rewards (baseline): ${chalk.blue(normalizeToken(gardenBABLRewards))} BABL`);

    console.log('');
    console.log('  Real rewards');
    console.log(`    Garden BABL unclaimed Rewards (real): ${chalk.green(normalizeToken(realUnclaimedRewards))} BABL`);
    console.log(`    Garden BABL estimated Rewards (real): ${chalk.cyan(normalizeToken(realEstimateRewards))} BABL`);
    console.log(`    Garden total BABL Rewards (real): ${chalk.blue(normalizeToken(realGardenBABLRewards))} BABL`);
  }
  console.log('Babylon Protocol');
  console.log(`  Total BABL unclaimed (baseline): ${chalk.green(normalizeToken(totalUnclaimedRewards))} BABL `);
  console.log(`  Total BABL pending (baseline): ${chalk.cyan(normalizeToken(totalEstimateRewards))} BABL `);
  console.log(`  Grand Total BABL (baseline): ${chalk.red(normalizeToken(totalRewards))} BABL 💰`);
  console.log('');
  console.log(`  Total BABL unclaimed (real): ${chalk.green(normalizeToken(totalRealUnclaimedRewards))} BABL `);
  console.log(`  Total BABL pending (real): ${chalk.cyan(normalizeToken(totalRealEstimateRewards))} BABL `);
  console.log(`  Grand Total BABL (real): ${chalk.blue(normalizeToken(totalRealRewards))} BABL 💰`);
});
