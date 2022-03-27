const { expect } = require('chai');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { getERC20, increaseBlock, increaseTime, proposalState, eth, from } = require('utils/test-helpers');
const { getVoters, getProposal, selfDelegation, claimTokens } = require('utils/gov-helpers');
const { impersonateAddress } = require('lib/rpc');
const { ONE_YEAR_IN_SECONDS, ADDRESS_ZERO } = require('lib/constants');
const {
  createGarden,
  getDepositSigHash,
  getDepositSig,
  getWithdrawSig,
  getWithdrawSigHash,
  transferFunds,
  depositFunds,
} = require('fixtures/GardenHelper');

const { fund } = require('lib/whale');

describe('Heart', function () {
  let heartGarden;
  let heart;
  let signer1;
  let signer3;
  let garden1;
  let garden2;
  let garden3;
  let keeper;
  let owner;
  let treasury;
  let tokenIdentifier;
  let BABL;
  let FEI;
  let WETH;
  let FRAX;
  let DAI;
  let WBTC;
  let CBABL;
  let hBABL;
  let USDC;
  let cDAI;
  let deployer;
  let voters;
  let token;
  let governor;
  let priceOracle;
  let heartGardenSigner;
  let feeDistributionWeights;
  let babController;
  let gardenValuer;

  beforeEach(async () => {
    ({
      gardenValuer,
      treasury,
      heartGarden,
      babController,
      heart,
      signer1,
      signer3,
      garden1,
      garden2,
      garden3,
      owner,
      keeper,
      deployer,
      priceOracle,
      tokenIdentifier,
    } = await setupTests()());
    WETH = await getERC20(addresses.tokens.WETH);
    BABL = await getERC20(addresses.tokens.BABL);
    FRAX = await getERC20(addresses.tokens.FRAX);
    DAI = await getERC20(addresses.tokens.DAI);
    USDC = await getERC20(addresses.tokens.USDC);
    hBABL = await getERC20(heartGarden.address);
    FEI = await getERC20(addresses.tokens.FEI);
    WBTC = await getERC20(addresses.tokens.WBTC);
    CBABL = await getERC20('0x812eedc9eba9c428434fd3ce56156b4e23012ebc');
    token = await ethers.getContractAt('BABLToken', '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74');
    governor = await ethers.getContractAt('BabylonGovernor', '0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24');
    voters = await getVoters();
    heartGardenSigner = await impersonateAddress(heartGarden.address);
    await selfDelegation(token, voters);
    await claimTokens(token, voters);

    cDAI = await ethers.getContractAt('ICToken', '0xa6c25548df506d84afd237225b5b34f2feb1aa07');
    feeDistributionWeights = await heart.connect(owner).getFeeDistributionWeights();
    await heart.connect(owner).setHeartGardenAddress(heartGarden.address);
    // Impersonate visor and add heart to the whitelist
    const visorOwner = await impersonateAddress('0xc40ccde9c951ace468154d1d39917d8f8d11b38c');
    const visor = await ethers.getContractAt('IHypervisor', '0xF19F91d7889668A533F14d076aDc187be781a458');
    await visor.connect(visorOwner).appendList([heart.address], { gasPrice: 0 });
    // Adds weekly rewards
    await BABL.connect(owner).approve(heart.address, eth(5000));
    await heart.connect(owner).addReward(eth(5000), eth(300));
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
      expect(await heart.connect(owner).weeklyRewardAmount()).to.equal(eth(300));
      expect(await heart.connect(owner).bablRewardLeft()).to.equal(eth(5000));
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

  describe('resolveGardenVotes', async function () {
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
      const amountToLend = eth(5000);
      const whaleSigner = await impersonateAddress('0x40154ad8014df019a53440a60ed351dfba47574e');
      await BABL.connect(whaleSigner).transfer(heart.address, amountToLend, { gasPrice: 0 });
      await expect(heart.connect(signer1).lendFusePool(addresses.tokens.BABL, amountToLend, { gasPrice: 0 })).to.be
        .reverted;
    });
  });

  describe('bond asset by sig', async function () {
    it('can bond asset by sig', async function () {
      // make heart a keeper
      await babController.connect(owner).addKeeper(heart.address);

      await heart.connect(owner).updateBond(cDAI.address, eth(0.05));

      const whalecdaiSigner = await impersonateAddress('0x2d160210011a992966221f428f63326f76066ba9');
      const amountToBond = eth(1000);
      const priceInBABL = eth(0.1);
      const amountIn = amountToBond.mul(priceInBABL).mul(eth(1.05)).div(eth()).div(eth());
      const minAmountOut = amountIn;
      const nonce = 0;
      const maxFee = from(0);
      const fee = from(0);

      await cDAI.connect(whalecdaiSigner).transfer(signer3.address, amountToBond, { gasPrice: 0 });

      // Add fuse assets to token identifier
      await tokenIdentifier.connect(owner).updateCompoundPair([cDAI.address], [DAI.address], { gasPrice: 0 });
      // User approves the Heart
      await cDAI.connect(signer3).approve(heart.address, amountToBond, { gasPrice: 0 });

      console.log(signer3.address);
      const sig = await getDepositSig(
        heartGarden.address,
        signer3,
        amountIn,
        minAmountOut,
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      // Bond the asset
      await heart
        .connect(keeper)
        .bondAssetBySig(
          cDAI.address,
          amountToBond,
          amountIn,
          minAmountOut,
          nonce,
          maxFee,
          priceInBABL,
          eth(),
          fee,
          signer3.address,
          ADDRESS_ZERO,
          sig,
          {
            gasPrice: 0,
          },
        );

      expect(await hBABL.balanceOf(signer3.address)).to.be.closeTo(minAmountOut, 0);
    });
  });

  describe('bond asset', async function () {
    it('normal signer cannot enter a new bond asset', async function () {
      await expect(heart.connect(signer1).updateBond(cDAI.address, eth('0.05'), { gasPrice: 0 })).to.be.reverted;
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
      await expect(heart.connect(signer1).bondAsset(addresses.tokens.BABL, 1, 1, ADDRESS_ZERO, { gasPrice: 0 })).to.be
        .reverted;
    });

    it('user cannot bond a small amount', async function () {
      await heart.connect(owner).updateBond(cDAI.address, eth('0.05'), { gasPrice: 0 });
      const whalecdaiSigner = await impersonateAddress('0x2d160210011a992966221f428f63326f76066ba9');
      await cDAI.connect(whalecdaiSigner).transfer(signer1.address, 1, { gasPrice: 0 });
      await cDAI.connect(signer1).approve(heart.address, 1, { gasPrice: 0 });
      // Add fuse assets to token identifier
      await tokenIdentifier.connect(owner).updateCompoundPair([cDAI.address], [DAI.address], { gasPrice: 0 });
      await expect(heart.connect(signer1).bondAsset(addresses.tokens.cDAI, 1, 1, ADDRESS_ZERO, { gasPrice: 0 })).to.be
        .reverted;
    });

    it('user can bond an appropriate amount and receive the discount', async function () {
      await heart.connect(owner).updateBond(cDAI.address, eth('0.05'), { gasPrice: 0 });
      const whalecdaiSigner = await impersonateAddress('0x2d160210011a992966221f428f63326f76066ba9');
      const amount = eth(20000);
      const pricePerShare = await gardenValuer.calculateGardenValuation(heartGarden.address, addresses.tokens.BABL);
      // Add fuse assets to token identifier
      await tokenIdentifier.connect(owner).updateCompoundPair([cDAI.address], [DAI.address], { gasPrice: 0 });
      const price = await priceOracle.getPrice(cDAI.address, addresses.tokens.BABL);
      const minAmountOut = amount.mul(price).mul(eth(1.05)).div(eth()).div(eth()).mul(pricePerShare).div(eth());
      console.log('minAmountOut', minAmountOut.toString());

      await cDAI.connect(whalecdaiSigner).transfer(signer3.address, amount, { gasPrice: 0 });
      // User approves the heart
      await cDAI.connect(signer3).approve(heart.address, amount, { gasPrice: 0 });
      // Bond the asset
      await heart
        .connect(signer3)
        .bondAsset(cDAI.address, amount, minAmountOut.mul(99).div(100), ADDRESS_ZERO, { gasPrice: 0 });

      expect(await hBABL.balanceOf(signer3.address)).to.be.closeTo(minAmountOut, minAmountOut.div(100));
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
      await expect(heart.connect(signer1).borrowFusePool(addresses.tokens.FRAX, eth('50000'), { gasPrice: 0 })).to.be
        .reverted;
    });

    it('will repay DAI after borrowing it', async function () {
      const amountToLend = eth('5000');
      const amountToBorrow = eth('50000');
      const whaleSigner = await impersonateAddress('0x40154ad8014df019a53440a60ed351dfba47574e');
      await BABL.connect(whaleSigner).transfer(heart.address, amountToLend, { gasPrice: 0 });
      await heart.connect(owner).lendFusePool(addresses.tokens.BABL, amountToLend, { gasPrice: 0 });
      await heart.connect(owner).borrowFusePool(addresses.tokens.DAI, amountToBorrow);
      expect(await DAI.balanceOf(heart.address)).to.equal(amountToBorrow);
      await heart.connect(owner).repayFusePool(addresses.tokens.DAI, amountToBorrow.sub(amountToBorrow.div(20)));
      expect(await DAI.balanceOf(heart.address)).to.be.closeTo(amountToBorrow.div(20), amountToBorrow.div(20).div(10));
    });
  });

  describe('trades heart assets', async function () {
    it('will trade DAI for WETH', async function () {
      const amountToTrade = eth('500');
      const whaleSigner = await impersonateAddress('0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7');
      await DAI.connect(whaleSigner).transfer(heart.address, amountToTrade, { gasPrice: 0 });
      await heart.connect(owner).trade(addresses.tokens.DAI, addresses.tokens.WETH, amountToTrade, 1, { gasPrice: 0 });
      const price = await priceOracle.connect(owner).getPrice(addresses.tokens.DAI, addresses.tokens.WETH);
      const expectedWETH = amountToTrade.mul(price).div(1e9).div(1e9);
      expect(await WETH.balanceOf(heart.address)).to.be.closeTo(expectedWETH, expectedWETH.div(15));
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
  describe('protectBABL', async function () {
    describe('protects if BABL price is lower than threshold', async function () {
      [
        { name: 'USDC', token: addresses.tokens.USDC, slippage: eth(0.02), hop: addresses.tokens.WETH },
        { name: 'DAI', token: addresses.tokens.DAI, slippage: eth(0.02), hop: addresses.tokens.WETH },
        { name: 'FEI', token: addresses.tokens.FEI, slippage: eth(0.5), hop: addresses.tokens.USDC },
      ].forEach(({ token, name, slippage, hop }) => {
        it(`with ${name} as purchase asset`, async function () {
          const price = await priceOracle.getPrice(addresses.tokens.BABL, token);

          await fund([heart.address]);

          await heart.connect(owner).updateAssetToPurchase(token);
          await heart.connect(keeper).protectBABL(price.add(1), price, eth(), slippage, hop);
        });
      });
    });
  });

  describe('pump', async function () {
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
        eth(0.01),
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
        eth(0.01),
      );
      expect(await WETH.balanceOf(garden2.address)).to.be.closeTo(
        balanceGarden2BeforePump.add(totalPumpedGardens.div(3)),
        eth(0.01),
      );
      expect(await WETH.balanceOf(garden3.address)).to.be.closeTo(
        balanceGarden3BeforePump.add(totalPumpedGardens.div(3)),
        eth(0.01),
      );
      // Checks fuse pool
      const amountLentToFuse = amountInFees.mul(feeDistributionWeights[4]).div(1e9).div(1e9);
      expect(statsAfterPump[5]).to.be.closeTo(amountLentToFuse, amountLentToFuse.div(100));
      expect(await cDAI.getCash()).to.be.closeTo(
        fuseBalanceDAIBeforePump.add(amountLentToFuse.mul(daiPerWeth).div(eth())),
        fuseBalanceDAIBeforePump.add(amountLentToFuse.mul(daiPerWeth).div(eth()).div(100)),
      );
      // Checks weekly rewards
      expect(await heart.bablRewardLeft()).to.equal(eth(4700));
      expect(await BABL.balanceOf(heartGarden.address)).to.be.equal(
        heartBABLBalanceBeforePump.add(bablBought.div(2)).add(await heart.weeklyRewardAmount()),
      );
    }
    it('will revert if garden address has not been set', async function () {
      await expect(heart.connect(signer1).pump()).to.be.reverted;
    });

    it('will revert if garden votes have not been set', async function () {
      await expect(heart.connect(signer1).pump()).to.be.reverted;
    });

    it('will pump correctly with 3 WETH', async function () {
      const amountInFees = eth(3);
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
      const amountInFees = eth(3).add(eth(2000).mul(wethPerDai).div(1e9).div(1e9));
      await WETH.connect(owner).transfer(heart.address, eth(3));
      await DAI.connect(owner).transfer(heart.address, eth(1000));
      await USDC.connect(owner).transfer(heart.address, 1000 * 1e6);
      await pumpAmount(amountInFees);
    });
  });
});
