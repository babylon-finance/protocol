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
      { network, tenderly, getTenderlyContract, upgradesDeployer, getContract, ethers, getRapid },
      runSuper,
    ) => {
      const { proxy, from, to, account } = args;
      const signers = await ethers.getSigners();
      const signer = signers[account];

      const gasPrice = await getRapid();
      console.log('gasPrice', gasPrice.toString());
      console.log('signer', signer.address);

      console.log(`Upgrading ${from} to ${to}.`);
      const controller = await upgradesDeployer.upgradeAdmin(proxy, from, to, undefined, signer, {
        log: true,
        gasPrice,
      });

      console.log(`Uploading contract to Tenderly`);

      await tenderly.push(await getTenderlyContract(to));
    },
  );
