const { task } = require('hardhat/config');

task('gate')
  .addVariadicPositionalParam('accounts', 'Accounts to give creator permission to', [])
  .setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
    const [, owner] = await ethers.getSigners();

    console.log('owner', owner.address);

    const mardukGate = await getContract('MardukGate');
    await mardukGate.connect(owner).grantCreatorsInBatch(
      args.accounts,
      args.accounts.map((acc) => true),
      { ...(await getGasPrice()), gasLimit: 300000 },
    );
    console.log(`Gave creator permission to ${args.accounts}`);
  });
