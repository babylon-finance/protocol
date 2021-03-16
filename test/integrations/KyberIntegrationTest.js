const { expect } = require('chai');
const { waffle, ethers } = require('hardhat');
// const { impersonateAddress } = require("../../utils/rpc");
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const addresses = require('../../utils/addresses');
const { EMPTY_BYTES, ONE_DAY_IN_SECONDS } = require('../../utils/constants');

const { loadFixture } = waffle;

describe('KyberTradeIntegration', function () {
  let system;
  let kyberIntegration;
  let kyberAbi;
  let garden;
  let userSigner1;
  let userSigner3;
  let strategy;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    kyberIntegration = system.integrations.kyberTradeIntegration;
    kyberAbi = kyberIntegration.interface;
    userSigner3 = system.signer3;
    userSigner1 = system.signer1;
    garden = system.comunities.one;
    strategy = system.strategies[0];
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await system.babController.deployed();
      const deployedKyber = await kyberIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedKyber).to.equal(true);
    });
  });

  describe('Trading', function () {
    let wethToken;
    let usdcToken;

    beforeEach(async () => {
      wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
      usdcToken = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
    });

    it('trade weth to usdc', async function () {
      await garden.connect(userSigner3).deposit(ethers.utils.parseEther('2'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('2'),
      });
      await garden.connect(userSigner1).deposit(ethers.utils.parseEther('2'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('2'),
      });
      expect(await wethToken.balanceOf(garden.address)).to.equal(ethers.utils.parseEther('4.1'));

      const dataEnter = kyberAbi.encodeFunctionData(
        kyberAbi.functions['trade(address,uint256,address,uint256,bytes)'],
        [
          addresses.tokens.WETH,
          ethers.utils.parseEther('1'),
          usdcToken.address,
          ethers.utils.parseEther('900') / 10 ** 12,
          EMPTY_BYTES,
        ],
      );

      const dataExit = kyberAbi.encodeFunctionData(kyberAbi.functions['trade(address,uint256,address,uint256,bytes)'], [
        usdcToken.address,
        ethers.utils.parseEther('900') / 10 ** 12,
        addresses.tokens.WETH,
        ethers.utils.parseEther('0.1'),
        EMPTY_BYTES,
      ]);

      await strategy.connect(userSigner1).setIntegrationData(kyberIntegration.address, dataEnter, dataExit, [], [], {
        gasPrice: 0,
      });

      await strategy.connect(userSigner3).curateIdea(await garden.balanceOf(userSigner3.getAddress()));

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      await strategy.executeInvestment(ethers.utils.parseEther('1'), {
        gasPrice: 0,
      });

      expect(await wethToken.balanceOf(strategy.address)).to.equal(ethers.utils.parseEther('0'));
      expect(await usdcToken.balanceOf(strategy.address)).to.be.gt(ethers.utils.parseEther('97') / 10 ** 12);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);

      // await strategy.finalizeInvestment({ gasPrice: 0 });
      // expect(await usdcToken.balanceOf(strategy.address)).to.equal(0);
    });
  });
});
