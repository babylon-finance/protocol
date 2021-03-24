const { ethers } = require('hardhat');
const { ONE_DAY_IN_SECONDS, EMPTY_BYTES } = require('../../utils/constants.js');
const addresses = require('../../utils/addresses');

async function createKyberDummyStrategy(garden, kyberIntegration, signer) {
  await garden.connect(signer).addStrategy(
    ethers.utils.parseEther('10'),
    ethers.utils.parseEther('5'),
    ONE_DAY_IN_SECONDS * 30,
    ethers.utils.parseEther('0.05'), // 5%
    ethers.utils.parseEther('1'),
  );
  const strategies = await garden.getStrategies();
  const lastStrategyAddr = strategies[strategies.length - 1];
  const kyberAbi = kyberIntegration.interface;
  const dataEnter = kyberAbi.encodeFunctionData(kyberAbi.functions['trade(address,uint256,address,uint256,bytes)'], [
    addresses.tokens.WETH,
    ethers.utils.parseEther('1'),
    addresses.tokens.USDC,
    ethers.utils.parseEther('900') / 10 ** 12,
    EMPTY_BYTES,
  ]);

  const dataExit = kyberAbi.encodeFunctionData(kyberAbi.functions['trade(address,uint256,address,uint256,bytes)'], [
    addresses.tokens.USDC,
    ethers.utils.parseEther('900') / 10 ** 12,
    addresses.tokens.WETH,
    ethers.utils.parseEther('0.1'),
    EMPTY_BYTES,
  ]);

  const strategy = await ethers.getContractAt('Strategy', lastStrategyAddr);
  await strategy.connect(signer).setIntegrationData(kyberIntegration.address, dataEnter, dataExit, [], [], {
    gasPrice: 0,
  });
  return strategy;
}

async function curateStrategy(strategy, garden, signers) {
  await garden.connect(signers[0]).deposit(ethers.utils.parseEther('2'), 1, signers[0].getAddress(), {
    value: ethers.utils.parseEther('2'),
  });
  let balanceSigner = await garden.balanceOf(signers[0].getAddress());
  await strategy.connect(signers[0]).curateIdea(balanceSigner);

  await garden.connect(signers[1]).deposit(ethers.utils.parseEther('2'), 1, signers[1].getAddress(), {
    value: ethers.utils.parseEther('2'),
  });
  balanceSigner = await garden.balanceOf(signers[1].getAddress());
  await strategy.connect(signers[1]).curateIdea(balanceSigner);
}

async function executeStrategy(strategy) {
  ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

  await strategy.executeInvestment(ethers.utils.parseEther('1'), {
    gasPrice: 0,
  });
}

async function finalizeStrategy(strategy) {
  ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
  await strategy.finalizeInvestment({ gasPrice: 0 });
}

async function createStrategy(kind, signers, kyberIntegration, garden) {
  const strategy = await createKyberDummyStrategy(garden, kyberIntegration, signers[0]);
  await curateStrategy(strategy, garden, signers);
  if (kind === 'candidate') {
    return strategy;
  }
  await executeStrategy(strategy);
  if (kind === 'active') {
    return strategy;
  }
  await finalizeStrategy(strategy);
  return strategy;
}

module.exports = {
  createStrategy,
};
