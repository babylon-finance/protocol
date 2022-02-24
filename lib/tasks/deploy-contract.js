const { task } = require('hardhat/config');

const NONCE = +process.env.NONCE;

// npx hardhat deploy-contract --contract StrategyV15 --network mainnet
task('deploy-contract')
  .addParam('contract', '')
  .addVariadicPositionalParam('params', '', [])
  .setAction(
    async (
      args,
      { deployments, network, tenderly, getTenderlyContract, upgradesDeployer, getContract, ethers, getGasPrice },
      runSuper,
    ) => {
      const { deploy } = deployments;
      const { contract, params } = args;
      const signers = await ethers.getSigners();
      const signer = signers[0];

      console.log('signer', signer.address);

      const mappedParams = [];
      for (const param of params) {
        if (param.startsWith('0x')) {
          mappedParams.push(param);
        } else {
          mappedParams.push((await deployments.get(param)).address);
        }
      }

      console.log('args', mappedParams);

      const deployment = await deploy(contract, {
        from: signer.address,
        args: mappedParams,
        log: true,
        ...(await getGasPrice()),
        nonce: NONCE,
      });

      if (network.live && deployment.newlyDeployed) {
        await tenderly.push(await getTenderlyContract(contract));
      }
    },
  );
