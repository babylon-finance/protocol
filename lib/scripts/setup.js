const { ONE_DAY_IN_SECONDS } = require('../constants.js');
const addresses = require('../addresses.js');
const { getAssetWhale } = require('../whale.js');

async function setup(hre) {
  const { ethers, deployments } = hre;
  const startBlock = await ethers.provider.getBlock();
  const impersonateAddress = async (address) => {
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [address],
    });

    const signer = await ethers.provider.getSigner(address);
    signer.address = signer._address;

    return signer;
  };

  const {
    createStrategy,
    executeStrategy,
    finalizeStrategy,
    injectFakeProfits,
  } = require('../../test/fixtures/StrategyHelper');
  const [
    deployer,
    keeper,
    owner,
    signer1,
    signer2,
    signer3,
    signer4,
    signer5,
    signer6,
    signer7,
    signer8,
  ] = await ethers.getSigners();

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
    1,
  ];
  const babController = await ethers.getContractAt(
    'BabController',
    (await deployments.get('BabControllerProxy')).address,
  );
  const ishtarGate = await ethers.getContractAt('IshtarGate', (await deployments.get('IshtarGate')).address);
  const oneInchTradeIntegration = await ethers.getContractAt(
    'OneInchTradeIntegration',
    (await deployments.get('OneInchTradeIntegration')).address,
  );

  // Gives signer1 creator permissions
  await ishtarGate.connect(owner).setCreatorPermissions(signer1.address, true, { gasPrice: 0 });
  await ishtarGate.connect(owner).setCreatorPermissions(owner.address, true, { gasPrice: 0 });
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
      {
        value: ethers.utils.parseEther('1'),
      },
    );

  const gardens = await babController.getGardens();

  const garden1 = await ethers.getContractAt('Garden', gardens[0]);

  const garden2 = await ethers.getContractAt('Garden', gardens[1]);

  const garden3 = await ethers.getContractAt('Garden', gardens[2]);

  await ethers.getContractAt('Garden', gardens[3]);

  // Grants community access
  for (let i = 0; i < gardens.length; i += 1) {
    await ishtarGate.connect(signer1).grantGardenAccessBatch(
      gardens[i],
      [
        deployer.address,
        keeper.address,
        owner.address,
        signer1.address,
        signer2.address,
        // local test wallets
        signer4.address,
        signer5.address,
        signer6.address,
        signer7.address,
        signer8.address,
      ],
      [3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
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
    oneInchTradeIntegration.address,
    garden3,
  );
  await executeStrategy(strategy1);
  await injectFakeProfits(strategy1, ethers.utils.parseEther('5000'));
  await finalizeStrategy(strategy1, { time: ONE_DAY_IN_SECONDS.mul(ethers.BigNumber.from(30)) });

  // Create strategies
  await createStrategy('buy', 'dataset', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden1);
  await createStrategy('buy', 'deposit', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden2);

  await createStrategy('buy', 'deposit', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden3);
  await createStrategy('buy', 'dataset', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden3);

  console.log('Contracts deployed...');

  console.log('Deploying test strategies...');

  await createStrategy('buy', 'active', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden3);
  await createStrategy('buy', 'active', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden3);

  console.log('Giving Reserve Assets to owner and test accounts...');
  const dai = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
  const daiWhaleAddress = getAssetWhale(addresses.tokens.DAI);
  const daiWhaleSigner = await impersonateAddress(daiWhaleAddress);
  const usdc = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
  const usdcWhaleAddress = getAssetWhale(addresses.tokens.USDC); // Has USDC
  const usdcWhaleSigner = await impersonateAddress(usdcWhaleAddress);
  const weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  const wethWhaleAddress = getAssetWhale(addresses.tokens.USDC);
  const wethWhaleSigner = await impersonateAddress(wethWhaleAddress);

  console.log('Giving DAI...');
  await dai.connect(daiWhaleSigner).transfer(owner.address, ethers.utils.parseEther('1000'), {
    gasPrice: 0,
  });
  await dai.connect(daiWhaleSigner).transfer(deployer.address, ethers.utils.parseEther('1000'), {
    gasPrice: 0,
  });
  await dai.connect(daiWhaleSigner).transfer(signer1.address, ethers.utils.parseEther('1000'), {
    gasPrice: 0,
  });

  // Assigned wallets for user testing
  await dai.connect(daiWhaleSigner).transfer(signer4.address, ethers.utils.parseEther('1000'), {
    gasPrice: 0,
  });
  await dai.connect(daiWhaleSigner).transfer(signer5.address, ethers.utils.parseEther('1000'), {
    gasPrice: 0,
  });
  await dai.connect(daiWhaleSigner).transfer(signer6.address, ethers.utils.parseEther('1000'), {
    gasPrice: 0,
  });
  await dai.connect(daiWhaleSigner).transfer(signer7.address, ethers.utils.parseEther('1000'), {
    gasPrice: 0,
  });
  await dai.connect(daiWhaleSigner).transfer(signer8.address, ethers.utils.parseEther('1000'), {
    gasPrice: 0,
  });

  console.log('Giving USDC...');
  const thousandUSDC = ethers.BigNumber.from(1000 * 1000000);

  await usdc.connect(usdcWhaleSigner).transfer(owner.address, thousandUSDC, {
    gasPrice: 0,
  });
  await usdc.connect(usdcWhaleSigner).transfer(deployer.address, thousandUSDC, {
    gasPrice: 0,
  });
  await usdc.connect(usdcWhaleSigner).transfer(signer1.address, thousandUSDC, {
    gasPrice: 0,
  });

  // Assigned wallets for user testing
  await usdc.connect(usdcWhaleSigner).transfer(signer4.address, thousandUSDC, {
    gasPrice: 0,
  });
  await usdc.connect(usdcWhaleSigner).transfer(signer5.address, thousandUSDC, {
    gasPrice: 0,
  });
  await usdc.connect(usdcWhaleSigner).transfer(signer6.address, thousandUSDC, {
    gasPrice: 0,
  });
  await usdc.connect(usdcWhaleSigner).transfer(signer7.address, thousandUSDC, {
    gasPrice: 0,
  });
  await usdc.connect(usdcWhaleSigner).transfer(signer8.address, thousandUSDC, {
    gasPrice: 0,
  });

  console.log('Giving WETH...');
  await weth.connect(wethWhaleSigner).transfer(deployer.address, ethers.utils.parseEther('5'), {
    gasPrice: 0,
  });
  await weth.connect(wethWhaleSigner).transfer(owner.address, ethers.utils.parseEther('5'), {
    gasPrice: 0,
  });
  await weth.connect(wethWhaleSigner).transfer(signer1.address, ethers.utils.parseEther('5'), {
    gasPrice: 0,
  });

  // Assigned wallets for user testing
  await weth.connect(wethWhaleSigner).transfer(signer4.address, ethers.utils.parseEther('5'), {
    gasPrice: 0,
  });
  await weth.connect(wethWhaleSigner).transfer(signer5.address, ethers.utils.parseEther('5'), {
    gasPrice: 0,
  });
  await weth.connect(wethWhaleSigner).transfer(signer6.address, ethers.utils.parseEther('5'), {
    gasPrice: 0,
  });
  await weth.connect(wethWhaleSigner).transfer(signer7.address, ethers.utils.parseEther('5'), {
    gasPrice: 0,
  });
  await weth.connect(wethWhaleSigner).transfer(signer8.address, ethers.utils.parseEther('5'), {
    gasPrice: 0,
  });

  console.log('Test strategies deployed...');
  console.log('Artifacts sync complete..');
  console.log('📡 Contract deploy complete! \n');

  console.log('Created and started garden', garden1.address);
  console.log('Created manual testing garden', garden3.address);
  const endBlock = await ethers.provider.getBlock();
  console.log('Difference in time for manual testing (in secs)', endBlock.timestamp - startBlock.timestamp);
}

module.exports = {
  setup,
};
