const { ethers, upgrades, config } = require('hardhat');
const addresses = require('../lib/addresses');
const fs = require('fs');

const { ONE_DAY_IN_SECONDS, ADDRESS_ZERO } = require('../lib/constants.js');
const { TWAP_ORACLE_WINDOW, TWAP_ORACLE_GRANULARITY } = require('../lib/system.js');

const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
} = require('../test/fixtures/StrategyHelper');

async function main() {
  const [owner, signer1, signer2, signer3] = await ethers.getSigners();

  const BabController = await ethers.getContractFactory('BabController', owner);
  // the deployer is an proxy admin
  const babController = await upgrades.deployProxy(BabController, []);

  await babController.addReserveAsset(addresses.tokens.WETH);
  await babController.addKeepers(Object.values(addresses.users));

  // Deployment of BABL Token contract
  const BABLToken = await ethers.getContractFactory('BABLToken', owner);
  const bablToken = await BABLToken.connect(owner).deploy(ADDRESS_ZERO); // We will use CREATE2

  // Deployment of Time Lock Registry contract
  const TimeLockRegistry = await ethers.getContractFactory('TimeLockRegistry', owner);
  const timeLockRegistry = await TimeLockRegistry.deploy(bablToken.address);

  // Sets the Time Lock Registry address
  await bablToken.setTimeLockRegistry(timeLockRegistry.address);

  // Approve Time Lock Registry to handle 31% of the Tokens for vesting (Team, Advisors, Investors)
  await bablToken.approve(timeLockRegistry.address, ethers.utils.parseEther('310000'));

  const SafeDecimalMathFactory = await ethers.getContractFactory('SafeDecimalMath');
  const SafeDecimalMath = await SafeDecimalMathFactory.deploy();

  const RewardsDistributor = await ethers.getContractFactory('RewardsDistributor', {
    libraries: {
      SafeDecimalMath: SafeDecimalMath.address,
    },
    signer: owner,
  });

  const rewardsDistributor = await RewardsDistributor.deploy(bablToken.address, babController.address);

  const GardenValuer = await ethers.getContractFactory('GardenValuer', owner);
  const gardenValuer = await GardenValuer.deploy(babController.address);

  const Treasury = await ethers.getContractFactory('Treasury', owner);
  const treasury = await Treasury.deploy(babController.address);

  const IshtarGate = await ethers.getContractFactory('IshtarGate', owner);
  const ishtarGate = await IshtarGate.deploy(babController.address, 'http://json.api/test');

  const GardenFactory = await ethers.getContractFactory('GardenFactory', owner);
  const gardenFactory = await GardenFactory.deploy();

  const LongStrategyFactory = await ethers.getContractFactory('LongStrategyFactory', owner);
  const longStrategyFactory = await LongStrategyFactory.deploy();

  const LiquidityPoolStrategyFactory = await ethers.getContractFactory('LiquidityPoolStrategyFactory', owner);
  const liquidityPoolStrategyFactory = await LiquidityPoolStrategyFactory.deploy();

  const YieldFarmingStrategyFactory = await ethers.getContractFactory('YieldFarmingStrategyFactory', owner);
  const yieldFarmingStrategyFactory = await YieldFarmingStrategyFactory.deploy();

  const LendStrategyFactory = await ethers.getContractFactory('LendStrategyFactory', owner);
  const lendStrategyFactory = await LendStrategyFactory.deploy();

  const UniswapTWAP = await ethers.getContractFactory('UniswapTWAP', owner);
  const uniswapTWAPAdapter = await UniswapTWAP.deploy(
    babController.address,
    addresses.uniswap.factory,
    TWAP_ORACLE_WINDOW,
    TWAP_ORACLE_GRANULARITY,
  );

  const PriceOracle = await ethers.getContractFactory('PriceOracle', owner);
  const priceOracle = await PriceOracle.deploy(babController.address, addresses.compound.OpenOracle, [
    uniswapTWAPAdapter.address,
  ]);

  // Sets the price oracle and gardenvaluer address
  await babController.editPriceOracle(priceOracle.address);
  await babController.editTreasury(treasury.address);
  await babController.editGardenValuer(gardenValuer.address);
  await babController.editIshtarGate(ishtarGate.address);
  await babController.editRewardsDistributor(rewardsDistributor.address);
  await babController.editGardenFactory(gardenFactory.address);
  await babController.editStrategyFactory(0, longStrategyFactory.address);
  await babController.editStrategyFactory(1, liquidityPoolStrategyFactory.address);
  await babController.editStrategyFactory(2, yieldFarmingStrategyFactory.address);
  await babController.editStrategyFactory(3, lendStrategyFactory.address);

  // Create integrations
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

  const gardenParams = [
    ethers.utils.parseEther('20'), // Max Deposit Limit
    1, // Min Garden Token Supply
    ethers.utils.parseEther('1000'), // Min Liquidity Asset | ie: Uniswap Volume
    1, // Deposit Hardlock | 1 second
    ethers.utils.parseEther('0.10'), // Min Contribution
    ONE_DAY_IN_SECONDS, // Strategy Cooldown Period
    ethers.utils.parseEther('0.10'), // Min Voter Quorum | 10%
    ONE_DAY_IN_SECONDS * 3, // Min Strategy Duration
    ONE_DAY_IN_SECONDS * 365, // Max Strategy Duration
  ];

  // Gives signer1 creator permissions
  await ishtarGate.connect(owner).setCreatorPermissions(signer1.address, true, { gasPrice: 0 });

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'Absolute ETH Return [beta]', 'EYFA', gardenParams, 'http...', {
      value: ethers.utils.parseEther('1'),
    });

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'ETH Yield Farm [a]', 'EYFB', gardenParams, 'http...', {
      value: ethers.utils.parseEther('1'),
    });

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'ETH Yield Farm [b]', 'EYFG', gardenParams, 'http...', {
      value: ethers.utils.parseEther('1'),
    });

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'ETH Yield Farm [d]', 'EYFG', gardenParams, 'http...', {
      value: ethers.utils.parseEther('1'),
    });

  const gardens = await babController.getGardens();

  const garden1 = await ethers.getContractAt('Garden', gardens[0]);

  const garden2 = await ethers.getContractAt('Garden', gardens[1]);

  const garden3 = await ethers.getContractAt('Garden', gardens[2]);

  const garden4 = await ethers.getContractAt('Garden', gardens[3]);

  // Grants community access
  for (let i = 0; i < gardens.length; i += 1) {
    await ishtarGate
      .connect(signer1)
      .grantGardenAccessBatch(
        gardens[i],
        [owner.address, signer1.address, signer2.address, signer3.address],
        [3, 3, 3, 3],
        {
          gasPrice: 0,
        },
      );
  }
  // Create strategies
  const strategy11 = (
    await createStrategy('long', 'dataset', [signer1, signer2, signer3], kyberTradeIntegration.address, garden1)
  ).address;
  const strategy21 = (
    await createStrategy('long', 'deposit', [signer1, signer2, signer3], kyberTradeIntegration.address, garden2)
  ).address;

  await createStrategy('long', 'deposit', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);
  await createStrategy('long', 'dataset', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);

  console.log('Created and started garden', garden1.address);
  console.log('Created manual testing garden', garden3.address);

  const contractsToPublish = [
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
  ];

  console.log('Contracts deployed...');

  console.log('Deploying test strategies...');
  await createStrategy('long', 'active', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);
  await createStrategy('long', 'active', [signer1, signer2, signer3], kyberTradeIntegration.address, garden3);
  console.log('Active strategies deployed...');
  console.log('Deploying finalized strategy with profits...');
  const strategy1 = await createStrategy(
    'long',
    'vote',
    [signer1, signer2, signer3],
    kyberTradeIntegration.address,
    garden3,
  );
  await executeStrategy(strategy1);
  await injectFakeProfits(strategy1, ethers.utils.parseEther('5000'));
  await finalizeStrategy(strategy1, { time: ONE_DAY_IN_SECONDS.mul(ethers.BigNumber.from(30)) });
  console.log('Test strategies deployed...');

  console.log('Syncing artifacts for export...');
  // Let the fixture response determine which contracts to write address
  // files for and export accordingly in contracts.js.
  contractsToPublish.forEach((contractObj) => {
    const name = contractObj.name;
    const address = contractObj.contract.address;

    if (!name) {
      console.log('No name provided for contract, exiting...');
      process.exit(1);
    }

    fs.writeFileSync(`artifacts/${name}.address`, address);
  });

  console.log('Artifacts sync complete..');
  console.log('📡 Contract deploy complete! \n');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
