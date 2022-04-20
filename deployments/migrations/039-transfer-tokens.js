const fs = require('fs-extra');
const { sleep, from, eth, formatNumber } = require('lib/helpers');

let MULTISIG = process.env.MULTISIG || '';

module.exports = async ({ getNamedAccounts, deployments, ethers, getSigner, getChainId, getContract, getGasPrice }) => {
  const signers = await ethers.getSigners();
  const chainId = await getChainId();

  if (chainId === '1337') {
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
    await bablToken
      .connect(deployerSigner)
      .transfer(rewardsDistributor.address, eth().mul(500000), { ...(await getGasPrice()) })
  ).wait();

  console.log('Send 305k BABL tokens to TimeLockRegistry');
  await (
    await bablToken
      .connect(deployerSigner)
      .transfer(timeLockRegistry.address, eth().mul('305000'), { ...(await getGasPrice()) })
  ).wait();

  console.log('Register investor and team allocations');
  const investorsVestingStart = new Date(2021, 6, 27); // July 27th real token vesting start for investors
  const teamVestingStart = new Date(2021, 2, 15);
  console.log(`Team vestings starts at ${teamVestingStart}`);
  console.log(`Investor vestings starts at ${investorsVestingStart}`);
  const allocations = JSON.parse(fs.readFileSync('./deployments/allocations.json')).map((alloc) => {
    return {
      receiver: alloc[0],
      distribution: ethers.utils.parseEther(alloc[1].replace(',', '')),
      investorType: alloc[2],
      vestingStartingDate: alloc[2]
        ? Math.round(teamVestingStart.getTime() / 1000)
        : Math.round(investorsVestingStart.getTime() / 1000),
    };
  });
  const batchSize = 20;
  for (let i = 0; i < allocations.length; i += batchSize) {
    await (
      await timeLockRegistry
        .connect(deployerSigner)
        .registerBatch(allocations.slice(i, i + batchSize), { ...(await getGasPrice()) })
    ).wait();
  }
  console.log(
    `Total amount of BABL tokens in registrations is ${ethers.utils.formatUnits(await timeLockRegistry.totalTokens())}`,
  );

  console.log('Send 23k to MULTISIG');
  await (
    await bablToken.connect(deployerSigner).transfer(MULTISIG, eth().mul(23000), { ...(await getGasPrice()) })
  ).wait();

  const balance = await bablToken.balanceOf(deployerSigner.address);
  console.log(`Send ${ethers.utils.formatUnits(balance, 'ether')} to the Treasury`);
  await (
    await bablToken.connect(deployerSigner).transfer(treasury.address, balance, { ...(await getGasPrice()) })
  ).wait();

  console.log('Disable BABL transfers');
  await (await bablToken.connect(deployerSigner).disableTokensTransfers({ ...(await getGasPrice()) })).wait();
};

module.exports.tags = ['Transfer'];
