const chalk = require('chalk');
const { task } = require('hardhat/config');
const { from, eth, formatNumber, formatUnit } = require('../helpers');
const { ONE_DAY_IN_SECONDS } = require('lib/constants');

function getEstimateBaselineRewards(now, returned, allocated, executedAt, updatedAt, benchmark, distributor, rewards) {
  let ratio;
  const timeDiff = now - executedAt;
  const timedAPY = from(ONE_DAY_IN_SECONDS * 365).div(from(timeDiff > 0 ? timeDiff : 1));

  let returnedAPY;
  if (returned >= allocated) {
    // profit
    returnedAPY = from(allocated).add(from(returned).sub(from(allocated)).mul(from(timedAPY)));
  } else {
    // loses
    returnedAPY = from(allocated).sub(from(returned)).mul(from(timedAPY));
    returnedAPY = returnedAPY.lt(allocated) ? from(allocated).sub(from(returnedAPY)) : 0;
  }
  const profit = from(returnedAPY).mul(eth()).mul(eth()).div(from(allocated)).div(eth());
  const realProfit = from(returned).mul(eth()).mul(eth()).div(from(allocated)).div(eth());

  if (profit.lt(benchmark[12])) {
    // Segment 1 : very bad strategies
    ratio = from(benchmark[14]);
  } else if (profit.lt(benchmark[13])) {
    // Segment 2: not cool strategies
    ratio = from(benchmark[15]);
  } else {
    // Segment 3: cool strategies
    ratio = from(benchmark[16]);
  }
  const numerator = from(rewards);
  const denominator = from(benchmark[11]).add(
    from(benchmark[12]).mul(from(ratio)).mul(eth()).mul(from(realProfit)).div(eth()).div(eth()).div(eth()),
  );
  const result = numerator.mul(eth()).mul(eth()).div(denominator).div(eth());
  return result;
}

