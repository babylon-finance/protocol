const { task } = require('hardhat/config');

// npx hardhat upgrade-admin --account 0 --proxy BabControllerProxy --from BabController --to BabControllerV3 --network rinkeby
task('upgrade-admin')
  .addParam('proxy', '')
  .addParam('from', '')
  .addParam('to', '')
  .addParam('account', '')
  .setAction(
    async (
      args,
      { network, tenderly, getTenderlyContract, upgradesDeployer, getContract, ethers, getGasPrice },
      runSuper,
    ) => {
      const { proxy, from, to, account } = args;
      const signers = await ethers.getSigners();
      const signer = signers[account];

      console.log('signer', signer.address);

      console.log(`Upgrading ${from} to ${to}.`);
      const controller = await upgradesDeployer.upgradeAdmin(proxy, from, to, undefined, {
        log: true,
        ...(await getGasPrice()),
        from: signer.address,
      });
    },
  );
