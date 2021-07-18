const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('../../lib/addresses');
const {
  ONE_DAY_IN_SECONDS,
  ONE_ETH,
  NOW,
  PROTOCOL_FEE,
  PROFIT_PROTOCOL_FEE,
  PROFIT_STRATEGIST_SHARE,
  PROFIT_STEWARD_SHARE,
  PROFIT_LP_SHARE,
} = require('../../lib/constants.js');
const { increaseTime } = require('../utils/test-helpers');
const { from, eth, parse } = require('../../lib/helpers');
const { GARDEN_PARAMS_STABLE, GARDEN_PARAMS, ADDRESS_ZERO, DAI_STRATEGY_PARAMS } = require('../../lib/constants');
const { impersonateAddress } = require('../../lib/rpc');

const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  getStrategy,
  getStrategyState,
  executeStrategy,
  vote,
  finalizeStrategy,
  injectFakeProfits,
} = require('../fixtures/StrategyHelper');

const { createGarden } = require('../fixtures/GardenHelper');

const { setupTests } = require('../fixtures/GardenFixture');

async function createWallets(number) {
  const walletAddresses = [];
  for (let i = 0; i < number; i++) {
    const newWallet = ethers.Wallet.createRandom();
    walletAddresses.push(newWallet);
  }
  return walletAddresses;
}

async function depositBatch(owner, garden, walletAddresses) {
  for (let i = 0; i < walletAddresses.length; i++) {
    // TODO Change "owner depositing on behalf of users" by direct deposits by the new generated wallets
    await garden.connect(owner).deposit(ethers.utils.parseEther('0.1'), 1, walletAddresses[i].address, false, {
      value: ethers.utils.parseEther('0.1'),
    });
  }
}

