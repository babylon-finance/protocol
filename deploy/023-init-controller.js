const KEEPER = process.env.KEEPER || '';

module.exports = async ({ getNamedAccounts, deployments, ethers, getSigner }) => {
  if (!KEEPER) {
    throw new Error('Keeper address is not set');
  }
  console.log('keeper', KEEPER);

  const { deployer } = await getNamedAccounts();
  const owner = await getSigner(deployer);

  const controller = await deployments.get('BabControllerProxy');
  const priceOracle = await deployments.get('PriceOracle');
  const treasury = await deployments.get('Treasury');
  const gardenValuer = await deployments.get('GardenValuer');
  const ishtarGate = await deployments.get('IshtarGate');
  const rewardsDistributor = await deployments.get('RewardsDistributor');
  const gardenFactory = await deployments.get('GardenFactory');
  const longStrategyFactory = await deployments.get('LongStrategyFactory');
  const liquidityPoolStrategyFactory = await deployments.get('LiquidityPoolStrategyFactory');
  const yieldFarmingStrategyFactory = await deployments.get('YieldFarmingStrategyFactory');

  const lendStrategyFactory = await deployments.get('LendStrategyFactory');

  const controllerContract = await ethers.getContractAt('BabController', controller.address);

  // Add WETH
  await controllerContract.connect(owner).addReserveAsset('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2');
  // TODO: use OpenZeppelin Defender Keeper
  await controllerContract.connect(owner).addKeepers([KEEPER]);

  // Sets the price oracle and gardenvaluer address
  await controllerContract.connect(owner).editPriceOracle(priceOracle.address);
  await controllerContract.connect(owner).editTreasury(treasury.address);
  await controllerContract.connect(owner).editGardenValuer(gardenValuer.address);
  await controllerContract.connect(owner).editIshtarGate(ishtarGate.address);
  await controllerContract.connect(owner).editRewardsDistributor(rewardsDistributor.address);
  await controllerContract.connect(owner).editGardenFactory(gardenFactory.address);
  await controllerContract.connect(owner).editStrategyFactory(0, longStrategyFactory.address);
  await controllerContract.connect(owner).editStrategyFactory(1, liquidityPoolStrategyFactory.address);
  await controllerContract.connect(owner).editStrategyFactory(2, yieldFarmingStrategyFactory.address);
  await controllerContract.connect(owner).editStrategyFactory(3, lendStrategyFactory.address);

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
    console.log(`Adding integration ${integration} to BabController`);
    const deployment = await deployments.get(integration);
    const contract = await ethers.getContractAt(integration, deployment.address);
    await controllerContract.connect(owner).addIntegration(await contract.getName(), deployment.address);
  }
};

module.exports.tags = ['Init'];
module.exports.dependencies = ['Aave'];
