const fs = require('fs-extra');

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
  const rewardsDistributor = await getContract('RewardsDistributor', 'RewardsDistributorProxy');
  const timeLockRegistry = await getContract('TimeLockRegistry');
  const treasury = await getContract('Treasury');

  console.log('Send 500k BABL tokens to RewardsDistributor');
  await (
    await bablToken.connect(deployerSigner).transfer(rewardsDistributor.address, ONE_ETH.mul(500000), { gasPrice })
  ).wait();

  console.log('Send 305k BABL tokens to TimeLockRegistry');
  await (
    await bablToken.connect(deployerSigner).transfer(timeLockRegistry.address, ONE_ETH.mul('305000'), { gasPrice })
  ).wait();

  console.log('Register investor and team allocations');
  const investorsVestingStart = new Date();
  const teamVestingStart = new Date(2021, 2, 15);
  console.log(`Team vestings starts at ${teamVestingStart}`);
  console.log(`Investor vestings starts at ${investorsVestingStart}`);
  const allocations = JSON.parse(fs.readFileSync('./deployments/allocations.json')).map((alloc) => {
    return {
      receiver: alloc[0],
      distribution: ethers.utils.parseEther(alloc[1].replace(',', '')),
      investorType: alloc[2],
      vestingStartingDate: alloc[2] ? teamVestingStart.getTime() / 1000 : investorsVestingStart.getTime() / 1000,
    };
  });
  const batchSize = 20;
  for (let i = 0; i < allocations.length; i += batchSize) {
    await (
      await timeLockRegistry.connect(deployerSigner).registerBatch(allocations.slice(i, i + batchSize), { gasPrice })
    ).wait();
  }
  console.log(
    `Total amount of BABL tokens in registrations is ${ethers.utils.formatUnits(await timeLockRegistry.totalTokens())}`,
  );

  console.log('Send 23k to MULTISIG');
  await (await bablToken.connect(deployerSigner).transfer(MULTISIG, ONE_ETH.mul(23000), { gasPrice })).wait();

  const balance = await bablToken.balanceOf(deployerSigner.address);
  console.log(`Send ${ethers.utils.formatUnits(balance, 'ether')} to the Treasury`);
  await (await bablToken.connect(deployerSigner).transfer(treasury.address, balance, { gasPrice })).wait();

  console.log('Disable BABL transfers');
  await (await bablToken.connect(deployerSigner).disableTokensTransfers({ gasPrice })).wait();
};

module.exports.tags = ['Transfer'];
