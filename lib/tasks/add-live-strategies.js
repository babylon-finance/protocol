const { getUsers } = require('lib/web3');
const { task } = require('hardhat/config');

// npx hardhat add-live-strategies --account 1 --network mainnet
task('add-live-strategies')
  .addParam('account', '')
  .setAction(
    async (
      args,
      { network, tenderly, getTenderlyContract, upgradesDeployer, getContract, ethers, getGasPrice },
      runSuper,
    ) => {
      const { account } = args;
      const signers = await ethers.getSigners();
      const signer = signers[account];

      const gasPrice = await getGasPrice();

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

      const strategies = (await controller.getLiveStrategies(50)).filter(
        (s) => s !== '0x0000000000000000000000000000000000000000',
      );
      console.log('strategies', strategies);
      const tx = await distributor.addLiveStrategies(strategies, { gasPrice });
      console.log(`Tx hash ${tx.hash}`);
      await tx.wait();
    },
  );
