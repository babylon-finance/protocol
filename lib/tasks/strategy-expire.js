const { task } = require('hardhat/config');

task('strategy:expire')
  .addVariadicPositionalParam('strategies', 'Strategies to expire', [])
  .setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
    const [, owner] = await ethers.getSigners();

    console.log('owner', owner.address);

    for (const strategy of args.strategies) {
      const strategyContract = await ethers.getContractAt('Strategy', strategy, owner);

      await strategyContract.deleteCandidateStrategy({ ...(await getGasPrice()) });

      console.log(`Expired strategy ${strategy}`);
    }
  });
