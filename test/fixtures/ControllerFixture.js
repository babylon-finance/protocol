const { ethers } = require('hardhat');
const { ONE_DAY_IN_SECONDS } = require('../../utils/constants.js');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../../utils/system.js');
const addresses = require('../../utils/addresses');
const argsUtil = require('../../utils/arguments.js');

async function deployFolioFixture() {
  const [owner, signer1, signer2, signer3] = await ethers.getSigners();
  
  const BabController = await ethers.getContractFactory('BabController', owner);
  const babController = await BabController.deploy(...argsUtil.readArgumentsFile('BabController'));

  await babController.addReserveAsset(addresses.tokens.WETH);
  await babController.addKeepers(Object.values(addresses.users));

  // Deployment of BABL Token contract
  const BABLToken = await ethers.getContractFactory("BABLToken", owner);
  const bablToken = await BABLToken.deploy();

  // Deployment of Time Lock Registry contract
  const TimeLockRegistry = await ethers.getContractFactory("TimeLockRegistry", owner);
  const timeLockRegistry = await TimeLockRegistry.deploy(bablToken.address);

  // Sets the Time Lock Registry address
  await bablToken.setTimeLockRegistry(timeLockRegistry.address);

  // Approve Time Lock Registry to handle 31% of the Tokens for vesting (Team, Advisors, Investors)
  await bablToken.approve(timeLockRegistry.address, ethers.utils.parseEther("310000"));

  const GardenValuer = await ethers.getContractFactory('GardenValuer', owner);
  const PriceOracle = await ethers.getContractFactory('PriceOracle', owner);
  const ReservePool = await ethers.getContractFactory('ReservePool', owner);
  const Treasury = await ethers.getContractFactory('Treasury', owner);
  const UniswapTWAP = await ethers.getContractFactory('UniswapTWAP', owner);
  const GardenFactory = await ethers.getContractFactory('GardenFactory', owner);
  const StrategyFactory = await ethers.getContractFactory('StrategyFactory', owner);
  const gardenValuer = await GardenValuer.deploy(babController.address);
  const reservePool = await ReservePool.deploy(babController.address);
  const treasury = await Treasury.deploy(babController.address);
  const gardenFactory = await GardenFactory.deploy();
  const strategyFactory = await StrategyFactory.deploy();

  const uniswapTWAPAdapter = await UniswapTWAP.deploy(
    babController.address,
    addresses.uniswap.factory,
    TWAP_ORACLE_WINDOW,
    TWAP_ORACLE_GRANULARITY,
  );
  const priceOracle = await PriceOracle.deploy(babController.address, addresses.compound.OpenOracle, [
    uniswapTWAPAdapter.address,
  ]);
  // Sets the price oracle and gardenvaluer address
  babController.editPriceOracle(priceOracle.address);
  babController.editTreasury(treasury.address);
  babController.editGardenValuer(gardenValuer.address);
  babController.editReservePool(reservePool.address);
  babController.editGardenFactory(gardenFactory.address);
  babController.editStrategyFactory(strategyFactory.address);

  const AaveIntegration = await ethers.getContractFactory('AaveIntegration', owner);
  const aaveIntegration = await AaveIntegration.deploy(babController.address, addresses.tokens.WETH, 50);

  const CompoundIntegration = await ethers.getContractFactory('CompoundIntegration', owner);
  const compoundIntegration = await CompoundIntegration.deploy(babController.address, addresses.tokens.WETH, 50);

  const KyberTradeIntegration = await ethers.getContractFactory('KyberTradeIntegration', owner);
  const kyberTradeIntegration = await KyberTradeIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.kyber.proxy,
  );

  const OneInchIntegration = await ethers.getContractFactory('OneInchTradeIntegration', owner);
  const oneInchTradeIntegration = await OneInchIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.oneinch.exchange,
  );

  const BalancerIntegration = await ethers.getContractFactory('BalancerIntegration', owner);
  const balancerIntegration = await BalancerIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.balancer.factory,
  );

  const UniswapPoolIntegration = await ethers.getContractFactory('UniswapPoolIntegration', owner);
  const uniswapPoolIntegration = await UniswapPoolIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.uniswap.router,
  );

  const YearnVaultIntegration = await ethers.getContractFactory('YearnVaultIntegration', owner);
  const yearnVaultIntegration = await YearnVaultIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.yearn.vaultRegistry,
  );

  const integrationsList = [
    aaveIntegration,
    compoundIntegration,
    kyberTradeIntegration,
    oneInchTradeIntegration,
    balancerIntegration,
    uniswapPoolIntegration,
    yearnVaultIntegration,
  ];

  // Adding integrations
  integrationsList.forEach(async (integration) => {
    babController.addIntegration(await integration.getName(), integration.address);
  });

  const integrationsAddressList = integrationsList.map((iter) => iter.address);
  // Creates a new Garden instance

  await babController
    .connect(signer1)
    .createRollingGarden(integrationsAddressList, addresses.tokens.WETH, 'Absolute ETH Return [beta]', 'EYFA');

  await babController
    .connect(signer1)
    .createRollingGarden(integrationsAddressList, addresses.tokens.WETH, 'ETH Yield Farm [a]', 'EYFB');

  await babController
    .connect(signer1)
    .createRollingGarden(integrationsAddressList, addresses.tokens.WETH, 'ETH Yield Farm [b]', 'EYFG');

  const gardens = await babController.getGardens();

  const garden = await ethers.getContractAt('RollingGarden', gardens[0]);

  const garden2 = await ethers.getContractAt('RollingGarden', gardens[1]);

  const garden3 = await ethers.getContractAt('RollingGarden', gardens[2]);

  // Initial deposit
  await garden.connect(signer1).start(
    ethers.utils.parseEther('10'),
    1,
    ethers.utils.parseEther('1000'),
    2,
    ethers.utils.parseEther('0.01'),
    ONE_DAY_IN_SECONDS,
    ethers.utils.parseEther('0.13'), // 13% Ideator
    ethers.utils.parseEther('0.05'), // 5% Voters
    ethers.utils.parseEther('0.02'), // 2% garden creator
    ethers.utils.parseEther('0.10'), // 10% quorum
    ONE_DAY_IN_SECONDS * 3,
    ONE_DAY_IN_SECONDS * 365,
    { value: ethers.utils.parseEther('0.1') },
  );

  await garden.connect(signer1).addStrategy(
    ethers.utils.parseEther('10'),
    await garden.totalSupply(),
    ONE_DAY_IN_SECONDS * 30,
    ethers.utils.parseEther('0.05'), // 5%
    ethers.utils.parseEther('1'),
  );

  console.log('Created and started garden', garden.address);

  const strategies = await garden.getStrategies();

  return {
    babController,
    bablToken,
    timeLockRegistry,
    reservePool,
    treasury,
    integrations: {
      aaveIntegration,
      compoundIntegration,
      kyberTradeIntegration,
      oneInchTradeIntegration,
      balancerIntegration,
      uniswapPoolIntegration,
      yearnVaultIntegration,
    },
    comunities: {
      one: garden,
      two: garden2,
      three: garden3,
    },
    strategies: [await ethers.getContractAt('Strategy', strategies[0])],
    gardenValuer,
    priceOracle,
    owner,
    signer1,
    signer2,
    signer3,
    contractsToPublish: [
      { name: 'BabController', contract: babController },
      { name: 'BABLToken', contract: bablToken },
      { name: 'TimeLockRegistry', contract: timeLockRegistry }, 
      { name: 'StrategyFactory', contract: strategyFactory },
      { name: 'KyberTradeIntegration', contract: kyberTradeIntegration },
      { name: 'BalancerIntegration', contract: balancerIntegration },
      { name: 'YearnVaultIntegration', contract: yearnVaultIntegration },
      { name: 'UniswapPoolIntegration', contract: uniswapPoolIntegration },
    ],
  };
}

module.exports = { deployFolioFixture };
