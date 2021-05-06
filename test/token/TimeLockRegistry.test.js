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

    it('totalTokens value is correct', async function () {
      await timeLockRegistry.connect(owner).register(signer1.address, ONE_ETH, true, 1614618000);
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
});
