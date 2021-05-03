const { ONE_ETH } = require('../../lib/constants');

let MULTISIG = process.env.MULTISIG || '';

module.exports = async ({ getNamedAccounts, deployments, ethers, getSigner, getChainId, getContract, getRapid }) => {
  const signers = await ethers.getSigners();
  const chainId = await getChainId();
  const gasPrice = await getRapid();

  if (chainId === '31337') {
    // use the third signer as MULTISIG
    MULTISIG = signers[2].address;
  } else if (!MULTISIG) {
    throw new Error('MULTISIG address is not set');
  }
  console.log('MULTISIG', MULTISIG);

  const { deployer } = await getNamedAccounts();
  const deployerSigner = await getSigner(deployer);

  const bablToken = await getContract('BABLToken');
  const rewardsDistributor = await getContract('RewardsDistributor');
  const timeLockRegistry = await getContract('TimeLockRegistry');
  const treasury = await getContract('Treasury');

  console.log('Send 500k BABL tokens to RewardsDistributor');
  await bablToken.connect(deployerSigner).transfer(rewardsDistributor.address, ONE_ETH.mul(500000), { gasPrice });

  console.log('Send 293.2k BABL tokens to MULTISIG');
  await bablToken.connect(deployerSigner).transfer(MULTISIG, ONE_ETH.mul('293200'), { gasPrice });

  // Locally singer2 is the MULTISIG; on mainnet approval has to be done after deployment
  if (chainId === '31337') {
    console.log('Approve 293.2k BABL to TimeLockRegistry for investors and team');
    await bablToken.connect(signers[2]).approve(timeLockRegistry.address, ONE_ETH.mul('293200'), { gasPrice });
  } else {
    console.log('You have to approve 293200 tokens for the TimeLockReigstry from the MULTISIG.');
    console.log("await bablToken.connect(MULTISIG).approve(timeLockRegistry.address, ONE_ETH.mul('293200')");
  }

  // TODO: Register vestings for the investors and the team
  console.log('Send 16k to MULTISIG');
  await bablToken.connect(deployerSigner).transfer(MULTISIG, ONE_ETH.mul(16000), { gasPrice });

  console.log('Send 190.8k to the Treasury');
  await bablToken.connect(deployerSigner).transfer(treasury.address, ONE_ETH.mul(190800), { gasPrice });

  console.log('Disable BABL transfers');
  await bablToken.connect(deployerSigner).disableTokensTransfers({ gasPrice });
};

module.exports.tags = ['Transfer'];
