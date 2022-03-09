const { expect } = require('chai');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { getERC20, increaseBlock, increaseTime, proposalState, eth, from } = require('utils/test-helpers');
const { getVoters, getProposal, selfDelegation, claimTokens } = require('utils/gov-helpers');
const { impersonateAddress } = require('lib/rpc');
const { ONE_YEAR_IN_SECONDS, ADDRESS_ZERO } = require('lib/constants');

describe('Heart Unit Test', function () {
  let heartGarden;
  let heart;
  let signer1;
  let garden1;
  let garden2;
  let garden3;
  let keeper;
  let owner;
  let treasury;
  let priceOracle;
  let tokenIdentifier;
  let BABL;
  let WETH;
  let DAI;
  let CBABL;
  let hBABL;
  let USDC;
  let cDAI;
  let voters;
  let token;
  let governor;
  let heartGardenSigner;
  let feeDistributionWeights;

  beforeEach(async () => {
    ({
      heartGarden,
      heart,
      signer1,
      garden1,
      garden2,
      garden3,
      owner,
      keeper,
      priceOracle,
      tokenIdentifier,
      treasury,
    } = await setupTests()());
    WETH = await getERC20(addresses.tokens.WETH);
    BABL = await getERC20(addresses.tokens.BABL);
    DAI = await getERC20(addresses.tokens.DAI);
    USDC = await getERC20(addresses.tokens.USDC);
    hBABL = await getERC20(heartGarden.address);
    CBABL = await getERC20('0x812eedc9eba9c428434fd3ce56156b4e23012ebc');
    token = await ethers.getContractAt('BABLToken', '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74');
    governor = await ethers.getContractAt('BabylonGovernor', '0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24');
    voters = await getVoters();
    heartGardenSigner = await impersonateAddress(heartGarden.address);
    await selfDelegation(token, voters);
    await claimTokens(token, voters);

    cDAI = await ethers.getContractAt('ICToken', '0xa6c25548df506d84afd237225b5b34f2feb1aa07');
    await heart.connect(owner).setHeartGardenAddress(heartGarden.address);
    feeDistributionWeights = await heart.connect(owner).getFeeDistributionWeights();
    // Impersonate visor and add heart to the whitelist
    const visorOwner = await impersonateAddress('0xc40ccde9c951ace468154d1d39917d8f8d11b38c');
    const visor = await ethers.getContractAt('IHypervisor', '0xF19F91d7889668A533F14d076aDc187be781a458');
    await visor.connect(visorOwner).appendList([heart.address], { gasPrice: 0 });
    // Adds weekly rewards
    await BABL.connect(owner).approve(heart.address, eth('5000'));
    await heart.connect(owner).addReward(eth('5000'), eth('300'));
  });

  describe('can call getter methods', async function () {
    it('calls all attributes ', async function () {
      expect((await heart.connect(owner).getVotedGardens()).length).to.equal(0);
      expect((await heart.connect(owner).getGardenWeights()).length).to.equal(0);
      expect(await heart.connect(owner).minAmounts(addresses.tokens.DAI)).to.equal(eth(500));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.USDC)).to.equal(from(500 * 1e6));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.WETH)).to.equal(eth(0.5));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.WBTC)).to.equal(from(3 * 1e6));
      expect(await heart.connect(owner).assetToCToken(addresses.tokens.DAI)).to.equal(
        '0xA6C25548dF506d84Afd237225B5B34F2Feb1aa07',
      );
      expect(await heart.connect(owner).assetToLend()).to.equal(addresses.tokens.DAI);
      expect(await heart.connect(owner).lastPumpAt()).to.equal(0);
      expect(await heart.connect(owner).lastVotesAt()).to.equal(0);
      expect(await heart.connect(owner).weeklyRewardAmount()).to.equal(eth('300'));
      expect(await heart.connect(owner).bablRewardLeft()).to.equal(eth('5000'));
      const fees = await heart.connect(owner).getFeeDistributionWeights();
      expect(fees[0]).to.equal(eth(0.1));
      expect(fees[1]).to.equal(eth(0.3));
      expect(fees[2]).to.equal(eth(0.25));
      expect(fees[3]).to.equal(eth(0.15));
      expect(fees[4]).to.equal(eth(0.2));
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
      await heart.connect(owner).setMinTradeAmount(addresses.tokens.DAI, eth(800));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.DAI)).to.equal(eth(800));
    });

    it('can add a reward to distribute weekly', async function () {
      await BABL.connect(owner).approve(heart.address, eth(5000));
      await heart.connect(owner).addReward(eth(5000), eth(400));
      expect(await heart.connect(owner).bablRewardLeft()).to.equal(eth(10000));
      expect(await heart.connect(owner).weeklyRewardAmount()).to.equal(eth(400));
    });

    it('can top up a reward', async function () {
      await BABL.connect(owner).approve(heart.address, eth(8000));
      await heart.connect(owner).addReward(eth(5000), eth(400));
      await heart.connect(owner).addReward(eth(3000), eth(100));
      expect(await heart.connect(owner).bablRewardLeft()).to.equal(eth(13000));
      expect(await heart.connect(owner).weeklyRewardAmount()).to.equal(eth(100));
    });

    it('cannot update the asset to lend to an invalid asset', async function () {
      await expect(heart.connect(owner).updateAssetToLend(addresses.tokens.USDC)).to.be.reverted;
    });

    it('can update the asset to lend to a valid fuse asset', async function () {
      await heart.connect(owner).updateAssetToLend(addresses.tokens.FEI);
      expect(await heart.connect(owner).assetToLend()).to.equal(addresses.tokens.FEI);
    });

    it('cannot update the asset to purchase to an invalid asset', async function () {
      await expect(heart.connect(owner).updateAssetToPurchase(ADDRESS_ZERO)).to.be.reverted;
    });

    it('can update the asset to purchase to a valid asset', async function () {
      await heart.connect(owner).updateAssetToPurchase(addresses.tokens.FRAX);
      expect(await heart.connect(owner).assetForPurchases()).to.equal(addresses.tokens.FRAX);
    });

    it('can update the fee weights', async function () {
      await heart.connect(owner).updateFeeWeights([eth(0.11), eth(0.51), eth(0.16), eth(0.17), eth(0.18)]);
      expect(await heart.connect(owner).feeDistributionWeights(0)).to.equal(eth(0.11));
      expect(await heart.connect(owner).feeDistributionWeights(1)).to.equal(eth(0.51));
      expect(await heart.connect(owner).feeDistributionWeights(2)).to.equal(eth(0.16));
      expect(await heart.connect(owner).feeDistributionWeights(3)).to.equal(eth(0.17));
      expect(await heart.connect(owner).feeDistributionWeights(4)).to.equal(eth(0.18));
    });
    it('can update the markets', async function () {
      await expect(heart.connect(owner).updateMarkets()).to.not.be.reverted;
    });
  });

  describe('keeper', async function () {
    it('can resolve garden votes', async function () {
      await heart
        .connect(keeper)
        .resolveGardenVotes([garden1.address, garden2.address, garden3.address], [eth(0.33), eth(0.33), eth(0.33)]);
      const weights = await heart.connect(owner).getGardenWeights();
      expect(weights[0]).to.equal(eth(0.33));
      expect(weights[1]).to.equal(eth(0.33));
      expect(weights[2]).to.equal(eth(0.33));
      const gardens = await heart.connect(owner).getVotedGardens();
      expect(gardens[0]).to.equal(garden1.address);
      expect(gardens[1]).to.equal(garden2.address);
      expect(gardens[2]).to.equal(garden3.address);
    });

    it.skip('can vote for proposal on behalf of the heart', async function () {
      // needs governor mocks
      // Note: cannot use governor mocks as GOVERNOR address is hardcoded in Heart contract
      // const mockGovernor = await getGovernorMock(token, deployer);
      const { id, args } = await getProposal(governor);
      const heartGardenBABLBalance = await token.balanceOf(heartGarden.address);
      // Get delegation from Heart Garden
      // TODO (IMPORTANT) we need to create a privilege function at Garden.sol level and upgrade
      await token.connect(heartGardenSigner).delegate(heart.address, { gasPrice: 0 });
      await increaseBlock(1);
      // Propose
      await governor.connect(voters[1])['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await increaseBlock(1);
      // Vote
      await heart.connect(keeper).voteProposal(id, true);
      const [heartHasVoted, heartSupport, heartVotes] = await governor.getReceipt(id, heart.address);
      expect(heartHasVoted).to.eq(true);
      expect(heartSupport).to.eq(1);
      expect(heartVotes).to.eq(heartGardenBABLBalance);
    });

    it.skip('cannot vote for proposal that is not active', async function () {
      // It works, skipped due to it takes long time to increase blocks as it is using real governor
      // TODO: needs mocks
      const { id, args } = await getProposal(governor);
      // Get delegation from Heart Garden
      // TODO (IMPORTANT) we need to create a privilege function at Garden.sol level and upgrade to delegate into heart SC
      await token.connect(heartGardenSigner).delegate(heart.address, { gasPrice: 0 });
      await increaseBlock(1);
      // Propose
      await governor.connect(voters[1])['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await expect(heart.connect(keeper).voteProposal(id, true)).to.be.revertedWith(
        'BABLToken::getPriorVotes: not yet determined',
      );
      await increaseBlock((await governor.votingPeriod()).add(1));
      // Voting time passed
      await expect(heart.connect(keeper).voteProposal(id, true)).to.be.revertedWith(
        'Governor: vote not currently active',
      );
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      // 3: Defeated state
      const state = await governor.state(id);
      expect(state).to.eq(proposalState.Defeated);
    });

    it.skip('can only vote for a proposal once', async function () {
      const { id, args } = await getProposal(governor);
      // Get delegation from Heart Garden
      await token.connect(heartGardenSigner).delegate(heart.address, { gasPrice: 0 });
      await increaseBlock(1);
      // Propose
      await governor.connect(voters[1])['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await increaseBlock(1);
      // Vote
      await heart.connect(keeper).voteProposal(id, true);
      await expect(heart.connect(keeper).voteProposal(id, false)).to.be.revertedWith(
        'GovernorCompatibilityBravo: vote already cast',
      );
    });

    it('heart does increase its voting power by each new BABL received as it self delegated in constructor', async function () {
      const heartBalance = await token.getCurrentVotes(heart.address);
      expect(heartBalance).to.eq(eth('5000'));
      const heartSigner = await impersonateAddress(heart.address);
      const heartGardenBalance = await token.balanceOf(heartGarden.address);
      const voterBalance = await token.balanceOf(voters[0].address);
      // get heart garden delegation
      await token.connect(heartGardenSigner).delegate(heart.address, { gasPrice: 0 });
      const heartVotingPower2 = await token.getCurrentVotes(heart.address);
      expect(heartVotingPower2).to.eq(heartGardenBalance.add(heartBalance));
      // remove delegation
      await token.connect(heartGardenSigner).delegate(heartGarden.address, { gasPrice: 0 });
      const heartVotingPower3 = await token.getCurrentVotes(heart.address);
      expect(heartVotingPower3).to.eq(heartBalance);
      // get out of vesting
      await increaseTime(ONE_YEAR_IN_SECONDS * 3);
      // By a simple transfer its gets voting power as it self delegated during constructor
      // If not self-delegated its own balance will never count unless heart self-delegates
      await token.connect(voters[0]).transfer(heart.address, await token.balanceOf(voters[0].address), { gasPrice: 0 });
      const heartVotingPower4 = await token.getCurrentVotes(heart.address);
      expect(heartVotingPower4).to.eq(voterBalance.add(heartBalance));
      // return BABL back
      await token
        .connect(heartSigner)
        .transfer(voters[0].address, await token.balanceOf(heart.address), { gasPrice: 0 });
      const heartVotingPower5 = await token.getCurrentVotes(heart.address);
      expect(heartVotingPower5).to.eq(0);
    });
  });

  describe('lend fuse pool', async function () {
    it('will lend an asset that is already owned', async function () {
      const amountToLend = eth('5000');
      const whaleSigner = await impersonateAddress('0x40154ad8014df019a53440a60ed351dfba47574e');
      await BABL.connect(whaleSigner).transfer(heart.address, amountToLend, { gasPrice: 0 });
      const bablBalanceBefore = await BABL.connect(owner).balanceOf(heart.address);
      await heart.connect(owner).lendFusePool(addresses.tokens.BABL, amountToLend, { gasPrice: 0 });
      const bablBalanceAfter = await BABL.connect(owner).balanceOf(heart.address);
      await expect(bablBalanceAfter).to.equal(bablBalanceBefore.sub(amountToLend));
      await expect(await CBABL.connect(owner).balanceOf(heart.address)).to.be.gt(0);
    });

    it('will revert if called by non owner', async function () {
      const amountToLend = eth('5000');
      const whaleSigner = await impersonateAddress('0x40154ad8014df019a53440a60ed351dfba47574e');
      await BABL.connect(whaleSigner).transfer(heart.address, amountToLend, { gasPrice: 0 });
      await expect(heart.connect(signer1).lendFusePool(addresses.tokens.BABL, amountToLend, { gasPrice: 0 })).to.be
        .reverted;
    });
  });

  describe('bond assets', async function () {
    it('normal signer cannot enter a new bond asset', async function () {
      await expect(heart.connect(signer1).updateBond(cDAI.address, eth('0.05'), { gasPrice: 0 })).to
        .be.reverted;
    });

    it('owner can enter a new bond asset', async function () {
      await heart.connect(owner).updateBond(cDAI.address, eth('0.05'), { gasPrice: 0 });
      expect(await heart.bondAssets(cDAI.address)).to.equal(eth('0.05'));
    });

    it('owner can update the discount of a bond asset', async function () {
      await heart.connect(owner).updateBond(cDAI.address, eth('0.05'), { gasPrice: 0 });
      expect(await heart.bondAssets(cDAI.address)).to.equal(eth('0.05'));
      await heart.connect(owner).updateBond(cDAI.address, eth('0.03'), { gasPrice: 0 });
      expect(await heart.bondAssets(cDAI.address)).to.equal(eth('0.03'));
    });

    it('user cannot bond asset that is not added', async function () {
      await expect(heart.connect(signer1).bondAsset(addresses.tokens.BABL, 1, 1, { gasPrice: 0 })).to.be.reverted;
    });

    it('user cannot bond a small amount', async function () {
      await heart.connect(owner).updateBond(cDAI.address, eth('0.05'), { gasPrice: 0 });
      const whalecdaiSigner = await impersonateAddress('0x2d160210011a992966221f428f63326f76066ba9');
      await cDAI.connect(whalecdaiSigner).transfer(signer1.address, 1, { gasPrice: 0 });
      await cDAI.connect(signer1).approve(heart.address, 1, { gasPrice: 0 });
      // Add fuse assets to token identifier
      await tokenIdentifier.connect(owner).updateCompoundPair([cDAI.address], [DAI.address], { gasPrice: 0 });
      await expect(heart.connect(signer1).bondAsset(addresses.tokens.cDAI, 1, 1, { gasPrice: 0 })).to.be.reverted;
    });

    it('user can bond an appropriate amount and receive the discount', async function () {
      await heart.connect(owner).updateBond(cDAI.address, eth('0.05'), { gasPrice: 0 });
      const whalecdaiSigner = await impersonateAddress('0x2d160210011a992966221f428f63326f76066ba9');
      const amount = eth('20000');
      await cDAI.connect(whalecdaiSigner).transfer(signer1.address, amount, { gasPrice: 0 });
      const hBABLBalance = await hBABL.balanceOf(signer1.address);
      // Add fuse assets to token identifier
      await tokenIdentifier.connect(owner).updateCompoundPair([cDAI.address], [DAI.address], { gasPrice: 0 });
      // User approves the heart
      await cDAI.connect(signer1).approve(heart.address, amount, { gasPrice: 0 });
      // Bond the asset
      await heart.connect(signer1).bondAsset(cDAI.address, amount, 1, { gasPrice: 0 });
      expect(await hBABL.balanceOf(signer1.address)).to.be.closeTo(
        hBABLBalance.add(eth('70')),
        eth('10'),
      );
    });
  });

  describe('borrow fuse pool', async function () {
    it('will borrow DAI after lending BABL', async function () {
      const amountToLend = eth('5000');
      const amountToBorrow = eth('50000');
      const whaleSigner = await impersonateAddress('0x40154ad8014df019a53440a60ed351dfba47574e');
      await BABL.connect(whaleSigner).transfer(heart.address, amountToLend, { gasPrice: 0 });
      await heart.connect(owner).lendFusePool(addresses.tokens.BABL, amountToLend, { gasPrice: 0 });
      await heart.connect(owner).borrowFusePool(addresses.tokens.DAI, amountToBorrow);
      expect(await DAI.balanceOf(heart.address)).to.equal(amountToBorrow);
    });

    it('will revert if trying to borrow too much', async function () {
      const amountToLend = eth('5000');
      const amountToBorrow = eth('250000');
      const whaleSigner = await impersonateAddress('0x40154ad8014df019a53440a60ed351dfba47574e');
      await BABL.connect(whaleSigner).transfer(heart.address, amountToLend, { gasPrice: 0 });
      await heart.connect(owner).lendFusePool(addresses.tokens.BABL, amountToLend, { gasPrice: 0 });
      await expect(heart.connect(owner).borrowFusePool(addresses.tokens.DAI, amountToBorrow)).to.be.reverted;
    });

    it('will revert if called by non owner', async function () {
      const amountToLend = eth('5000');
      const whaleSigner = await impersonateAddress('0x40154ad8014df019a53440a60ed351dfba47574e');
      await BABL.connect(whaleSigner).transfer(heart.address, amountToLend, { gasPrice: 0 });
      await heart.connect(owner).lendFusePool(addresses.tokens.BABL, amountToLend, { gasPrice: 0 });
      await expect(
        heart.connect(signer1).borrowFusePool(addresses.tokens.FRAX, eth('50000'), { gasPrice: 0 }),
      ).to.be.reverted;
    });
  });

  async function pumpAmount(amountInFees) {
    const daiPerWeth = await priceOracle.connect(owner).getPrice(WETH.address, DAI.address);
    await heart
      .connect(keeper)
      .resolveGardenVotes([garden1.address, garden2.address, garden3.address], [eth(0.33), eth(0.33), eth(0.33)]);

    const wethTreasuryBalanceBeforePump = await WETH.balanceOf(treasury.address);
    const bablTreasuryBalanceBeforePump = await BABL.balanceOf(treasury.address);
    const heartBABLBalanceBeforePump = await BABL.balanceOf(heartGarden.address);
    const balanceGarden1BeforePump = await WETH.balanceOf(garden1.address);
    const balanceGarden2BeforePump = await WETH.balanceOf(garden2.address);
    const balanceGarden3BeforePump = await WETH.balanceOf(garden3.address);
    const fuseBalanceDAIBeforePump = await cDAI.getCash();
    await heart.connect(signer1).pump();
    const statsAfterPump = await heart.getTotalStats();
    // Check the total fees is 3 WETH
    expect(statsAfterPump[0]).to.be.closeTo(amountInFees, amountInFees.div(100));
    // Check that we sent exactly 0.3 WETH to treasury and stat is right
    expect((await WETH.balanceOf(treasury.address)).sub(wethTreasuryBalanceBeforePump)).to.be.closeTo(
      amountInFees.mul(feeDistributionWeights[0]).div(1e9).div(1e9),
      eth('0.01'),
    );
    expect(statsAfterPump[1]).to.be.closeTo(
      amountInFees.mul(feeDistributionWeights[0]).div(1e9).div(1e9),
      amountInFees.mul(feeDistributionWeights[0]).div(1e9).div(1e9).div(100),
    );
    // Checks buybacks
    const bablBought = statsAfterPump[2];
    expect(await BABL.balanceOf(heartGarden.address)).to.be.gte(heartBABLBalanceBeforePump.add(bablBought.div(2)));
    expect(await BABL.balanceOf(treasury.address)).to.be.gte(bablTreasuryBalanceBeforePump.add(bablBought.div(2)));
    // Checks liquidity
    expect(statsAfterPump[3]).to.be.closeTo(
      amountInFees.mul(feeDistributionWeights[2]).div(1e9).div(1e9),
      amountInFees.mul(feeDistributionWeights[2]).div(1e9).div(1e9).div(100),
    );
    // Checks garden seed investments
    const totalPumpedGardens = amountInFees.mul(feeDistributionWeights[3]).div(1e9).div(1e9);
    expect(statsAfterPump[4]).to.be.closeTo(totalPumpedGardens, totalPumpedGardens.div(100));
    expect(await WETH.balanceOf(garden1.address)).to.be.closeTo(
      balanceGarden1BeforePump.add(totalPumpedGardens.div(3)),
      eth('0.01'),
    );
    expect(await WETH.balanceOf(garden2.address)).to.be.closeTo(
      balanceGarden2BeforePump.add(totalPumpedGardens.div(3)),
      eth('0.01'),
    );
    expect(await WETH.balanceOf(garden3.address)).to.be.closeTo(
      balanceGarden3BeforePump.add(totalPumpedGardens.div(3)),
      eth('0.01'),
    );
    // Checks fuse pool
    const amountLentToFuse = amountInFees.mul(feeDistributionWeights[4]).div(1e9).div(1e9);
    expect(statsAfterPump[5]).to.be.closeTo(amountLentToFuse, amountLentToFuse.div(100));
    expect(await cDAI.getCash()).to.be.closeTo(
      fuseBalanceDAIBeforePump.add(amountLentToFuse.mul(daiPerWeth).div(eth())),
      fuseBalanceDAIBeforePump.add(amountLentToFuse.mul(daiPerWeth).div(eth()).div(100)),
    );
    // Checks weekly rewards
    expect(await heart.bablRewardLeft()).to.equal(eth('4700'));
    expect(await BABL.balanceOf(heartGarden.address)).to.be.equal(
      heartBABLBalanceBeforePump.add(bablBought.div(2)).add(await heart.weeklyRewardAmount()),
    );
  }

  describe('pump', async function () {
    it('will revert if garden address has not been set', async function () {
      await expect(heart.connect(signer1).pump()).to.be.reverted;
    });

    it('will revert if garden votes have not been set', async function () {
      await heart.connect(owner).setHeartGardenAddress(heartGarden.address);
      await expect(heart.connect(signer1).pump()).to.be.reverted;
    });

    it('will pump correctly with 3 WETH', async function () {
      const amountInFees = eth('3');
      await WETH.connect(owner).transfer(heart.address, amountInFees);
      await pumpAmount(amountInFees);
    });

    it('will pump correctly with 3 ETH, 1000 DAI', async function () {
      const wethPerDai = await priceOracle.connect(owner).getPrice(DAI.address, WETH.address);
      const amountInFees = eth(3).add(eth(1000).mul(wethPerDai).div(eth()));
      await WETH.connect(owner).transfer(heart.address, eth(3));
      await DAI.connect(owner).transfer(heart.address, eth(1000));
      await pumpAmount(amountInFees);
    });

    it('will pump correctly with 3 ETH, 1000 DAI, 1000 USDC', async function () {
      const wethPerDai = await priceOracle.connect(owner).getPrice(DAI.address, WETH.address);
      const amountInFees = ethers.utils
        .parseEther('3')
        .add(eth('2000').mul(wethPerDai).div(1e9).div(1e9));
      await WETH.connect(owner).transfer(heart.address, eth('3'));
      await DAI.connect(owner).transfer(heart.address, eth('1000'));
      await USDC.connect(owner).transfer(heart.address, 1000 * 1e6);
      await pumpAmount(amountInFees);
    });
  });
});
