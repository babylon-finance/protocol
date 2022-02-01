const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const {
  GARDENS,
  NOW,
  PROFIT_STRATEGIST_SHARE,
  PROFIT_STEWARD_SHARE,
  PROFIT_LP_SHARE,
  ONE_DAY_IN_SECONDS,
  PROTOCOL_FEE,
  PROFIT_PROTOCOL_FEE,
  GARDEN_PARAMS_STABLE,
  GARDEN_PARAMS,
  ADDRESS_ZERO,
  ONE_YEAR_IN_SECONDS,
} = require('lib/constants.js');
const {
  pick,
  increaseTime,
  normalizeDecimals,
  getERC20,
  getContract,
  parse,
  from,
  eth,
} = require('utils/test-helpers');
const { impersonateAddress } = require('lib/rpc');

const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  getStrategy,
  getStrategyState,
  executeStrategy,
  vote,
  finalizeStrategy,
  injectFakeProfits,
  substractFakeProfits,
} = require('fixtures/StrategyHelper');

const {
  createGarden,
  getDepositSigHash,
  getDepositSig,
  getWithdrawSig,
  getWithdrawSigHash,
  transferFunds,
  depositFunds,
} = require('fixtures/GardenHelper');

const { setupTests } = require('fixtures/GardenFixture');

