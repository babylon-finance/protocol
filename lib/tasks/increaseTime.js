const { task } = require('hardhat/config');

const ONE_DAY_IN_SECONDS = 60 * 60 * 24;

task('increaseTime')
  .addParam('days', 'Number of days')
  .setAction(async (args, { getContract, ethers, getRapid }, runSuper) => {
    const days = args.days;

    const provider = new ethers.providers.JsonRpcProvider();

    await provider.send('evm_increaseTime', [Number(days) * ONE_DAY_IN_SECONDS]);
    await provider.send('evm_mine');

    console.log(`Increased time by ${days} days.`);
  });
