const { task } = require('hardhat/config');

task('gate')
  .addVariadicPositionalParam('accounts', 'Accounts to give creator permission to', [])
  .setAction(async (args, { getContract, ethers, getRapid }, runSuper) => {
    const [, owner] = await ethers.getSigners();

    const gasPrice = await getRapid();
    console.log('gasPrice', gasPrice);

    console.log('owner', owner.address);

    const ishtarGate = await getContract('IshtarGate');
    await ishtarGate.connect(owner).grantCreatorsInBatch(
      args.accounts,
      args.accounts.map((acc) => true),
      { gasPrice },
    );
    console.log(`Gave creator permission to ${args.accounts}`);
  });