describe('Garden', function () {
  let babController;
  let rewardsDistributor;
  let owner;
  let keeper;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let mardukGate;
  let balancerIntegration;
  let uniswapV3TradeIntegration;
  let daiGarden;
  let usdcGarden;
  let gardenNFT;
  let gardenValuer;
  let babViewer;
  let bablToken;

  let usdc;
  let weth;
  let dai;
  let wbtc;

  async function deleteCandidateStrategies(community) {
    const garden = await ethers.getContractAt('Garden', community);
    // As the disabled garden has still 2 candidate strategies, we need to expire them before removing the garden
    const strategies = await garden.getStrategies();
    for (let i = 0; i < strategies.length; i++) {
      const strategy = await ethers.getContractAt('Strategy', strategies[i]);
      await strategy.connect(owner).deleteCandidateStrategy();
    }
  }

  beforeEach(async () => {
    ({
      babController,
      rewardsDistributor,
      gardenNFT,
      keeper,
      owner,
      signer1,
      signer2,
      signer3,
      garden1,
      mardukGate,
      balancerIntegration,
      uniswapV3TradeIntegration,
      gardenValuer,
      babViewer,

      dai,
      usdc,
      weth,
      wbtc,
    } = await setupTests()());
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
  describe('delegate votes into heart', async function () {
    it('heart garden can delegate into heart', async function () {
      const heartGarden = await ethers.getContractAt('Garden', garden1.address);
      const heart = signer1;
      const token = await ethers.getContractAt('BABLToken', '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74', owner);
      const heartDelegatee1 = await token.delegates(heartGarden.address);
      expect(heartDelegatee1).to.eq(ADDRESS_ZERO); // No delegation yet
      const emergencyOwner = await impersonateAddress('0x0B892EbC6a4bF484CDDb7253c6BD5261490163b9');
      await heartGarden.connect(emergencyOwner).delegateVoteIntoHeart(heart.address);
      const heartDelegatee2 = await token.delegates(heartGarden.address);
      expect(heartDelegatee2).to.eq(signer1.address);
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

  describe('pseudo-public rights by gardener', async function () {
    it('should allow deposits to a Ishar gate owner despite its individual permission is set to 0 but general deposit permission is allowed', async function () {
      expect(await mardukGate.connect(signer1).canJoinAGarden(garden1.address, signer3.address)).to.equal(true);
      // Remove permissions
      await mardukGate.connect(signer1).setGardenAccess(signer3.address, garden1.address, 0, { gasPrice: 0 });
      expect(await mardukGate.connect(signer1).canJoinAGarden(garden1.address, signer3.address)).to.equal(false);
      await expect(
        garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
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

      garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
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
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
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
      const [, , canAddStrategy3] = await babViewer
        .connect(signer1)
        .getGardenPermissions(garden1.address, signer3.address);
      expect(canAddStrategy3).to.equal(true);
    });

    it('should allow the vote by an Ishar gate owner despite its individual permission is set to 0 but general voting permission is allowed', async function () {
      await garden1.connect(signer2).deposit(eth(), 1, signer2.getAddress(), false, {
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
    it('only the protocol should be able to custom garden profit sharing (95% to LP) while creation', async function () {
      await babController
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
          [eth('0'), eth('0'), eth('0.95')],
          {
            value: eth(),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[4]);
      const profitSharing = await rewardsDistributor.getGardenProfitsSharing(newGarden.address);
      expect(profitSharing[0]).to.equal(eth('0'));
      expect(profitSharing[1]).to.equal(eth('0'));
      expect(profitSharing[2]).to.equal(eth('0.95'));
    });
    it('only the protocol should be able to custom garden profit sharing (95% to Stewards) while creation', async function () {
      await babController
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
          [eth('0'), eth('0.95'), eth('0')],
          {
            value: eth(),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[4]);
      const profitSharing = await rewardsDistributor.getGardenProfitsSharing(newGarden.address);
      expect(profitSharing[0]).to.equal(eth('0'));
      expect(profitSharing[1]).to.equal(eth('0.95'));
      expect(profitSharing[2]).to.equal(eth('0'));
    });
    it('only the protocol should be able to custom garden profit sharing (95% to Strategist) while creation', async function () {
      await babController
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
          [eth('0.95'), eth('0'), eth('0')],
          {
            value: eth(),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[4]);
      const profitSharing = await rewardsDistributor.getGardenProfitsSharing(newGarden.address);
      expect(profitSharing[0]).to.equal(eth('0.95'));
      expect(profitSharing[1]).to.equal(eth('0'));
      expect(profitSharing[2]).to.equal(eth('0'));
    });
    it('only the protocol should be able to custom garden profit sharing (15% , 40%, 40%) while creation', async function () {
      await babController
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
          [eth('0.15'), eth('0.40'), eth('0.40')],
          {
            value: eth(),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[4]);
      const profitSharing = await rewardsDistributor.getGardenProfitsSharing(newGarden.address);
      expect(profitSharing[0]).to.equal(eth('0.15'));
      expect(profitSharing[1]).to.equal(eth('0.40'));
      expect(profitSharing[2]).to.equal(eth('0.40'));
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

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), false);

      const gardenBalanceBefore = await usdc.balanceOf(garden.address);
      const supplyBefore = await garden.totalSupply();

      const [, , , , , principalBefore, ,] = await garden.getContributor(signer3.address);

      amountIn = eth(1000);
      minAmountOut = from(1000 * 1e6);

      const sig = await getWithdrawSig(garden.address, signer3, amountIn, minAmountOut, 1, 0, false);
      await garden
        .connect(keeper)
        .withdrawBySig(amountIn, minAmountOut, 1, 0, false, ADDRESS_ZERO, eth(), 0, 0, sig.v, sig.r, sig.s);

      const supplyAfter = await garden.totalSupply();
      expect(supplyBefore.sub(supplyAfter)).to.be.eq(amountIn);

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceBefore.sub(gardenBalanceAfter)).to.equal(minAmountOut);

      const [, , , , , principalAfter, ,] = await garden.getContributor(signer3.address);
      expect(principalBefore.sub(principalAfter)).to.equal(minAmountOut);
      expect(principalAfter).to.equal(0);
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

        await garden.connect(signer3).deposit(depositIn, depositOut, signer3.getAddress(), false);

        const supplyBefore = await garden.totalSupply();
        const balanceBefore = await ethers.provider.getBalance(signer3.address);
        const [, , , , , principalBefore, ,] = await garden.getContributor(signer3.address);

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
                sig.v,
                sig.r,
                sig.s,
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
                sig.v,
                sig.r,
                sig.s,
              ),
          ).to.changeTokenBalances(
            erc20,
            [keeper, garden, signer3],
            [fee, minAmountOut.mul(-1), minAmountOut.sub(fee)],
          );
        }

        const supplyAfter = await garden.totalSupply();
        expect(supplyBefore.sub(supplyAfter)).to.eq(amountIn);

        const [, , , , , principalAfter, ,] = await garden.getContributor(signer3.address);
        expect(principalBefore.sub(principalAfter)).to.equal(minAmountOut);
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

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), false);

      amountIn = eth(1000);
      minAmountOut = from(1000 * 1e6);
      const sig = await getWithdrawSig(garden.address, signer3, amountIn, minAmountOut, 1, 0, false);
      await expect(
        garden
          .connect(signer3)
          .withdrawBySig(amountIn, minAmountOut, 1, 0, false, ADDRESS_ZERO, eth(), 0, 0, sig.v, sig.r, sig.s),
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

      const gardenBalance = await usdc.balanceOf(garden.address);
      const supplyBefore = await garden.totalSupply();

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), false);

      amountIn = eth(1000);
      minAmountOut = from(1000 * 1e6);
      const sig = await getWithdrawSig(garden.address, signer3, amountIn, minAmountOut, 8, 0, false);

      await expect(
        garden
          .connect(keeper)
          .withdrawBySig(amountIn, minAmountOut, 8, 0, false, ADDRESS_ZERO, eth(), 0, 0, sig.v, sig.r, sig.s),
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

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), false);

      const supplyBefore = await garden.totalSupply();

      const balanceBefore = await garden.balanceOf(signer3.address);

      const strategy = await getStrategy();
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
          sig.v,
          sig.r,
          sig.s,
        );

      // put the funds back
      await usdc.connect(await impersonateAddress(signer3.address)).transfer(garden.address, gardenBalanceBefore, {
        gasPrice: 0,
      });

      const supplyAfter = await garden.totalSupply();
      expect(supplyBefore.sub(supplyAfter)).to.be.eq(amountIn);

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      console.log(gardenBalanceAfter.toString(), gardenBalanceBefore.toString());
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

      await garden.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), false);

      const supplyBefore = await garden.totalSupply();

      const balanceBefore = await garden.balanceOf(signer3.address);

      const strategy = await getStrategy();
      await vote(strategy, [signer1, signer2, signer3]);

      await executeStrategy(strategy, { amount: amountIn.sub(amountIn.mul(PROTOCOL_FEE).div(eth())) });

      // lose 500 DAI
      await substractFakeProfits(strategy, eth(500));

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
          sig.v,
          sig.r,
          sig.s,
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

      await garden1.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), false, {
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

      await garden1.connect(signer3).deposit(amountIn, minAmountOut, signer3.getAddress(), false, {
        value: eth(),
        gasPrice: 0,
      });

      const beforeWithdrawal = await ethers.provider.getBalance(signer3.address);

      await garden1.connect(signer3).withdraw(eth(999999999), minAmountOut, signer3.getAddress(), false, ADDRESS_ZERO, {
        gasPrice: 0,
      });

      expect((await ethers.provider.getBalance(signer3.address)).sub(beforeWithdrawal)).to.be.eq(minAmountOut);
    });

    it('can withdraw with a penalty from a straetgy with losses', async function () {
      const garden = await createGarden();

      const strategy = await getStrategy();
      await vote(strategy, [signer1, signer2, signer3]);

      await executeStrategy(strategy, { amount: eth().sub(eth().mul(PROTOCOL_FEE).div(eth())) });

      // lose 1000 DAI
      await substractFakeProfits(strategy, eth(1000));

      const pricePerShare = await gardenValuer.calculateGardenValuation(garden.address, addresses.tokens.WETH);

      const beforeWithdrawal = await ethers.provider.getBalance(signer1.address);

      const minAmountOut = eth(0.5).mul(975).div(1000).mul(pricePerShare).div(eth());

      await garden
        .connect(signer1)
        .withdraw(eth(0.5), minAmountOut, signer1.getAddress(), true, strategy.address, { gasPrice: 0 });

      // receive less due to penalty and strategy loss
      expect((await ethers.provider.getBalance(signer1.address)).sub(beforeWithdrawal)).to.gte(minAmountOut);
    });

    it('can withdraw funds with a penalty', async function () {
      const garden = await createGarden();

      const strategy = await getStrategy();
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
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
        value: eth(),
      });
      expect(await garden1.totalContributors()).to.equal(2);
      await expect(garden1.connect(signer3).withdraw(eth('20'), 1, signer3.getAddress()), false, ADDRESS_ZERO).to.be
        .reverted;
    });

    it('cannot withdraw more garden tokens than they have deposited', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
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
      const { active, finalized, executedAt, exitedAt, updatedAt } = await getStrategyState(strategyContract);
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
      const { active, finalized, executedAt, exitedAt, updatedAt } = await getStrategyState(strategyContract);
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

      await garden1.connect(signer2).deposit(eth('5'), 1, signer2.getAddress(), false, {
        value: eth('5'),
        gasPrice: 0,
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 5]); // to bypass hardlock
      const beforeBalance = await garden1.balanceOf(signer2.address);

      const lockedBalance = await garden1.getLockedBalance(signer2.address);

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

      await garden1.connect(signer2).deposit(eth('5'), 1, signer2.getAddress(), false, {
        value: eth('5'),
        gasPrice: 0,
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 5]); // to bypass hardlock
      const beforeBalance = await garden1.balanceOf(signer2.address);

      const lockedBalance = await garden1.getLockedBalance(signer2.address);

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
      const [, , , , , principalBefore, ,] = await garden.getContributor(signer3.address);

      const sig = await getDepositSig(garden.address, signer3, amountIn, minAmountOut, false, nonce, maxFee);

      await garden
        .connect(keeper)
        .depositBySig(amountIn, minAmountOut, false, nonce, maxFee, eth(), fee, sig.v, sig.r, sig.s);

      const [, , , , , principalAfter, ,] = await garden.getContributor(signer3.address);

      const supplyAfter = await garden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.eq(minAmountOut);

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(amountIn);

      expect(principalAfter.sub(principalBefore)).to.equal(amountIn);
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
      const [, , , , , principalBefore, ,] = await garden.getContributor(signer3.address);

      const sig = await getDepositSig(garden.address, signer3, amountIn, minAmountOut, false, nonce, maxFee);

      await garden
        .connect(keeper)
        .depositBySig(amountIn, minAmountOut, false, nonce, maxFee, eth(), fee, sig.v, sig.r, sig.s);

      const [, , , , , principalAfter, ,] = await garden.getContributor(signer3.address);

      const supplyAfter = await garden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.eq(minAmountOut.sub(eth(1000)));

      const gardenBalanceAfter = await usdc.balanceOf(garden.address);
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(amountIn.sub(fee));

      expect(principalAfter.sub(principalBefore)).to.equal(amountIn.sub(fee));
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

        const sig = await getDepositSig(garden.address, signer3, amountIn, minAmountOut, false, nonce, maxFee);

        await expect(() =>
          garden
            .connect(keeper)
            .depositBySig(amountIn, minAmountOut, false, nonce, maxFee, eth(), fee, sig.v, sig.r, sig.s),
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

      const sig = await getDepositSig(garden.address, signer3, amountIn, minAmountOut, false, nonce, maxFee);
      await expect(
        garden
          .connect(signer3)
          .depositBySig(amountIn, minAmountOut, false, nonce, maxFee, eth(), fee, sig.v, sig.r, sig.s),
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

      const sig = await getDepositSig(garden.address, signer3, amountIn, minAmountOut, false, nonce, maxFee);
      await expect(
        garden
          .connect(keeper)
          .depositBySig(amountIn, minAmountOut, false, nonce, maxFee, eth(), fee, sig.v, sig.r, sig.s),
      ).to.be.revertedWith('BAB#089');
    });
    // TODO: Test minAmountOut is respected
    // TODO: Test mintNFT is respected
  });

  describe('deposit', async function () {
    it('a contributor can make an initial deposit and withdraw with DAI', async function () {
      const whaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'; // Has DAI
      const whaleSigner = await impersonateAddress(whaleAddress);
      await dai.connect(whaleSigner).transfer(signer1.address, eth('1000'), {
        gasPrice: 0,
      });
      await dai.connect(whaleSigner).transfer(signer3.address, eth('1000'), {
        gasPrice: 0,
      });
      await dai.connect(signer1).approve(babController.address, eth('1000'), {
        gasPrice: 0,
      });

      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.DAI,
          'Absolute DAI Return [beta]',
          'EYFA',
          'http...',
          0,
          GARDEN_PARAMS_STABLE,
          eth('100'),
          [false, false, false],
          [0, 0, 0],
          {},
        );
      const gardens = await babController.getGardens();
      daiGarden = await ethers.getContractAt('Garden', gardens[4]);
      expect(await daiGarden.totalContributors()).to.equal(1);

      const gardenBalance = await dai.balanceOf(daiGarden.address);
      const supplyBefore = await daiGarden.totalSupply();

      await mardukGate.connect(signer1).setGardenAccess(signer3.address, daiGarden.address, 1, { gasPrice: 0 });
      await dai.connect(signer3).approve(daiGarden.address, eth('1000'), { gasPrice: 0 });

      await daiGarden.connect(signer3).deposit(eth(1000), eth(1000), signer3.getAddress(), false);
      const gardenBalanceAfter = await dai.balanceOf(daiGarden.address);

      // await daiGarden.connect(keeper).processDeposit(signer3.address, eth());

      const supplyAfter = await daiGarden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.closeTo(eth('1000'), eth('0.1'));

      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(eth('1000'));
      expect(await daiGarden.totalContributors()).to.equal(2);

      ethers.provider.send('evm_increaseTime', [1]);

      await daiGarden
        .connect(signer3)
        .withdraw(await daiGarden.balanceOf(signer3.address), 1, signer3.getAddress(), false, ADDRESS_ZERO);

      expect(await daiGarden.totalContributors()).to.equal(1);
    });

    it('a contributor can make an initial deposit and withdraw with USDC', async function () {
      const whaleAddress = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503'; // Has USDC
      const whaleSigner = await impersonateAddress(whaleAddress);
      const thousandUSDC = ethers.BigNumber.from(1000 * 1000000);
      await usdc.connect(whaleSigner).transfer(signer1.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(whaleSigner).transfer(signer3.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdc.connect(signer1).approve(babController.address, thousandUSDC, {
        gasPrice: 0,
      });
      const params = [...GARDEN_PARAMS_STABLE];
      params[3] = thousandUSDC.div(10);
      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.USDC,
          'Absolute USDC Return [beta]',
          'EYFA',
          'http...',
          0,
          params,
          thousandUSDC.div(10),
          [false, false, false],
          [0, 0, 0],
          {},
        );
      const gardens = await babController.getGardens();
      usdcGarden = await ethers.getContractAt('Garden', gardens[4]);
      expect(await usdcGarden.totalContributors()).to.equal(1);
      const gardenBalance = await usdc.balanceOf(usdcGarden.address);
      const supplyBefore = await usdcGarden.totalSupply();
      await mardukGate.connect(signer1).setGardenAccess(signer3.address, usdcGarden.address, 1, { gasPrice: 0 });
      await usdc.connect(signer3).approve(usdcGarden.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdcGarden.connect(signer3).deposit(thousandUSDC, eth(1000), signer3.getAddress(), false);
      const gardenBalanceAfter = await usdc.balanceOf(usdcGarden.address);
      const supplyAfter = await usdcGarden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.closeTo(eth('1000'), eth('0.1'));
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(thousandUSDC);
      expect(await usdcGarden.totalContributors()).to.equal(2);
      ethers.provider.send('evm_increaseTime', [1]);
      await usdcGarden
        .connect(signer3)
        .withdraw(await usdcGarden.balanceOf(signer3.address), 1, signer3.getAddress(), false, ADDRESS_ZERO);
      expect(await usdcGarden.totalContributors()).to.equal(1);
    });

    describe('mint NFT', async function () {
      it('mints an NFT if asked', async function () {
        await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), true, {
          value: eth(),
        });
        expect(await gardenNFT.balanceOf(signer3.address)).to.eq(1);
      });
      it('does NOT mint an NFT if NOT asked', async function () {
        await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
          value: eth(),
        });
        expect(await gardenNFT.balanceOf(signer3.address)).to.eq(0);
      });
    });

    describe('have a limit', async function () {
      it('reverts if the deposit is bigger than the limit', async function () {
        await expect(
          garden1.connect(signer3).deposit(eth('21'), 1, signer3.getAddress(), false, {
            value: eth('21'),
          }),
        ).to.be.reverted;
      });
    });

    describe('can be done after making a garden public', async function () {
      it('a user can still deposit after a garden is granted public access', async function () {
        await garden1.connect(signer1).makeGardenPublic();
        await expect(
          garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
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
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
        value: eth(),
      });
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      // Communities
      // Manager deposit in fixture is only 1
      expect(supplyAfter.sub(supplyBefore)).to.be.closeTo(eth(), eth('0.1'));
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(eth());
      expect(await garden1.totalContributors()).to.equal(2);
      // Contributor Struct
      const contributor = await garden1.getContributor(signer3.getAddress());
      expect(contributor[0]).to.be.gt(0);
      expect(contributor[1]).to.be.gt(0);
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
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false);
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      // Communities
      // Manager deposit in fixture is only 1
      expect(supplyAfter.sub(supplyBefore)).to.be.closeTo(eth(), eth('0.1'));
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(eth());
      expect(await garden1.totalContributors()).to.equal(2);
      // Contributor Struct
      const contributor = await garden1.getContributor(signer3.getAddress());
      expect(contributor[0]).to.be.gt(0);
      expect(contributor[1]).to.be.gt(0);
    });

    it('can make multiple deposits', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
        value: eth(),
      });
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
        value: eth(),
      });
      expect(await garden1.totalContributors()).to.equal(2);
    });

    it('multiple contributors can make deposits', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
        value: eth(),
      });

      await garden1.connect(signer2).deposit(eth(), 1, signer2.getAddress(), false, {
        value: eth(),
      });

      // Note: Garden is initialized with manager as first contributor
      expect(await garden1.totalContributors()).to.equal(3);
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
            DEFAULT_STRATEGY_PARAMS,
            [1],
            [balancerIntegration.address],
            [addresses.balancer.pools.wethdai],
            {
              gasLimit: 9500000,
              gasPrice: 0,
            },
          ),
      ).to.be.reverted;
    });

    it('a contributor should be able to add an strategy', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
        value: eth(),
      });
      const AbiCoder = ethers.utils.AbiCoder;
      const abiCoder = new AbiCoder();
      const encodedData = abiCoder.encode(['address', 'uint256'], [addresses.balancer.pools.wethdai, 0]);

      await expect(
        garden1
          .connect(signer3)
          .addStrategy('name', 'STRT', DEFAULT_STRATEGY_PARAMS, [1], [balancerIntegration.address], encodedData),
      ).to.not.be.reverted;
    });

    it('a contributor should not be able to add an strategy with a small stake', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
        value: eth(),
      });
      const params = [...DEFAULT_STRATEGY_PARAMS];
      params[1] = eth('0');
      let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
      let iface = new ethers.utils.Interface(ABI);
      let encodedData = iface.encodeFunctionData('babylonFinanceStrategyOpData', [addresses.balancer.pools.wethdai, 0]);

      await expect(
        garden1.connect(signer3).addStrategy('name', 'STRT', params, [1], [balancerIntegration.address], encodedData),
      ).to.be.reverted;
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
        const user1Avg = user1Balance > 0 ? user1Deposits[5].mul(eth()).div(user1Balance) : 0;
        const user2Avg = user2Balance > 0 ? user2Deposits[5].mul(eth()).div(user2Balance) : 0;

        expect(
          await babViewer.connect(signer1).getGardenUserAvgPricePerShare(garden.address, signer1.address),
        ).to.equal(user1Avg);
        expect(
          await babViewer.connect(signer1).getGardenUserAvgPricePerShare(garden.address, signer3.address),
        ).to.equal(user2Avg);
      });
    });
  });
});
