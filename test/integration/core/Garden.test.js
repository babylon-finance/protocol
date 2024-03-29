const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const {
  GARDENS,
  PROFIT_STRATEGIST_SHARE,
  PROFIT_STEWARD_SHARE,
  PROFIT_LP_SHARE,
  ONE_DAY_IN_SECONDS,
  PROTOCOL_FEE,
  GARDEN_PARAMS,
  ADDRESS_ZERO,
  ONE_YEAR_IN_SECONDS,
  WETH_STRATEGY_PARAMS,
} = require('lib/constants.js');
const { pick, increaseTime, getERC20, from, eth, getTimestamp } = require('utils/test-helpers');
const { impersonateAddress } = require('lib/rpc');

const {
  strategyParamsToArray,
  createStrategy,
  getStrategy,
  getStrategyState,
  executeStrategy,
  vote,
  finalizeStrategy,
  injectFakeProfits,
  substractFakeProfits,
} = require('fixtures/StrategyHelper');

const { createGarden, getDepositSig, getWithdrawSig, transferFunds, depositFunds } = require('fixtures/GardenHelper');

const { setupTests } = require('fixtures/GardenFixture');

describe('Garden', function () {
  let babController;
  let rewardsDistributor;
  let heart;
  let owner;
  let emergency;
  let gov;
  let timelockController;
  let keeper;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let mardukGate;
  let uniswapV3TradeIntegration;
  let heartGarden;
  let gardenNFT;
  let gardenValuer;
  let viewer;
  let bablToken;

  let usdc;
  let weth;
  let dai;
  let babl;

  beforeEach(async () => {
    ({
      babController,
      rewardsDistributor,
      heart,
      gardenNFT,
      keeper,
      owner,
      timelockController,
      signer1,
      signer2,
      signer3,
      garden1,
      heartGarden,
      mardukGate,
      uniswapV3TradeIntegration,
      gardenValuer,
      viewer,
      bablToken,

      dai,
      babl,
      usdc,
      weth,
    } = await setupTests()());
    emergency = await impersonateAddress('0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e');
    gov = await impersonateAddress(timelockController.address);
  });

  describe('construction', async function () {
    it('should have expected properties upon deployment', async function () {
      expect(await garden1.totalContributors()).to.equal(1);
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      expect(await garden1.controller()).to.equal(babController.address);
      expect(await garden1.strategyCooldownPeriod()).to.equal(ONE_DAY_IN_SECONDS);
      expect(await garden1.minVotesQuorum()).to.equal(eth('0.10'));
      expect(await garden1.minStrategyDuration()).to.equal(ONE_DAY_IN_SECONDS * 3);
      expect(await garden1.maxStrategyDuration()).to.equal(ONE_DAY_IN_SECONDS * 365);
    });
  });

  describe('assigning extra creators', async function () {
    it('should allow the creator to add them', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).addExtraCreators([signer2.getAddress(), ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]);
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      expect(await garden1.extraCreators(0)).to.equal(await signer2.getAddress());
    });

    it('should not allow any other person to do it', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await expect(
        garden1.connect(signer2).addExtraCreators([signer2.getAddress(), ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]),
      ).to.be.revertedWith('BAB#095');
    });

    it('should only allow the creator to do it once', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).addExtraCreators([signer2.getAddress(), ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]);
      await expect(
        garden1.connect(signer1).addExtraCreators([signer3.getAddress(), ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]),
      ).to.be.revertedWith('BAB#094');
    });
  });

  describe('transfer garden tokens', async function () {
    it('can transfer to a non-contributor account', async function () {
      await fund([signer1.address], { tokens: [addresses.tokens.DAI] });

      const garden = await createGarden({
        reserveAsset: addresses.tokens.DAI,
        publicGardenStrategistsStewards: [true, true, true],
      });
      await babController.connect(owner).enableGardenTokensTransfers();

      const amount = await garden.balanceOf(signer1.address);
      await garden.connect(signer1).transfer(signer2.address, amount);

      const ts = await getTimestamp();

      let [
        lastDepositAt,
        initialDepositAt,
        claimedAt,
        claimedBABL,
        claimedRewards,
        withdrawnSince,
        totalDeposits,
        nonce,
        lockedBalance,
      ] = await garden.getContributor(signer1.address);

      expect(lastDepositAt).to.eq(0);
      expect(initialDepositAt).to.eq(0);
      expect(claimedAt).to.eq(0);
      expect(claimedBABL).to.eq(0);
      expect(claimedRewards).to.eq(0);
      expect(withdrawnSince).to.eq(0);
      expect(totalDeposits).to.eq(0);
      expect(nonce).to.eq(1);
      expect(lockedBalance).to.eq(0);

      [
        lastDepositAt,
        initialDepositAt,
        claimedAt,
        claimedBABL,
        claimedRewards,
        withdrawnSince,
        totalDeposits,
        nonce,
        lockedBalance,
      ] = await garden.getContributor(signer2.address);

      expect(lastDepositAt).to.eq(ts);
      expect(initialDepositAt).to.eq(ts);
      expect(claimedAt).to.eq(0);
      expect(claimedBABL).to.eq(0);
      expect(claimedRewards).to.eq(0);
      expect(withdrawnSince).to.eq(0);
      expect(totalDeposits).to.eq(0);
      expect(nonce).to.eq(0);
      expect(lockedBalance).to.eq(0);

      expect(await garden.balanceOf(signer1.address)).to.eq(0);
      expect(await garden.balanceOf(signer2.address)).to.eq(amount);
    });

    it('fail to transfer locked tokens', async function () {
      await fund([signer1.address], { tokens: [addresses.tokens.WETH] });

      const garden = await createGarden({
        reserveAsset: addresses.tokens.WETH,
        publicGardenStrategistsStewards: [true, true, true],
      });
      await babController.connect(owner).enableGardenTokensTransfers();

      await getStrategy({ garden: garden });

      const amount = await garden.balanceOf(signer1.address);
      await expect(garden.connect(signer1).transfer(signer2.address, amount)).to.be.revertedWith('BAB#007');
    });
  });

  describe('transfer creator rights', async function () {
    it('should allow transfering creator rights', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).transferCreatorRights(await signer2.getAddress(), 0);
      expect(await garden1.creator()).to.equal(await signer2.getAddress());
    });

    it('should not allow renouncing creator rights if the garden is private', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await expect(garden1.connect(signer1).transferCreatorRights(ADDRESS_ZERO, 0)).to.be.reverted;
    });

    it('should allow renouncing creator rights if the garden is public', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).makeGardenPublic();
      await expect(garden1.connect(signer1).transferCreatorRights(ADDRESS_ZERO, 0)).to.not.be.reverted;
      expect(await garden1.creator()).to.equal(ADDRESS_ZERO);
    });

    it('should only allow transfering creator rights by a creator', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await expect(garden1.connect(signer2).transferCreatorRights(await signer2.getAddress(), 0)).to.be.revertedWith(
        'BAB#017',
      );
    });

    it('should allow changing an extra creator as well', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).addExtraCreators([signer2.getAddress(), ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]);
      expect(await garden1.extraCreators(0)).to.equal(await signer2.getAddress());
      await garden1.connect(signer2).transferCreatorRights(await signer3.getAddress(), 0);
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      expect(await garden1.extraCreators(0)).to.equal(await signer3.getAddress());
    });

    it('should not allow changing an extra creator with wrong index', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).addExtraCreators([signer2.getAddress(), ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]);
      expect(await garden1.extraCreators(0)).to.equal(await signer2.getAddress());
      await expect(garden1.connect(signer2).transferCreatorRights(await signer3.getAddress(), 1)).to.be.revertedWith(
        'BAB#017',
      );
    });

    it('should not allow changing an extra creator by the wrong sender', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).addExtraCreators([signer2.getAddress(), ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]);
      expect(await garden1.extraCreators(0)).to.equal(await signer2.getAddress());
      await expect(garden1.connect(signer3).transferCreatorRights(await signer3.getAddress(), 0)).to.be.revertedWith(
        'BAB#017',
      );
    });

    it('should not allow changing a creator to an address that it is already one', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).addExtraCreators([signer2.getAddress(), ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]);
      expect(await garden1.extraCreators(0)).to.equal(await signer2.getAddress());
      await expect(garden1.connect(signer2).transferCreatorRights(await signer1.getAddress(), 0)).to.be.revertedWith(
        'BAB#094',
      );
    });
  });

  describe('delegate votes into heart', async function () {
    it('heart garden can delegate into heart', async function () {
      const token = await ethers.getContractAt('BABLToken', '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74', owner);
      const heartDelegatee1 = await token.delegates(heartGarden.address);
      expect(heartDelegatee1).to.eq(ADDRESS_ZERO); // No delegation yet
      const creator = await impersonateAddress(await heartGarden.creator());
      await heartGarden.connect(creator).delegateVotes(token.address, heart.address);
      const heartDelegatee2 = await token.delegates(heartGarden.address);
      expect(heartDelegatee2).to.eq(heart.address);
    });
  });

  describe('recover original creator position', async function () {
    it('should allow recovering of creator rights by emergency', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).makeGardenPublic();
      await expect(garden1.connect(signer1).transferCreatorRights(ADDRESS_ZERO, 0)).to.not.be.reverted;
      expect(await garden1.creator()).to.equal(ADDRESS_ZERO);
      await garden1
        .connect(emergency)
        .updateCreators(signer1.address, [ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]);
      expect(await garden1.creator()).to.eq(signer1.address);
    });
    it('should allow recovering of creator rights by governance', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).makeGardenPublic();
      await expect(garden1.connect(signer1).transferCreatorRights(ADDRESS_ZERO, 0)).to.not.be.reverted;
      expect(await garden1.creator()).to.equal(ADDRESS_ZERO);
      await garden1
        .connect(gov)
        .updateCreators(signer1.address, [ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]);
      expect(await garden1.creator()).to.eq(signer1.address);
    });
    it('should NOT allow recovering creator rights by a non authorized user', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).makeGardenPublic();
      await expect(garden1.connect(signer1).transferCreatorRights(ADDRESS_ZERO, 0)).to.not.be.reverted;
      expect(await garden1.creator()).to.equal(ADDRESS_ZERO);
      await expect(
        garden1
          .connect(signer1)
          .updateCreators(signer1.address, [ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]),
      ).to.be.revertedWith('Only governance or emergency can call this');
      expect(await garden1.creator()).to.eq(ADDRESS_ZERO);
    });
    it('should NOT allow recovering of creator rights by governance if original creator has not renounced before', async function () {
      expect(await garden1.creator()).to.equal(await signer1.getAddress());
      await garden1.connect(signer1).makeGardenPublic();
      // Extra creator cannot replace original creator or any other creator except itself
      await expect(
        garden1
          .connect(emergency)
          .updateCreators(signer2.address, [ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO, ADDRESS_ZERO]),
      ).to.be.revertedWith('BAB#097');
      expect(await garden1.creator()).to.equal(signer1.address);
    });
  });
  describe('pseudo-public rights by gardener', async function () {
    it('should allow deposits to a Ishar gate owner despite its individual permission is set to 0 but general deposit permission is allowed', async function () {
      expect(await mardukGate.connect(signer1).canJoinAGarden(garden1.address, signer3.address)).to.equal(true);
      // Remove permissions
      await mardukGate.connect(signer1).setGardenAccess(signer3.address, garden1.address, 0, { gasPrice: 0 });
      expect(await mardukGate.connect(signer1).canJoinAGarden(garden1.address, signer3.address)).to.equal(false);
      await expect(
        garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
          value: eth(),
          gasPrice: 0,
        }),
      ).to.be.revertedWith('BAB#029');
      const canJoin =
        (await mardukGate.connect(signer1).canJoinAGarden(garden1.address, signer3.address)) ||
        ((await mardukGate.canAccessBeta(signer3.address)) && !(await garden1.privateGarden()));
      expect(canJoin).to.equal(false);
      // Make garden public first at BabController then at garden level
      await garden1.connect(signer1).makeGardenPublic();

      garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
        gasPrice: 0,
      });
      expect(await garden1.balanceOf(signer3.address)).to.equal(eth());
      const canJoin2 =
        (await mardukGate.connect(signer1).canJoinAGarden(garden1.address, signer3.address)) ||
        ((await mardukGate.canAccessBeta(signer3.address)) && !(await garden1.privateGarden()));
      expect(canJoin2).to.equal(true);
    });

    it('should allow the strategy creation by an Ishar gate owner despite its individual permission is set to 0 but general strategy creation permission is allowed', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
        gasPrice: 0,
      });
      await expect(getStrategy({ garden: garden1, signers: [signer3] })).not.to.be.reverted;
      // Remove permissions (0 is below LP even)
      await mardukGate.connect(signer1).setGardenAccess(signer3.address, garden1.address, 0, { gasPrice: 0 });
      await expect(getStrategy({ garden: garden1, signers: [signer3] })).to.be.revertedWith('BAB#030');
      expect(await mardukGate.connect(signer1).canAddStrategiesInAGarden(garden1.address, signer3.address)).to.equal(
        false,
      );
      // Enable strategist creator rights - the garden needs to be public
      await expect(garden1.connect(signer1).setPublicRights(true, false)).to.be.revertedWith('BAB#090');
      await garden1.connect(signer1).makeGardenPublic();
      await garden1.connect(signer1).setPublicRights(true, false);
      await expect(getStrategy({ garden: garden1, signers: [signer3] })).not.to.be.reverted;
      const [, , canAddStrategy3] = await viewer
        .connect(signer1)
        .getGardenPermissions(garden1.address, signer3.address);
      expect(canAddStrategy3).to.equal(true);
    });

    it('should allow the vote by an Ishar gate owner despite its individual permission is set to 0 but general voting permission is allowed', async function () {
      await garden1.connect(signer2).deposit(eth(), 1, signer2.getAddress(), ADDRESS_ZERO, {
        value: eth(),
        gasPrice: 0,
      });
      const canJoin =
        (await mardukGate.connect(signer1).canVoteInAGarden(garden1.address, signer2.address)) ||
        ((await mardukGate.canAccessBeta(signer2.address)) && (await garden1.publicStewards()));

      expect(canJoin).to.equal(true);
      // Remove permissions (0 is below LP even)
      await mardukGate.connect(signer1).setGardenAccess(signer2.address, garden1.address, 0, { gasPrice: 0 });
      const canJoin2 =
        (await mardukGate.connect(signer1).canVoteInAGarden(garden1.address, signer2.address)) ||
        ((await mardukGate.canAccessBeta(signer2.address)) && (await garden1.publicStewards()));
      expect(canJoin2).to.equal(false);

      // Enable voting power rights to users - the garden needs to be public
      await expect(garden1.connect(signer1).setPublicRights(false, true)).to.be.revertedWith('BAB#090');
      await garden1.connect(signer1).makeGardenPublic();
      await garden1.connect(signer1).setPublicRights(false, true);
      const canJoin3 =
        (await mardukGate.connect(signer1).canVoteInAGarden(garden1.address, signer2.address)) ||
        ((await mardukGate.canAccessBeta(signer2.address)) && (await garden1.publicStewards()));
      expect(canJoin3).to.equal(true);
    });
  });

  describe('profit sharing', async function () {
    it('garden is initialized with default profit sharing if not set during initialization', async function () {
      // TODO CHECK all require at modifier
      const profitSharing = await rewardsDistributor.getGardenProfitsSharing(garden1.address);
      expect(profitSharing[0]).to.equal(PROFIT_STRATEGIST_SHARE);
      expect(profitSharing[1]).to.equal(PROFIT_STEWARD_SHARE);
      expect(profitSharing[2]).to.equal(PROFIT_LP_SHARE);
    });

    it('should fail if trying to set garden profit sharing params by non-contract account', async function () {
      // TODO CHECK all require at modifier
      await expect(
        rewardsDistributor.setProfitRewards(
          garden1.address,
          PROFIT_STRATEGIST_SHARE.toString(),
          PROFIT_STEWARD_SHARE.toString(),
          PROFIT_LP_SHARE.toString(),
        ),
      ).to.be.reverted;
    });

    async function testPublicSharing(shares) {
      const newGarden = await createGarden({ publicSharing: shares });
      const profitSharing = await rewardsDistributor.getGardenProfitsSharing(newGarden.address);

      expect(profitSharing[0]).to.equal(shares[0]);
      expect(profitSharing[1]).to.equal(shares[1]);
      expect(profitSharing[2]).to.equal(shares[2]);
    }

    it('only the protocol should be able to custom garden profit sharing (95% to LP) while creation', async function () {
      await testPublicSharing([eth(0), eth(0), eth(0.95)]);
    });

    it('only the protocol should be able to custom garden profit sharing (95% to Stewards) while creation', async function () {
      await testPublicSharing([eth(0), eth(0.95), eth(0)]);
    });

    it('only the protocol should be able to custom garden profit sharing (95% to Strategist) while creation', async function () {
      await testPublicSharing([eth(0.95), eth(0), eth(0)]);
    });

    it('only the protocol should be able to custom garden profit sharing (15% , 40%, 40%) while creation', async function () {
      await testPublicSharing([eth(0.15), eth(0.4), eth(0.4)]);
    });

    it('should fail if the protocol try a custom profit sharing which sum is below 95% while creation', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'New Garden',
            'NEWG',
            'http...',
            0,
            GARDEN_PARAMS,
            eth(),
            [false, false, false],
            [eth('0.14'), eth('0.40'), eth('0.40')],
            {
              value: eth(),
            },
          ),
      ).to.be.revertedWith('BAB#092');
    });

    it('should fail if the protocol try a custom profit sharing which sum is above 95% while creation', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'New Garden',
            'NEWG',
            'http...',
            0,
            GARDEN_PARAMS,
            eth(),
            [false, false, false],
            [eth('0.14'), eth('0.45'), eth('0.40')],
            {
              value: eth(),
            },
          ),
      ).to.be.revertedWith('BAB#092');
    });

    it('should fail if the protocol try a custom profit sharing which sum is below 95% while creation (by decimal difference)', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'New Garden',
            'NEWG',
            'http...',
            0,
            GARDEN_PARAMS,
            eth(),
            [false, false, false],
            [eth('0.1499999999'), eth('0.40'), eth('0.40')],
            {
              value: eth(),
            },
          ),
      ).to.be.revertedWith('BAB#092');
    });

    it('should fail if the protocol try a custom profit sharing which sum is above 95% while creation (by decimal difference)', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'New Garden',
            'NEWG',
            'http...',
            0,
            GARDEN_PARAMS,
            eth(),
            [false, false, false],
            [eth('0.15'), eth('0.40000001'), eth('0.40')],
            {
              value: eth(),
            },
          ),
      ).to.be.revertedWith('BAB#092');
    });
  });

  describe('withdrawBySig', async function () {
    it('can withdraw', async function () {
      let amountIn = from(1000 * 1e6);
      let minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), ADDRESS_ZERO);

      const gardenBalanceBefore = await usdc.balanceOf(garden.address);
      const supplyBefore = await garden.totalSupply();

      const [, , , , , withdrawnSinceBefore, totalDepositsBefore, ,] = await garden.getContributor(signer3.address);

      amountIn = eth(1000);
      minAmountOut = from(1000 * 1e6);

      const sig = await getWithdrawSig(garden.address, signer3, amountIn, minAmountOut, 1, 0, false);
      await garden
        .connect(keeper)
        .withdrawBySig(amountIn, minAmountOut, 1, 0, false, ADDRESS_ZERO, eth(), 0, 0, signer3.address, sig);

      const supplyAfter = await garden.totalSupply();
      expect(supplyBefore.sub(supplyAfter)).to.be.eq(amountIn);

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceBefore.sub(gardenBalanceAfter)).to.equal(minAmountOut);

      const [, , , , , withdrawnSinceAfter, totalDepositsAfter, ,] = await garden.getContributor(signer3.address);
      expect(totalDepositsBefore.sub(totalDepositsAfter)).to.equal(minAmountOut);
      expect(totalDepositsAfter).to.equal(0);
    });

    it('smart contract can withdraw', async function () {
      const walletFactory = await ethers.getContractFactory('ERC1271WalletMock');
      const wallet = await walletFactory.deploy(signer3.address);
      const signerWallet = await impersonateAddress(wallet.address);

      let amountIn = from(1000 * 1e6);
      let minAmountOut = eth(1000);

      await fund([signer1.address, wallet.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });
      await garden.connect(signer1).makeGardenPublic();

      await usdc.connect(signerWallet).approve(garden.address, amountIn, { gasPrice: 0 });

      await garden.connect(signerWallet).deposit(amountIn, minAmountOut, wallet.address, ADDRESS_ZERO, { gasPrice: 0 });

      const gardenBalanceBefore = await usdc.balanceOf(garden.address);
      const supplyBefore = await garden.totalSupply();

      const [, , , , , withdrawnSinceBefore, totalDepositsBefore, ,] = await garden.getContributor(wallet.address);

      amountIn = eth(1000);
      minAmountOut = from(1000 * 1e6);

      const sig = await getWithdrawSig(garden.address, signer3, amountIn, minAmountOut, 1, 0, false);
      await garden
        .connect(keeper)
        .withdrawBySig(amountIn, minAmountOut, 1, 0, false, ADDRESS_ZERO, eth(), 0, 0, wallet.address, sig);

      const supplyAfter = await garden.totalSupply();
      expect(supplyBefore.sub(supplyAfter)).to.be.eq(amountIn);

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceBefore.sub(gardenBalanceAfter)).to.equal(minAmountOut);

      const [, , , , , withdrawnSinceAfter, totalDepositsAfter, ,] = await garden.getContributor(wallet.address);
      expect(totalDepositsBefore.sub(totalDepositsAfter)).to.equal(minAmountOut);
      expect(totalDepositsAfter).to.equal(0);
    });

    [
      {
        token: addresses.tokens.WETH,
        name: 'WETH',
        opts: {
          depositIn: eth(),
          depositOut: eth(),
          amountIn: eth(0.5),
          minAmountOut: eth(0.5),
          fee: eth(0.01),
          maxFee: eth(0.01),
        },
      },
      {
        token: addresses.tokens.USDC,
        name: 'USDC',
        opts: {
          depositIn: from(1000 * 1e6),
          depositOut: eth(1000),
          amountIn: eth(500),
          minAmountOut: from(500 * 1e6),
          fee: from(100 * 1e6),
          maxFee: from(100 * 1e6),
        },
      },
    ].forEach(({ token, name, opts }) => {
      it(`can witdraw with a Keeper fee into ${name} garden`, async function () {
        const { amountIn, minAmountOut, fee, maxFee, depositIn, depositOut } = opts;

        const erc20 = await getERC20(token);

        await fund([signer1.address, signer3.address], { tokens: [token] });

        const garden = await createGarden({ reserveAsset: token });

        await erc20.connect(signer3).approve(garden.address, depositIn, {
          gasPrice: 0,
        });

        await garden.connect(signer3).deposit(depositIn, depositOut, signer3.getAddress(), ADDRESS_ZERO);

        const supplyBefore = await garden.totalSupply();
        const balanceBefore = await ethers.provider.getBalance(signer3.address);

        const sig = await getWithdrawSig(garden.address, signer3, amountIn, minAmountOut, 1, maxFee);

        if (token === addresses.tokens.WETH) {
          await expect(() =>
            garden
              .connect(keeper)
              .withdrawBySig(
                amountIn,
                minAmountOut,
                1,
                maxFee,
                false,
                ADDRESS_ZERO,
                eth(),
                0,
                fee,
                signer3.address,
                sig,
              ),
          ).to.changeTokenBalances(erc20, [keeper, garden], [fee, minAmountOut.mul(-1)]);

          expect((await ethers.provider.getBalance(signer3.address)).sub(balanceBefore)).to.be.eq(
            minAmountOut.sub(fee),
          );
        } else {
          await expect(() =>
            garden
              .connect(keeper)
              .withdrawBySig(
                amountIn,
                minAmountOut,
                1,
                maxFee,
                false,
                ADDRESS_ZERO,
                eth(),
                0,
                fee,
                signer3.address,
                sig,
              ),
          ).to.changeTokenBalances(
            erc20,
            [keeper, garden, signer3],
            [fee, minAmountOut.mul(-1), minAmountOut.sub(fee)],
          );
        }

        const supplyAfter = await garden.totalSupply();
        expect(supplyBefore.sub(supplyAfter)).to.eq(amountIn);
      });
    });

    it('rejects if not keeper', async function () {
      let amountIn = from(1000 * 1e6);
      let minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), ADDRESS_ZERO);

      amountIn = eth(1000);
      minAmountOut = from(1000 * 1e6);
      const sig = await getWithdrawSig(garden.address, signer3, amountIn, minAmountOut, 1, 0, false);
      await expect(
        garden
          .connect(signer3)
          .withdrawBySig(amountIn, minAmountOut, 1, 0, false, ADDRESS_ZERO, eth(), 0, 0, signer3.address, sig),
      ).to.be.revertedWith('BAB#018');
    });

    it('rejects wrong nonce', async function () {
      let amountIn = from(1000 * 1e6);
      let minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), ADDRESS_ZERO);

      amountIn = eth(1000);
      minAmountOut = from(1000 * 1e6);
      const sig = await getWithdrawSig(garden.address, signer3, amountIn, minAmountOut, 8, 0, false);

      await expect(
        garden
          .connect(keeper)
          .withdrawBySig(amountIn, minAmountOut, 8, 0, false, ADDRESS_ZERO, eth(), 0, 0, signer3.address, sig),
      ).to.be.revertedWith('BAB#089');
    });

    it('can withdraw with a penalty', async function () {
      let amountIn = from(1000 * 1e6);
      let minAmountOut = eth(1000);
      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), ADDRESS_ZERO);

      const supplyBefore = await garden.totalSupply();

      const balanceBefore = await garden.balanceOf(signer3.address);

      const strategy = await getStrategy({ garden: garden, signers: [signer1] });
      await vote(strategy, [signer1, signer2, signer3]);

      await executeStrategy(strategy, { amount: amountIn.sub(amountIn.mul(PROTOCOL_FEE).div(eth())) });

      const gardenBalanceBefore = await usdc.balanceOf(garden.address);
      const beforeWithdrawal = await usdc.balanceOf(signer3.address);

      amountIn = eth(500);
      minAmountOut = from(475 * 1e6);

      const pricePerShare = await gardenValuer.calculateGardenValuation(garden.address, addresses.tokens.USDC);
      const strategyNAV = await strategy.getNAV();

      const sig = await getWithdrawSig(garden.address, signer3, amountIn, minAmountOut, 1, 0, true);

      // remove USDC funds from Garden so penalty would be applied
      await usdc.connect(await impersonateAddress(garden.address)).transfer(signer3.address, gardenBalanceBefore, {
        gasPrice: 0,
      });

      await garden
        .connect(keeper)
        .withdrawBySig(
          amountIn,
          minAmountOut,
          1,
          0,
          true,
          strategy.address,
          pricePerShare,
          strategyNAV,
          0,
          signer3.address,
          sig,
        );

      // put the funds back
      await usdc.connect(await impersonateAddress(signer3.address)).transfer(garden.address, gardenBalanceBefore, {
        gasPrice: 0,
      });

      const supplyAfter = await garden.totalSupply();
      expect(supplyBefore.sub(supplyAfter)).to.be.eq(amountIn);

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceAfter.sub(gardenBalanceBefore)).to.be.closeTo(from(0), from(25 * 1e6));

      // check users garden shares
      const balanceAfter = await garden.balanceOf(signer3.address);
      expect(balanceBefore.sub(balanceAfter)).to.eq(amountIn);
      expect(balanceAfter).to.equal(amountIn);

      // check user USDC balance; account for 2.5% penalty
      expect((await usdc.balanceOf(signer3.address)).sub(beforeWithdrawal)).to.be.gte(minAmountOut);
    });

    it('can withdraw with a penalty from a strategy in losses', async function () {
      let amountIn = from(1000 * 1e6);
      let minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), ADDRESS_ZERO);

      const supplyBefore = await garden.totalSupply();

      const balanceBefore = await garden.balanceOf(signer3.address);

      const strategy = await getStrategy({ garden: garden, signers: [signer1] });
      await vote(strategy, [signer1, signer2, signer3]);

      await executeStrategy(strategy, { amount: amountIn.sub(amountIn.mul(PROTOCOL_FEE).div(eth())) });

      // lose 100 DAI
      await substractFakeProfits(strategy, eth(10));

      const pricePerShare = await gardenValuer.calculateGardenValuation(garden.address, addresses.tokens.USDC);

      const gardenBalanceBefore = await usdc.balanceOf(garden.address);
      const beforeWithdrawal = await usdc.balanceOf(signer3.address);

      amountIn = eth(500);
      minAmountOut = eth(500).mul(975).div(1000).mul(pricePerShare).div(eth()).div(1e12);

      const strategyNAV = await strategy.getNAV();

      const sig = await getWithdrawSig(garden.address, signer3, amountIn, minAmountOut, 1, 0, true);

      // remove USDC funds from Garden so penalty would be applied
      await usdc.connect(await impersonateAddress(garden.address)).transfer(signer3.address, gardenBalanceBefore, {
        gasPrice: 0,
      });

      await garden
        .connect(keeper)
        .withdrawBySig(
          amountIn,
          minAmountOut,
          1,
          0,
          true,
          strategy.address,
          pricePerShare,
          strategyNAV,
          0,
          signer3.address,
          sig,
        );

      // put the funds back
      await usdc.connect(await impersonateAddress(signer3.address)).transfer(garden.address, gardenBalanceBefore, {
        gasPrice: 0,
      });

      const supplyAfter = await garden.totalSupply();
      expect(supplyBefore.sub(supplyAfter)).to.be.eq(amountIn);

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceAfter.sub(gardenBalanceBefore)).to.be.closeTo(from(0), from(25 * 1e6));

      // check users garden shares
      const balanceAfter = await garden.balanceOf(signer3.address);
      expect(balanceBefore.sub(balanceAfter)).to.eq(amountIn);
      expect(balanceAfter).to.equal(amountIn);

      // check user USDC balance; account for 2.5% penalty
      expect((await usdc.balanceOf(signer3.address)).sub(beforeWithdrawal)).to.be.gte(minAmountOut);
    });
  });

  describe('withdraw', async function () {
    it('can withdraw funds if garden has free liquidity', async function () {
      const amountIn = eth();
      const minAmountOut = eth();

      await garden1.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
        gasPrice: 0,
      });

      const beforeWithdrawal = await ethers.provider.getBalance(signer3.address);

      await garden1.connect(signer3).withdraw(amountIn, minAmountOut, signer3.getAddress(), false, ADDRESS_ZERO, {
        gasPrice: 0,
      });

      expect((await ethers.provider.getBalance(signer3.address)).sub(beforeWithdrawal)).to.be.eq(minAmountOut);
    });

    it('can withdraw all funds', async function () {
      const amountIn = eth();
      const minAmountOut = eth();

      await garden1.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
        gasPrice: 0,
      });

      const beforeWithdrawal = await ethers.provider.getBalance(signer3.address);

      await garden1.connect(signer3).withdraw(eth(999999999), minAmountOut, signer3.getAddress(), false, ADDRESS_ZERO, {
        gasPrice: 0,
      });

      expect((await ethers.provider.getBalance(signer3.address)).sub(beforeWithdrawal)).to.be.eq(minAmountOut);
    });

    it('can withdraw funds with a penalty', async function () {
      const garden = await createGarden();
      const strategy = await getStrategy({ garden: garden, signers: [signer1] });
      await vote(strategy, [signer1, signer2, signer3]);
      await executeStrategy(strategy, { amount: eth().sub(eth().mul(PROTOCOL_FEE).div(eth())) });
      const beforeWithdrawal = await ethers.provider.getBalance(signer1.address);
      await garden.connect(signer1).withdraw(eth(0.5), 1, signer1.getAddress(), true, strategy.address);
      expect((await ethers.provider.getBalance(signer1.address)).sub(beforeWithdrawal)).to.be.closeTo(
        eth(0.48),
        eth(0.01),
      );
    });

    it('cannot withdraw gardens until the time ends', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
      });
      expect(await garden1.totalContributors()).to.equal(2);
      await expect(garden1.connect(signer3).withdraw(eth('20'), 1, signer3.getAddress()), false, ADDRESS_ZERO).to.be
        .reverted;
    });

    it('cannot withdraw more garden tokens than they have deposited', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
      expect(await garden1.totalContributors()).to.equal(2);
      await expect(garden1.connect(signer3).withdraw(eth('1.12'), 2, signer3.getAddress()), false, ADDRESS_ZERO).to.be
        .reverted;
      await expect(garden1.connect(signer3).withdraw(eth('20'), 2, signer3.getAddress()), false, ADDRESS_ZERO).to.to.be
        .reverted;
    });

    it('strategist or voters can withdraw garden tokens that were locked during strategy execution (negative profits) once they are unlocked after finishing active strategies', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(strategyContract, eth(), 42);
      const { active, finalized, executedAt, exitedAt, updatedAt } = await getStrategyState(strategyContract);
      expect(active).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(eth('0.1'));

      await finalizeStrategy(strategyContract, 42);

      await garden1
        .connect(signer2)
        .withdraw(await garden1.balanceOf(signer2.address), 1, signer2.getAddress(), false, ADDRESS_ZERO);

      const WITHDRAWsigner2Balance = await garden1.balanceOf(signer2.address);
      await expect(WITHDRAWsigner2Balance).to.be.equal(eth('0'));
    });

    it('strategist or voters can withdraw garden tokens that were locked during strategy execution (positive profits) once they are unlocked after finishing active strategies', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(strategyContract, eth(), 42);
      const { active } = await getStrategyState(strategyContract);
      expect(active).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(eth('0.1'));

      await injectFakeProfits(strategyContract, eth('200')); // We inject positive profits

      await finalizeStrategy(strategyContract, 42);

      // Can now withdraw stake amount as it is again unlocked
      await expect(
        garden1
          .connect(signer2)
          .withdraw(await garden1.balanceOf(signer2.address), 1, signer2.getAddress(), false, ADDRESS_ZERO),
      ).not.to.be.reverted;

      const WITHDRAWsigner2Balance = await garden1.balanceOf(signer2.address);
      await expect(WITHDRAWsigner2Balance).to.be.equal(eth('0'));
    });

    it('strategist is taken the exact (quadratic) amount of stake after a negative profit strategy with negative results', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(strategyContract, eth(), 42);
      const { active } = await getStrategyState(strategyContract);
      expect(active).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(eth('0.1'));
      const InitialStrategistBalance = await garden1.balanceOf(signer1.address);

      await finalizeStrategy(strategyContract, 42);

      // Being a negative profit strategy, the corresponding % of the loss is reduced (burned) from the strategists stake
      const value =
        (ethers.BigNumber.from(await strategyContract.capitalReturned()) /
          ethers.BigNumber.from(await strategyContract.capitalAllocated())) *
        ethers.BigNumber.from(await strategyContract.stake());
      const value2 = ethers.BigNumber.from(await strategyContract.stake()) - value;
      const toBurn = value2 * 1.75; // Quadratic penalty for bad strategists
      const finalStrategistBalance = await garden1.balanceOf(signer1.address);
      const finalReducedBalance = InitialStrategistBalance.toString() - toBurn.toString();
      await expect(finalStrategistBalance).to.be.closeTo(finalReducedBalance.toString(), eth('0.005'));
    });

    it('strategist or voters can withdraw garden tokens during strategy execution if they have enough unlocked amount in their balance and not trying to withdraw the equivalent votes associated to a running strategy', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      // It is executed
      await executeStrategy(strategyContract, eth(), 42);

      await garden1.connect(signer2).deposit(eth('5'), 1, signer2.getAddress(), ADDRESS_ZERO, {
        value: eth('5'),
        gasPrice: 0,
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 5]); // to bypass hardlock
      const beforeBalance = await garden1.balanceOf(signer2.address);

      const [, , , , , , , lockedBalance] = await garden1.getContributor(signer2.address);

      // Due to the strategy is under execution the withdrawal without penalty does not allow to withdraw the whole balance if votes had been compromised in the executing strategy
      await expect(
        garden1
          .connect(signer2)
          .withdraw(beforeBalance.sub(lockedBalance), 1, signer2.getAddress(), false, ADDRESS_ZERO),
      );
    });

    it('should not fail if strategist or voters try to withdraw all their garden tokens during strategy execution with 0 staked amount but some voting amount associated to a running strategy', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      // It is executed
      await executeStrategy(strategyContract, eth(), 42);

      await garden1.connect(signer2).deposit(eth('5'), 1, signer2.getAddress(), ADDRESS_ZERO, {
        value: eth('5'),
        gasPrice: 0,
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 5]); // to bypass hardlock
      const beforeBalance = await garden1.balanceOf(signer2.address);

      const [, , , , , , , lockedBalance] = await garden1.getContributor(signer2.address);

      // Due to the strategy is under execution the withdrawal without penalty does not allow to withdraw the whole balance if votes had been compromised in the executing strategy
      await expect(
        garden1
          .connect(signer2)
          .withdraw(beforeBalance.sub(lockedBalance), 1, signer2.getAddress(), false, ADDRESS_ZERO),
      ).to.not.be.reverted;
    });

    it('should fail if finalizeStrategy is from a non-strategy address', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      // It is executed
      await executeStrategy(strategyContract, eth(), 42);

      await injectFakeProfits(strategyContract, eth('200')); // We inject positive profits
      await finalizeStrategy(strategyContract, 0);
      await expect(finalizeStrategy(strategyContract, 0)).to.be.revertedWith('BAB#050');

      await expect(
        garden1.finalizeStrategy(from('14263257018321332'), from('90333961116035100'), from(0)),
      ).to.be.revertedWith('BAB#020');
    });
  });

  describe('depositBySig', async function () {
    it('can deposit', async function () {
      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);
      const fee = from(0);
      const maxFee = from(0);
      const nonce = 0;

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      const gardenBalance = await usdc.balanceOf(garden.address);
      const supplyBefore = await garden.totalSupply();
      const [, , , , , withdrawnSinceBefore, totalDepositsBefore, ,] = await garden.getContributor(signer3.address);

      const sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        minAmountOut,
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      await garden
        .connect(keeper)
        .depositBySig(
          amountIn,
          minAmountOut,
          nonce,
          maxFee,
          signer3.address,
          eth(),
          fee,
          signer3.address,
          ADDRESS_ZERO,
          sig,
        );

      const supplyAfter = await garden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.eq(minAmountOut);

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(amountIn);

      const [, , , , , withdrawnSinceAfter, totalDepositsAfter, ,] = await garden.getContributor(signer3.address);
      expect(totalDepositsAfter.sub(totalDepositsBefore)).to.equal(amountIn);
    });

    it('smart contract can deposit', async function () {
      const walletFactory = await ethers.getContractFactory('ERC1271WalletMock');
      const wallet = await walletFactory.deploy(signer3.address);

      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);
      const fee = from(0);
      const maxFee = from(0);
      const nonce = 0;

      await fund([signer1.address, wallet.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });
      await garden.connect(signer1).makeGardenPublic();

      await usdc.connect(await impersonateAddress(wallet.address)).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      const gardenBalance = await usdc.balanceOf(garden.address);
      const supplyBefore = await garden.totalSupply();

      const [, , , , , withdrawnSinceBefore, totalDepositsBefore, ,] = await garden.getContributor(wallet.address);

      const sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        minAmountOut,
        nonce,
        maxFee,
        wallet.address,
        ADDRESS_ZERO,
      );

      await garden
        .connect(keeper)
        .depositBySig(
          amountIn,
          minAmountOut,
          nonce,
          maxFee,
          wallet.address,
          eth(),
          fee,
          wallet.address,
          ADDRESS_ZERO,
          sig,
        );

      const supplyAfter = await garden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.eq(minAmountOut);

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(amountIn);

      const [, , , , , withdrawnSinceAfter, totalDepositsAfter, ,] = await garden.getContributor(wallet.address);
      expect(totalDepositsAfter.sub(totalDepositsBefore)).to.equal(amountIn);
    });

    it('can deposit with fee > minContribution', async function () {
      const amountIn = from(2000 * 1e6);
      const minAmountOut = eth(2000);
      const fee = from(1000 * 1e6);
      const maxFee = from(1000 * 1e6);
      const nonce = 0;

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      const gardenBalance = await usdc.balanceOf(garden.address);
      const supplyBefore = await garden.totalSupply();

      const [, , , , , withdrawnSinceBefore, totalDepositsBefore, ,] = await garden.getContributor(signer3.address);

      const sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        minAmountOut,
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      await garden
        .connect(keeper)
        .depositBySig(
          amountIn,
          minAmountOut,
          nonce,
          maxFee,
          signer3.address,
          eth(),
          fee,
          signer3.address,
          ADDRESS_ZERO,
          sig,
        );

      const supplyAfter = await garden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.eq(minAmountOut.sub(eth(1000)));

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(amountIn.sub(fee));

      const [, , , , , withdrawnSinceAfter, totalDepositsAfter, ,] = await garden.getContributor(signer3.address);
      expect(totalDepositsAfter.sub(totalDepositsBefore)).to.equal(amountIn.sub(fee));
    });

    [
      {
        token: addresses.tokens.WETH,
        name: 'WETH',
        opts: {
          amountIn: eth(),
          minAmountOut: eth(),
          fee: eth(0.01),
          maxFee: eth(0.01),
        },
      },
      {
        token: addresses.tokens.USDC,
        name: 'USDC',
        opts: {
          amountIn: from(1000 * 1e6),
          minAmountOut: eth(1000),
          fee: from(100 * 1e6),
          maxFee: from(100 * 1e6),
        },
      },
    ].forEach(({ token, name, opts }) => {
      it(`can deposit with a Keeper fee into ${name} garden`, async function () {
        const { amountIn, minAmountOut, fee, maxFee } = opts;

        const nonce = 0;

        const erc20 = await getERC20(token);

        await fund([signer1.address, signer3.address], { tokens: [token] });

        const garden = await createGarden({ reserveAsset: token });

        await erc20.connect(signer3).approve(garden.address, amountIn, {
          gasPrice: 0,
        });

        const gardenBalance = await erc20.balanceOf(garden.address);
        const supplyBefore = await garden.totalSupply();

        const sig = await getDepositSig(
          garden.address,
          signer3,
          amountIn,
          minAmountOut,
          nonce,
          maxFee,
          signer3.address,
          ADDRESS_ZERO,
        );

        await expect(() =>
          garden
            .connect(keeper)
            .depositBySig(
              amountIn,
              minAmountOut,
              nonce,
              maxFee,
              signer3.address,
              eth(),
              fee,
              signer3.address,
              ADDRESS_ZERO,
              sig,
            ),
        ).to.changeTokenBalances(erc20, [keeper, garden, signer3], [fee, amountIn.sub(fee), amountIn.mul(-1)]);

        const supplyAfter = await garden.totalSupply();
        expect(supplyAfter.sub(supplyBefore)).to.be.eq(
          minAmountOut.sub(fee.mul(eth()).div(from(10).pow(await erc20.decimals()))),
        );
      });
    });

    it('rejects if not keeper', async function () {
      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);
      const fee = from(0);
      const maxFee = from(0);
      const nonce = 0;

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      const sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        minAmountOut,
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );
      await expect(
        garden
          .connect(signer3)
          .depositBySig(
            amountIn,
            minAmountOut,
            nonce,
            maxFee,
            signer3.address,
            eth(),
            fee,
            signer3.address,
            ADDRESS_ZERO,
            sig,
          ),
      ).to.be.revertedWith('BAB#018');
    });

    it('rejects wrong nonce', async function () {
      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);
      const fee = from(0);
      const maxFee = from(0);
      const nonce = 7;

      await fund([signer1.address, signer3.address], [addresses.tokens.USDC]);

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      const sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        minAmountOut,
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );
      await expect(
        garden
          .connect(keeper)
          .depositBySig(
            amountIn,
            minAmountOut,
            nonce,
            maxFee,
            signer3.address,
            eth(),
            fee,
            signer3.address,
            ADDRESS_ZERO,
            sig,
          ),
      ).to.be.revertedWith('BAB#089');
    });
    // TODO: Test minAmountOut is respected
    // TODO: Test mintNFT is respected
  });

  describe('deposit', async function () {
    it('can deposit DAI', async function () {
      const amountIn = eth(1000);
      const minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.DAI] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.DAI });

      await dai.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      const gardenBalance = await dai.balanceOf(garden.address);
      const supplyBefore = await garden.totalSupply();

      const [, , , , , withdrawnSinceBefore, totalDepositsBefore, ,] = await garden.getContributor(signer3.address);

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), ADDRESS_ZERO);

      const supplyAfter = await garden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.eq(minAmountOut);

      const gardenBalanceAfter = await dai.balanceOf(garden.address);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(amountIn);

      const [, , , , , withdrawnSinceAfter, totalDepositsAfter, ,] = await garden.getContributor(signer3.address);
      expect(totalDepositsAfter.sub(totalDepositsBefore)).to.equal(amountIn);
    });

    it('can deposit with referral', async function () {
      const amountIn = eth(1000);
      const minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.DAI] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.DAI, overrideHardlock: 86400 * 21 });

      await babController.connect(owner).updateGardenAffiliateRate(garden.address, eth());

      await dai.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), signer2.address);

      expect(await babController.affiliateRewards(signer2.address)).to.equal(amountIn.div(2));
      expect(await babController.affiliateRewards(signer3.address)).to.equal(amountIn.div(2));
    });

    it('can deposit USDC', async function () {
      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      const gardenBalance = await usdc.balanceOf(garden.address);
      const supplyBefore = await garden.totalSupply();

      const [, , , , , withdrawnSinceBefore, totalDepositsBefore, ,] = await garden.getContributor(signer3.address);
      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), ADDRESS_ZERO);

      const supplyAfter = await garden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.eq(minAmountOut);

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(amountIn);

      const [, , , , , withdrawnSinceAfter, totalDepositsAfter, ,] = await garden.getContributor(signer3.address);
      expect(totalDepositsAfter.sub(totalDepositsBefore)).to.equal(amountIn);
    });

    describe('can be done after making a garden public', async function () {
      it('a user can still deposit after a garden is granted public access', async function () {
        await garden1.connect(signer1).makeGardenPublic();
        await expect(
          garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
            value: eth(),
          }),
        ).not.to.be.reverted;
        const signer3Balance = await garden1.balanceOf(signer3.address);
        expect(signer3Balance).to.be.equal(eth());
      });
    });

    it('can make an initial deposit', async function () {
      expect(await garden1.totalContributors()).to.equal(1);
      const gardenBalance = await weth.balanceOf(garden1.address);
      const supplyBefore = await garden1.totalSupply();
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
      });
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      // Communities
      // Manager deposit in fixture is only 1
      expect(supplyAfter.sub(supplyBefore)).to.be.closeTo(eth(), eth('0.1'));
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(eth());
      expect(await garden1.totalContributors()).to.equal(2);
    });

    it('can deposit WETH directly in a WETH garden', async function () {
      expect(await garden1.totalContributors()).to.equal(1);
      const gardenBalance = await weth.balanceOf(garden1.address);
      const supplyBefore = await garden1.totalSupply();

      // impersonate and give
      const whaleAddress = '0x2f0b23f53734252bda2277357e97e1517d6b042a'; // Has WETH
      const whaleSigner = await impersonateAddress(whaleAddress);
      const tenWETH = eth('10');
      await weth.connect(whaleSigner).transfer(signer3.address, tenWETH, {
        gasPrice: 0,
      });
      await weth.connect(signer3).approve(garden1.address, tenWETH, {
        gasPrice: 0,
      });
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO);
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      // Communities
      // Manager deposit in fixture is only 1
      expect(supplyAfter.sub(supplyBefore)).to.be.closeTo(eth(), eth('0.1'));
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(eth());
      expect(await garden1.totalContributors()).to.equal(2);
    });

    it('can make multiple deposits', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
      });
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
      });
      expect(await garden1.totalContributors()).to.equal(2);
    });

    it('multiple contributors can make deposits', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
      });

      await garden1.connect(signer2).deposit(eth(), 1, signer2.getAddress(), ADDRESS_ZERO, {
        value: eth(),
      });

      // Note: Garden is initialized with manager as first contributor
      expect(await garden1.totalContributors()).to.equal(3);
    });
  });

  describe('claimNFT', async function () {
    it('claims NFT for a contributor', async function () {
      const amountIn = eth(1000);
      const minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.DAI] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.DAI });

      await dai.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), ADDRESS_ZERO);
      await expect(garden.connect(signer3).claimNFT()).to.be.revertedWith('BAB#125');
      await increaseTime(1);
      await garden.connect(signer3).claimNFT();

      expect(await gardenNFT.balanceOf(signer3.address)).to.eq(1);
    });

    it('rejects if not a contributor', async function () {
      const amountIn = eth(1000);
      const minAmountOut = eth(1000);

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.DAI] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.DAI });

      await dai.connect(signer3).approve(garden.address, amountIn, {
        gasPrice: 0,
      });

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), ADDRESS_ZERO);

      await expect(garden.connect(signer2).claimNFT()).to.be.revertedWith('BAB#015');
    });
  });

  describe('addStrategy', async function () {
    it('should not be able to add an strategy unless there is a contributor', async function () {
      await expect(
        garden1
          .connect(signer2)
          .addStrategy(
            'name',
            'STRT',
            strategyParamsToArray(WETH_STRATEGY_PARAMS),
            [0],
            [uniswapV3TradeIntegration.address],
            [addresses.tokens.DAI],
            {
              gasLimit: 9500000,
              gasPrice: 0,
            },
          ),
      ).to.be.reverted;
    });

    it('a contributor should be able to add an strategy', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
      });
      const AbiCoder = ethers.utils.AbiCoder;
      const abiCoder = new AbiCoder();
      const encodedData = abiCoder.encode(['address', 'uint256'], [addresses.tokens.DAI, 0]);

      await expect(
        garden1
          .connect(signer3)
          .addStrategy(
            'name',
            'STRT',
            strategyParamsToArray(WETH_STRATEGY_PARAMS),
            [0],
            [uniswapV3TradeIntegration.address],
            encodedData,
          ),
      ).to.not.be.reverted;
    });

    it('a contributor should not be able to add an strategy with a small stake', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), ADDRESS_ZERO, {
        value: eth(),
      });
      const params = strategyParamsToArray(WETH_STRATEGY_PARAMS);
      params[1] = eth(0);
      let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
      let iface = new ethers.utils.Interface(ABI);
      let encodedData = iface.encodeFunctionData('babylonFinanceStrategyOpData', [addresses.tokens.DAI, 0]);

      await expect(
        garden1
          .connect(signer3)
          .addStrategy('name', 'STRT', params, [0], [uniswapV3TradeIntegration.address], encodedData),
      ).to.be.reverted;
    });
  });

  describe('checkLastPricePerShare', async function () {
    it('can deposit and withdraw if pricePerShare within slippage', async function () {
      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);
      const fee = from(0);
      const maxFee = from(0);
      let nonce = 0;

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn.mul(4), {
        gasPrice: 0,
      });

      let sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        minAmountOut,
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      await garden
        .connect(keeper)
        .depositBySig(
          amountIn,
          minAmountOut,
          nonce,
          maxFee,
          signer3.address,
          eth(),
          fee,
          signer3.address,
          ADDRESS_ZERO,
          sig,
        );

      nonce += 1;
      sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        minAmountOut,
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      // deposit is accepted with the same price per share
      await garden
        .connect(keeper)
        .depositBySig(
          amountIn,
          minAmountOut,
          nonce,
          maxFee,
          signer3.address,
          eth(),
          fee,
          signer3.address,
          ADDRESS_ZERO,
          sig,
        );

      nonce += 1;
      sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        minAmountOut.div(2),
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      // deposit is accepted with the price per share max up
      await garden
        .connect(keeper)
        .depositBySig(
          amountIn,
          minAmountOut.div(2),
          nonce,
          maxFee,
          signer3.address,
          eth(2),
          fee,
          signer3.address,
          ADDRESS_ZERO,
          sig,
        );

      nonce += 1;
      sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        minAmountOut,
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      // deposit is accepted with the price per share max down
      await garden
        .connect(keeper)
        .depositBySig(
          amountIn,
          minAmountOut,
          nonce,
          maxFee,
          signer3.address,
          eth(),
          fee,
          signer3.address,
          ADDRESS_ZERO,
          sig,
        );
    });

    it('decay grows slippage up in one year', async function () {
      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);
      const fee = from(0);
      const maxFee = from(0);
      let nonce = 0;

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn.mul(2), {
        gasPrice: 0,
      });

      await increaseTime(ONE_YEAR_IN_SECONDS);

      const sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        from(0),
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      await garden
        .connect(keeper)
        .depositBySig(
          amountIn,
          from(0),
          nonce,
          maxFee,
          signer3.address,
          eth(3),
          fee,
          signer3.address,
          ADDRESS_ZERO,
          sig,
        );
    });

    it('decay grows slippage down in one year', async function () {
      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);
      const fee = from(0);
      const maxFee = from(0);
      let nonce = 0;

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await usdc.connect(signer3).approve(garden.address, amountIn.mul(2), {
        gasPrice: 0,
      });

      await increaseTime(ONE_YEAR_IN_SECONDS);

      const sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        from(0),
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      await garden
        .connect(keeper)
        .depositBySig(
          amountIn,
          from(0),
          nonce,
          maxFee,
          signer3.address,
          eth().div(3),
          fee,
          signer3.address,
          ADDRESS_ZERO,
          sig,
        );
    });

    it('revert if change is higher than allowed by slippage', async function () {
      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);
      const fee = from(0);
      const maxFee = from(0);
      let nonce = 0;

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await garden
        .connect(signer1)
        .updateGardenParams([
          await garden.maxDepositLimit(),
          await garden.minLiquidityAsset(),
          await garden.depositHardlock(),
          await garden.minContribution(),
          await garden.strategyCooldownPeriod(),
          await garden.minVotesQuorum(),
          await garden.minStrategyDuration(),
          await garden.maxStrategyDuration(),
          await garden.minVoters(),
          1,
          eth(),
          0,
          0,
        ]);

      await usdc.connect(signer3).approve(garden.address, amountIn.mul(2), {
        gasPrice: 0,
      });

      let sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        minAmountOut,
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      await garden
        .connect(keeper)
        .depositBySig(
          amountIn,
          minAmountOut,
          nonce,
          maxFee,
          signer3.address,
          eth(),
          fee,
          signer3.address,
          ADDRESS_ZERO,
          sig,
        );

      nonce += 1;
      sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        from(0),
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      await expect(
        garden
          .connect(keeper)
          .depositBySig(
            amountIn,
            from(0),
            nonce,
            maxFee,
            signer3.address,
            eth(2).add(1),
            fee,
            signer3.address,
            ADDRESS_ZERO,
            sig,
          ),
      ).to.be.revertedWith('BAB#118');
    });

    it('revert if change is lower than allowed by slippage', async function () {
      const amountIn = from(1000 * 1e6);
      const minAmountOut = eth(1000);
      const fee = from(0);
      const maxFee = from(0);
      let nonce = 0;

      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await garden
        .connect(signer1)
        .updateGardenParams([
          await garden.maxDepositLimit(),
          await garden.minLiquidityAsset(),
          await garden.depositHardlock(),
          await garden.minContribution(),
          await garden.strategyCooldownPeriod(),
          await garden.minVotesQuorum(),
          await garden.minStrategyDuration(),
          await garden.maxStrategyDuration(),
          await garden.minVoters(),
          1,
          eth(),
          0,
          0,
        ]);

      await usdc.connect(signer3).approve(garden.address, amountIn.mul(2), {
        gasPrice: 0,
      });

      let sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        minAmountOut,
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      await garden
        .connect(keeper)
        .depositBySig(
          amountIn,
          minAmountOut,
          nonce,
          maxFee,
          signer3.address,
          eth(),
          fee,
          signer3.address,
          ADDRESS_ZERO,
          sig,
        );

      nonce += 1;
      sig = await getDepositSig(
        garden.address,
        signer3,
        amountIn,
        from(0),
        nonce,
        maxFee,
        signer3.address,
        ADDRESS_ZERO,
      );

      await expect(
        garden
          .connect(keeper)
          .depositBySig(
            amountIn,
            from(0),
            nonce,
            maxFee,
            signer3.address,
            eth(0.5).sub(1),
            fee,
            signer3.address,
            ADDRESS_ZERO,
            sig,
          ),
      ).to.be.revertedWith('BAB#118');
    });
  });

  describe('updateGardenParams', async function () {
    it('can update', async function () {
      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });

      await garden
        .connect(signer1)
        .updateGardenParams([
          eth(1),
          eth(2),
          from(3),
          eth(4),
          ONE_DAY_IN_SECONDS * 5,
          eth(0.06),
          ONE_DAY_IN_SECONDS * 7,
          ONE_DAY_IN_SECONDS * 8,
          from(9),
          from(10),
          from(11),
          from(0),
          from(0),
        ]);

      expect(await garden.maxDepositLimit()).to.eq(eth());
      expect(await garden.minLiquidityAsset()).to.eq(eth(2));
      expect(await garden.depositHardlock()).to.eq(3);
      expect(await garden.minContribution()).to.eq(eth(4));
      expect(await garden.strategyCooldownPeriod()).to.eq(ONE_DAY_IN_SECONDS * 5);
      expect(await garden.minVotesQuorum()).to.eq(eth(0.06));
      expect(await garden.minStrategyDuration()).to.eq(ONE_DAY_IN_SECONDS * 7);
      expect(await garden.maxStrategyDuration()).to.eq(ONE_DAY_IN_SECONDS * 8);
      expect(await garden.minVoters()).to.eq(9);
      expect(await garden.pricePerShareDecayRate()).to.eq(10);
      expect(await garden.pricePerShareDelta()).to.eq(11);
    });

    it('can update custom integrations only if not verified', async function () {
      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });
      expect(await garden.customIntegrationsEnabled()).to.eq(false);
      expect(await garden.verifiedCategory()).to.eq(0);

      // Testing a garden that is not verified and without custom integrations
      await garden
        .connect(signer1)
        .updateGardenParams([
          eth(1),
          eth(2),
          from(3),
          eth(4),
          ONE_DAY_IN_SECONDS * 5,
          eth(0.06),
          ONE_DAY_IN_SECONDS * 7,
          ONE_DAY_IN_SECONDS * 8,
          from(9),
          from(10),
          from(11),
          from(0),
          from(1),
        ]);
      expect(await garden.customIntegrationsEnabled()).to.eq(true);
      await garden.connect(owner).verifyGarden(1);

      // A garden that is verified should be able to set it to false
      await garden
        .connect(signer1)
        .updateGardenParams([
          eth(1),
          eth(2),
          from(3),
          eth(4),
          ONE_DAY_IN_SECONDS * 5,
          eth(0.06),
          ONE_DAY_IN_SECONDS * 7,
          ONE_DAY_IN_SECONDS * 8,
          from(9),
          from(10),
          from(11),
          from(0),
          from(0),
        ]);

      expect(await garden.customIntegrationsEnabled()).to.eq(false);

      // A garden that is verified should not be able to set it back to true
      await garden
        .connect(signer1)
        .updateGardenParams([
          eth(1),
          eth(2),
          from(3),
          eth(4),
          ONE_DAY_IN_SECONDS * 5,
          eth(0.06),
          ONE_DAY_IN_SECONDS * 7,
          ONE_DAY_IN_SECONDS * 8,
          from(9),
          from(10),
          from(11),
          from(0),
          from(1),
        ]);
      expect(await garden.customIntegrationsEnabled()).to.eq(false);
    });
  });

  describe('verify garden', async function () {
    it('governance can update verification category', async function () {
      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });
      expect(await garden.verifiedCategory()).to.eq(0);
      await garden.connect(owner).verifyGarden(1);
      expect(await garden.verifiedCategory()).to.eq(1);
    });

    it('creator cannot update verification category', async function () {
      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.USDC] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.USDC });
      await expect(garden.connect(signer1).verifyGarden(1)).to.be.reverted;
    });
  });
  describe('update strategy rewards', async function () {
    it('governance can update strategy rewards', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      // It is executed
      await executeStrategy(strategyContract, eth(), 42);
      await finalizeStrategy(strategyContract, 42);
      const rewards = await strategyContract.strategyRewards();
      const capitalReturned = await strategyContract.capitalReturned();
      const rewardsSetAside = await garden1.reserveAssetRewardsSetAside();
      const bablBalanceBefore = await bablToken.balanceOf(heartGarden.address);
      await garden1.connect(gov).updateStrategyRewards(strategyContract.address, eth(), eth(), eth(), true);
      expect(await strategyContract.strategyRewards())
        .to.eq(eth())
        .to.not.eq(rewards);
      expect(await strategyContract.capitalReturned())
        .to.eq(eth())
        .to.not.eq(capitalReturned);
      expect(await garden1.reserveAssetRewardsSetAside())
        .to.eq(eth())
        .to.not.eq(rewardsSetAside);
      expect(await bablToken.balanceOf(heartGarden.address)).to.eq(bablBalanceBefore);
    });
    it('governance can update strategy rewards in the heart garden', async function () {
      const strategistShare = eth(0.1);
      const stewardsShare = eth(0.1);
      const lpShare = eth(0.8);
      const creatorBonus = eth(0.1);
      const profitWeight = eth(0.65);
      const principalWeight = eth(0.35);
      const benchmark = [eth(0.8), eth(1.03), eth(1), eth(1), eth(1)];
      const maxBablCap = eth(100000);
      await rewardsDistributor
        .connect(owner)
        .setBABLMiningParameters([
          strategistShare,
          stewardsShare,
          lpShare,
          creatorBonus,
          profitWeight,
          principalWeight,
          benchmark[0],
          benchmark[1],
          benchmark[2],
          benchmark[3],
          benchmark[4],
          maxBablCap,
        ]);
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        heartGarden,
      );
      // It is executed
      await executeStrategy(strategyContract, eth(), 42);
      await finalizeStrategy(strategyContract, 42);
      const rewards = await strategyContract.strategyRewards();
      const capitalReturned = await strategyContract.capitalReturned();
      const rewardsSetAside = await heartGarden.reserveAssetRewardsSetAside();
      const bablBalanceBefore = await bablToken.balanceOf(heartGarden.address);
      await heartGarden
        .connect(gov)
        .updateStrategyRewards(strategyContract.address, rewards.mul(2), capitalReturned, rewardsSetAside, true);
      const bablBalanceAfter = await bablToken.balanceOf(heartGarden.address);
      expect(await strategyContract.strategyRewards()).to.eq(rewards.mul(2));
      expect(await strategyContract.capitalReturned()).to.eq(capitalReturned);
      expect(await heartGarden.reserveAssetRewardsSetAside()).to.eq(rewardsSetAside);
      expect(bablBalanceAfter).to.eq(bablBalanceBefore.mul(2));
      await heartGarden
        .connect(gov)
        .updateStrategyRewards(strategyContract.address, rewards, capitalReturned, rewardsSetAside, true);
      expect(await bablToken.balanceOf(heartGarden.address)).to.eq(bablBalanceBefore);
    });
    it('anyone can NOT update strategy rewards', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      await executeStrategy(strategyContract, eth(), 42);
      await finalizeStrategy(strategyContract, 42);
      const rewards = await strategyContract.strategyRewards();
      const capitalReturned = await strategyContract.capitalReturned();
      const rewardsSetAside = await garden1.reserveAssetRewardsSetAside();
      await expect(
        garden1.connect(signer1).updateStrategyRewards(strategyContract.address, eth(), eth(), eth(), true),
      ).to.be.revertedWith('Only governance or emergency can call this');
    });
  });

  describe('avg share price per user', async function () {
    pick(GARDENS).forEach(({ token, name }) => {
      it(`should get the avg share price of a user in ${name} garden`, async function () {
        await transferFunds(token);
        const garden = await createGarden({ reserveAsset: token });
        await depositFunds(token, garden);

        const user1Balance = await garden.balanceOf(signer1.address);
        const user2Balance = await garden.balanceOf(signer3.address);
        const user1Deposits = await garden.getContributor(signer1.address);
        const user2Deposits = await garden.getContributor(signer3.address);
        const user1Avg = user1Balance > 0 ? user1Deposits[6].mul(eth()).div(user1Balance) : 0;
        const user2Avg = user2Balance > 0 ? user2Deposits[6].mul(eth()).div(user2Balance) : 0;

        expect(await viewer.connect(signer1).getGardenUserAvgPricePerShare(garden.address, signer1.address)).to.equal(
          user1Avg,
        );
        expect(await viewer.connect(signer1).getGardenUserAvgPricePerShare(garden.address, signer3.address)).to.equal(
          user2Avg,
        );
      });
    });
  });

  describe('updates user lock', async function () {
    it(`can update the lock in the heart garden`, async function () {
      const garden = await createGarden({ reserveAsset: addresses.tokens.DAI });
      await depositFunds(addresses.tokens.DAI, garden);
      // Reverts if calling it on a normal garden
      await expect(garden.updateUserLock(signer1.address, 86400 * 365, 0)).to.be.reverted;
      const heartSigner = await impersonateAddress(await babController.heart());

      expect(await heartGarden.userLock(signer1.address)).to.equal(0);
      const balance = await heartGarden.balanceOf(signer1.address);
      await heartGarden.connect(heartSigner).updateUserLock(signer1.address, 86400 * 365, 0, { gasPrice: 0 });
      expect(await heartGarden.userLock(signer1.address)).to.equal(86400 * 365);
      expect(await heartGarden.getVotingPower(signer1.address)).to.equal(balance.div(4));
      // Can't change it to a lower amount
      await expect(heartGarden.connect(heartSigner).updateUserLock(signer1.address, 1, balance, { gasPrice: 0 })).to.be
        .reverted;
      // Can change it after it expired
      ethers.provider.send('evm_increaseTime', [86400 * 365]);
      await expect(
        heartGarden.connect(heartSigner).updateUserLock(signer1.address, 86400 * 365 * 4, balance, { gasPrice: 0 }),
      ).not.to.be.reverted;
      expect(await heartGarden.userLock(signer1.address)).to.equal(86400 * 365 * 2.5);
      expect(await heartGarden.getVotingPower(signer1.address)).to.be.closeTo(
        balance.div(40).mul(25),
        balance.div(100),
      );
    });
    [
      { name: '< min of 6 months', amount: ONE_DAY_IN_SECONDS * 183 - 1 },
      { name: '> max of 4 years', amount: ONE_DAY_IN_SECONDS * 365 * 4 + 1 },
    ].forEach(({ name, amount }) => {
      it(`can NOT update the lock if out of bounds using a lock ${name}`, async function () {
        const heartSigner = await impersonateAddress(await babController.heart());

        await expect(
          heartGarden.connect(heartSigner).updateUserLock(signer1.address, amount, 0, { gasPrice: 0 }),
        ).to.be.revertedWith('BAB#134');
      });
    });
    it(`can leave after lock period ends and re-join a garden`, async function () {
      const lockTime = ONE_DAY_IN_SECONDS * 183;
      const signer1lock1 = await heartGarden.userLock(signer1.address);
      const heartSigner = await impersonateAddress(await babController.heart());
      const balance = await heartGarden.balanceOf(signer1.address);
      await heartGarden.connect(heartSigner).updateUserLock(signer1.address, lockTime, balance, { gasPrice: 0 });
      await increaseTime(lockTime);
      // Leave the garden completely
      await expect(
        heartGarden
          .connect(signer1)
          .withdraw(await heartGarden.balanceOf(signer1.address), eth(1), signer1.getAddress(), false, ADDRESS_ZERO, {
            gasPrice: 0,
          }),
      ).not.reverted;
      expect(signer1lock1)
        .to.eq(await heartGarden.userLock(signer1.address))
        .to.eq(0);
      // Re join the garden after leaving completely
      await babl.connect(signer1).approve(heartGarden.address, eth(30), {
        gasPrice: 0,
      });
      // Normal deposit after without going through the heart does not lock
      await heartGarden.connect(signer1).deposit(eth(30), 1, signer1.getAddress(), ADDRESS_ZERO, {
        gasPrice: 0,
      });
      await expect(await heartGarden.userLock(signer1.address)).to.eq(0);
    });
    it(`can NOT withdraw before lock period ends`, async function () {
      const balance = await heartGarden.balanceOf(signer1.address);
      const heartSigner = await impersonateAddress(await babController.heart());
      await heartGarden
        .connect(heartSigner)
        .updateUserLock(signer1.address, ONE_DAY_IN_SECONDS * 183, balance, { gasPrice: 0 });
      const signer1lock2 = await heartGarden.userLock(signer1.address);
      await increaseTime(ONE_DAY_IN_SECONDS * 30);
      await expect(
        heartGarden
          .connect(signer1)
          .withdraw(await heartGarden.balanceOf(signer1.address), eth(1), signer1.getAddress(), false, ADDRESS_ZERO, {
            gasPrice: 0,
          }),
      ).to.be.revertedWith('BAB#003');
      expect(await heartGarden.userLock(signer1.address)).to.eq(signer1lock2);
    });
  });

  describe('EmergencyModule', async function () {
    it('can wrap ETH', async function () {
      await fund([signer1.address, signer3.address], { tokens: [addresses.tokens.DAI] });

      const garden = await createGarden({ reserveAsset: addresses.tokens.DAI });

      await fund([garden.address], { tokens: [addresses.tokens.ETH], amounts: [eth(10)] });

      const balance = await weth.balanceOf(garden.address);
      await garden.connect(gov).wrap();
      expect((await weth.balanceOf(garden.address)).sub(balance)).to.eq(eth(10));
    });
  });
});
