module.exports = async ({
  getNamedAccounts,
  deployments,
  upgradesDeployer,
  getGasPrice,
  network,
  tenderly,
  getTenderlyContracts,
}) => {
  const { deployer } = await getNamedAccounts();
  const signers = await ethers.getSigners();
  const chainId = await getChainId();
  const signer = await getSigner(deployer);

  let KEEPER = process.env.KEEPER;

  if (chainId === '1337') {
    // user second signer as Keeper
    KEEPER = signers[1].address;
  } else if (!KEEPER) {
    throw new Error('Keeper address is not set');
  }

  console.log('KEEPER', KEEPER);
  const deployment = await upgradesDeployer.deployAdminProxy(
    'BabController',
    'BabControllerProxy',
    { from: deployer, log: true, ...(await getGasPrice()) },
    {
      initializer: { method: 'initialize', args: [] },
    },
  );

  const controller = await ethers.getContractAt('BabController', deployment.address, signer);

  if (!(await controller.isValidReserveAsset('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'))) {
    console.log('Setting reserve asset to WETH');
    await (
      await controller.addReserveAsset('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', { ...(await getGasPrice()) })
    ).wait();
  }

  if (!(await controller.isValidReserveAsset('0x6B175474E89094C44Da98b954EedeAC495271d0F'))) {
    console.log('Adding DAI as reserve asset');
    await (
      await controller.addReserveAsset('0x6B175474E89094C44Da98b954EedeAC495271d0F', { ...(await getGasPrice()) })
    ).wait();
  }

  if (!(await controller.isValidReserveAsset('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'))) {
    console.log('Adding USDC as reserve asset');
    await (
      await controller.addReserveAsset('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', { ...(await getGasPrice()) })
    ).wait();
  }

  if (!(await controller.isValidReserveAsset('0x2260fac5e5542a773aa44fbcfedf7c193bc2c599'))) {
    console.log('Adding WBTC as reserve asset');
    await (
      await controller.addReserveAsset('0x2260fac5e5542a773aa44fbcfedf7c193bc2c599', { ...(await getGasPrice()) })
    ).wait();
  }

  if (!(await controller.isValidReserveAsset('0xf4dc48d260c93ad6a96c5ce563e70ca578987c74'))) {
    console.log('Adding BABL as reserve asset');
    await (
      await controller.addReserveAsset('0xf4dc48d260c93ad6a96c5ce563e70ca578987c74', { ...(await getGasPrice()) })
    ).wait();
  }

  // Use OpenZeppelin Defender Keeper
  if (!(await controller.isValidKeeper(KEEPER))) {
    console.log(`Adding KEEPER ${KEEPER}`);
    await (await controller.addKeepers([KEEPER], { ...(await getGasPrice()) })).wait();
  }

  if (network.live && controller.newlyDeployed) {
    const contracts = await getTenderlyContracts(['BabController', 'BabControllerProxy', 'ProxyAdmin']);
    await tenderly.push(contracts);
  }
};

module.exports.tags = ['Controller'];
