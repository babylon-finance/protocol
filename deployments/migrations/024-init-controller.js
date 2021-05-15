let KEEPER = process.env.KEEPER || '';

module.exports = async ({ getNamedAccounts, deployments, ethers, getSigner, getChainId, getRapid }) => {
  const chainId = await getChainId();
  const signers = await ethers.getSigners();
  const gasPrice = await getRapid();

  if (chainId === '31337') {
    // user second signer as Keeper
    KEEPER = signers[1].address;
  } else if (!KEEPER) {
    throw new Error('Keeper address is not set');
  }
  console.log('KEEPER', KEEPER);

  const { deployer } = await getNamedAccounts();
  const owner = await getSigner(deployer);

  const controller = await deployments.get('BabControllerProxy');
  const priceOracle = await deployments.get('PriceOracle');
  const treasury = await deployments.get('Treasury');
  const gardenValuer = await deployments.get('GardenValuer');
  const ishtarGate = await deployments.get('IshtarGate');
  const rewardsDistributor = await deployments.get('RewardsDistributor');
  const gardenFactory = await deployments.get('GardenFactory');
  const strategyFactory = await deployments.get('StrategyFactory');

  const controllerContract = await ethers.getContractAt('BabController', controller.address);

  // Add WETH
  console.log('Setting reserve asset to WETH');
  await controllerContract.connect(owner).addReserveAsset('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', { gasPrice });
  console.log('Adding DAI as reserve asset');
  await controllerContract.connect(owner).addReserveAsset('0x6B175474E89094C44Da98b954EedeAC495271d0F', { gasPrice });
  console.log('Adding USDC as reserve asset');
  await controllerContract.connect(owner).addReserveAsset('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', { gasPrice });
  // Use OpenZeppelin Defender Keeper
  console.log(`Adding KEEPER ${KEEPER}`);
  await controllerContract.connect(owner).addKeepers([KEEPER], { gasPrice });

  console.log(`Setting price oracle on controller ${priceOracle.address}`);
  await controllerContract.connect(owner).editPriceOracle(priceOracle.address, { gasPrice });
  console.log(`Setting treasury on controller ${treasury.address}`);
  await controllerContract.connect(owner).editTreasury(treasury.address, { gasPrice });
  console.log(`Setting garden valuer on controller ${gardenValuer.address}`);
  await controllerContract.connect(owner).editGardenValuer(gardenValuer.address, { gasPrice });
  console.log(`Setting ishtar gate on controller ${ishtarGate.address}`);
  await controllerContract.connect(owner).editIshtarGate(ishtarGate.address, { gasPrice });
  console.log(`Setting rewards distributor on controller ${rewardsDistributor.address}`);
  await controllerContract.connect(owner).editRewardsDistributor(rewardsDistributor.address, { gasPrice });
  console.log(`Setting garden factory on controller ${gardenFactory.address}`);
  await controllerContract.connect(owner).editGardenFactory(gardenFactory.address, { gasPrice });
  console.log(`Setting strategy factory on controller ${strategyFactory.address}`);
  await controllerContract.connect(owner).editStrategyFactory(strategyFactory.address, { gasPrice });

  // Adding integrations
  for (const integration of [
    'KyberTradeIntegration',
    'OneInchTradeIntegration',
    'BalancerIntegration',
    'UniswapPoolIntegration',
    'YearnVaultIntegration',
    'CompoundLendIntegration',
    'AaveLendIntegration',
    'SushiswapPoolIntegration',
    'OneInchPoolIntegration',
  ]) {
    const deployment = await deployments.get(integration);
    const contract = await ethers.getContractAt(integration, deployment.address);
    console.log(`Adding integration ${integration}(${deployment.address}) to BabController`);
    await controllerContract.connect(owner).addIntegration(await contract.getName(), deployment.address, { gasPrice });
  }
  const oneinch = await deployments.get('OneInchTradeIntegration');
  // Set default trade integration
  console.log('Setting default trade integration', oneinch.address);
  await controllerContract.connect(owner).setDefaultTradeIntegration(oneinch.address, { gasLimit: 1000000, gasPrice });

  // Adding operations
  const ops = ['BuyOperation', 'AddLiquidityOperation', 'DepositVaultOperation', 'LendOperation'];
  for (let i = 0; i < ops.length; i++) {
    const operation = ops[i];
    const deployment = await deployments.get(operation);
    console.log(`Adding operation ${operation}(${deployment.address}) to BabController`);
    await controllerContract.connect(owner).setOperation(i, deployment.address, { gasPrice });
  }
};

module.exports.tags = ['Init'];
