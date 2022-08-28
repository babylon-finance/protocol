const { expect } = require('chai');
const { ethers, deployments } = require('hardhat');
const { deploy } = deployments;
const { fund, getWhaleSigner } = require('lib/whale');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { ONE_DAY_IN_SECONDS } = require('lib/constants.js');
const { getERC20, increaseTime } = require('utils/test-helpers');
const { impersonateAddress } = require('lib/rpc');

describe('Liquidation', function () {
  let signer1;
  let signer2;
  let DAI;
  let BABL;
  let WHITELIST_END_TS;
  let CLAIM_END_TS;
  let owner;
  let babController;
  let liquidation;

  beforeEach(async () => {
    ({ babController, owner, signer1, signer2 } = await setupTests()());
    await fund([signer1.address, signer2.address]);
    const currentTS = (await ethers.provider.getBlock()).timestamp;
    WHITELIST_END_TS = currentTS + ONE_DAY_IN_SECONDS * 7; // 7 day
    CLAIM_END_TS = WHITELIST_END_TS + 7 * ONE_DAY_IN_SECONDS; // 1 day to claim
    BABL = await getERC20(addresses.tokens.BABL);
    DAI = await getERC20(addresses.tokens.DAI);
    const deployment = await deploy('Liquidation', {
      from: signer1.address,
      args: [babController.address, WHITELIST_END_TS, CLAIM_END_TS],
    });
    liquidation = await ethers.getContractAt('Liquidation', deployment.address);
  });

  describe('deployment', async function () {
    it(`gets deployed with the right attributes`, async function () {
      const whitelistEnd = await liquidation.whitelistEnd();
      const claimEnd = await liquidation.claimEnd();
      const snapshotBlockNumber = await liquidation.snapshotBlockNumber();
      expect(whitelistEnd).to.equal(WHITELIST_END_TS);
      expect(claimEnd).to.equal(CLAIM_END_TS);
      expect(snapshotBlockNumber).to.equal(0);
    });
  });

  describe('setters', async function () {
    it(`emergency owner can set the variables`, async function () {
      await liquidation.connect(owner).setWhitelistEnd(1);
      await liquidation.connect(owner).setClaimEnd(2);
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address, signer2.address]);
      expect(await liquidation.whitelistEnd()).to.equal(1);
      expect(await liquidation.claimEnd()).to.equal(2);
      expect(await liquidation.snapshotBlockNumber()).to.be.gt(0);
    });

    it(`other account cannot set the variables`, async function () {
      await expect(liquidation.connect(signer1).setWhitelistEnd(1)).to.be.revertedWith(
        'Only governance or emergency can call this',
      );
      await expect(liquidation.connect(signer1).setClaimEnd(2)).to.be.revertedWith(
        'Only governance or emergency can call this',
      );
      await expect(
        liquidation.connect(signer1).setSnapshotBlockNumber([signer1.address, signer2.address]),
      ).to.be.revertedWith('Only governance or emergency can call this');
    });
  });

  describe('add to whitelist', async function () {
    it(`a user can add himself to the whitelist`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      expect(await liquidation.whitelistAmounts(signer1.address)).to.equal(0);
      await liquidation.connect(signer1).addToWhitelist();
      expect(await liquidation.whitelistAmounts(signer1.address)).to.equal(await BABL.balanceOf(signer1.address));
      expect(await liquidation.totalWhitelistAmount()).to.equal(await BABL.balanceOf(signer1.address));
    });

    it(`a user cannot add himself to the whitelist twice`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      await liquidation.connect(signer1).addToWhitelist();
      await expect(liquidation.connect(signer1).addToWhitelist()).to.be.revertedWith('BAB#136');
    });

    it(`a user cannot add himself to the whitelist after the time is over`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      await increaseTime(ONE_DAY_IN_SECONDS * 7 + 1);
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 7 + 1]);
      await expect(liquidation.connect(signer1).addToWhitelist()).to.be.revertedWith('BAB#137');
    });

    it(`a user without cannot add himself to the whitelist until the block is set`, async function () {
      await expect(liquidation.connect(signer1).addToWhitelist()).to.be.revertedWith('BAB#140');
    });

    it(`a user without balance cannot add himself to the whitelist`, async function () {
      const noBablAddress = '0xdbf5e9c5206d0db70a90108bf936da60221dc080';
      const noBabl = await impersonateAddress(noBablAddress);

      await liquidation.connect(owner).setSnapshotBlockNumber([noBablAddress]);
      await expect(liquidation.connect(noBabl).addToWhitelist()).to.be.revertedWith('BAB#140');
    });
  });

  describe('claim proceeds', async function () {
    it(`a user that is in the whitelist can claim`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      await liquidation.connect(signer1).addToWhitelist();
      await increaseTime(ONE_DAY_IN_SECONDS * 7 + 2);
      // Send exact same amount to contract and set it as total
      const bablBalance = await BABL.balanceOf(signer1.address);
      const whaleSigner = await getWhaleSigner(DAI.address);
      await DAI.connect(whaleSigner).transfer(liquidation.address, bablBalance, {
        gasPrice: 0,
      });
      await liquidation.connect(owner).setGlobalLiquidationAmount(bablBalance);
      const balanceBefore = await DAI.balanceOf(signer1.address);
      await liquidation.connect(signer1).claimProceeds();
      const balanceAfter = await DAI.balanceOf(signer1.address);
      expect(balanceAfter.sub(balanceBefore)).to.eq(bablBalance);
    });

    it(`a user that is in the whitelist cannot claim twice`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      await liquidation.connect(signer1).addToWhitelist();
      await increaseTime(ONE_DAY_IN_SECONDS * 7 + 2);
      const bablBalance = await BABL.balanceOf(signer1.address);
      const whaleSigner = await getWhaleSigner(DAI.address);
      await DAI.connect(whaleSigner).transfer(liquidation.address, bablBalance, {
        gasPrice: 0,
      });
      await liquidation.connect(owner).setGlobalLiquidationAmount(bablBalance);
      await liquidation.connect(signer1).claimProceeds();
      await expect(liquidation.connect(signer1).claimProceeds()).to.be.revertedWith('BAB#012');
    });

    it(`a user that is in the whitelist cannot claim if global amount is not set`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      await increaseTime(ONE_DAY_IN_SECONDS * 7 + 2);
      await expect(liquidation.connect(signer1).claimProceeds()).to.be.revertedWith('BAB#139');
    });

    it(`a user that is not in the whitelist cannot claim`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      const whaleSigner = await getWhaleSigner(DAI.address);
      await DAI.connect(whaleSigner).transfer(liquidation.address, 1, {
        gasPrice: 0,
      });
      await liquidation.connect(owner).setGlobalLiquidationAmount(1);
      await increaseTime(ONE_DAY_IN_SECONDS * 7 + 2);
      await expect(liquidation.connect(signer1).claimProceeds()).to.be.revertedWith('BAB#139');
    });

    it(`a user that is in the whitelist cannot claim until whitelist is over`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      await liquidation.connect(signer1).addToWhitelist();
      const whaleSigner = await getWhaleSigner(DAI.address);
      await DAI.connect(whaleSigner).transfer(liquidation.address, 1, {
        gasPrice: 0,
      });
      await liquidation.connect(owner).setGlobalLiquidationAmount(1);
      await increaseTime(ONE_DAY_IN_SECONDS * 3);
      await expect(liquidation.connect(signer1).claimProceeds()).to.be.revertedWith('BAB#138');
    });

    it(`a user that is in the whitelist cannot claim once the claim is over`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      await liquidation.connect(signer1).addToWhitelist();
      const whaleSigner = await getWhaleSigner(DAI.address);
      await DAI.connect(whaleSigner).transfer(liquidation.address, 1, {
        gasPrice: 0,
      });
      await liquidation.connect(owner).setGlobalLiquidationAmount(1);
      await increaseTime(ONE_DAY_IN_SECONDS * 20 + 1);
      await expect(liquidation.connect(signer1).claimProceeds()).to.be.revertedWith('BAB#138');
    });
  });

  describe('unclaimed proceeds', async function () {
    it(`owner can recover proceeds once the claim is over`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      await liquidation.connect(signer1).addToWhitelist();
      const bablBalance = await BABL.balanceOf(signer1.address);
      const whaleSigner = await getWhaleSigner(DAI.address);
      await DAI.connect(whaleSigner).transfer(liquidation.address, bablBalance, {
        gasPrice: 0,
      });
      await liquidation.connect(owner).setGlobalLiquidationAmount(bablBalance);
      await increaseTime(ONE_DAY_IN_SECONDS * 15);
      const balanceBefore = await DAI.balanceOf(owner.address);
      const allProceeds = await DAI.balanceOf(liquidation.address);
      await liquidation.connect(owner).retrieveRemaining();
      const balanceAfter = await DAI.balanceOf(owner.address);
      expect(balanceAfter.sub(balanceBefore)).to.eq(allProceeds);
      expect(await DAI.balanceOf(liquidation.address)).to.eq(0);
    });

    it(`owner cannot recover proceeds until claim is over`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      await liquidation.connect(signer1).addToWhitelist();
      await increaseTime(ONE_DAY_IN_SECONDS * 5);
      const whaleSigner = await getWhaleSigner(DAI.address);
      const bablBalance = await BABL.balanceOf(signer1.address);
      await DAI.connect(whaleSigner).transfer(liquidation.address, bablBalance, {
        gasPrice: 0,
      });
      await liquidation.connect(owner).setGlobalLiquidationAmount(bablBalance);
      await expect(liquidation.connect(owner).retrieveRemaining()).to.be.revertedWith('BAB#142');
    });

    it(`non owner cannot recover proceeds once the claim is over`, async function () {
      await liquidation.connect(owner).setSnapshotBlockNumber([signer1.address]);
      await liquidation.connect(signer1).addToWhitelist();
      await increaseTime(ONE_DAY_IN_SECONDS * 15);
      const bablBalance = await BABL.balanceOf(signer1.address);
      const whaleSigner = await getWhaleSigner(DAI.address);
      await DAI.connect(whaleSigner).transfer(liquidation.address, bablBalance, {
        gasPrice: 0,
      });
      await liquidation.connect(owner).setGlobalLiquidationAmount(bablBalance);
      await expect(liquidation.connect(signer1).retrieveRemaining()).to.be.revertedWith(
        'Only governance or emergency can call this',
      );
    });
  });
});
