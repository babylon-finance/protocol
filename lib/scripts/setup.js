const {
  ONE_DAY_IN_SECONDS,
  GARDEN_PARAMS,
  BABL_GARDEN_PARAMS,
  WBTC_GARDEN_PARAMS,
  USDC_GARDEN_PARAMS,
} = require('../constants.js');
const addresses = require('../addresses.js');

async function setup(hre) {
  const { fund } = require('../whale');
  const { impersonateAddress } = require('../rpc');
  const { getERC20, eth, from, increaseTime } = require('utils/test-helpers');
  const { ethers } = hre;
  const { getContracts, deployFixture } = require('lib/deploy');
  const startBlock = await ethers.provider.getBlock();

  console.log('--- START SETUP SCRIPT ---');
  let owner;
  let ownerV2;
  let controller;
  let distributor;
  let distributorAssistant;
  let valuer;
  let gov;
  let deployer;
  let keeper;
  let gardens;
  let strategyNft;
  let gardensNAV;
  let snapshotId;
  let heartGarden;
  let ishtarGate;
  let gnosis;
  let tokenIdentifier;
  let heart;
  let heartViewer;

  const {
    createStrategy,
    executeStrategy,
    finalizeStrategy,
    injectFakeProfits,
  } = require('../../test/fixtures/StrategyHelper');
  const [
    // deployer,
    // keeper,
    signer1,
    signer2,
    signer3,
    signer4,
    signer5,
    signer6,
    signer7,
    signer8,
  ] = await ethers.getSigners();

  ({
    owner,
    ownerV2,
    gov,
    keeper,
    gardens,
    gardensNAV,
    strategyNft,
    // valuer,
    heartGarden,
    // heartViewer,
  } = await deployFixture());

  ({
    owner,
    ownerV2,
    gov,
    deployer,
    keeper,
    controller,
    distributor,
    distributorAssistant,
    strategyNft,
    valuer,
    gardens,
    ishtarGate,
    gnosis,
    tokenIdentifier,
    heart,
  } = await getContracts());

  const gardenParams = GARDEN_PARAMS;

  const uniswapV3TradeIntegration = await ethers.getContractAt(
    'UniswapV3TradeIntegration',
    '0xc300FB5dE5384bcA63fb6eb3EfD9DB7dFd10325C',
  );

  const timelockController = gov;

  const bablToken = await ethers.getContractAt('BABLToken', addresses.tokens.BABL);

  console.log('creator permissions');
  // Gives signer1 creator permissions
  await ishtarGate.connect(ownerV2).setCreatorPermissions(signer1.address, true, { gasPrice: 0 });
  await ishtarGate.connect(ownerV2).setCreatorPermissions(deployer.address, true, { gasPrice: 0 });

  // Give assigned wallets creator permission
  await ishtarGate.connect(ownerV2).setCreatorPermissions(signer4.address, true, { gasPrice: 0 });
  await ishtarGate.connect(ownerV2).setCreatorPermissions(signer5.address, true, { gasPrice: 0 });
  await ishtarGate.connect(ownerV2).setCreatorPermissions(signer6.address, true, { gasPrice: 0 });
  await ishtarGate.connect(ownerV2).setCreatorPermissions(signer7.address, true, { gasPrice: 0 });
  await ishtarGate.connect(ownerV2).setCreatorPermissions(signer8.address, true, { gasPrice: 0 });

  const NFT_URI = 'https://babylon.mypinata.cloud/ipfs/QmcL826qNckBzEk2P11w4GQrrQFwGvR6XmUCuQgBX9ck1v';

  // Some old pin from testing, but should work fine for this purpose
  const NFT_SEED = '504592746';

  console.log('Giving Reserve Assets to owner and test accounts...');
  console.log('Giving DAI...');
  console.log('Giving USDC...');
  console.log('Giving WETH...');
  console.log('Giving WBTC...');
  console.log('Giving BABL...');
  await fund(
    [
      deployer.address,
      signer1.address,
      signer4.address,
      signer5.address,
      signer6.address,
      signer7.address,
      signer8.address,
    ],
    {
      tokens: [
        addresses.tokens.USDC,
        addresses.tokens.DAI,
        addresses.tokens.WETH,
        addresses.tokens.BABL,
        addresses.tokens.WBTC,
      ],
    },
  );

  console.log('creating gardens');

  console.log('creating BABL garden');
  console.log('BABL balance', ethers.utils.formatEther(await bablToken.balanceOf(signer1.address)));
  await bablToken.connect(signer1).approve(controller.address, await bablToken.balanceOf(signer1.address), {
    gasPrice: 0,
  });

  await controller
    .connect(signer1)
    .createGarden(
      addresses.tokens.BABL,
      'The Test Heart of Babylon',
      'hBABL',
      NFT_URI,
      NFT_SEED,
      BABL_GARDEN_PARAMS,
      eth('30'),
      [true, true, true],
      [0, 0, 0],
      {
        value: 0,
      },
    );

  console.log('creating USDC garden');
  const usdcToken = await getERC20(addresses.tokens.USDC);
  await usdcToken.connect(signer1).approve(controller.address, await usdcToken.balanceOf(signer1.address), {
    gasPrice: 0,
  });
  await controller
    .connect(signer1)
    .createGarden(
      addresses.tokens.USDC,
      'USDC Stronghold',
      'USDCS',
      NFT_URI,
      NFT_SEED,
      USDC_GARDEN_PARAMS,
      ethers.BigNumber.from('1000000000'),
      [true, true, true],
      [0, 0, 0],
      {
        value: 0,
      },
    );

  console.log('creating WBTC garden');
  const wbtcToken = await getERC20(addresses.tokens.WBTC);
  await wbtcToken.connect(signer1).approve(controller.address, await wbtcToken.balanceOf(signer1.address), {
    gasPrice: 0,
  });
  await controller
    .connect(signer1)
    .createGarden(
      addresses.tokens.WBTC,
      'WBTC Vault',
      'WBTCS',
      NFT_URI,
      NFT_SEED,
      WBTC_GARDEN_PARAMS,
      ethers.BigNumber.from('10000000'),
      [true, true, true],
      [0, 0, 0],
      {
        value: 0,
      },
    );

  await controller
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'Absolute ETH Return [beta]',
      'EYFA',
      NFT_URI,
      NFT_SEED,
      gardenParams,
      eth('1'),
      [true, true, true],
      [0, 0, 0],
      {
        value: eth('1'),
      },
    );

  await controller
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'ETH Yield Farm [a]',
      'EYFB',
      NFT_URI,
      NFT_SEED,
      gardenParams,
      eth('1'),
      [true, true, true],
      [0, 0, 0],
      {
        value: eth('1'),
      },
    );

  await controller
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'ETH Yield Farm [b]',
      'EYFG',
      NFT_URI,
      NFT_SEED,
      gardenParams,
      eth('1'),
      [true, true, true],
      [0, 0, 0],
      {
        value: eth('1'),
      },
    );

  await controller
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'ETH Yield Farm [d]',
      'EYFG',
      NFT_URI,
      NFT_SEED,
      gardenParams,
      eth('1'),
      [true, true, true],
      [0, 0, 0],
      {
        value: eth('1'),
      },
    );

  console.log('after creating gardens');
  const updatedGardens = await controller.getGardens();
  const gardensLength = from(updatedGardens.length);

  // Set the heart
  // await heartViewer.connect(gov).setHeartGarden(heartGarden.address, { gasPrice: 0 });

  const garden1 = await ethers.getContractAt('Garden', updatedGardens[gardensLength.sub(4)]);

  const garden2 = await ethers.getContractAt('Garden', updatedGardens[gardensLength.sub(3)]);

  const garden3 = await ethers.getContractAt('Garden', updatedGardens[gardensLength.sub(2)]);

  const heartTestGarden = await ethers.getContractAt('Garden', updatedGardens[gardensLength.sub(1)]);

  await heart
    .connect(keeper)
    .resolveGardenVotes(
      [garden1.address, garden2.address, garden3.address],
      [eth().div(3), eth().div(3), eth().div(3)],
    );

  console.log('Granting access');
  // Grants community access to the last new created 7 gardens to save time
  for (let i = from(updatedGardens.length).sub(7); i < updatedGardens.length; i += 1) {
    const gardenContract = await ethers.getContractAt('Garden', updatedGardens[i]);
    const creator = await impersonateAddress(await gardenContract.creator());
    await ishtarGate.connect(creator).grantGardenAccessBatch(
      updatedGardens[i],
      [
        deployer.address,
        keeper.address,
        signer1.address,
        signer2.address,
        // local test wallets
        signer4.address,
        signer5.address,
        signer6.address,
        signer7.address,
        signer8.address,
      ],
      [3, 3, 3, 3, 3, 3, 3, 3, 3],
      {
        gasPrice: 0,
      },
    );
  }

  console.log('Active strategies deployed...');
  console.log('Deploying finalized strategy with profits...');
  const strategy1 = await createStrategy(
    'buy',
    'vote',
    [signer1, signer2, signer3],
    uniswapV3TradeIntegration.address,
    garden3,
    keeper,
  );
  console.log('trying to execute');
  await executeStrategy(strategy1, { amount: eth('3'), executedBy: keeper });
  console.log('executed');

  await injectFakeProfits(strategy1, eth().mul(100));

  await increaseTime(ONE_DAY_IN_SECONDS * 365 * 3);
  await finalizeStrategy(strategy1, { time: ONE_DAY_IN_SECONDS.mul(ethers.BigNumber.from(30)), executedBy: keeper });
  // Create strategies
  await createStrategy(
    'buy',
    'dataset',
    [signer1, signer2, signer3],
    uniswapV3TradeIntegration.address,
    garden1,
    keeper,
  );

  await createStrategy(
    'buy',
    'deposit',
    [signer1, signer2, signer3],
    uniswapV3TradeIntegration.address,
    garden2,
    keeper,
  );

  await createStrategy(
    'buy',
    'deposit',
    [signer1, signer2, signer3],
    uniswapV3TradeIntegration.address,
    garden3,
    keeper,
  );
  await createStrategy(
    'buy',
    'dataset',
    [signer1, signer2, signer3],
    uniswapV3TradeIntegration.address,
    garden3,
    keeper,
  );

  console.log('Contracts deployed...');

  console.log('Deploying test strategies...');

  await createStrategy(
    'buy',
    'active',
    [signer1, signer2, signer3],
    uniswapV3TradeIntegration.address,
    garden3,
    keeper,
  );
  await createStrategy(
    'buy',
    'active',
    [signer1, signer2, signer3],
    uniswapV3TradeIntegration.address,
    garden3,
    keeper,
  );

  console.log('Test strategies deployed...');
  console.log('Artifacts sync complete..');
  console.log('📡 Contract deploy complete! \n');

  console.log('Created and started garden', garden1.address);
  console.log('Created manual testing garden', garden3.address);
  const endBlock = await ethers.provider.getBlock();
  console.log('Difference in time for manual testing (in secs)', endBlock.timestamp - startBlock.timestamp);

  if (process.env.HRE_NO_AUTOMINE === 'true') {
    console.log('Disabling automine...');
    await ethers.provider.send('evm_setAutomine', [false]);
    await ethers.provider.send('evm_setIntervalMining', [5000]);
    console.log('Disabling automine complete!');
  }
}

module.exports = {
  setup,
};
