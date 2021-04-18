const { ethers, upgrades } = require('hardhat');
const { ONE_DAY_IN_SECONDS } = require('../../utils/constants.js');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../../utils/system.js');
const addresses = require('../../utils/addresses');
const { impersonateAddress } = require('../../utils/rpc');
const { createStrategy } = require('./StrategyHelper.js');

async function deployFolioFixture() {
  const [owner, signer1, signer2, signer3] = await ethers.getSigners();

  const SafeDecimalMathFactory = await ethers.getContractFactory('SafeDecimalMath');
  const SafeDecimalMath = await SafeDecimalMathFactory.deploy();

  const BabController = await ethers.getContractFactory('BabController', owner);
  // the deployer is an proxy admin
  const babController = await upgrades.deployProxy(BabController, []);

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
  const Treasury = await ethers.getContractFactory('Treasury', owner);
  const UniswapTWAP = await ethers.getContractFactory('UniswapTWAP', owner);
  const GardenFactory = await ethers.getContractFactory('GardenFactory', owner);
  const LongStrategyFactory = await ethers.getContractFactory('LongStrategyFactory', owner);
  const LiquidityPoolStrategyFactory = await ethers.getContractFactory('LiquidityPoolStrategyFactory', owner);
  const YieldFarmingStrategyFactory = await ethers.getContractFactory('YieldFarmingStrategyFactory', owner);
  const LendStrategyFactory = await ethers.getContractFactory('LendStrategyFactory', owner);

  const gardenValuer = await GardenValuer.deploy(babController.address);
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

  const OneInchPoolIntegration = await ethers.getContractFactory('OneInchPoolIntegration', owner);
  const oneInchPoolIntegration = await OneInchPoolIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.oneinch.factory,
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
    oneInchPoolIntegration,
  ];

  // Adding integrations
  integrationsList.forEach(async (integration) => {
    babController.addIntegration(await integration.getName(), integration.address);
  });

  // Creates a new Garden instance

  const gardenParams = [
    ethers.utils.parseEther('20'),
    1,
    ethers.utils.parseEther('1000'),
    2,
    ethers.utils.parseEther('0.01'),
    ONE_DAY_IN_SECONDS,
    ethers.utils.parseEther('0.10'), // 10% quorum
    ONE_DAY_IN_SECONDS * 3,
    ONE_DAY_IN_SECONDS * 365,
  ];

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'Absolute ETH Return [beta]', 'EYFA', gardenParams, {
      value: ethers.utils.parseEther('0.1'),
    });

  await babController.connect(signer1).createGarden(addresses.tokens.WETH, 'ETH Yield Farm [a]', 'EYFB', gardenParams, {
    value: ethers.utils.parseEther('0.1'),
  });

  await babController.connect(signer1).createGarden(addresses.tokens.WETH, 'ETH Yield Farm [b]', 'EYFG', gardenParams, {
    value: ethers.utils.parseEther('0.1'),
  });

  await babController.connect(signer1).createGarden(addresses.tokens.WETH, 'ETH Yield Farm [d]', 'EYFG', gardenParams, {
    value: ethers.utils.parseEther('0.1'),
  });

  const gardens = await babController.getGardens();

  const garden1 = await ethers.getContractAt('Garden', gardens[0]);

  const garden2 = await ethers.getContractAt('Garden', gardens[1]);

  const garden3 = await ethers.getContractAt('Garden', gardens[2]);

  const garden4 = await ethers.getContractAt('Garden', gardens[3]);

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

  const daiWhaleSigner = await impersonateAddress('0x6B175474E89094C44Da98b954EedeAC495271d0F');
  const wethWhaleSigner = await impersonateAddress('0xC8dDA504356195ba5344E5a9826Ce07DfEaA97b6');

  return {
    babController,
    bablToken,
    timeLockRegistry,
    treasury,
    rewardsDistributor,
    kyberTradeIntegration,
    oneInchTradeIntegration,
    balancerIntegration,
    uniswapPoolIntegration,
    yearnVaultIntegration,
    sushiswapPoolIntegration,
    oneInchPoolIntegration,
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
    daiWhaleSigner,
    wethWhaleSigner,

    contractsToPublish: [
      { name: 'AaveLendIntegration', contract: aaveLendIntegration },
      { name: 'BABLToken', contract: bablToken },
      { name: 'BabController', contract: babController },
      { name: 'BalancerIntegration', contract: balancerIntegration },
      { name: 'CompoundLendIntegration', contract: compoundLendIntegration },
      { name: 'GardenValuer', contract: gardenValuer },
      { name: 'KyberTradeIntegration', contract: kyberTradeIntegration },
      { name: 'LongStrategyFactory', contract: longStrategyFactory },
      { name: 'OneInchPoolIntegration', contract: oneInchPoolIntegration },
      { name: 'OneInchTradeIntegration', contract: oneInchTradeIntegration },
      { name: 'RewardsDistributor', contract: rewardsDistributor },
      { name: 'SushiswapPoolIntegration', contract: sushiswapPoolIntegration },
      { name: 'TimeLockRegistry', contract: timeLockRegistry },
      { name: 'UniswapPoolIntegration', contract: uniswapPoolIntegration },
      { name: 'YearnVaultIntegration', contract: yearnVaultIntegration },
    ],
  };
}

module.exports = { deployFolioFixture };
