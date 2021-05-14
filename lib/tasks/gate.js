const { task } = require('hardhat/config');

task('gate')
  .addParam('account', 'Account to give creator permission to.')
  .setAction(async (args, { getContract, ethers, getRapid }, runSuper) => {
    const [, owner] = await ethers.getSigners();
    const gasPrice = await getRapid();

    console.log('owner', owner.address);

    const ishtarGate = await getContract('IshtarGate');
    await ishtarGate.connect(owner).setCreatorPermissions(args.account, true, { gasPrice });
    console.log(`Gave creator permission to ${args.address}`);
  });
