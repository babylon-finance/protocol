const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_ETH, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('../../lib/constants');
const { impersonateAddress } = require('../../lib/rpc');
const { increaseTime } = require('../utils/test-helpers');

const { setupTests } = require('../fixtures/GardenFixture');

const OWNER_BALANCE = ONE_ETH.mul(16000);
const REWARDS_BALANCE = ONE_ETH.mul(500000);
const REGISTRY_BALANCE = ONE_ETH.mul(310000);
const TOTAL_REGISTERED_TOKENS = ONE_ETH.mul(268950);

describe('TimeLockRegistry', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let timeLockRegistry;
  let rewardsDistributor;
  let babController;

  beforeEach(async () => {
    ({
      owner,
      bablToken,
      timeLockRegistry,
      rewardsDistributor,
      babController,
      signer1,
      signer2,
      signer3,
    } = await setupTests()());
  });

  describe('deployment', function () {
    it('the owner is correct', async function () {
      expect(await timeLockRegistry.owner()).to.equal(owner.address);
    });

    it('timeLockRegistry should have 310k tokens after deployment', async function () {
      const ownerBalance = await bablToken.balanceOf(timeLockRegistry.address);
      expect(ownerBalance).to.equal(ONE_ETH.mul(310000));
    });

    it('timeLockRegistry should have all registrations', async function () {
      expect((await timeLockRegistry.getRegistrations()).length).to.be.eq(79);
    });
  });

  describe('registerBatch', function () {
    it('can register multiple addresses at once', async function () {
      await timeLockRegistry.connect(owner).registerBatch([
        {
          receiver: signer1.address,
          distribution: ethers.utils.parseEther('1000'),
          investorType: true,
          vestingStartingDate: 1614618000,
        },
        {
          receiver: signer2.address,
          distribution: ethers.utils.parseEther('500'),
          investorType: false,
          vestingStartingDate: 1614618000,
        },
        {
          receiver: signer3.address,
          distribution: ethers.utils.parseEther('100'),
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

    it.skip('totalTokens value is correct', async function () {
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
    it('totalTokens value is correct', async function () {
      const teamSigner = await impersonateAddress('0x908295e2be3a36021aadaaed0bbb124fd602cbf2');

      await bablToken.connect(teamSigner).claimMyTokens();
      expect(await timeLockRegistry.totalTokens()).to.be.eq(TOTAL_REGISTERED_TOKENS.sub(ONE_ETH.mul(17000)));
    });
  });

  describe('cancelRegistration', function () {
    it('totalTokens value is correct', async function () {
      const teamSigner = await impersonateAddress('0x908295e2be3a36021aadaaed0bbb124fd602cbf2');

      await timeLockRegistry.connect(owner).cancelRegistration(teamSigner.address);
      expect(await timeLockRegistry.totalTokens()).to.be.eq(TOTAL_REGISTERED_TOKENS.sub(ONE_ETH.mul(17000)));
    });
  });
  describe('Quality Tests: Register ->  Claim -> Time passes -> Unlocking balances -> Transfers', function () {
    it('Should unlock correct amount of BABL tokens during the vesting and depending on each personal conditions', async function () {
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await timeLockRegistry
        .connect(owner)
        .register(signer1.address, ethers.utils.parseEther('1000'), true, 1614618000);

      await timeLockRegistry
        .connect(owner)
        .register(signer2.address, ethers.utils.parseEther('500'), false, 1614618000);

      // Tokens are claimed by the Team Member and the registration is deleted in Time Lock Registry
      await bablToken.connect(signer1).claimMyTokens();
      await bablToken.connect(signer2).claimMyTokens();

      const userSigner1LockedBalance1 = await bablToken.viewLockedBalance(signer1.address);
      const userSigner1Balance1 = await bablToken.balanceOf(signer1.address);

      const userSigner2LockedBalance1 = await bablToken.viewLockedBalance(signer2.address);
      const userSigner2Balance1 = await bablToken.balanceOf(signer2.address);

      // We move ahead 365 days
      await increaseTime(ONE_DAY_IN_SECONDS * 340);

      const userSigner1LockedBalance2 = await bablToken.viewLockedBalance(signer1.address);
      const userSigner1Balance2 = await bablToken.balanceOf(signer1.address);

      const userSigner2LockedBalance2 = await bablToken.viewLockedBalance(signer2.address);
      const userSigner2Balance2 = await bablToken.balanceOf(signer2.address);

      expect(userSigner1Balance2).to.equal(userSigner1Balance1);
      expect(userSigner2Balance2).to.equal(userSigner2Balance1);
      expect(userSigner1LockedBalance2).to.be.closeTo('718567692478437341451', ethers.utils.parseEther('0.0005')); // Team 4 Y vesting (1/4 available after 1Y)
      expect(userSigner2LockedBalance2).to.be.closeTo('312378451082360899712', ethers.utils.parseEther('0.0005')); // Investor 3Y vesting (1/3 available after 1Y)
    });
    it('Should unlock all vested tokens after 3Y for investors and after 4Y for team members and advisors', async function () {
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await timeLockRegistry
        .connect(owner)
        .register(signer1.address, ethers.utils.parseEther('1000'), true, 1614618000);

      await timeLockRegistry
        .connect(owner)
        .register(signer2.address, ethers.utils.parseEther('500'), false, 1614618000);

      // Tokens are claimed by the Team Member and the registration is deleted in Time Lock Registry
      await bablToken.connect(signer1).claimMyTokens();
      await bablToken.connect(signer2).claimMyTokens();

      const userSigner1LockedBalance1 = await bablToken.viewLockedBalance(signer1.address);
      const userSigner1Balance1 = await bablToken.balanceOf(signer1.address);

      const userSigner2LockedBalance1 = await bablToken.viewLockedBalance(signer2.address);
      const userSigner2Balance1 = await bablToken.balanceOf(signer2.address);

      // We move ahead 3Y
      await increaseTime(ONE_DAY_IN_SECONDS * 1095);

      const userSigner1LockedBalance2 = await bablToken.viewLockedBalance(signer1.address);
      const userSigner1Balance2 = await bablToken.balanceOf(signer1.address);
      const userSigner2LockedBalance2 = await bablToken.viewLockedBalance(signer2.address);
      const userSigner2Balance2 = await bablToken.balanceOf(signer2.address);

      expect(userSigner1Balance2).to.equal(userSigner1Balance1);
      expect(userSigner2Balance2).to.equal(userSigner2Balance1);
      expect(userSigner1LockedBalance2).to.be.closeTo('201444404807204464738', ethers.utils.parseEther('0.0005')); // Team 4 Y vesting (3/4 available after 3Y)
      expect(userSigner2LockedBalance2).to.be.equal('0'); // Investor 3Y vesting (all available after 3Y)
      // We move ahead 365 days more
      await increaseTime(ONE_DAY_IN_SECONDS * 365);

      const userSigner1LockedBalance3 = await bablToken.viewLockedBalance(signer1.address);
      expect(userSigner1LockedBalance3).to.be.equal('0'); // Team 4Y vesting (all available after 4Y)
    });

    it('be able to transfer all babl tokens after vesting passes (3Y investors, 4Y to team/advisors)', async function () {
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await timeLockRegistry
        .connect(owner)
        .register(signer1.address, ethers.utils.parseEther('1000'), true, 1614618000);

      await timeLockRegistry
        .connect(owner)
        .register(signer2.address, ethers.utils.parseEther('500'), false, 1614618000);

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
      expect(await bablToken.viewLockedBalance(signer1.address)).to.be.closeTo(
        signer1LockedBalance,
        ethers.utils.parseEther('0.0005'),
      ); // New received tokens are not locked

      await increaseTime(ONE_DAY_IN_SECONDS * 365);
      await bablToken.connect(signer1).transfer(signer2.address, await bablToken.balanceOf(signer1.address)); // signer 1 sends all its balance to signer 2
      expect(await bablToken.viewLockedBalance(signer1.address)).to.be.equal(0); // New received tokens are not locked
      expect(await bablToken.viewLockedBalance(signer2.address)).to.be.equal(0); // New received tokens are not locked
      expect(await bablToken.balanceOf(signer2.address)).to.be.equal(ethers.utils.parseEther('1500'));
    });
  });
});
