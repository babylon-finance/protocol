const { ONE_DAY_IN_SECONDS, GARDEN_PARAMS, BABL_GARDEN_PARAMS } = require('../constants.js');
const addresses = require('../addresses.js');

async function setup(hre) {
  const { fund } = require('../whale');
  const { impersonateAddress } = require('../rpc');
  const { ethers, deployments } = hre;
  const startBlock = await ethers.provider.getBlock();

  console.log('--- START SETUP SCRIPT ---');

  const {
    createStrategy,
    executeStrategy,
    finalizeStrategy,
    injectFakeProfits,
  } = require('../../test/fixtures/StrategyHelper');
  const [
    deployer,
    keeper,
    signer1,
    signer2,
    signer3,
    signer4,
    signer5,
    signer6,
    signer7,
    signer8,
  ] = await ethers.getSigners();

  const gardenParams = GARDEN_PARAMS;

  const babController = await ethers.getContractAt(
    'BabController',
    (await deployments.get('BabControllerProxy')).address,
  );
  const ishtarGate = await ethers.getContractAt('IshtarGate', (await deployments.get('IshtarGate')).address);

  const uniswapV3TradeIntegration = await ethers.getContractAt(
    'UniswapV3TradeIntegration',
    (await deployments.get('UniswapV3TradeIntegration')).address,
  );
  const timelockController = await getContract('TimelockController');

  const owner = await impersonateAddress(timelockController.address);
  const bablToken = await ethers.getContractAt('BABLToken', addresses.tokens.BABL);
  const ownerToken = await impersonateAddress(await bablToken.owner());
  console.log('enable token transfers');
  await bablToken.connect(ownerToken).enableTokensTransfers({ gasPrice: 0 });
  console.log('creator permissions');
  // Gives signer1 creator permissions
  await ishtarGate.connect(owner).setCreatorPermissions(signer1.address, true, { gasPrice: 0 });
  await ishtarGate.connect(owner).setCreatorPermissions(deployer.address, true, { gasPrice: 0 });

  // Give assigned wallets creator permission
  await ishtarGate.connect(owner).setCreatorPermissions(signer4.address, true, { gasPrice: 0 });
  await ishtarGate.connect(owner).setCreatorPermissions(signer5.address, true, { gasPrice: 0 });
  await ishtarGate.connect(owner).setCreatorPermissions(signer6.address, true, { gasPrice: 0 });
  await ishtarGate.connect(owner).setCreatorPermissions(signer7.address, true, { gasPrice: 0 });
  await ishtarGate.connect(owner).setCreatorPermissions(signer8.address, true, { gasPrice: 0 });

  const NFT_URI = 'https://babylon.mypinata.cloud/ipfs/QmcL826qNckBzEk2P11w4GQrrQFwGvR6XmUCuQgBX9ck1v';

  // Some old pin from testing, but should work fine for this purpose
  const NFT_SEED = '504592746';

  console.log('Giving Reserve Assets to owner and test accounts...');
  console.log('Giving DAI...');
  console.log('Giving USDC...');
  console.log('Giving WETH...');
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
      tokens: [addresses.tokens.USDC, addresses.tokens.DAI, addresses.tokens.WETH, addresses.tokens.BABL],
    },
  );

  console.log('creating gardens');

  console.log('creating BABL garden');
  console.log('BABL balance', ethers.utils.formatEther(await bablToken.balanceOf(signer1.address)));
  await bablToken.connect(signer1).approve(babController.address, await bablToken.balanceOf(signer1.address), {
    gasPrice: 0,
  });
  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.BABL,
      'BABL Stronghold',
      'BABLS',
      NFT_URI,
      NFT_SEED,
      BABL_GARDEN_PARAMS,
      ethers.utils.parseEther('30'),
      [false, false, false],
      [0, 0, 0],
      {
        value: 0,
      },
    );

  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'Absolute ETH Return [beta]',
      'EYFA',
      NFT_URI,
      NFT_SEED,
      gardenParams,
      ethers.utils.parseEther('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: ethers.utils.parseEther('1'),
      },
    );

  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'ETH Yield Farm [a]',
      'EYFB',
      NFT_URI,
      NFT_SEED,
      gardenParams,
      ethers.utils.parseEther('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: ethers.utils.parseEther('1'),
      },
    );

  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'ETH Yield Farm [b]',
      'EYFG',
      NFT_URI,
      NFT_SEED,
      gardenParams,
      ethers.utils.parseEther('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: ethers.utils.parseEther('1'),
      },
    );

  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'ETH Yield Farm [d]',
      'EYFG',
      NFT_URI,
      NFT_SEED,
      gardenParams,
      ethers.utils.parseEther('1'),
      [false, false, false],
      [0, 0, 0],
      {
        value: ethers.utils.parseEther('1'),
      },
    );

  console.log('after creating gardens');
  const gardens = await babController.getGardens();

  const gardenBabl = gardens[0];

  const garden1 = await ethers.getContractAt('Garden', gardens[2]);

  const garden2 = await ethers.getContractAt('Garden', gardens[3]);

  const garden3 = await ethers.getContractAt('Garden', gardens[4]);

  console.log('Granting access');
  // Grants community access
  for (let i = 0; i < gardens.length; i += 1) {
    await ishtarGate.connect(signer1).grantGardenAccessBatch(
      gardens[i],
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
  );

  await executeStrategy(strategy1);
  // await injectFakeProfits(strategy1, ethers.utils.parseEther('5000'));
  await finalizeStrategy(strategy1, { time: ONE_DAY_IN_SECONDS.mul(ethers.BigNumber.from(30)) });

  // Create strategies
  await createStrategy('buy', 'dataset', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden1);
  await createStrategy('buy', 'deposit', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden2);

  await createStrategy('buy', 'deposit', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden3);
  await createStrategy('buy', 'dataset', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden3);

  console.log('Contracts deployed...');

  console.log('Deploying test strategies...');

  await createStrategy('buy', 'active', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden3);
  await createStrategy('buy', 'active', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden3);

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