task('mining').setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
  const [deployer, owner] = await ethers.getSigners();

  const block = await ethers.provider.getBlock();
  const now = block.timestamp;

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const distributor = await getContract('RewardsDistributor', 'RewardsDistributorProxy', owner);
  const strategyNft = await getContract('StrategyNFT', 'StrategyNFT', deployer);
  const token = await ethers.getContractAt('BABLToken', '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74', deployer);
  const heartGarden = await ethers.getContractAt('IGarden', '0xaA2D49A1d66A58B8DD0687E730FefC2823649791', deployer);
  const gardens = await babController.getGardens();

  let totalRewards = from(0);
  let totalUnclaimedRewards = from(0);
  let totalEstimateRewards = from(0);
  let totalRealUnclaimedRewards = from(0); // We do not count strategist's if negative profit
  let totalRealEstimateRewards = from(0); // We do not count strategist's if negative profit
  let totalRealRewards = from(0); // We do not count strategist's if negative profit
  let totalBaseline = from(0);
  let totalHeartRewardsFinalized = from(0);
  let totalHeartRewardsPending = from(0);
  let capitalAllocatedHeartStrategies = from(0);
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('IGarden', garden);
    const strategies = await gardenContract.getStrategies();
    const finalizedStrategies = await gardenContract.getFinalizedStrategies();
    let gardenBABLRewards = from(0);
    let unclaimedRewards = from(0);
    let estimateRewards = from(0);
    let realGardenBABLRewards = from(0);
    let realUnclaimedRewards = from(0);
    let realEstimateRewards = from(0);
    let gardenBaselineRewards = from(0);
    for (const strategy of finalizedStrategies) {
      // Finalized strategies
      const strategyContract = await ethers.getContractAt('Strategy', strategy);
      const capitalAllocated = await strategyContract.capitalAllocated();
      const strategyReturned = await strategyContract.capitalReturned();
      const [, , , finalized, , ,] = await strategyContract.getStrategyState();
      const totalNegativeVotes = await strategyContract.totalNegativeVotes();

      if (finalized) {
        // Just check that we only get finalized strategies
        let rewards = await strategyContract.strategyRewards();
        const baselineRewards = rewards; // As there were different weight changes by bip 1 and 7 we assume baseline to become real one here
        unclaimedRewards = unclaimedRewards.add(rewards);
        gardenBaselineRewards = gardenBaselineRewards.add(baselineRewards);
        if (garden === heartGarden.address) {
          totalHeartRewardsFinalized = totalHeartRewardsFinalized.add(rewards);
        }
        if (strategyReturned.gte(capitalAllocated)) {
          realUnclaimedRewards = realUnclaimedRewards.add(rewards);
        } else {
          if (totalNegativeVotes.gt(0)) {
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
      }
    }
    for (const strategy of strategies) {
      // Ongoing (live) strategies
      const strategyContract = await ethers.getContractAt('Strategy', strategy);
      const capitalAllocated = await strategyContract.capitalAllocated();
      const strategyNAV = await strategyContract.getNAV();
      const [, , , finalized, executedAt, , updatedAt] = await strategyContract.getStrategyState();
      const totalNegativeVotes = await strategyContract.totalNegativeVotes();
      if (executedAt.gt(0) && !finalized) {
        // Just check that we only get live strategies that started already
        let strategyEstimateRewards = await distributor.estimateStrategyRewards(strategy);
        const benchmark = await distributor.connect(deployer)['checkMining(uint256,address)'](1, strategy);

        const baselineRewards = await getEstimateBaselineRewards(
          now,
          strategyNAV,
          capitalAllocated,
          executedAt,
          updatedAt,
          benchmark,
          distributor,
          strategyEstimateRewards,
        );
        estimateRewards = estimateRewards.add(strategyEstimateRewards);
        gardenBaselineRewards = gardenBaselineRewards.add(baselineRewards);
        if (garden === heartGarden.address) {
          totalHeartRewardsPending = totalHeartRewardsPending.add(strategyEstimateRewards);
          capitalAllocatedHeartStrategies = capitalAllocatedHeartStrategies.add(capitalAllocated);
        }
        if (strategyNAV.gte(capitalAllocated)) {
          realEstimateRewards = realEstimateRewards.add(strategyEstimateRewards);
        } else {
          if (totalNegativeVotes.gt(0)) {
            // We do not sum the strategist 10% if negative profits
            // Stewards voting against the strategy will receive their 10% BABL for stewards
            strategyEstimateRewards = strategyEstimateRewards.mul(90).div(100);
            realEstimateRewards = realEstimateRewards.add(strategyEstimateRewards);
          } else {
            // We do not sum the strategist 10% if negative profits
            // We also do not deliver stewards 10%, as there were not stewards voting against the strategy
            strategyEstimateRewards = strategyEstimateRewards.mul(80).div(100);
            realEstimateRewards = realEstimateRewards.add(strategyEstimateRewards);
          }
        }
      }
    }
    // Total garden data
    gardenBABLRewards = unclaimedRewards.add(estimateRewards);
    realGardenBABLRewards = realUnclaimedRewards.add(realEstimateRewards);
    // Baseline rewards
    totalRewards = totalRewards.add(gardenBABLRewards);
    totalEstimateRewards = totalEstimateRewards.add(estimateRewards);
    totalUnclaimedRewards = totalUnclaimedRewards.add(unclaimedRewards);
    // Inferred baseline rewards
    totalBaseline = totalBaseline.add(gardenBaselineRewards);
    // Real rewards
    totalRealRewards = totalRealRewards.add(realGardenBABLRewards);
    totalRealEstimateRewards = totalRealEstimateRewards.add(realEstimateRewards);
    totalRealUnclaimedRewards = totalRealUnclaimedRewards.add(realUnclaimedRewards);
    console.log('');
    console.log(`${await gardenContract.name()} garden `);
    console.log('  Garden rewards');
    console.log(
      `    Garden BABL unclaimed Rewards (real): ${chalk.green(formatUnit(realUnclaimedRewards))} BABL (${chalk.green(
        formatUnit(unclaimedRewards),
      )})`,
    );
    console.log(
      `    Garden BABL estimated Rewards (real): ${chalk.cyan(formatUnit(realEstimateRewards))} BABL (${chalk.cyan(
        formatUnit(estimateRewards),
      )})`,
    );
    console.log(`    Garden Total BABL Rewards (real): ${chalk.blue(formatUnit(realGardenBABLRewards))} BABL`);
    console.log(`    Garden Estimated baseline supply: ${chalk.red(formatUnit(gardenBaselineRewards))} BABL`);
  }
  const totalBABL = eth(500000);
  const remainingBABL = await token.balanceOf(distributor.address);
  const heartBalance = await token.balanceOf(heartGarden.address);
  const claimedBABL = totalBABL.sub(remainingBABL);
  const heartGardenBABLBalance = await token.balanceOf(heartGarden.address);
  console.log('');
  console.log('');
  console.log('Babylon Protocol Mining Performance');
  console.log('');
  console.log(` Supply performance:`);
  console.log(`  Rewards Distributor BABL balance: ${chalk.green(formatUnit(remainingBABL))} BABL 💰`);
  console.log(`  BABL Claimed: ${chalk.red(formatUnit(claimedBABL))} BABL 💰`);
  console.log(`  BABL Stake in Heart Garden: ${chalk.cyan(formatUnit(heartGardenBABLBalance))} BABL 💰`);
  console.log(
    `     Heart Garden BABL Rewards (auto-compounded): ${chalk.cyan(formatUnit(totalHeartGardenBABLRewards))} BABL 💰`,
  );
  console.log(
    `     Heart Garden BABL Rewards (pending): ${chalk.cyan(formatUnit(totalHeartGardenEstimateBABLRewards))} BABL 💰`,
  );
  console.log(
    `  BABL Stake in Heart Garden: ${chalk.cyan(
      formatUnit(heartBalance.add(capitalAllocatedHeartStrategies)),
    )} BABL 💰`,
  );
  console.log(
    `     Heart Garden BABL Rewards (auto-compounded): ${chalk.cyan(formatUnit(totalHeartRewardsFinalized))} BABL 💰`,
  );
  console.log(`     Heart Garden BABL Rewards (pending): ${chalk.cyan(formatUnit(totalHeartRewardsPending))} BABL 💰`);
  console.log(
    `  BABL Available supply: ${chalk.green(formatUnit(remainingBABL.add(claimedBABL).sub(totalRealRewards)))} BABL 💰`,
  );
  console.log(`  BABL Exposed supply (baseline): ${chalk.blueBright(formatUnit(totalBaseline))} BABL 💰`);
  console.log('');
  console.log(' Real delivery performance:');
  console.log(
    `  Total BABL unclaimed (real): ${chalk.green(formatUnit(totalRealUnclaimedRewards))} BABL (${chalk.green(
      formatUnit(totalUnclaimedRewards),
    )})`,
  );
  console.log(
    `  Total BABL pending (real): ${chalk.cyan(formatUnit(totalRealEstimateRewards))} BABL (${chalk.cyan(
      formatUnit(totalEstimateRewards),
    )})`,
  );
  console.log(
    `  Grand Total BABL (real): ${chalk.blue(formatUnit(totalRealRewards))} BABL 💰 (${chalk.blue(
      formatUnit(totalRewards),
    )})`,
  );
  console.log('');
  console.log(' Lost by strategist and stewards due to bad strategies:');
  console.log(
    `  Unclaimed (real): -${chalk.red(formatUnit(totalUnclaimedRewards.sub(totalRealUnclaimedRewards)))} BABL`,
  );
  console.log(`  Pending (real): -${chalk.red(formatUnit(totalEstimateRewards.sub(totalRealEstimateRewards)))} BABL`);
  console.log('');
});
