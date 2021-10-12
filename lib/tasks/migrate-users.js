const { getUsers } = require('lib/web3');
const { task } = require('hardhat/config');

// npx hardhat migrate-users --account 1 --network mainnet
task('migrate-users')
  .addParam('account', '')
  .setAction(
    async (
      args,
      { network, tenderly, getTenderlyContract, upgradesDeployer, getContract, ethers, getRapid },
      runSuper,
    ) => {
      const { account } = args;
      const signers = await ethers.getSigners();
      const signer = signers[account];

      console.log('signer', signer.address);

      let controller = await ethers.getContractAt(
        'BabController',
        '0xd4a5b5fcb561daf3adf86f8477555b92fba43b5f',
        signer,
      );

      const distributor = await ethers.getContractAt(
        'RewardsDistributor',
        '0x40154ad8014df019a53440a60ed351dfba47574e',
        signer,
      );
      const gardens = await controller.getGardens();

      for (const garden of gardens) {
        const gardenContract = await ethers.getContractAt('Garden', garden);
        console.log(`Migrating garden ${garden} ${await gardenContract.name()}`);
        const users = (await getUsers(garden)).map((u) => u.address);
        console.log('users', users);

        if (!!users && !!users.length) {
          const [, beta] = await distributor.getBetaMigration(garden, users[0]);
          // migrate only if garden is not migrated yet
          if (!beta[0] && !beta[0]) {
            const gasPrice = await getRapid();
            const tx = await distributor.migrateBetaUsers(garden, users, { gasPrice });
            console.log(`Tx hash ${tx.hash}`);
            await tx.wait();
            console.log(`Migrated garden ${garden} ${await gardenContract.name()}`);
          } else {
            console.log('Already migrated');
          }
        }
      }
    },
  );
