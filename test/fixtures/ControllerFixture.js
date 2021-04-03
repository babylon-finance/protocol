const { ethers } = require('hardhat');
const { ONE_DAY_IN_SECONDS } = require('../../utils/constants.js');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../../utils/system.js');
const addresses = require('../../utils/addresses');
const argsUtil = require('../../utils/arguments.js');
const { createStrategy } = require('./StrategyHelper.js');

async function deployFolioFixture() {
  const [owner, signer1, signer2, signer3] = await ethers.getSigners();

  const SafeDecimalMathFactory = await ethers.getContractFactory('SafeDecimalMath');
  const SafeDecimalMath = await SafeDecimalMathFactory.deploy();

  const BabController = await ethers.getContractFactory('BabController', owner);
  const babController = await BabController.deploy(...argsUtil.readArgumentsFile('BabController'));

  await babController.addReserveAsset(addresses.tokens.WETH);
  await babController.addKeepers(Object.values(addresses.users));

  // Deployment of BABL Token contract
  const BABLToken = await ethers.getContractFactory('BABLToken', owner);
  const bablToken = await BABLToken.connect(owner).deploy();

  // Deployment of Time Lock Registry contract
  const TimeLockRegistry = await ethers.getContractFactory('TimeLockRegistry', owner);
  const timeLockRegistry = await TimeLockRegistry.deploy(bablToken.address);

  // Sets the Time Lock Registry address
  await bablToken.setTimeLockRegistry(timeLockRegistry.address);

  // Approve Time Lock Registry to handle 31% of the Tokens for vesting (Team, Advisors, Investors)
  await bablToken.approve(timeLockRegistry.address, ethers.utils.parseEther('310000'));

  const RewardsDistributor = await ethers.getContractFactory('RewardsDistributor', {
    libraries: {
      SafeDecimalMath: SafeDecimalMath.address,
    },
    signer: owner,
  });

  const rewardsDistributor = await RewardsDistributor.deploy(bablToken.address, babController.address);

  const GardenValuer = await ethers.getContractFactory('GardenValuer', owner);
  const PriceOracle = await ethers.getContractFactory('PriceOracle', owner);
  const ReservePool = await ethers.getContractFactory('ReservePool', owner);
  const Treasury = await ethers.getContractFactory('Treasury', owner);
  const UniswapTWAP = await ethers.getContractFactory('UniswapTWAP', owner);
  const GardenFactory = await ethers.getContractFactory('GardenFactory', owner);
  const LongStrategyFactory = await ethers.getContractFactory('LongStrategyFactory', owner);
  const LiquidityPoolStrategyFactory = await ethers.getContractFactory('LiquidityPoolStrategyFactory', owner);
  const YieldFarmingStrategyFactory = await ethers.getContractFactory('YieldFarmingStrategyFactory', owner);
  const LendStrategyFactory = await ethers.getContractFactory('LendStrategyFactory', owner);

  const gardenValuer = await GardenValuer.deploy(babController.address);
  const reservePool = await ReservePool.deploy(babController.address);
  const treasury = await Treasury.deploy(babController.address);
  const gardenFactory = await GardenFactory.deploy();
  const longStrategyFactory = await LongStrategyFactory.deploy();
  const liquidityPoolStrategyFactory = await LiquidityPoolStrategyFactory.deploy();
  const yieldFarmingStrategyFactory = await YieldFarmingStrategyFactory.deploy();
  const lendStrategyFactory = await LendStrategyFactory.deploy();

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
  babController.editRewardsDistributor(rewardsDistributor.address);
  babController.editReservePool(reservePool.address);
  babController.editGardenFactory(gardenFactory.address);
  babController.editStrategyFactory(0, longStrategyFactory.address);
  babController.editStrategyFactory(1, liquidityPoolStrategyFactory.address);
  babController.editStrategyFactory(2, yieldFarmingStrategyFactory.address);
  babController.editStrategyFactory(3, lendStrategyFactory.address);

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
  const SushiswapPoolIntegration = await ethers.getContractFactory('SushiswapPoolIntegration', owner);
  const sushiswapPoolIntegration = await SushiswapPoolIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.sushiswap.router,
  );

  const YearnVaultIntegration = await ethers.getContractFactory('YearnVaultIntegration', owner);
  const yearnVaultIntegration = await YearnVaultIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.yearn.vaultRegistry,
  );

  const CompoundLendIntegration = await ethers.getContractFactory('CompoundLendIntegration', owner);
  const compoundLendIntegration = await CompoundLendIntegration.deploy(babController.address, addresses.tokens.WETH);

  const AaveLendIntegration = await ethers.getContractFactory('AaveLendIntegration', owner);
  const aaveLendIntegration = await AaveLendIntegration.deploy(babController.address, addresses.tokens.WETH);

  const integrationsList = [
    kyberTradeIntegration,
    oneInchTradeIntegration,
    balancerIntegration,
    uniswapPoolIntegration,
    yearnVaultIntegration,
    compoundLendIntegration,
    aaveLendIntegration,
    sushiswapPoolIntegration,
  ];

  // Adding integrations
  integrationsList.forEach(async (integration) => {
    babController.addIntegration(await integration.getName(), integration.address);
  });

  // Creates a new Garden instance

  await babController.connect(signer1).createRollingGarden(addresses.tokens.WETH, 'Absolute ETH Return [beta]', 'EYFA');

  await babController.connect(signer1).createRollingGarden(addresses.tokens.WETH, 'ETH Yield Farm [a]', 'EYFB');

  await babController.connect(signer1).createRollingGarden(addresses.tokens.WETH, 'ETH Yield Farm [b]', 'EYFG');

  await babController.connect(signer1).createRollingGarden(addresses.tokens.WETH, 'ETH Yield Farm [d]', 'EYFG');

  const gardens = await babController.getGardens();

  const garden1 = await ethers.getContractAt('RollingGarden', gardens[0]);

  const garden2 = await ethers.getContractAt('RollingGarden', gardens[1]);

  const garden3 = await ethers.getContractAt('RollingGarden', gardens[2]);

  const garden4 = await ethers.getContractAt('RollingGarden', gardens[3]);

  // Initial deposit
  await garden1.connect(signer1).start(
    ethers.utils.parseEther('20'),
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

  // Initial deposit
  await garden2.connect(signer1).start(
    ethers.utils.parseEther('20'),
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

  // NOTE: Use this garden for manual testing in the dApp
  // Initial deposit
  await garden3.connect(signer1).start(
    ethers.utils.parseEther('20'),
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

  // Create strategies
  const strategy11 = (
    await createStrategy(0, 'dataset', [signer1, signer2, signer3], kyberTradeIntegration.address, garden1)
  ).address;
  const strategy21 = (
    await createStrategy(0, 'deposit', [signer1, signer2, signer3], kyberTradeIntegration.address, garden2)
  ).address;

  await createStrategy(0, 'deposit', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);
  await createStrategy(0, 'dataset', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);

  console.log('Created and started garden', garden1.address);
  console.log('Created manual testing garden', garden3.address);

  return {
    babController,
    bablToken,
    timeLockRegistry,
    reservePool,
    treasury,
    rewardsDistributor,
    kyberTradeIntegration,
    oneInchTradeIntegration,
    balancerIntegration,
    uniswapPoolIntegration,
    yearnVaultIntegration,
    sushiswapPoolIntegration,
    compoundLendIntegration,
    aaveLendIntegration,

    garden1,
    garden2,
    garden3,
    garden4,

    strategy11,
    strategy21,

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
      { name: 'LongStrategyFactory', contract: longStrategyFactory },
      { name: 'RewardsDistributor', contract: rewardsDistributor },
      { name: 'KyberTradeIntegration', contract: kyberTradeIntegration },
      { name: 'BalancerIntegration', contract: balancerIntegration },
      { name: 'YearnVaultIntegration', contract: yearnVaultIntegration },
      { name: 'UniswapPoolIntegration', contract: uniswapPoolIntegration },
      { name: 'SushiswapPoolIntegration', contract: sushiswapPoolIntegration },
      { name: 'CompoundLendIntegration', contract: compoundLendIntegration },
      { name: 'AaveLendIntegration', contract: aaveLendIntegration },
    ],
  };
}

module.exports = { deployFolioFixture };
