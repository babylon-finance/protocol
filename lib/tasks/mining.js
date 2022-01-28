const chalk = require('chalk');
const { task } = require('hardhat/config');
const { from, eth, formatNumber } = require('../helpers');
const { ONE_DAY_IN_SECONDS } = require('lib/constants');

function normalizeToken(amount) {
  const normalizedNumber = amount.mul(eth()).div(ethers.utils.parseEther('0.001')).div(eth()).toNumber() / 1000;
  return normalizedNumber;
}

function getEstimateBaselineRewards(now, returned, allocated, executedAt, updatedAt, benchmark, distributor, rewards) {
  let ratio;
  const timeDiff = now - executedAt;
  const timedAPY = ethers.BigNumber.from(ONE_DAY_IN_SECONDS * 365).div(
    ethers.BigNumber.from(BigInt(timeDiff) > 0 ? timeDiff : 1),
  );

  let returnedAPY;
  if (returned >= allocated) {
    // profit
    returnedAPY = ethers.BigNumber.from(allocated).add(
      ethers.BigNumber.from(returned).sub(ethers.BigNumber.from(allocated)).mul(ethers.BigNumber.from(timedAPY)),
    );
  } else {
    // loses
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
  const numerator = ethers.BigNumber.from(rewards);
  const denominator = ethers.BigNumber.from(benchmark[11]).add(
    ethers.BigNumber.from(benchmark[12])
      .mul(ethers.BigNumber.from(ratio))
      .mul(eth())
      .mul(ethers.BigNumber.from(realProfit))
      .div(eth())
      .div(eth())
      .div(eth()),
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

  const gardens = await babController.getGardens();

  let totalRewards = from(0);
  let totalUnclaimedRewards = from(0);
  let totalEstimateRewards = from(0);
  let totalRealUnclaimedRewards = from(0); // We do not count strategist's if negative profit
  let totalRealEstimateRewards = from(0); // We do not count strategist's if negative profit
  let totalRealRewards = from(0); // We do not count strategist's if negative profit
  let totalBaseline = from(0);
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('Garden', garden);
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
      const strategyNAV = await strategyContract.getNAV();
      const strategyReturned = await strategyContract.capitalReturned();
      const [, , , finalized, executedAt, , updatedAt] = await strategyContract.getStrategyState();
      const totalNegativeVotes = await strategyContract.totalNegativeVotes();
      const strategyName = await strategyNft.getStrategyName(strategy);

      if (finalized) {
        // Just check that we only get finalized strategies
        const strategist = await strategyContract.strategist();
        const creator = await gardenContract.creator();
        let rewards = await strategyContract.strategyRewards();
        const benchmark = await distributor.checkMining(1, strategy);
        const baselineRewards = rewards; // As there were different weight changes by bip 1 and 7 we assume baseline to become real one here
        unclaimedRewards = unclaimedRewards.add(rewards);
        gardenBaselineRewards = gardenBaselineRewards.add(baselineRewards);
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
      }
    }
    for (const strategy of strategies) {
      // Ongoing (live) strategies
      const strategyContract = await ethers.getContractAt('Strategy', strategy);
      const capitalAllocated = await strategyContract.capitalAllocated();
      const strategyNAV = await strategyContract.getNAV();
      const [, , , finalized, executedAt, , updatedAt] = await strategyContract.getStrategyState();
      const totalNegativeVotes = await strategyContract.totalNegativeVotes();
      if (BigInt(executedAt) > 0 && !finalized) {
        // Just check that we only get live strategies that started already
        const strategist = await strategyContract.strategist();
        const creator = await gardenContract.creator();
        let strategyEstimateRewards = await distributor.estimateStrategyRewards(strategy);
        const strategyName = await strategyNft.getStrategyName(strategy);
        const benchmark = await distributor.checkMining(1, strategy);

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
        if (BigInt(strategyNAV) >= BigInt(capitalAllocated)) {
          realEstimateRewards = realEstimateRewards.add(strategyEstimateRewards);
        } else {
          if (BigInt(totalNegativeVotes) > 0) {
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
      `    Garden BABL unclaimed Rewards (real): ${chalk.green(
        normalizeToken(realUnclaimedRewards),
      )} BABL (${chalk.green(normalizeToken(unclaimedRewards))})`,
    );
    console.log(
      `    Garden BABL estimated Rewards (real): ${chalk.cyan(normalizeToken(realEstimateRewards))} BABL (${chalk.cyan(
        normalizeToken(estimateRewards),
      )})`,
    );
    console.log(`    Garden Total BABL Rewards (real): ${chalk.blue(normalizeToken(realGardenBABLRewards))} BABL`);
    console.log(`    Garden Estimated baseline supply: ${chalk.red(normalizeToken(gardenBaselineRewards))} BABL`);
  }
  console.log('');
  console.log('');
  console.log('Babylon Protocol');
  console.log('');
  console.log(` Baseline Supply estimated performance:' ${chalk.blueBright(normalizeToken(totalBaseline))} BABL 💰`);
  console.log(`  Total BABL unclaimed (baseline): ${chalk.green(normalizeToken(totalUnclaimedRewards))} BABL `);
  console.log(`  Total BABL pending (baseline): ${chalk.cyan(normalizeToken(totalEstimateRewards))} BABL `);
  console.log(`  Grand Total BABL (baseline): ${chalk.blue(normalizeToken(totalRewards))} BABL 💰`);
  console.log('');
  console.log(' Real delivery performance:');
  console.log(`  Total BABL unclaimed (real): ${chalk.green(normalizeToken(totalRealUnclaimedRewards))} BABL `);
  console.log(`  Total BABL pending (real): ${chalk.cyan(normalizeToken(totalRealEstimateRewards))} BABL `);
  console.log(`  Grand Total BABL (real): ${chalk.blue(normalizeToken(totalRealRewards))} BABL 💰`);
  console.log('');
  console.log(' Lost by strategist and stewards due to bad strategies:');
  console.log(
    `  Unclaimed (real): -${chalk.red(normalizeToken(totalUnclaimedRewards.sub(totalRealUnclaimedRewards)))} BABL`,
  );
  console.log(
    `  Pending (real): -${chalk.red(normalizeToken(totalEstimateRewards.sub(totalRealEstimateRewards)))} BABL`,
  );
  console.log('');
});
