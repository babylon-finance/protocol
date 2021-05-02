const { ONE_DAY_IN_SECONDS } = require('../constants.js');
const addresses = require('../addresses.js');

async function setup({ ethers, deployments }) {
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

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'Absolute ETH Return [beta]', 'EYFA', 'http...', 0, gardenParams, {
      value: ethers.utils.parseEther('1'),
    });

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'ETH Yield Farm [a]', 'EYFB', 'http...', 0, gardenParams, {
      value: ethers.utils.parseEther('1'),
    });

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'ETH Yield Farm [b]', 'EYFG', 'http...', 0, gardenParams, {
      value: ethers.utils.parseEther('1'),
    });

  await babController
    .connect(signer1)
    .createGarden(addresses.tokens.WETH, 'ETH Yield Farm [d]', 'EYFG', 'http...', 0, gardenParams, {
      value: ethers.utils.parseEther('1'),
    });

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

  console.log('Test strategies deployed...');
  console.log('Artifacts sync complete..');
  console.log('📡 Contract deploy complete! \n');

  console.log('Created and started garden', garden1.address);
  console.log('Created manual testing garden', garden3.address);
}

module.exports = {
  setup,
};
