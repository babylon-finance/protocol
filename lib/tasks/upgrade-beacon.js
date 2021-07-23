const { task } = require('hardhat/config');

// npx hardhat upgrade-admin --account 0 --proxy BabControllerProxy --from BabController --to BabControllerV3 --network rinkeby
task('upgrade-beacon')
  .addParam('beacon', '')
  .addParam('from', '')
  .addParam('to', '')
  .addParam('account', '')
  .setAction(
    async (
      args,
      { network, tenderly, getTenderlyContract, upgradesDeployer, getContract, ethers, getRapid },
      runSuper,
    ) => {
      const { beacon, from, to, account } = args;
      const signers = await ethers.getSigners();
      const signer = signers[account];

      const gasPrice = await getRapid();
      console.log('gasPrice', gasPrice.toString());
      console.log('signer', signer.address);

      console.log(`Upgrading ${from} to ${to}.`);
      const controller = await upgradesDeployer.upgradeBeacon(beacon, from, to, undefined, {
        from: signer.address,
        log: true,
        gasPrice,
      });

      console.log(`Uploading contract to Tenderly`);

      await tenderly.push(await getTenderlyContract(to));
    },
  );
