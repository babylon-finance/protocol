const { ethers } = require('hardhat');
const { ONE_DAY_IN_SECONDS } = require('../../utils/constants.js');
const addresses = require('../../utils/addresses');

async function createLongStrategy(garden, integration, signer) {
  await garden.connect(signer).addStrategy(
    0, // Long Strategy
    ethers.utils.parseEther('10'),
    ethers.utils.parseEther('5'),
    ONE_DAY_IN_SECONDS * 30,
    ethers.utils.parseEther('0.05'), // 5%
    ethers.utils.parseEther('1'),
  );
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];

  const strategy = await ethers.getContractAt('LongStrategy', lastStrategyAddr);
  await strategy
    .connect(signer)
    .setLongData(
      integration,
      [],
      [],
      addresses.tokens.WETH,
      addresses.tokens.USDC,
      ethers.utils.parseEther('1'),
      ethers.utils.parseEther('900') / 10 ** 12,
      {
        gasPrice: 0,
      },
    );

  return strategy;
}

async function deposit(garden, signers) {
  await garden.connect(signers[0]).deposit(ethers.utils.parseEther('2'), 1, signers[0].getAddress(), {
    value: ethers.utils.parseEther('2'),
  });
  await garden.connect(signers[1]).deposit(ethers.utils.parseEther('2'), 1, signers[1].getAddress(), {
    value: ethers.utils.parseEther('2'),
  });
}

async function vote(garden, signers, strategy) {
  const [signer1, signer2] = signers;

  const signer1Balance = await garden.balanceOf(signer1.getAddress());
  const signer2Balance = await garden.balanceOf(signer2.getAddress());

  await strategy.resolveVoting(
    [signer1.getAddress(), signer1.getAddress()],
    [signer1Balance, signer2Balance],
    signer1Balance.add(signer2Balance).toString(),
    signer1Balance.add(signer2Balance).toString(),
    0,
    { gasPrice: 0 },
  );
}

async function execute(strategy) {
  ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

  await strategy.executeInvestment(ethers.utils.parseEther('1'), 0, {
    gasPrice: 0,
  });
}

async function finalize(strategy) {
  ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
  await strategy.finalizeInvestment(0, { gasPrice: 0 });
}

async function createStrategy(state, kind, signers, integration, garden) {
  let strategy;
  if (kind === 0) {
    strategy = await createLongStrategy(garden, integration, signers[0]);
  }
  if (state === 'dataset') {
    return strategy;
  }
  await deposit(garden, signers);
  if (state === 'deposit') {
    return strategy;
  }
  await vote(garden, signers, strategy);
  if (state === 'vote') {
    return strategy;
  }
  await execute(strategy);
  if (state === 'active') {
    return strategy;
  }
  await finalize(strategy);
  return strategy;
}

module.exports = {
  createStrategy,
};
