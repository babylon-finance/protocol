const { ONE_DAY_IN_SECONDS } = require('../constants.js');
const addresses = require('../addresses.js');

async function setup(hre) {
  const { ethers, deployments } = hre;

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
  const [deployer, keeper, owner, signer1, signer2, signer3] = await ethers.getSigners();

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

  const NFT_URI = 'https://babylon.mypinata.cloud/ipfs/QmcL826qNckBzEk2P11w4GQrrQFwGvR6XmUCuQgBX9ck1v';

  await babController
    .connect(signer1)
    .createGarden(
      addresses.tokens.WETH,
      'Absolute ETH Return [beta]',
      'EYFA',
      NFT_URI,
      0,
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
      0,
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
      0,
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
      0,
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
    await ishtarGate
      .connect(signer1)
      .grantGardenAccessBatch(
        gardens[i],
        [deployer.address, keeper.address, owner.address, signer1.address, signer2.address, signer3.address],
        [3, 3, 3, 3, 3, 3],
        {
          gasPrice: 0,
        },
      );
  }
  // Create strategies
  await createStrategy('buy', 'dataset', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden1);
  await createStrategy('buy', 'deposit', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden2);

  await createStrategy('buy', 'deposit', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden3);
  await createStrategy('buy', 'dataset', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden3);

  console.log('Contracts deployed...');

  console.log('Deploying test strategies...');

  await createStrategy('buy', 'active', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden3);
  await createStrategy('buy', 'active', [signer1, signer2, signer3], oneInchTradeIntegration.address, garden3);

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

  console.log('Giving Reserve Assets to owner and signer 1 account...');
  const dai = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
  const daiWhaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'; // Has DAI
  const daiWhaleSigner = await impersonateAddress(daiWhaleAddress);
  const usdc = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
  const usdcWhaleAddress = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503'; // Has USDC
  const usdcWhaleSigner = await impersonateAddress(usdcWhaleAddress);
  const weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  const wethWhaleAddress = '0x2f0b23f53734252bda2277357e97e1517d6b042a';
  const wethWhaleSigner = await impersonateAddress(wethWhaleAddress);
  console.log('Giving DAI...');
  await dai.connect(daiWhaleSigner).transfer(owner.address, ethers.utils.parseEther('1000'), {
    gasPrice: 0,
  });
  await dai.connect(daiWhaleSigner).transfer(signer1.address, ethers.utils.parseEther('1000'), {
    gasPrice: 0,
  });
  console.log('Giving USDC...');
  const thousandUSDC = ethers.BigNumber.from(1000 * 1000000);

  await usdc.connect(usdcWhaleSigner).transfer(owner.address, thousandUSDC, {
    gasPrice: 0,
  });
  await usdc.connect(usdcWhaleSigner).transfer(signer1.address, thousandUSDC, {
    gasPrice: 0,
  });
  console.log('Giving WETH...');
  await weth.connect(wethWhaleSigner).transfer(owner.address, ethers.utils.parseEther('5'), {
    gasPrice: 0,
  });
  await weth.connect(wethWhaleSigner).transfer(signer1.address, ethers.utils.parseEther('5'), {
    gasPrice: 0,
  });

  console.log('Test strategies deployed...');
  console.log('Artifacts sync complete..');
  console.log('📡 Contract deploy complete! \n');

  console.log('Created and started garden', garden1.address);
  console.log('Created manual testing garden', garden3.address);
}

module.exports = {
  setup,
};
