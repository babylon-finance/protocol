const { expect } = require('chai');

const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { GARDEN_PARAMS_STABLE, GARDEN_PARAMS, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { impersonateAddress } = require('lib/rpc');
const { createStrategy, executeStrategy, finalizeStrategy, getStrategy } = require('fixtures/StrategyHelper');
const { createGarden } = require('fixtures/GardenHelper');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');
const { ethers } = require('hardhat');
const { fund } = require('lib/whale');

describe('BabController', function () {
  let babController;
  let treasury;
  let bablToken;
  let garden1;
  let garden2;
  let garden3;
  let signer1;
  let signer2;
  let signer3;
  let uniswapV3TradeIntegration;
  let rewardsDistributor;
  let strategy11;
  let owner;
  let MULTISIG;
  let dai;
  let babl;

  beforeEach(async () => {
    ({
      babl,
      dai,
      babController,
      bablToken,
      owner,
      signer1,
      signer2,
      signer3,
      treasury,
      garden1,
      garden2,
      garden3,
      strategy11,
      uniswapV3TradeIntegration,
      rewardsDistributor,
    } = await setupTests()());
    const signers = await ethers.getSigners();
    MULTISIG = signers[2];
    await fund([signer1.address, signer2.address, signer3.address]);
  });

  describe('createGarden', function () {
    it('can create a new garden with DAI as the reserve asset', async function () {
      await createGarden({ reserveAsset: addresses.tokens.DAI });
    });
  });

  describe('setPauseGuardian', function () {
    it('should pause globally the protocol principal functions', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setGlobalPause(true);
      await expect(
        garden1.connect(signer1).deposit(eth(), 1, signer1.getAddress(), ADDRESS_ZERO, {
          value: eth(),
        }),
      ).to.be.revertedWith('BAB#083');
    });

    it('should pause individually a garden', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([garden1.address], true);
      const signer1Garden2Balance = await garden2.balanceOf(signer1.address);
      await expect(
        garden2.connect(signer1).deposit(eth(), 1, signer1.getAddress(), ADDRESS_ZERO, {
          value: eth(),
        }),
      ).to.be.not.reverted;
      const signer1Garden2Balance2 = await garden2.balanceOf(signer1.address);
      expect(signer1Garden2Balance2.sub(signer1Garden2Balance)).to.equal(eth());
      await expect(
        garden1.connect(signer1).deposit(eth(), 1, signer1.getAddress(), ADDRESS_ZERO, {
          value: eth(),
        }),
      ).to.be.revertedWith('BAB#083');
    });

    it('should pause individually a strategy', async function () {
      const long1 = await getStrategy({ garden: garden1 });
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([long1.address], true);
      await expect(executeStrategy(long1, eth())).to.be.revertedWith('BAB#083');
    });

    it('should pause individually the reward distributor main functions', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([rewardsDistributor.address], true);
    });

    it('should pause individually the BABL Token main functions as a TimeLockedToken', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([bablToken.address], true);
      await expect(
        bablToken.connect(owner).transfer(signer1.address, eth('1000'), {
          gasPrice: 0,
        }),
      ).to.be.revertedWith('BAB#083');
    });

    it('owner can unpause a strategy', async function () {
      const long1 = await getStrategy({ garden: garden1, state: 'vote' });

      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([long1.address], true);

      await expect(executeStrategy(long1, eth())).to.be.revertedWith('BAB#083');

      await babController.connect(owner).setSomePause([long1.address], false);
      await executeStrategy(long1, eth());
    });

    it('owner can unpause a garden', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await expect(babController.connect(signer1).setSomePause([garden1.address], true)).to.be.not.reverted;
      await garden2.connect(signer1).deposit(eth(), 1, signer1.getAddress(), ADDRESS_ZERO, {
        value: eth(),
      });
      await expect(
        garden1.connect(signer1).deposit(eth(), 1, signer1.getAddress(), ADDRESS_ZERO, {
          value: eth(),
        }),
      ).to.be.revertedWith('BAB#083');
      await babController.connect(owner).setSomePause([garden1.address], false);
      garden1.connect(signer1).deposit(eth(), 1, signer1.getAddress(), ADDRESS_ZERO, {
        value: eth(),
      });
    });

    it('owner can unpause the reward distributor main functions', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([rewardsDistributor.address], true);
      await expect(babController.connect(signer1).setSomePause([rewardsDistributor.address], false)).to.be.revertedWith(
        'Not enough privileges',
      );
      const newBablToken = await impersonateAddress('0xf4dc48d260c93ad6a96c5ce563e70ca578987c74');
      await babController.connect(owner).setSomePause([rewardsDistributor.address], false);
    });

    it('owner can unpause the BABL Token main functions as a TimeLockedToken', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([bablToken.address], true);
      await expect(
        bablToken.connect(MULTISIG).transfer(signer1.address, eth('1000'), {
          gasPrice: 0,
        }),
      ).to.be.revertedWith('BAB#083');
      await babController.connect(owner).setSomePause([bablToken.address], false);
      await bablToken.connect(MULTISIG).transfer(signer1.address, eth('10'), {
        gasPrice: 0,
      });
    });
  });

  describe('claimRewards', function () {
    it('can claim', async function () {
      const amountIn = eth(1000);
      const minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.DAI] });
      await fund([babController.address], { tokens: [addresses.tokens.BABL] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.DAI });

      await babController.connect(owner).updateGardenAffiliateRate(garden.address, eth());

      await dai.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), signer2.address);

      const prevBalance = await babl.balanceOf(signer2.address);

      await babController.connect(signer2).claimRewards();
      await babController.connect(signer3).claimRewards();

      expect((await babl.balanceOf(signer2.address)).sub(prevBalance)).to.eq(amountIn.div(2));
      expect((await babl.balanceOf(signer3.address)).sub(prevBalance)).to.eq(amountIn.div(2));
    });
  });
});
