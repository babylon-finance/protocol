const { expect } = require('chai');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { getERC20 } = require('utils/test-helpers');

describe('Heart Unit Test', function () {
  let heartGarden;
  let heart;
  let signer1;
  let garden1;
  let garden2;
  let garden3;
  let keeper;
  let owner;
  let BABL;

  beforeEach(async () => {
    ({ heartGarden, heart, signer1, garden1, garden2, garden3, owner, keeper } = await setupTests()());
    BABL = await getERC20(addresses.tokens.BABL);
  });

  describe('can call getter methods', async function () {
    it('calls all attributes ', async function () {
      expect((await heart.connect(owner).getVotedGardens()).length).to.equal(0);
      expect((await heart.connect(owner).getGardenWeights()).length).to.equal(0);
      expect(await heart.connect(owner).minAmounts(addresses.tokens.DAI)).to.equal(ethers.utils.parseEther('500'));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.USDC)).to.equal(ethers.BigNumber.from(500 * 1e6));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.WETH)).to.equal(ethers.utils.parseEther('0.5'));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.WBTC)).to.equal(ethers.BigNumber.from(3 * 1e6));
      expect(await heart.connect(owner).assetToCToken(addresses.tokens.DAI)).to.equal(
        '0xA6C25548dF506d84Afd237225B5B34F2Feb1aa07',
      );
      expect(await heart.connect(owner).assetToLend()).to.equal(addresses.tokens.DAI);
      expect(await heart.connect(owner).lastPumpAt()).to.equal(0);
      expect(await heart.connect(owner).lastVotesAt()).to.equal(0);
      expect(await heart.connect(owner).weeklyRewardAmount()).to.equal(0);
      expect(await heart.connect(owner).bablRewardLeft()).to.equal(0);
      const fees = await heart.connect(owner).getFeeDistributionWeights();
      expect(fees[0]).to.equal(ethers.utils.parseEther('0.10'));
      expect(fees[1]).to.equal(ethers.utils.parseEther('0.50'));
      expect(fees[2]).to.equal(ethers.utils.parseEther('0.15'));
      expect(fees[3]).to.equal(ethers.utils.parseEther('0.15'));
      expect(fees[4]).to.equal(ethers.utils.parseEther('0.10'));
      const stats = await heart.connect(owner).getTotalStats();
      expect(stats[0]).to.equal(0);
      expect(stats[1]).to.equal(0);
      expect(stats[2]).to.equal(0);
      expect(stats[3]).to.equal(0);
      expect(stats[4]).to.equal(0);
    });
  });

  describe('can update attributes', async function () {
    it('can update the min trade amount ', async function () {
      await heart.connect(owner).setMinTradeAmount(addresses.tokens.DAI, ethers.utils.parseEther('800'));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.DAI)).to.equal(ethers.utils.parseEther('800'));
    });

    it('can add a reward to distribute weekly', async function () {
      await BABL.connect(owner).approve(heart.address, ethers.utils.parseEther('5000'));
      await heart.connect(owner).addReward(ethers.utils.parseEther('5000'), ethers.utils.parseEther('400'));
      expect(await heart.connect(owner).bablRewardLeft()).to.equal(ethers.utils.parseEther('5000'));
      expect(await heart.connect(owner).weeklyRewardAmount()).to.equal(ethers.utils.parseEther('400'));
    });

    it('can top up a reward', async function () {
      await BABL.connect(owner).approve(heart.address, ethers.utils.parseEther('8000'));
      await heart.connect(owner).addReward(ethers.utils.parseEther('5000'), ethers.utils.parseEther('400'));
      await heart.connect(owner).addReward(ethers.utils.parseEther('3000'), ethers.utils.parseEther('100'));
      expect(await heart.connect(owner).bablRewardLeft()).to.equal(ethers.utils.parseEther('8000'));
      expect(await heart.connect(owner).weeklyRewardAmount()).to.equal(ethers.utils.parseEther('100'));
    });

    it('cannot update the asset to lend to an invalid asset', async function () {
      await expect(heart.connect(owner).updateAssetToLend(addresses.tokens.USDC)).to.be.reverted;
    });

    it('can update the asset to lend to a valid fuse asset', async function () {
      await heart.connect(owner).updateAssetToLend(addresses.tokens.FEI);
      expect(await heart.connect(owner).assetToLend()).to.equal(addresses.tokens.FEI);
    });

    it('can update the fee weights', async function () {
      await heart
        .connect(owner)
        .updateFeeWeights([
          ethers.utils.parseEther('0.11'),
          ethers.utils.parseEther('0.51'),
          ethers.utils.parseEther('0.16'),
          ethers.utils.parseEther('0.17'),
          ethers.utils.parseEther('0.18'),
        ]);
      expect(await heart.connect(owner).feeDistributionWeights(0)).to.equal(ethers.utils.parseEther('0.11'));
      expect(await heart.connect(owner).feeDistributionWeights(1)).to.equal(ethers.utils.parseEther('0.51'));
      expect(await heart.connect(owner).feeDistributionWeights(2)).to.equal(ethers.utils.parseEther('0.16'));
      expect(await heart.connect(owner).feeDistributionWeights(3)).to.equal(ethers.utils.parseEther('0.17'));
      expect(await heart.connect(owner).feeDistributionWeights(4)).to.equal(ethers.utils.parseEther('0.18'));
    });

    it('can update the markets', async function () {
      await expect(heart.connect(owner).updateMarkets()).to.not.be.reverted;
    });
  });

  describe('keeper', async function () {
    it('can resolve garden votes', async function () {
      await heart
        .connect(keeper)
        .resolveGardenVotes(
          [garden1.address, garden2.address, garden3.address],
          [ethers.utils.parseEther('0.33'), ethers.utils.parseEther('0.33'), ethers.utils.parseEther('0.33')],
        );
      const weights = await heart.connect(owner).getGardenWeights();
      expect(weights[0]).to.equal(ethers.utils.parseEther('0.33'));
      expect(weights[1]).to.equal(ethers.utils.parseEther('0.33'));
      expect(weights[2]).to.equal(ethers.utils.parseEther('0.33'));
      const gardens = await heart.connect(owner).getVotedGardens();
      expect(gardens[0]).to.equal(garden1.address);
      expect(gardens[1]).to.equal(garden2.address);
      expect(gardens[2]).to.equal(garden3.address);
    });

    it.skip('can vote for proposal on behalf of the heart', async function () {
      // needs governor mocks
      // TODO: governor create proposal and move it to active
      await heart.connect(keeper).voteProposal(1, true);
    });

    it.skip('cannot vote for proposal that is not active', async function () {
      // needs governor mocks
      // TODO: governor create proposal and move it to active
      await heart.connect(keeper).voteProposal(1, true);
    });

    it.skip('can only vote for a proposal once', async function () {
      // needs governor mocks
      // TODO: governor create proposal and move it to active
      await heart.connect(keeper).voteProposal(1, true);
      expect(heart.connect(keeper).voteProposal(1, true)).to.be.reverted();
    });
  });

  describe('pump', async function () {
    it('will revert if garden votes have not been set', async function () {
      await expect(heart.connect(signer1).pump()).to.be.reverted;
    });

    // Needs mocks
    it('will revert if already pumped', async function () {});
    it('will revert if fees are not enough to pump', async function () {});
    it('will pump correctly with 3 ETH', async function () {});
    it('will pump correctly with 3 ETH, 1000 DAI', async function () {});
    it('will pump correctly with 3 ETH, 1000 DAI, 1000 USDC', async function () {});
  });
});
