const { task } = require('hardhat/config');

task('strategy:expire')
  .addVariadicPositionalParam('strategies', 'Strategies to expiret', [])
  .setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
    const [, owner] = await ethers.getSigners();

    const { maxPriorityFeePerGas } = await getGasPrice();
    console.log('maxPriorityFeePerGas', maxPriorityFeePerGas);

    console.log('owner', owner.address);

    for (const strategy of args.strategies) {
      const strategyContract = await ethers.getContractAt('Strategy', strategy, owner);

      await strategyContract.deleteCandidateStrategy({ maxPriorityFeePerGas });

      console.log(`Expired strategy ${strategy}`);
    }
  });
