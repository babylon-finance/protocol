const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_ETH, ONE_DAY_IN_SECONDS, NOW } = require('../../lib/constants');
const { impersonateAddress } = require('../../lib/rpc');
const { from, eth, parse } = require('../../lib/helpers');
const { increaseTime } = require('../utils/test-helpers');

const { setupTests } = require('../fixtures/GardenFixture');
const { getCombinedModifierFlags } = require('typescript');

const TOTAL_REGISTERED_TOKENS = eth(272950);

describe('TimeLockRegistry', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let timeLockRegistry;

  async function checkVestingStartingDate(contributor) {
    let [team, vestingBegins, vestingEnds, lastClaim] = await timeLockRegistry.checkVesting(contributor);
    expect(vestingBegins).to.be.gt(1614553200);
    if (team === false) {
      expect(vestingBegins).to.be.closeTo(from(NOW), ONE_DAY_IN_SECONDS.div(50));
    } else if (team === true) {
      // 1615762800 March the 15th original Team vesting
      expect(vestingBegins).to.be.closeTo(from(1615762800), ONE_DAY_IN_SECONDS.div(10));
    }
  }

  async function checkVestingEndDate(contributor) {
    let [team, vestingBegins, vestingEnds, lastClaim] = await timeLockRegistry.checkVesting(contributor);
    if (team === false) {
      expect(vestingEnds).to.be.closeTo(from(NOW + 3 * (365 * ONE_DAY_IN_SECONDS)), ONE_DAY_IN_SECONDS.div(50));
    } else if (team === true) {
      // 1615762800 March the 15th original Team vesting
      expect(vestingEnds).to.be.closeTo(from(1615762800 + 4 * (365 * ONE_DAY_IN_SECONDS)), ONE_DAY_IN_SECONDS.div(10));
    }
  }

  beforeEach(async () => {
    ({ owner, bablToken, timeLockRegistry, signer1, signer2, signer3 } = await setupTests()());
    const block = await ethers.provider.getBlock();
    now = block.timestamp;
  });

  describe('token allocations', function () {
    it('the owner is correct', async function () {
      expect(await timeLockRegistry.owner()).to.equal(owner.address);
    });

    it('should have 305k tokens after deployment', async function () {
      const ownerBalance = await bablToken.balanceOf(timeLockRegistry.address);
      expect(ownerBalance).to.equal(ONE_ETH.mul(305000));
    });

    it('should have all registrations', async function () {
      expect((await timeLockRegistry.getRegistrations()).length).to.be.eq(80);
    });

    it('vestingStartDate should not be before March 15st PST for Team and NOW for Investors', async function () {
      const registrations = await timeLockRegistry.getRegistrations();
      for (let i = 0; i < registrations.length; i++) {
        await checkVestingStartingDate(registrations[i]);
      }
    });

    it('vestingEndDate should not be before 3 years for investors and 4 years for team', async function () {
      const registrations = await timeLockRegistry.getRegistrations();
      for (let i = 0; i < registrations.length; i++) {
        await checkVestingEndDate(registrations[i]);
      }
    });

    it('vesting amount should not be above 24,750', async function () {
      const registrations = await timeLockRegistry.getRegistrations();
      for (let i = 0; i < registrations.length; i++) {
        expect(await timeLockRegistry.checkRegisteredDistribution(registrations[i])).to.be.lte(eth(24750));
        expect(await timeLockRegistry.checkRegisteredDistribution(registrations[i])).to.be.gt(0);
      }
    });
  });

  describe('registerBatch', function () {
    it('can register multiple addresses at once', async function () {
      await timeLockRegistry.connect(owner).registerBatch([
        {
          receiver: signer1.address,
          distribution: eth(1000),
          investorType: true,
          vestingStartingDate: 1614618000,
        },
        {
          receiver: signer2.address,
          distribution: eth(500),
          investorType: false,
          vestingStartingDate: 1614618000,
        },
        {
          receiver: signer3.address,
          distribution: eth(100),
          investorType: false,
          vestingStartingDate: 1614618000,
        },
      ]);

      let [isTeam, vestingBegins, vestingEnds] = await timeLockRegistry.connect(owner).checkVesting(signer1.address);

      expect(isTeam).to.equal(true);
      expect(vestingBegins).to.equal(1614618000);
      expect(vestingEnds).to.equal(1614618000 + ONE_DAY_IN_SECONDS * 365 * 4);

      [isTeam, vestingBegins, vestingEnds] = await timeLockRegistry.connect(owner).checkVesting(signer2.address);

      expect(isTeam).to.equal(false);
      expect(vestingBegins).to.equal(1614618000);
      expect(vestingEnds).to.equal(1614618000 + ONE_DAY_IN_SECONDS * 365 * 3);

      [isTeam, vestingBegins, vestingEnds] = await timeLockRegistry.connect(owner).checkVesting(signer3.address);

      expect(isTeam).to.equal(false);
      expect(vestingBegins).to.equal(1614618000);
      expect(vestingEnds).to.equal(1614618000 + ONE_DAY_IN_SECONDS * 365 * 3);
    });
  });

  describe('register', function () {
    it('can NOT register if there are not enough tokens', async function () {
      await expect(
        timeLockRegistry.connect(owner).register(signer1.address, ONE_ETH.mul(999999999999), true, 1614618000),
      ).to.be.revertedWith('Not enough tokens');
    });

    it('totalTokens value is correct', async function () {
      await timeLockRegistry.connect(owner).register(signer1.address, ONE_ETH, true, 1614618000, { gasPrice: 0 });
      expect(await timeLockRegistry.totalTokens()).to.be.eq(TOTAL_REGISTERED_TOKENS.add(ONE_ETH));
    });

    it('investors registered correctly', async function () {
      const [isTeam, ,] = await timeLockRegistry
        .connect(owner)
        .checkVesting('0x47abD153385B9b63eCBfF064E3c3E71e8f6e2Aaa');

      expect(isTeam).to.be.eq(false);
    });

    it('team registered correctly', async function () {
      const [isTeam, ,] = await timeLockRegistry
        .connect(owner)
        .checkVesting('0x908295e2be3a36021aadaaed0bbb124fd602cbf2');

      expect(isTeam).to.be.eq(true);
    });
  });

  describe('claim', function () {
    it('totalTokens value is correct after claim', async function () {
      const teamSigner = await impersonateAddress('0x908295e2be3a36021aadaaed0bbb124fd602cbf2');
      await bablToken.connect(teamSigner).claimMyTokens({ gasPrice: 0 });
      expect(await timeLockRegistry.totalTokens()).to.be.eq(TOTAL_REGISTERED_TOKENS.sub(ONE_ETH.mul(17000)));
    });
  });

  describe('cancelRegistration', function () {
    it('totalTokens value is correct after cancellation', async function () {
      const teamSigner = await impersonateAddress('0x908295e2be3a36021aadaaed0bbb124fd602cbf2');

      await timeLockRegistry.connect(owner).cancelRegistration(teamSigner.address);
      expect(await timeLockRegistry.totalTokens()).to.be.eq(TOTAL_REGISTERED_TOKENS.sub(ONE_ETH.mul(17000)));
    });
    it('cancel a wrong address before claim and re-register the right address', async function () {
      const teamSignerOK = await impersonateAddress('0x232775eAD28F0C0c750A097bA77302E7d84efd3B');

      await timeLockRegistry.connect(owner).cancelRegistration(teamSignerOK.address);
      expect(await timeLockRegistry.totalTokens()).to.be.eq(TOTAL_REGISTERED_TOKENS.sub(ONE_ETH.mul(17000)));

      const teamSignerWrong = await impersonateAddress('0x71763709Da2488F75bc2DB5d194769d801e97Fa8');

      await timeLockRegistry.connect(owner).register(teamSignerWrong.address, eth(17000), true, 1614618000);
      expect(await timeLockRegistry.totalTokens()).to.be.eq(TOTAL_REGISTERED_TOKENS);

      await timeLockRegistry.connect(owner).cancelRegistration(teamSignerWrong.address);
      expect(await timeLockRegistry.totalTokens()).to.be.eq(TOTAL_REGISTERED_TOKENS.sub(ONE_ETH.mul(17000)));

      await timeLockRegistry.connect(owner).register(teamSignerOK.address, eth(17000), true, 1614618000);
      expect(await timeLockRegistry.totalTokens()).to.be.eq(TOTAL_REGISTERED_TOKENS);
    });
  });

  describe('register -> claim -> time passes -> unlocking balances -> transfers', function () {
    it('should unlock correct amount of BABL tokens during the vesting and depending on each personal conditions', async function () {
      await timeLockRegistry.connect(owner).register(signer1.address, eth(1000), true, now);

      await timeLockRegistry.connect(owner).register(signer2.address, eth(500), false, now);
      // Tokens are claimed by the Team Member and the registration is deleted in Time Lock Registry
      await bablToken.connect(signer1).claimMyTokens();
      await bablToken.connect(signer2).claimMyTokens();

      const userSigner1LockedBalance1 = await bablToken.viewLockedBalance(signer1.address);
      const userSigner1Balance1 = await bablToken.balanceOf(signer1.address);

      const userSigner2LockedBalance1 = await bablToken.viewLockedBalance(signer2.address);
      const userSigner2Balance1 = await bablToken.balanceOf(signer2.address);
      expect(userSigner1Balance1).to.equal(userSigner1LockedBalance1);
      expect(userSigner2Balance1).to.equal(userSigner2LockedBalance1);

      // We move ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 2);

      const userSigner1LockedBalance2 = await bablToken.viewLockedBalance(signer1.address);
      const userSigner1Balance2 = await bablToken.balanceOf(signer1.address);

      const userSigner2LockedBalance2 = await bablToken.viewLockedBalance(signer2.address);
      const userSigner2Balance2 = await bablToken.balanceOf(signer2.address);

      expect(userSigner1Balance2).to.equal(userSigner1Balance1);
      expect(userSigner2Balance2).to.equal(userSigner2Balance1);
      expect(userSigner1LockedBalance2).to.be.closeTo(userSigner1Balance2.div(2), eth(0.001)); // Team 4 Y vesting (1/2 available after 2Y)
      expect(userSigner2LockedBalance2).to.be.closeTo(userSigner2Balance2.div(3), eth(0.001)); // Investor 3Y vesting (2/3 available after 2Y)
    });
    it('should unlock all vested tokens after 3Y for investors and after 4Y for team members and advisors', async function () {
      await timeLockRegistry.connect(owner).register(signer1.address, eth(1000), true, now);

      await timeLockRegistry.connect(owner).register(signer2.address, eth(500), false, now);

      // Tokens are claimed by the Team Member and the registration is deleted in Time Lock Registry
      await bablToken.connect(signer1).claimMyTokens();
      await bablToken.connect(signer2).claimMyTokens();

      const userSigner1Balance1 = await bablToken.balanceOf(signer1.address);
      const userSigner2Balance1 = await bablToken.balanceOf(signer2.address);

      // We move ahead 3Y
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 3);

      const userSigner1LockedBalance2 = await bablToken.viewLockedBalance(signer1.address);
      const userSigner1Balance2 = await bablToken.balanceOf(signer1.address);
      const userSigner2LockedBalance2 = await bablToken.viewLockedBalance(signer2.address);
      const userSigner2Balance2 = await bablToken.balanceOf(signer2.address);

      expect(userSigner1Balance2).to.equal(userSigner1Balance1);
      expect(userSigner2Balance2).to.equal(userSigner2Balance1);
      expect(userSigner1LockedBalance2).to.be.closeTo(userSigner1Balance1.div(4), eth(0.001)); // Team 4 Y vesting (3/4 available after 3Y)
      expect(userSigner2LockedBalance2).to.be.equal('0'); // Investor 3Y vesting (all available after 3Y)
      // We move ahead 365 days more
      await increaseTime(ONE_DAY_IN_SECONDS * 365);

      const userSigner1LockedBalance3 = await bablToken.viewLockedBalance(signer1.address);
      expect(userSigner1LockedBalance3).to.be.equal('0'); // Team 4Y vesting (all available after 4Y)
    });

    it('be able to transfer all babl tokens after vesting passes (3Y investors, 4Y to team/advisors)', async function () {
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await timeLockRegistry.connect(owner).register(signer1.address, eth(1000), true, now);

      await timeLockRegistry.connect(owner).register(signer2.address, eth(500), false, now);

      // Tokens are claimed by the Team Member and the registration is deleted in Time Lock Registry
      await bablToken.connect(signer1).claimMyTokens();
      await bablToken.connect(signer2).claimMyTokens();
      const signer1Balance = await bablToken.balanceOf(signer1.address);
      const signer2Balance = await bablToken.balanceOf(signer2.address);

      await increaseTime(ONE_DAY_IN_SECONDS * 1095);
      const signer1LockedBalance = await bablToken.viewLockedBalance(signer1.address);

      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();

      await bablToken.connect(signer2).transfer(signer1.address, signer2Balance); // signer 2 sends all its balance to signer 1
      expect(await bablToken.balanceOf(signer2.address)).to.be.equal(0);
      expect(await bablToken.balanceOf(signer1.address)).to.be.equal(signer1Balance.add(signer2Balance));
      expect(await bablToken.viewLockedBalance(signer1.address)).to.be.closeTo(signer1LockedBalance, eth(0.0005)); // New received tokens are not locked

      await increaseTime(ONE_DAY_IN_SECONDS * 365);
      await bablToken.connect(signer1).transfer(signer2.address, await bablToken.balanceOf(signer1.address)); // signer 1 sends all its balance to signer 2
      expect(await bablToken.viewLockedBalance(signer1.address)).to.be.equal(0); // New received tokens are not locked
      expect(await bablToken.viewLockedBalance(signer2.address)).to.be.equal(0); // New received tokens are not locked
      expect(await bablToken.balanceOf(signer2.address)).to.be.equal(eth(1500));
    });
  });
});