describe('Garden', function () {
  let babController;
  let rewardsDistributor;
  let owner;
  let keeper;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let ishtarGate;
  let balancerIntegration;
  let uniswapV3TradeIntegration;
  let daiGarden;
  let usdcGarden;
  let gardenNFT;

  let usdc;
  let weth;
  let dai;
  let wbtc;

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
      ishtarGate,
      balancerIntegration,
      uniswapV3TradeIntegration,

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
      expect(await garden1.minVotesQuorum()).to.equal(ethers.utils.parseEther('0.10'));
      expect(await garden1.minStrategyDuration()).to.equal(ONE_DAY_IN_SECONDS * 3);
      expect(await garden1.maxStrategyDuration()).to.equal(ONE_DAY_IN_SECONDS * 365);
    });
  });
  describe('pseudo-public rights by gardener', async function () {
    it('should allow deposits to a Ishar gate owner despite its individual permission is set to 0 but general deposit permission is allowed', async function () {
      expect(await ishtarGate.connect(signer1).canJoinAGarden(garden1.address, signer3.address)).to.equal(true);
      // Remove permissions
      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, garden1.address, 0, { gasPrice: 0 });
      await expect(
        garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
          gasPrice: 0,
        }),
      ).to.be.revertedWith('revert BAB#029');
      expect(await ishtarGate.connect(signer1).canJoinAGarden(garden1.address, signer3.address)).to.equal(false);
      // Make garden public first at BabController then at garden level
      expect(await babController.allowPublicGardens()).to.equal(false);
      await babController.connect(owner).setAllowPublicGardens();
      expect(await babController.allowPublicGardens()).to.equal(true);
      await garden1.connect(signer1).makeGardenPublic();
      await expect(
        garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
          gasPrice: 0,
        }),
      ).not.to.be.reverted;
      expect(await garden1.balanceOf(signer3.address)).to.equal(ethers.utils.parseEther('1'));
      expect(await ishtarGate.connect(signer1).canJoinAGarden(garden1.address, signer3.address)).to.equal(true);
    });
    it('should allow the strategy creation by an Ishar gate owner despite its individual permission is set to 0 but general strategy creation permission is allowed', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
        gasPrice: 0,
      });
      expect(await ishtarGate.connect(signer1).canAddStrategiesInAGarden(garden1.address, signer3.address)).to.equal(
        true,
      );
      await expect(getStrategy({ garden: garden1, signers: [signer3] })).not.to.be.reverted;
      // Remove permissions (0 is below LP even)
      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, garden1.address, 0, { gasPrice: 0 });
      await expect(getStrategy({ garden: garden1, signers: [signer3] })).to.be.revertedWith('revert BAB#030');
      expect(await ishtarGate.connect(signer1).canAddStrategiesInAGarden(garden1.address, signer3.address)).to.equal(
        false,
      );
      // Enable strategist creator rights - the garden needs to be public
      await expect(garden1.connect(signer1).setPublicRights(true, false)).to.be.revertedWith('revert BAB#088');
      await babController.connect(owner).setAllowPublicGardens();
      await garden1.connect(signer1).makeGardenPublic();
      await garden1.connect(signer1).setPublicRights(true, false);
      await expect(getStrategy({ garden: garden1, signers: [signer3] })).not.to.be.reverted;
      expect(await ishtarGate.connect(signer1).canAddStrategiesInAGarden(garden1.address, signer3.address)).to.equal(
        true,
      );
    });
    it('should allow the vote by an Ishar gate owner despite its individual permission is set to 0 but general voting permission is allowed', async function () {
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
        gasPrice: 0,
      });
      expect(await ishtarGate.connect(signer1).canVoteInAGarden(garden1.address, signer2.address)).to.equal(true);
      // Remove permissions (0 is below LP even)
      await ishtarGate.connect(signer1).setGardenAccess(signer2.address, garden1.address, 0, { gasPrice: 0 });
      expect(await ishtarGate.connect(signer1).canVoteInAGarden(garden1.address, signer2.address)).to.equal(false);

      // Enable voting power rights to users - the garden needs to be public
      await expect(garden1.connect(signer1).setPublicRights(false, true)).to.be.revertedWith('revert BAB#088');
      await babController.connect(owner).setAllowPublicGardens();
      await garden1.connect(signer1).makeGardenPublic();
      await garden1.connect(signer1).setPublicRights(false, true);
      expect(await ishtarGate.connect(signer1).canVoteInAGarden(garden1.address, signer2.address)).to.equal(true);
    });
  });

  describe('creation open to public', async function () {
    it('should allow the creation of a garden to a non-Ishtar gate user once garden creation is open to the public', async function () {
      await expect(
        babController
          .connect(signer2)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http:',
            0,
            GARDEN_PARAMS,
            ethers.utils.parseEther('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: ethers.utils.parseEther('0.1'),
            },
          ),
      ).to.be.revertedWith('revert User does not have creation permissions');
      await babController.connect(owner).openPublicGardenCreation();
      await expect(
        babController
          .connect(signer2)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http:',
            0,
            GARDEN_PARAMS,
            ethers.utils.parseEther('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: ethers.utils.parseEther('0.1'),
            },
          ),
      ).not.to.be.reverted;
    });
  });

  describe('payKeeper', async function () {
    it('anyone can NOT invoke payKeeper', async function () {
      await expect(garden1.connect(signer1).payKeeper(keeper.address, ONE_ETH)).to.be.revertedWith(/revert BAB#020/i);
    });
  });

  describe('state', async function () {
    it('only the protocol should be able to update active state', async function () {
      await expect(garden1.connect(signer1).setActive(true)).to.be.revertedWith(/revert BAB#016/i);
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
      ).to.be.revertedWith(/Transaction reverted: function call to a non-contract account/i);
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
          ethers.utils.parseEther('1'),
          [false, false, false],
          [ethers.utils.parseEther('0'), ethers.utils.parseEther('0'), ethers.utils.parseEther('0.95')],
          {
            value: ethers.utils.parseEther('1'),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[4]);
      const profitSharing = await rewardsDistributor.getGardenProfitsSharing(newGarden.address);
      expect(profitSharing[0]).to.equal(ethers.utils.parseEther('0'));
      expect(profitSharing[1]).to.equal(ethers.utils.parseEther('0'));
      expect(profitSharing[2]).to.equal(ethers.utils.parseEther('0.95'));
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
          ethers.utils.parseEther('1'),
          [false, false, false],
          [ethers.utils.parseEther('0'), ethers.utils.parseEther('0.95'), ethers.utils.parseEther('0')],
          {
            value: ethers.utils.parseEther('1'),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[4]);
      const profitSharing = await rewardsDistributor.getGardenProfitsSharing(newGarden.address);
      expect(profitSharing[0]).to.equal(ethers.utils.parseEther('0'));
      expect(profitSharing[1]).to.equal(ethers.utils.parseEther('0.95'));
      expect(profitSharing[2]).to.equal(ethers.utils.parseEther('0'));
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
          ethers.utils.parseEther('1'),
          [false, false, false],
          [ethers.utils.parseEther('0.95'), ethers.utils.parseEther('0'), ethers.utils.parseEther('0')],
          {
            value: ethers.utils.parseEther('1'),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[4]);
      const profitSharing = await rewardsDistributor.getGardenProfitsSharing(newGarden.address);
      expect(profitSharing[0]).to.equal(ethers.utils.parseEther('0.95'));
      expect(profitSharing[1]).to.equal(ethers.utils.parseEther('0'));
      expect(profitSharing[2]).to.equal(ethers.utils.parseEther('0'));
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
          ethers.utils.parseEther('1'),
          [false, false, false],
          [ethers.utils.parseEther('0.15'), ethers.utils.parseEther('0.40'), ethers.utils.parseEther('0.40')],
          {
            value: ethers.utils.parseEther('1'),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[4]);
      const profitSharing = await rewardsDistributor.getGardenProfitsSharing(newGarden.address);
      expect(profitSharing[0]).to.equal(ethers.utils.parseEther('0.15'));
      expect(profitSharing[1]).to.equal(ethers.utils.parseEther('0.40'));
      expect(profitSharing[2]).to.equal(ethers.utils.parseEther('0.40'));
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
            ethers.utils.parseEther('1'),
            [false, false, false],
            [ethers.utils.parseEther('0.14'), ethers.utils.parseEther('0.40'), ethers.utils.parseEther('0.40')],
            {
              value: ethers.utils.parseEther('1'),
            },
          ),
      ).to.be.revertedWith('revert BAB#089');
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
            ethers.utils.parseEther('1'),
            [false, false, false],
            [ethers.utils.parseEther('0.14'), ethers.utils.parseEther('0.45'), ethers.utils.parseEther('0.40')],
            {
              value: ethers.utils.parseEther('1'),
            },
          ),
      ).to.be.revertedWith('revert BAB#089');
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
            ethers.utils.parseEther('1'),
            [false, false, false],
            [ethers.utils.parseEther('0.1499999999'), ethers.utils.parseEther('0.40'), ethers.utils.parseEther('0.40')],
            {
              value: ethers.utils.parseEther('1'),
            },
          ),
      ).to.be.revertedWith('revert BAB#089');
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
            ethers.utils.parseEther('1'),
            [false, false, false],
            [ethers.utils.parseEther('0.15'), ethers.utils.parseEther('0.40000001'), ethers.utils.parseEther('0.40')],
            {
              value: ethers.utils.parseEther('1'),
            },
          ),
      ).to.be.revertedWith('revert BAB#089');
    });
  });

  describe('contributor power', async function () {
    it('the contributor power is calculated correctly if _to is after its last deposit (1 deposit from user)', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, NOW)).toString(),
      ).to.be.closeTo((499998254750568951).toString(), ethers.utils.parseEther('0.00005'));
    });
    it('the contributor power is calculated correctly if _to is after its last deposit and from = 0 (2 deposits from user)', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, NOW)).toString(),
      ).to.be.closeTo((666642802079881986).toString(), ethers.utils.parseEther('0.0005'));
    });
    it('the contributor power is calculated correctly if _to is between two deposits and from = 0 (2 distanced deposits from user)', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 1);
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      const signer3Timestamp = await garden1.getContributor(signer3.address);
      const value = ethers.BigNumber.from(signer3Timestamp[1]);
      await expect(
        await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, value.add(4)),
      ).to.be.closeTo((166666666666666666).toString(), ethers.utils.parseEther('0.05'));
    });
    it('the contributor power is calculated correctly if _from and _to are between two deposits', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90); // Getting some unlocked tokens
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1625141663, 1625141663)
        ).toString(),
      ).to.be.closeTo((500000000000000000).toString(), ethers.utils.parseEther('0.05'));
    });
    it('the contributor power is calculated correctly if _from is between two deposits and _to after the last deposit', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });

      await increaseTime(ONE_DAY_IN_SECONDS * 1); // Getting some unlocked tokens
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });

      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1622628863, 1624809743)
        ).toString(),
      ).to.be.closeTo((662205878389618258).toString(), ethers.utils.parseEther('0.005'));
    });
    it('the contributor power is calculated correctly if _from and _to are 2 years after the last deposit', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 2); // Getting some unlocked tokens
      // TODO CHECK VALUES
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1682615107, 1682874307)
        ).toString(),
      ).to.be.closeTo((666666666666666666).toString(), ethers.utils.parseEther('0.000005'));
    });
    it('the contributor power is calculated correctly if _from and _to are 2 years after the last deposit but several other deposits were taking place', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 1); // Getting some unlocked tokens
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('5'), 1, signer2.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 2); // Getting some unlocked tokens
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1682615107, 1682874307)
        ).toString(),
      ).to.be.closeTo((153846155020396967).toString(), ethers.utils.parseEther('0.0005'));
    });
    it('a malicious contributor cannot make a flash loan to get maximum contributor power', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('10'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('10'),
      });
      // Despite malicious contributor deposit 10ETH to increase its position, 11ETH out of 17 ETH (64%) (conviction deposit) it only gets 15% of contribution power within the time period
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, 1625245507)).toString(),
      ).to.be.closeTo((142857070336142271).toString(), ethers.utils.parseEther('0.0005'));
    });
    it('a malicious contributor cannot make a flash loan to get maximum contributor power from !=0 ', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('10'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('10'),
      });
      // Despite malicious contributor deposit 10ETH to increase its position, 11ETH out of 17 ETH (64%) (conviction deposit) it only gets 15% of contribution power within the time period
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1625245507)
        ).toString(),
      ).to.be.closeTo((142857070336142271).toString(), ethers.utils.parseEther('0.0005'));
    });
    it('a malicious contributor cannot make a flash loan to get maximum contributor power (2 big deposits) ', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('5'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('5'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
      });
      // Despite malicious contributor deposit new 5ETH to increase its position, 11ETH out of 17 ETH (64%) (conviction deposit) it only gets 50% of contribution power within the time period as most of the period had 50%
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1625245507)
        ).toString(),
      ).to.be.closeTo((499999750142340207).toString(), ethers.utils.parseEther('0.0005'));
    });
    it('contributor power is calculated correctly for different users in the same garden with the same power ', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('5'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('2'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('2'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('2'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('2'),
      });
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((499999988930846637).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer1.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((500000002767288110).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('contributor power is calculated correctly for different users if using _from and _to exact deposit timestamps ', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
      });
      const signer3DepositTimestamp = await garden1.getContributor(signer3.address);
      const signer1DepositTimestamp = await garden1.getContributor(signer1.address);
      await expect(
        (
          await rewardsDistributor.getContributorPower(
            garden1.address,
            signer1.address,
            signer1DepositTimestamp[0],
            signer1DepositTimestamp[0],
          )
        ).toString(),
      ).to.be.closeTo((944444444444444444).toString(), ethers.utils.parseEther('0.05'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(
            garden1.address,
            signer3.address,
            signer3DepositTimestamp[0],
            signer3DepositTimestamp[0],
          )
        ).toString(),
      ).to.be.equal('0');
    });
    it('contributor power is calculated correctly for different users if using _from and _to exact deposit timestamps (variation on deposits) ', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('3'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('3'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('3'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('3'),
      });
      const signer3DepositTimestamp = await garden1.getContributor(signer3.address);
      const signer1DepositTimestamp = await garden1.getContributor(signer1.address);
      await expect(
        (
          await rewardsDistributor.getContributorPower(
            garden1.address,
            signer1.address,
            signer1DepositTimestamp[1],
            signer1DepositTimestamp[1],
          )
        ).toString(),
      ).to.be.equal('0');
      await expect(
        (
          await rewardsDistributor.getContributorPower(
            garden1.address,
            signer1.address,
            signer1DepositTimestamp[0],
            signer1DepositTimestamp[0],
          )
        ).toString(),
      ).to.be.closeTo((833333333333333333).toString(), ethers.utils.parseEther('0.1'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(
            garden1.address,
            signer3.address,
            signer3DepositTimestamp[0],
            signer3DepositTimestamp[0],
          )
        ).toString(),
      ).to.be.closeTo((55555555555555555).toString(), ethers.utils.parseEther('0.05'));
    });
    it('contributor power is 100% for the creator if it is the only user (1 deposit)', async function () {
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((0).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer1.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((1000000000000000000).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('should work well when trying to hack it using the from = to', async function () {
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      // close to 49.99%
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer2.address, 1630602307, 1630602307)
        ).toString(),
      ).to.be.closeTo(ethers.utils.parseEther('0.4999').toString(), ethers.utils.parseEther('0.01'));
    });
    it('contributor power is 100% for the creator if it is the only user (several deposits)', async function () {
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((0).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer1.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((1000000000000000000).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('should fail get contributor power if _to < gardenInitializedAt', async function () {
      await expect(
        rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365635, 1617365640),
      ).to.be.revertedWith('revert BAB#065');
    });
    it('should fail get contributor power if _to < _from', async function () {
      await expect(
        rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365645, 1617365640),
      ).to.be.revertedWith('revert BAB#065');
    });
    it('contributor power is 100% for the creator if it is the only user (several distanced deposits)', async function () {
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('5'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('2'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('2'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((0).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (
          await rewardsDistributor.getContributorPower(garden1.address, signer1.address, 1617365661, 1630602307)
        ).toString(),
      ).to.be.closeTo((1000000000000000000).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('contributor power is 40% for signer 1, 30% for signers 2 and 3', async function () {
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('0.5'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('0.5'),
      });
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer1.address, 0, 1630602307)).toString(),
      ).to.be.closeTo((413967400713710268).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer2.address, 0, 1630602307)).toString(),
      ).to.be.closeTo((293016324178292452).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, 1630602307)).toString(),
      ).to.be.closeTo((293016256048574894).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('contributor power is 33%% each for 3 signers', async function () {
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await increaseTime(ONE_DAY_IN_SECONDS * 90);
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      // TODO CHECK FAIL SIGNER1 BY THE NEW FIX IN MAIN
      //await expect((await garden1.getContributorPower(signer1.address, 0, 1630602307)).toString()).to.be.closeTo((333333238251235557).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer2.address, 0, 1630602307)).toString(),
      ).to.be.closeTo((333333238251235557).toString(), ethers.utils.parseEther('0.0000005'));
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, 1630602307)).toString(),
      ).to.be.closeTo((333333202595448891).toString(), ethers.utils.parseEther('0.0000005'));
    });
    it('the contributor power is 0 if still not deposited in the garden', async function () {
      await expect(
        (await rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, NOW)).toString(),
      ).to.be.equal('0');
    });
    it('the contributor power is reverted if the time is before the garden initializes', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await expect(rewardsDistributor.getContributorPower(garden1.address, signer3.address, 0, 1617365660)).to.be
        .reverted;
    });
  });

  describe('withdraw', async function () {
    it('can withdraw funds if garden has free liquidity', async function () {
      await garden1.connect(signer3).deposit(eth(), 1, signer3.getAddress(), false, {
        value: eth(),
      });

      const beforeWithdrawal = await ethers.provider.getBalance(signer3.address);

      await garden1.connect(signer3).withdraw(eth(), 1, signer3.getAddress(), false, ADDRESS_ZERO);

      expect((await ethers.provider.getBalance(signer3.address)).sub(beforeWithdrawal)).to.be.closeTo(
        eth(0.99),
        eth(0.01),
      );
    });

    it('can withdraw funds with a penalty', async function () {
      const garden = await createGarden();

      const strategy = await getStrategy();
      await vote(strategy);

      await executeStrategy(strategy, { amount: eth().sub(eth().mul(PROTOCOL_FEE).div(eth())) });

      const beforeWithdrawal = await ethers.provider.getBalance(signer1.address);

      await garden.connect(signer1).withdraw(eth(0.5), 1, signer1.getAddress(), true, strategy.address);

      expect((await ethers.provider.getBalance(signer1.address)).sub(beforeWithdrawal)).to.be.closeTo(
        eth(0.46),
        eth(0.01),
      );
    });

    it('cannot withdraw gardens until the time ends', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('2'));
      expect(await garden1.totalContributors()).to.equal(2);
      await expect(
        garden1.connect(signer3).withdraw(ethers.utils.parseEther('20'), 1, signer3.getAddress()),
        false,
        ADDRESS_ZERO,
      ).to.be.reverted;
    });

    it('cannot withdraw more garden tokens than they have deposited', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('2'));
      expect(await garden1.totalContributors()).to.equal(2);
      await expect(
        garden1.connect(signer3).withdraw(ethers.utils.parseEther('1.12'), 2, signer3.getAddress()),
        false,
        ADDRESS_ZERO,
      ).to.be.reverted;
      await expect(
        garden1.connect(signer3).withdraw(ethers.utils.parseEther('20'), 2, signer3.getAddress()),
        false,
        ADDRESS_ZERO,
      ).to.to.be.reverted;
    });

    it('strategist or voters cannot withdraw more garden tokens than they have locked in active strategies', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      // It is executed
      const signer1Balance = await garden1.balanceOf(signer1.address);
      const signer2Balance = await garden1.balanceOf(signer2.address);
      const signer1LockedBalance = await garden1.getLockedBalance(signer1.address);
      const signer2LockedBalance = await garden1.getLockedBalance(signer2.address);
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);

      // Cannot withdraw locked stake amount
      await expect(
        garden1
          .connect(signer1)
          .withdraw(
            signer1Balance.sub(signer1LockedBalance).add(ethers.utils.parseEther('0.1')),
            1,
            signer1.getAddress(),
            false,
            ADDRESS_ZERO,
          ),
      ).to.be.reverted;
      // Cannot withdraw locked stake amount
      await expect(
        garden1
          .connect(signer2)
          .withdraw(
            signer2Balance.sub(signer2LockedBalance).add(ethers.utils.parseEther('0.1')),
            1,
            signer2.getAddress(),
            false,
            ADDRESS_ZERO,
          ),
      ).to.be.reverted;
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
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);
      const { active, finalized, executedAt, exitedAt, updatedAt } = await getStrategyState(strategyContract);
      expect(active).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(ethers.utils.parseEther('0.1'));

      await finalizeStrategy(strategyContract, 42);

      await garden1
        .connect(signer2)
        .withdraw(await garden1.balanceOf(signer2.address), 1, signer2.getAddress(), false, ADDRESS_ZERO);

      const WITHDRAWsigner2Balance = await garden1.balanceOf(signer2.address);
      await expect(WITHDRAWsigner2Balance).to.be.equal(ethers.utils.parseEther('0'));
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
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);
      const { active, finalized, executedAt, exitedAt, updatedAt } = await getStrategyState(strategyContract);
      expect(active).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(ethers.utils.parseEther('0.1'));

      await injectFakeProfits(strategyContract, ethers.utils.parseEther('200')); // We inject positive profits

      await finalizeStrategy(strategyContract, 42);

      // Can now withdraw stake amount as it is again unlocked
      await expect(
        garden1
          .connect(signer2)
          .withdraw(await garden1.balanceOf(signer2.address), 1, signer2.getAddress(), false, ADDRESS_ZERO),
      ).not.to.be.reverted;

      const WITHDRAWsigner2Balance = await garden1.balanceOf(signer2.address);
      await expect(WITHDRAWsigner2Balance).to.be.equal(ethers.utils.parseEther('0'));
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
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);
      const { active, finalized, executedAt, exitedAt, updatedAt } = await getStrategyState(strategyContract);
      expect(active).to.equal(true);

      expect(await strategyContract.strategist()).to.equal(signer1.address);
      expect(await strategyContract.stake()).to.equal(ethers.utils.parseEther('0.1'));
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
      await expect(finalStrategistBalance).to.be.closeTo(finalReducedBalance.toString(), 200);
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
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);

      await garden1.connect(signer2).deposit(ethers.utils.parseEther('5'), 1, signer2.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
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
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);

      await garden1.connect(signer2).deposit(ethers.utils.parseEther('5'), 1, signer2.getAddress(), false, {
        value: ethers.utils.parseEther('5'),
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

    it('should fail if startWithdrawalWindow is called more than once or from a non-strategy address', async function () {
      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );
      // It is executed
      await executeStrategy(strategyContract, ethers.utils.parseEther('1'), 42);

      await injectFakeProfits(strategyContract, ethers.utils.parseEther('200')); // We inject positive profits
      await finalizeStrategy(strategyContract, 0);
      await expect(finalizeStrategy(strategyContract, 0)).to.be.revertedWith('revert BAB#050');

      await expect(
        garden1.startWithdrawalWindow(
          ethers.BigNumber.from('1076070704097713768'),
          ethers.BigNumber.from('14263257018321332'),
          ethers.BigNumber.from('90333961116035100'),
          '0xd41b236f19726aba094b8b9d130620bfef535fd0',
        ),
      ).to.be.revertedWith('revert BAB#020');
    });
  });

  describe('deposit', async function () {
    it('cannot make a deposit when the garden is disabled', async function () {
      await expect(babController.connect(owner).disableGarden(garden1.address)).to.not.be.reverted;
      await expect(
        garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
        }),
      ).to.be.reverted;
    });

    it('a contributor can make an initial deposit and withdraw with DAI', async function () {
      const whaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'; // Has DAI
      const whaleSigner = await impersonateAddress(whaleAddress);
      await dai.connect(whaleSigner).transfer(signer1.address, ethers.utils.parseEther('1000'), {
        gasPrice: 0,
      });
      await dai.connect(whaleSigner).transfer(signer3.address, ethers.utils.parseEther('1000'), {
        gasPrice: 0,
      });
      await dai.connect(signer1).approve(babController.address, ethers.utils.parseEther('1000'), {
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
          ethers.utils.parseEther('100'),
          [false, false, false],
          [0, 0, 0],
          {},
        );
      const gardens = await babController.getGardens();
      daiGarden = await ethers.getContractAt('Garden', gardens[4]);
      expect(await daiGarden.totalContributors()).to.equal(1);
      const gardenBalance = await dai.balanceOf(daiGarden.address);
      const supplyBefore = await daiGarden.totalSupply();
      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, daiGarden.address, 1, { gasPrice: 0 });
      await dai.connect(signer3).approve(daiGarden.address, ethers.utils.parseEther('1000'), { gasPrice: 0 });
      await daiGarden.connect(signer3).deposit(ethers.utils.parseEther('1000'), 1, signer3.getAddress(), false);
      const gardenBalanceAfter = await dai.balanceOf(daiGarden.address);
      const supplyAfter = await daiGarden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.closeTo(
        ethers.utils.parseEther('1000'),
        ethers.utils.parseEther('0.1'),
      );
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(ethers.utils.parseEther('1000'));
      expect(await daiGarden.principal()).to.equal(ethers.utils.parseEther('1100'));
      expect(await daiGarden.totalContributors()).to.equal(2);
      ethers.provider.send('evm_increaseTime', [1]);
      await daiGarden
        .connect(signer3)
        .withdraw(await daiGarden.balanceOf(signer3.address), 1, signer3.getAddress(), false, ADDRESS_ZERO);
      expect(await daiGarden.principal()).to.equal(ethers.utils.parseEther('100'));
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
      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, usdcGarden.address, 1, { gasPrice: 0 });
      await usdc.connect(signer3).approve(usdcGarden.address, thousandUSDC, {
        gasPrice: 0,
      });
      await usdcGarden.connect(signer3).deposit(thousandUSDC, 1, signer3.getAddress(), false);
      const gardenBalanceAfter = await usdc.balanceOf(usdcGarden.address);
      const supplyAfter = await usdcGarden.totalSupply();
      expect(supplyAfter.sub(supplyBefore)).to.be.closeTo(
        ethers.utils.parseEther('1000'),
        ethers.utils.parseEther('0.1'),
      );
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(thousandUSDC);
      expect(await usdcGarden.principal()).to.equal(thousandUSDC.add(thousandUSDC.div(10)));
      expect(await usdcGarden.totalContributors()).to.equal(2);
      ethers.provider.send('evm_increaseTime', [1]);
      await usdcGarden
        .connect(signer3)
        .withdraw(await usdcGarden.balanceOf(signer3.address), 1, signer3.getAddress(), false, ADDRESS_ZERO);
      expect(await usdcGarden.principal()).to.equal(thousandUSDC.div(10));
      expect(await usdcGarden.totalContributors()).to.equal(1);
    });
    describe('mint NFT', async function () {
      it('mints an NFT if asked', async function () {
        await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), true, {
          value: ethers.utils.parseEther('1'),
        });
        expect(await gardenNFT.balanceOf(signer3.address)).to.eq(1);
      });
      it('does NOT mint an NFT if NOT asked', async function () {
        await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
        });
        expect(await gardenNFT.balanceOf(signer3.address)).to.eq(0);
      });
    });

    describe('have a limit', async function () {
      it('reverts if the deposit is bigger than the limit', async function () {
        await expect(
          garden1.connect(signer3).deposit(ethers.utils.parseEther('21'), 1, signer3.getAddress(), false, {
            value: ethers.utils.parseEther('21'),
          }),
        ).to.be.reverted;
      });
    });

    describe('can be disabled', async function () {
      it('reverts if the garden is disabled', async function () {
        await babController.connect(owner).disableGarden(garden1.address);
        await expect(
          garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
            value: ethers.utils.parseEther('1'),
          }),
        ).to.be.reverted;
      });
    });

    describe('can be done after making a garden public', async function () {
      it('a user can still deposit after a garden is granted public access', async function () {
        await babController.connect(owner).setAllowPublicGardens();
        await garden1.connect(signer1).makeGardenPublic();
        await expect(
          garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
            value: ethers.utils.parseEther('1'),
          }),
        ).not.to.be.reverted;
        const signer3Balance = await garden1.balanceOf(signer3.address);
        expect(signer3Balance).to.be.equal(ethers.utils.parseEther('1'));
      });
    });

    describe('can be done after reaching max limit of users', async function () {
      it('a user can still deposit after a garden reached its max limit of users but new users fail', async function () {
        // Downside the limit of new gardens to 10 to speed up the test
        await babController.connect(owner).setMaxContributorsPerGarden(10);
        const gardenParams = GARDEN_PARAMS;
        gardenParams[9] = 10;
        await babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'New Garden',
            'NEWG',
            'http...',
            0,
            gardenParams,
            ethers.utils.parseEther('1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: ethers.utils.parseEther('1'),
            },
          );
        const gardens = await babController.getGardens();
        const garden4 = await ethers.getContractAt('Garden', gardens[4]);
        await babController.connect(owner).setAllowPublicGardens();
        await garden4.connect(signer1).makeGardenPublic();

        // Signer 3 joins the new garden
        await garden4.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
        });
        // 8 new (random) people joins the garden as well + signer 3 + gardener = 10 = maximum
        const randomWallets = await createWallets(8);
        await depositBatch(owner, garden4, randomWallets);
        // Despite it is a public garden, no more contributors allowed <= 10 so it throws an exception for new users
        await expect(
          garden4.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), false, {
            value: ethers.utils.parseEther('1'),
          }),
        ).to.be.revertedWith('revert BAB#061');

        // Previous contributors belonging to the garden can still deposit
        await garden4.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
        });

        await garden4.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
        });
        expect((await garden4.balanceOf(signer3.address)).toString()).to.be.equal(ethers.utils.parseEther('3'));
      });
    });

    it('can make an initial deposit', async function () {
      expect(await garden1.totalContributors()).to.equal(1);
      const gardenBalance = await weth.balanceOf(garden1.address);
      const supplyBefore = await garden1.totalSupply();
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      // Communities
      // Manager deposit in fixture is only 1
      expect(supplyAfter.sub(supplyBefore)).to.be.closeTo(ethers.utils.parseEther('1'), ethers.utils.parseEther('0.1'));
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(ethers.utils.parseEther('1'));
      expect(await garden1.totalContributors()).to.equal(2);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('2'));
      const wethPosition = await garden1.principal();
      expect(wethPosition).to.be.gt(ethers.utils.parseEther('1.999'));
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
      const tenWETH = ethers.utils.parseEther('10');
      await weth.connect(whaleSigner).transfer(signer3.address, tenWETH, {
        gasPrice: 0,
      });
      await weth.connect(signer3).approve(garden1.address, tenWETH, {
        gasPrice: 0,
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false);
      const gardenBalanceAfter = await weth.balanceOf(garden1.address);
      const supplyAfter = await garden1.totalSupply();
      // Communities
      // Manager deposit in fixture is only 1
      expect(supplyAfter.sub(supplyBefore)).to.be.closeTo(ethers.utils.parseEther('1'), ethers.utils.parseEther('0.1'));
      expect(gardenBalanceAfter.sub(gardenBalance)).to.equal(ethers.utils.parseEther('1'));
      expect(await garden1.totalContributors()).to.equal(2);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('2'));
      const wethPosition = await garden1.principal();
      expect(wethPosition).to.be.gt(ethers.utils.parseEther('1.999'));
      // Contributor Struct
      const contributor = await garden1.getContributor(signer3.getAddress());
      expect(contributor[0]).to.be.gt(0);
      expect(contributor[1]).to.be.gt(0);
    });

    it('can make multiple deposits', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      // Note: Garden is initialized with manager as first contributor, hence the count and principal delta
      expect(await garden1.totalContributors()).to.equal(2);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('3'));
    });

    it('multiple contributors can make deposits', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });

      await garden1.connect(signer2).deposit(ethers.utils.parseEther('1'), 1, signer2.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });

      // Note: Garden is initialized with manager as first contributor
      expect(await garden1.totalContributors()).to.equal(3);
      expect(await garden1.principal()).to.equal(ethers.utils.parseEther('3'));
    });
  });

  describe('getGardenTokenMintQuantity', async function () {
    it('get correct amounts of tokens if 1 ETH deposited', async function () {
      const tokens = await garden1.getGardenTokenMintQuantity(ONE_ETH, false);

      expect(tokens).to.be.equal(ONE_ETH);
    });

    it('get correct amounts of tokens if 8 ETH deposited', async function () {
      garden1.connect(signer3).deposit(ONE_ETH.mul(8), 1, signer3.getAddress(), false, {
        value: ONE_ETH.mul(8),
      });
      const tokens = await garden1.getGardenTokenMintQuantity(ONE_ETH.mul(2), false);
      expect(tokens).to.be.equal(ONE_ETH.mul(2));
    });

    it('get correct amounts of tokens if 8 ETH deposited and strategy is executed', async function () {
      garden1.connect(signer3).deposit(ONE_ETH.mul(8), 1, signer3.getAddress(), false, {
        value: ONE_ETH.mul(8),
      });

      const strategyContract = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract);

      const tokens = await garden1.getGardenTokenMintQuantity(ONE_ETH.mul(3), false);
      expect(tokens).to.be.closeTo(ONE_ETH.mul(3), ONE_ETH.div(100));
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
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
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
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), false, {
        value: ethers.utils.parseEther('1'),
      });
      const params = [...DEFAULT_STRATEGY_PARAMS];
      params[1] = ethers.utils.parseEther('0');
      let ABI = ['function babylonFinanceStrategyOpData(address data, uint256 metadata)']; // 64 bytes
      let iface = new ethers.utils.Interface(ABI);
      let encodedData = iface.encodeFunctionData('babylonFinanceStrategyOpData', [addresses.balancer.pools.wethdai, 0]);

      await expect(
        garden1.connect(signer3).addStrategy('name', 'STRT', params, [1], [balancerIntegration.address], encodedData),
      ).to.be.reverted;
    });
  });
});
