const { expect } = require('chai');
const { waffle, ethers } = require('hardhat');
const { impersonateAddress } = require('../../utils/rpc');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const addresses = require('../../utils/addresses');
const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('../../utils/constants');

const { loadFixture } = waffle;

describe('BalancerIntegrationTest', function () {
  let system;
  let balancerIntegration;
  let balancerAbi;
  let garden;
  let userSigner1;
  let userSigner3;
  let strategy;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    balancerIntegration = system.integrations.balancerIntegration;
    userSigner1 = system.signer1;
    userSigner3 = system.signer3;
    balancerAbi = balancerIntegration.interface;
    garden = system.comunities.one;
    strategy = system.strategies[0];
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await system.babController.deployed();
      const deployedBalancer = await balancerIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedBalancer).to.equal(true);
    });
  });

  describe('Liquidity Pools', function () {
    let daiToken;
    let wethToken;
    let whaleSigner;
    let whaleWeth;
    let daiWethPool;

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(addresses.holders.DAI);
      whaleWeth = await impersonateAddress(addresses.holders.WETH);
      daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
      wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
      daiWethPool = await ethers.getContractAt('IBPool', addresses.balancer.pools.wethdai);
    });

    it('check that a valid pool is valid', async function () {
      expect(await balancerIntegration.isPool(addresses.balancer.pools.wethdai)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      expect(await balancerIntegration.isPool(ADDRESS_ZERO)).to.equal(false);
    });

    it('can enter and exit the weth dai pool', async function () {
      // expect(
      //   await daiToken
      //     .connect(whaleSigner)
      //     .transfer(garden.address, ethers.utils.parseEther("1000"), {
      //       gasPrice: 0
      //     })
      // );

      await garden.connect(userSigner1).deposit(ethers.utils.parseEther('3'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('3'),
      });
      await garden.connect(userSigner3).deposit(ethers.utils.parseEther('3'), 1, userSigner3.getAddress(), {
        value: ethers.utils.parseEther('3'),
      });

      const dataEnter = balancerAbi.encodeFunctionData(
        balancerAbi.functions['joinPool(address,uint256,address[],uint256[])'],
        [
          addresses.balancer.pools.wethdai,
          ethers.utils.parseEther('0.0001'),
          await daiWethPool.getFinalTokens(),
          [ethers.utils.parseEther('1000'), ethers.utils.parseEther('2')],
        ],
      );

      const dataExit = balancerAbi.encodeFunctionData(
        balancerAbi.functions['exitPool(address,uint256,address[],uint256[])'],
        [
          addresses.balancer.pools.wethdai,
          ethers.utils.parseEther('0.0001'),
          await daiWethPool.getFinalTokens(),
          [ethers.utils.parseEther('100'), ethers.utils.parseEther('0.1')],
        ],
      );

      await strategy
        .connect(userSigner1)
        .setIntegrationData(
          balancerIntegration.address,
          dataEnter,
          dataExit,
          [daiToken.address],
          [ethers.utils.parseEther('1000')],
          {
            gasPrice: 0,
          },
        );

      await strategy.connect(userSigner3).curateIdea(await garden.balanceOf(userSigner3.getAddress()));

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      // await strategy.executeInvestment(ethers.utils.parseEther("1"), {
      //   gasPrice: 0
      // });
      //
      // expect(await daiWethPool.balanceOf(strategy.address)).to.be.eq(
      //   ethers.utils.parseEther("0.001")
      // );
      //
      // ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 90]);
      //
      // await strategy.finalizeInvestment({ gasPrice: 0 });
      //
      // expect(await daiWethPool.balanceOf(strategy.address)).to.equal(0);
      // expect(await daiToken.balanceOf(strategy.address)).to.be.gt(
      //   ethers.utils.parseEther("0")
      // );
      // expect(await wethToken.balanceOf(strategy.address)).to.be.gt(
      //   ethers.utils.parseEther("4.00")
      // );
    });
  });
});
