const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('lib/addresses');
const { fund, createWallets } = require('lib/whale');
const {
  STRATEGY_EXECUTE_MAP,
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
} = require('lib/constants.js');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');
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
} = require('fixtures/StrategyHelper');

const {
  createGarden,
  getDepositSig,
  getWithdrawSig,
  transferFunds,
  depositFunds,
  getRewardsSig,
} = require('fixtures/GardenHelper');

const { setupTests } = require('fixtures/GardenFixture');

describe('rewards', function () {
  let babController;
  let bablToken;
  let rewardsDistributor;
  let rewardsAssistant;
  let owner;
  let keeper;
  let garden1;
  let ishtarGate;
  let balancerIntegration;
  let uniswapV3TradeIntegration;
  let daiGarden;
  let usdcGarden;
  let gardenNFT;
  let gardenValuer;
  let babViewer;
  let users;
  let heartTestGarden;

  let usdc;
  let weth;
  let dai;
  let wbtc;

  const gardenNum = 1;
  const strategyNum = 1;
  const depositNum = 1;
  const userNum = 2;

  let stakeInHeart = false; // Default value
  const stakeMinAmountOut = eth(0.9);
  const mintNft = false;
  const maxFee = 1;
  const fee = 1;

  beforeEach(async () => {
    ({
      babController,
      bablToken,
      rewardsDistributor,
      rewardsAssistant,
      gardenNFT,
      keeper,
      owner,
      garden1,
      heartTestGarden,
      ishtarGate,
      balancerIntegration,
      uniswapV3TradeIntegration,
      gardenValuer,
      babViewer,

      dai,
      usdc,
      weth,
      wbtc,
    } = await setupTests()());

    const reserveContract = await getERC20(addresses.tokens.WETH);
    users = await createWallets(userNum, {
      tokens: [addresses.tokens.WETH, addresses.tokens.ETH],
      amounts: [eth(900), eth(900)],
    });
    await ishtarGate.connect(owner).setMaxNumberOfInvites(999999);
    await ishtarGate.connect(owner).setCreatorPermissions(users[0].address, true, { gasPrice: 0 });
  });

  async function withdraw(gardens) {
    for (const garden of gardens) {
      for (let signer of users) {
        await garden
          .connect(signer)
          .withdraw(await garden.balanceOf(signer.address), 1, signer.getAddress(), false, ADDRESS_ZERO, {
            gasPrice: 0,
          });
        await increaseTime(3600);
      }
    }
  }
  async function claim(gardens, stake) {
    stakeInHeart = stake || stakeInHeart;
    for (const garden of gardens) {
      for (let signer of users) {
        await rewardsDistributor
          .connect(signer)
          .claimRewards([garden.address], stakeInHeart, stakeMinAmountOut, mintNft);
        await increaseTime(3600);
      }
    }
  }

  async function claimAll(gardens, stake) {
    stakeInHeart = stake || stakeInHeart;
    const gardenAddresses = gardens.map((gardens) => gardens.address);
    for (let signer of users) {
      await rewardsDistributor.connect(signer).claimRewards(gardenAddresses, stakeInHeart, stakeMinAmountOut, mintNft);
      await increaseTime(3600);
    }
  }

  async function claimAllBySig(gardens, stake) {
    stakeInHeart = stake || stakeInHeart;
    const gardenAddresses = gardens.map((gardens) => gardens.address);
    for (const signer of users) {
      const rewardsAll = await rewardsAssistant.getAllUserRewards(signer.address, gardenAddresses, {
        gasPrice: 0,
      });

      const gardensAddr = rewardsAll[0];
      const bablPerGarden = rewardsAll[1];
      const profitsPerGarden = rewardsAll[2];
      const totalBabl = rewardsAll[3];
      const totalProfits = rewardsAll[4];
      // Rewards nonce
      const userRewardsNonce = await rewardsDistributor.getUserRewardsNonce(signer.address);
      const contributorData = await heartTestGarden.getContributor(signer.address);
      // Heart Garden nonce
      const heartGardenUserNonce = contributorData[9];
      const boolSignatureData = [mintNft, stakeInHeart];
      const pricePerShare = await gardenValuer.calculateGardenValuation(heartTestGarden.address, bablToken.address);
      // We create the signature
      const sig = await getRewardsSig(
        signer,
        rewardsDistributor.address,
        totalBabl,
        totalProfits,
        userRewardsNonce,
        stakeMinAmountOut,
        heartGardenUserNonce,
        maxFee,
        mintNft,
        stakeInHeart,
      );
      // We prepare the call data
      const signatureData = [
        totalBabl,
        totalProfits,
        userRewardsNonce,
        stakeMinAmountOut,
        heartGardenUserNonce,
        maxFee,
        fee,
        pricePerShare,
      ];

      await rewardsDistributor
        .connect(keeper)
        .claimRewardsBySig(
          gardensAddr,
          bablPerGarden,
          profitsPerGarden,
          signatureData,
          boolSignatureData,
          sig.v,
          sig.r,
          sig.s,
          { gasPrice: 0 },
        );
    }
  }

  async function claimBySig(gardens, stake) {
    stakeInHeart = stake || stakeInHeart;
    for (const garden of gardens) {
      for (const signer of users) {
        const rewardsAll = await rewardsAssistant.getAllUserRewards(signer.address, [garden.address], {
          gasPrice: 0,
        });

        const gardens = rewardsAll[0];
        const bablPerGarden = rewardsAll[1];
        const profitsPerGarden = rewardsAll[2];
        const totalBabl = rewardsAll[3];
        const totalProfits = rewardsAll[4];
        // Rewards nonce
        const userRewardsNonce = await rewardsDistributor.getUserRewardsNonce(signer.address);
        const contributorData = await heartTestGarden.getContributor(signer.address);
        // Heart Garden nonce
        const heartGardenUserNonce = contributorData[9];
        const boolSignatureData = [mintNft, stakeInHeart];
        const pricePerShare = await gardenValuer.calculateGardenValuation(heartTestGarden.address, bablToken.address);
        // We create the signature
        const sig = await getRewardsSig(
          signer,
          rewardsDistributor.address,
          totalBabl,
          totalProfits,
          userRewardsNonce,
          stakeMinAmountOut,
          heartGardenUserNonce,
          maxFee,
          mintNft,
          stakeInHeart,
        );
        // We prepare the call data
        const signatureData = [
          totalBabl,
          totalProfits,
          userRewardsNonce,
          stakeMinAmountOut,
          heartGardenUserNonce,
          maxFee,
          fee,
          pricePerShare,
        ];

        await rewardsDistributor
          .connect(keeper)
          .claimRewardsBySig(
            gardens,
            bablPerGarden,
            profitsPerGarden,
            signatureData,
            boolSignatureData,
            sig.v,
            sig.r,
            sig.s,
            { gasPrice: 0 },
          );
      }
    }
  }

  async function finalize(strategies) {
    for (const strategy of strategies) {
      await injectFakeProfits(strategy, eth().mul(200));
      await strategy.connect(keeper).finalizeStrategy(0, '', 0, { gasPrice: 0 });
      await increaseTime(3600);
    }
  }

  async function execute(strategies) {
    for (const strategy of strategies) {
      await strategy.connect(keeper).executeStrategy(eth(0.1), 0, {
        gasPrice: 0,
      });
      await increaseTime(3600);
    }
  }

  async function create(gardens) {
    const strategies = [];
    for (const garden of gardens) {
      await increaseTime(3600);
      strategies.push(
        await getStrategy({ signers: users, garden, state: 'vote', specificParams: [addresses.tokens.DAI, 0] }),
      );
    }
    return strategies;
  }

  async function deposit(gardens) {
    const reserveContract = await getERC20(addresses.tokens.WETH);
    for (const garden of gardens) {
      for (let signer of users) {
        await reserveContract.connect(signer).approve(garden.address, eth(9999999), { gasPrice: 0 });
        for (let j = 0; j < depositNum; j++) {
          await garden.connect(signer).deposit(eth(0.1), eth(0.1), signer.getAddress(), false, {});
          await increaseTime(3600);
        }
      }
    }
  }

  it('simulate mining rewards launch', async function () {
    const gardens = [];
    for (let i = 0; i < gardenNum; i++) {
      const garden = await createGarden({ signer: users[0], params: [eth(1e4), ...GARDEN_PARAMS.slice(1)] });
      gardens.push(garden);
      await ishtarGate.connect(users[0]).grantGardenAccessBatch(
        garden.address,
        users.map((u) => u.address),
        users.map((u) => 3),
        {
          gasPrice: 0,
        },
      );
    }

    let strategies = [];
    for (let i = 0; i < strategyNum; i++) {
      const newStrategies = await create(gardens);

      await increaseTime(ONE_DAY_IN_SECONDS);
      await deposit(gardens);

      await increaseTime(ONE_DAY_IN_SECONDS);
      await execute(newStrategies);

      strategies = [...strategies, ...newStrategies];
    }

    await increaseTime(ONE_DAY_IN_SECONDS * 30);
    await finalize(strategies);

    await increaseTime(ONE_DAY_IN_SECONDS);
    // Options
    // a) normal claim vs. by sig
    // b) claim only or claim and stake
    // c) claim 1 by one or claim all
    await claim(gardens, false);
    // await claimBySig(gardens, false);
    // await claimAll(gardens, false);
    // await claimAllBySig(gardens, true);

    await increaseTime(ONE_DAY_IN_SECONDS);
    await withdraw(gardens);
  });
});
