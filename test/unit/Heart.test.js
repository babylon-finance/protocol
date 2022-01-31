const { expect } = require('chai');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { getERC20, increaseBlock, increaseTime, proposalState } = require('utils/test-helpers');
const {
  getVoters,
  getGovernorMock,
  getProposal,
  castVotes,
  selfDelegation,
  claimTokens,
} = require('utils/gov-helpers');
const { getContractFactory } = require('@nomiclabs/hardhat-ethers/types');
const { impersonateAddress } = require('lib/rpc');
const { ONE_YEAR_IN_SECONDS } = require('lib/constants');

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
  let deployer;
  let voters;
  let token;
  let governor;
  let heartGardenSigner;

  beforeEach(async () => {
    ({ heartGarden, heart, signer1, garden1, garden2, garden3, owner, keeper, deployer } = await setupTests()());
    BABL = await getERC20(addresses.tokens.BABL);
    token = await ethers.getContractAt('BABLToken', '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74');
    governor = await ethers.getContractAt('BabylonGovernor', '0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24');
    voters = await getVoters();
    heartGardenSigner = await impersonateAddress(heartGarden.address);
    await selfDelegation(token, voters);
    await claimTokens(token, voters);
  });

  describe('can call getter methods', async function () {
    it('calls all attributes ', async function () {
      expect((await heart.connect(owner).getVotedGardens()).length).to.equal(0);
      expect((await heart.connect(owner).getGardenWeights()).length).to.equal(0);
      expect(await heart.connect(owner).minAmounts(addresses.tokens.DAI)).to.equal(eth('500'));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.USDC)).to.equal(from(500 * 1e6));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.WETH)).to.equal(eth('0.5'));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.WBTC)).to.equal(from(3 * 1e6));
      expect(await heart.connect(owner).assetToCToken(addresses.tokens.DAI)).to.equal(
        '0xA6C25548dF506d84Afd237225B5B34F2Feb1aa07',
      );
      expect(await heart.connect(owner).assetToLend()).to.equal(addresses.tokens.DAI);
      expect(await heart.connect(owner).lastPumpAt()).to.equal(0);
      expect(await heart.connect(owner).lastVotesAt()).to.equal(0);
      expect(await heart.connect(owner).weeklyRewardAmount()).to.equal(0);
      expect(await heart.connect(owner).bablRewardLeft()).to.equal(0);
      const fees = await heart.connect(owner).getFeeDistributionWeights();
      expect(fees[0]).to.equal(eth('0.10'));
      expect(fees[1]).to.equal(eth('0.50'));
      expect(fees[2]).to.equal(eth('0.15'));
      expect(fees[3]).to.equal(eth('0.15'));
      expect(fees[4]).to.equal(eth('0.10'));
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
      await heart.connect(owner).setMinTradeAmount(addresses.tokens.DAI, eth('800'));
      expect(await heart.connect(owner).minAmounts(addresses.tokens.DAI)).to.equal(eth('800'));
    });

    it('can add a reward to distribute weekly', async function () {
      await BABL.connect(owner).approve(heart.address, eth('5000'));
      await heart.connect(owner).addReward(eth('5000'), eth('400'));
      expect(await heart.connect(owner).bablRewardLeft()).to.equal(eth('5000'));
      expect(await heart.connect(owner).weeklyRewardAmount()).to.equal(eth('400'));
    });

    it('can top up a reward', async function () {
      await BABL.connect(owner).approve(heart.address, eth('8000'));
      await heart.connect(owner).addReward(eth('5000'), eth('400'));
      await heart.connect(owner).addReward(eth('3000'), eth('100'));
      expect(await heart.connect(owner).bablRewardLeft()).to.equal(eth('8000'));
      expect(await heart.connect(owner).weeklyRewardAmount()).to.equal(eth('100'));
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
          eth('0.11'),
          eth('0.51'),
          eth('0.16'),
          eth('0.17'),
          eth('0.18'),
        ]);
      expect(await heart.connect(owner).feeDistributionWeights(0)).to.equal(eth('0.11'));
      expect(await heart.connect(owner).feeDistributionWeights(1)).to.equal(eth('0.51'));
      expect(await heart.connect(owner).feeDistributionWeights(2)).to.equal(eth('0.16'));
      expect(await heart.connect(owner).feeDistributionWeights(3)).to.equal(eth('0.17'));
      expect(await heart.connect(owner).feeDistributionWeights(4)).to.equal(eth('0.18'));
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
          [eth('0.33'), eth('0.33'), eth('0.33')],
        );
      const weights = await heart.connect(owner).getGardenWeights();
      expect(weights[0]).to.equal(eth('0.33'));
      expect(weights[1]).to.equal(eth('0.33'));
      expect(weights[2]).to.equal(eth('0.33'));
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
      const heartVotingPower1 = await token.getCurrentVotes(heart.address);
      const heartSigner = await impersonateAddress(heart.address);
      const heartGardenBalance = await token.balanceOf(heartGarden.address);
      const voterBalance = await token.balanceOf(voters[0].address);
      // get heart garden delegation
      await token.connect(heartGardenSigner).delegate(heart.address, { gasPrice: 0 });
      const heartVotingPower2 = await token.getCurrentVotes(heart.address);
      // remove delegation
      await token.connect(heartGardenSigner).delegate(heartGarden.address, { gasPrice: 0 });
      const heartVotingPower3 = await token.getCurrentVotes(heart.address);
      // get out of vesting
      await increaseTime(ONE_YEAR_IN_SECONDS * 3);
      // By a simple transfer its gets voting power as it self delegated during constructor
      // If not self-delegated its own balance will never count unless heart self-delegates
      await token.connect(voters[0]).transfer(heart.address, await token.balanceOf(voters[0].address), { gasPrice: 0 });
      const heartVotingPower4 = await token.getCurrentVotes(heart.address);
      // return BABL back
      await token
        .connect(heartSigner)
        .transfer(voters[0].address, await token.balanceOf(heart.address), { gasPrice: 0 });
      const heartVotingPower5 = await token.getCurrentVotes(heart.address);
      // receive BABL from voter again
      await token.connect(voters[0]).transfer(heart.address, await token.balanceOf(voters[0].address), { gasPrice: 0 });
      const heartVotingPower6 = await token.getCurrentVotes(heart.address);
      expect(heartVotingPower1).to.eq(0);
      expect(heartVotingPower2).to.eq(heartGardenBalance);
      expect(heartVotingPower3).to.eq(0);
      expect(heartVotingPower4).to.eq(voterBalance);
      expect(heartVotingPower5).to.eq(0);
      expect(heartVotingPower6).to.eq(voterBalance);
    });
  });

  describe('pump', async function () {
    it('will revert if garden address has not been set', async function () {
      await expect(heart.connect(signer1).pump()).to.be.reverted;
    });

    it('will revert if garden votes have not been set', async function () {
      await heart.connect(owner).setHeartGardenAddress(heartGarden.address);
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
