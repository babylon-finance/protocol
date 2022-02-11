const { task } = require('hardhat/config');

const NONCE = +process.env.NONCE;

// GAS_LIMIT=100000000000 npx hardhat deploy-contract --contract StrategyV15 --network mainnet
task('deploy-contract')
  .addParam('contract', '')
  .setAction(
    async (
      args,
      { deployments, network, tenderly, getTenderlyContract, upgradesDeployer, getContract, ethers, getGasPrice },
      runSuper,
    ) => {
      const { deploy } = deployments;
      const { contract, account } = args;
      const signers = await ethers.getSigners();
      const signer = signers[0];

      console.log('maxFeePerGas', maxFeePerGas.toString());
      console.log('signer', signer.address);

      const deployment = await deploy(contract, {
        from: signer.address,
        args: [],
        log: true,
        ...(await getGasPrice()),
        maxFeePerGas,
        nonce: NONCE,
      });

      if (network.live && deployment.newlyDeployed) {
        await tenderly.push(await getTenderlyContract(contract));
      }
    },
  );
