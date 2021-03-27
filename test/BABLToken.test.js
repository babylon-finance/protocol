// We import Chai to use its asserting functions here.

const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { EMPTY_BYTES, ONE_DAY_IN_SECONDS } = require('../utils/constants');

const { loadFixture } = waffle;

const addresses = require('../utils/addresses');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');
const { BigNumber } = require('@ethersproject/bignumber');

// `describe` is a Mocha function that allows you to organize your tests. It's
// not actually needed, but having your tests organized makes debugging them
// easier. All Mocha functions are available in the global scope.

// `describe` receives the name of a section of your test suite, and a callback.
// The callback must define the tests of that section. This callback can't be
// an async function.
describe('BABLToken contract', function () {
  // Mocha has four functions that let you hook into the the test runner's
  // lifecyle. These are: `before`, `beforeEach`, `after`, `afterEach`.

  // They're very useful to setup the environment for tests, and to clean it
  // up after they run.

  // A common pattern is to declare some variables, and assign them in the
  // `before` and `beforeEach` callbacks.

  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let timeLockRegistry;

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.

  beforeEach(async () => {
    ({ owner, bablToken, timeLockRegistry, signer1, signer2, signer3 } = await loadFixture(deployFolioFixture));

    // console.log(
    //   "Config:",
    //   oracle,
    //   valuer,
    //   ownerSigner,
    //   userSigner1,
    //   userSigner2,
    //   userSigner3
    // );
  });

  // You can nest describe calls to create subsections.
  describe('Deployment', function () {
    // `it` is another Mocha function. This is the one you use to define your
    // tests. It receives the test name, and a callback function.

    it('should successfully deploy BABLToken contract', async function () {
      const deployedc = await bablToken.deployed();
      expect(!!deployedc).to.equal(true);
    });

    it('should successfully deploy TimeLockRegistry contract', async function () {
      const deployedc2 = await timeLockRegistry.deployed();
      expect(!!deployedc2).to.equal(true);
    });

    it('should successfully have assigned the TimeLockRegistry address to BABLToken contract', async function () {
      // Set up TimeLockRegistry
      const addressRegistry = await bablToken.timeLockRegistry();
      expect(timeLockRegistry.address).to.equal(addressRegistry);
    });

    // If the callback function is async, Mocha will `await` it.
    it('Should set the right owner to BABL', async function () {
      // Expect receives a value, and wraps it in an Assertion object. These
      // objects have a lot of utility methods to assert values.

      // This test expects the owner variable stored in the contract to be equal
      // to our Signer's owner.
      expect(await bablToken.owner()).to.equal(owner.address);
    });

    // If the callback function is async, Mocha will `await` it.
    it('Should set the right owner to Registry', async function () {
      // Expect receives a value, and wraps it in an Assertion object. These
      // objects have a lot of utility methods to assert values.

      // This test expects the owner variable stored in the contract to be equal
      // to our Signer's owner.
      expect(await timeLockRegistry.owner()).to.equal(owner.address);
    });

    it('Should assign the total supply of tokens to the owner', async function () {
      const ownerBalance = await bablToken.balanceOf(owner.address);
      expect(await bablToken.totalSupply()).to.equal(ownerBalance);
    });
  });

  describe('Transactions', function () {
    it('Should transfer tokens between accounts', async function () {
      // Transfer 260_000e18 tokens from owner to userSigner1
      const value = ethers.utils.parseEther('260000');
      await bablToken.connect(owner).transfer(signer1.address, value);

      const addr1Balance = await bablToken.balanceOf(signer1.address);
      expect(addr1Balance).to.equal(value);

      // Transfer 180_000e18 tokens from userSigner1 to userSigner2
      // We use .connect(signer) to send a transaction from another account
      const value2 = ethers.utils.parseEther('180000');
      await bablToken.connect(signer1).transfer(signer2.address, value2);

      const addr2Balance = await bablToken.balanceOf(signer2.address);
      expect(addr2Balance).to.equal(value2);
    });

    it('Should fail if sender doesn’t have enough tokens', async function () {
      const initialOwnerBalance = await bablToken.balanceOf(owner.address);

      // Try to send 1 BABLToken from userSigner1 (0 tokens) to owner (1000 tokens).
      // `require` will evaluate false and revert the transaction.
      await expect(bablToken.connect(signer1).transfer(owner.address, 1)).to.be.revertedWith(
        'TimeLockedToken:: _transfer: insufficient balance',
      );

      // Owner balance shouldn't have changed.
      expect(await bablToken.balanceOf(owner.address)).to.equal(initialOwnerBalance);
    });

    it('Should update balances after transfers', async function () {
      const initialOwnerBalance = await bablToken.balanceOf(owner.address);
      const value = ethers.utils.parseEther('260000');
      // Transfer 260_000e18 tokens from owner to userSigner1.
      await bablToken.transfer(signer1.address, value);
      const value2 = ethers.utils.parseEther('180000');
      // Transfer another 180_000e18 tokens from owner to userSigner2.
      await bablToken.transfer(signer2.address, value2);

      // Check balances.
      const totalsent = ethers.utils.parseEther('440000');
      const finalOwnerBalance = await bablToken.balanceOf(owner.address);
      const differenceBalance = BigInt(initialOwnerBalance) - BigInt(totalsent);
      expect(finalOwnerBalance).to.equal(differenceBalance);

      const addr1Balance = await bablToken.balanceOf(signer1.address);
      expect(addr1Balance).to.equal(value);

      const addr2Balance = await bablToken.balanceOf(signer2.address);
      expect(addr2Balance).to.equal(value2);
    });
  });

  describe('Vesting', function () {
    // TODO CHECK ALLOWANCE FLOW WHICH IS FINALLY NEEDED TO DISPOSE/REGISTER BABL TOKENS ON BEHALF OF TOKEN.OWNER()
    it('Owner Should approve the allowance of 31% of 1M tokens to Time Lock Registry for vesting but keep balance without change', async function () {
      // Approve 310_000e18 tokens from owner to Time Lock Registry
      await bablToken.approve(timeLockRegistry.address, ethers.utils.parseEther('310000'));
      const ownerBalance = await bablToken.balanceOf(owner.address);
      expect(await bablToken.totalSupply()).to.equal(ownerBalance);

      // Check allowance has been done
      const allowSigner1 = await bablToken.allowance(owner.address, timeLockRegistry.address);
      expect(allowSigner1).to.equal(ethers.utils.parseEther('310000'));
    });

    it('Time Lock Registry should properly register 1 Team Member, 1 Advisor and 1 Investor with its own vesting conditions', async function () {
      // First of all there should be an allowance from BABL Token Owner into the Registry
      // Approve 310_000e18 tokens from owner to Time Lock Registry
      await bablToken.approve(timeLockRegistry.address, ethers.utils.parseEther('310000'));
      const ownerBalance = await bablToken.balanceOf(owner.address);
      expect(await bablToken.totalSupply()).to.equal(ownerBalance);

      // Check allowance has been done
      const allowSigner1 = await bablToken.allowance(owner.address, timeLockRegistry.address);
      expect(allowSigner1).to.equal(ethers.utils.parseEther('310000'));

      // Register 1 Team Member with 26_000 BABL 1Y cliff and 4Y of Vesting
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await timeLockRegistry.register(signer1.address, ethers.utils.parseEther('26000'), true, 1614618000);
      const userSigner1Registered = await timeLockRegistry.checkVesting(signer1.address);
      const userSigner1RegisteredTeam = userSigner1Registered[0];
      const userSigner1RegisteredCliff = userSigner1Registered[1];
      const userSigner1RegisteredVestingBegin = userSigner1Registered[2];
      const userSigner1RegisteredVestingEnd = userSigner1Registered[3];
      expect(userSigner1RegisteredTeam).to.equal(true);
      expect(userSigner1RegisteredCliff).to.equal(true);
      expect(userSigner1RegisteredVestingBegin).to.equal(1614618000);
      expect(userSigner1RegisteredVestingEnd).to.equal(1614618000 + ONE_DAY_IN_SECONDS * 365 * 4);

      // Register 1 Advisor with 2_000 BABL 1Y cliff and 4Y of Vesting
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await timeLockRegistry.register(signer2.address, ethers.utils.parseEther('2000'), true, 1614618000);
      const userSigner2Registered = await timeLockRegistry.checkVesting(signer2.address);
      const userSigner2RegisteredTeam = userSigner2Registered[0];
      const userSigner2RegisteredCliff = userSigner2Registered[1];
      const userSigner2RegisteredVestingBegin = userSigner2Registered[2];
      const userSigner2RegisteredVestingEnd = userSigner2Registered[3];
      expect(userSigner2RegisteredTeam).to.equal(true);
      expect(userSigner2RegisteredCliff).to.equal(true);
      expect(userSigner2RegisteredVestingBegin).to.equal(1614618000);
      expect(userSigner2RegisteredVestingEnd).to.equal(1614618000 + ONE_DAY_IN_SECONDS * 365 * 4);

      // Register 1 Investor with 10_000 BABL no Cliff and 3Y of Vesting
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await timeLockRegistry.register(signer3.address, ethers.utils.parseEther('10000'), false, 1614618000);
      const userSigner3Registered = await timeLockRegistry.checkVesting(signer3.address);
      const userSigner3RegisteredTeam = userSigner3Registered[0];
      const userSigner3RegisteredCliff = userSigner3Registered[1];
      const userSigner3RegisteredVestingBegin = userSigner3Registered[2];
      const userSigner3RegisteredVestingEnd = userSigner3Registered[3];
      expect(userSigner3RegisteredTeam).to.equal(false);
      expect(userSigner3RegisteredCliff).to.equal(false);
      expect(userSigner3RegisteredVestingBegin).to.equal(1614618000);
      expect(userSigner3RegisteredVestingEnd).to.equal(1614618000 + ONE_DAY_IN_SECONDS * 365 * 3);
    });

    it('Should cancel a registration of an Advisor before tokens are claimed', async function () {
      // Register 1 Advisor with 2_000 BABL 1Y cliff and 4Y of Vesting
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await timeLockRegistry.register(signer2.address, ethers.utils.parseEther('2000'), true, 1614618000);
      const userSigner2Registered = await timeLockRegistry.checkVesting(signer2.address);
      const userSigner2RegisteredTeam = userSigner2Registered[0];
      const userSigner2RegisteredCliff = userSigner2Registered[1];
      const userSigner2RegisteredVestingBegin = userSigner2Registered[2];
      const userSigner2RegisteredVestingEnd = userSigner2Registered[3];
      expect(userSigner2RegisteredTeam).to.equal(true);
      expect(userSigner2RegisteredCliff).to.equal(true);
      expect(userSigner2RegisteredVestingBegin).to.equal(1614618000);
      expect(userSigner2RegisteredVestingEnd).to.equal(1614618000 + ONE_DAY_IN_SECONDS * 365 * 4);

      // Cancel the registration of above registered Advisor before the claim is done
      const ownerSignerBalance = await bablToken.balanceOf(owner.address);
      const registryBalance = await bablToken.balanceOf(timeLockRegistry.address);
      const newOwnerSignerBalance = BigInt(ownerSignerBalance) + BigInt(registryBalance);

      await timeLockRegistry.cancelRegistration(signer2.address);

      expect(newOwnerSignerBalance).to.equal(await bablToken.balanceOf(owner.address));
      expect(await bablToken.balanceOf(timeLockRegistry.address)).to.equal(0);
      await expect(timeLockRegistry.cancelRegistration(signer2.address)).to.be.revertedWith('Not registered');
    });

    it('Should cancel all delivered tokens after a Team Member left before cliff', async function () {
      // Register 1 Team Member with 26_000 BABL 1Y cliff and 4Y of Vesting
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await timeLockRegistry.register(signer1.address, ethers.utils.parseEther('26000'), true, 1614618000);
      const userSigner1Registered = await timeLockRegistry.checkVesting(signer1.address);
      const userSigner1RegisteredTeam = userSigner1Registered[0];
      const userSigner1RegisteredCliff = userSigner1Registered[1];
      const userSigner1RegisteredVestingBegin = userSigner1Registered[2];
      const userSigner1RegisteredVestingEnd = userSigner1Registered[3];
      expect(userSigner1RegisteredTeam).to.equal(true);
      expect(userSigner1RegisteredCliff).to.equal(true);
      expect(userSigner1RegisteredVestingBegin).to.equal(1614618000);
      expect(userSigner1RegisteredVestingEnd).to.equal(1614618000 + ONE_DAY_IN_SECONDS * 365 * 4);

      // Tokens are claimed by the Team Member and the registration is deleted in Time Lock Registry
      await bablToken.connect(signer1).claimMyTokens();
      // We move ahead 30 days
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 30]);

      const userSigner1Balance = await bablToken.balanceOf(signer1.address);
      const userSigner1LockedBalance = await bablToken.viewLockedBalance(signer1.address);
      expect(userSigner1Balance).to.equal(ethers.utils.parseEther('26000'));
      await expect(timeLockRegistry.cancelRegistration(signer2.address)).to.be.revertedWith('Not registered');

      // Cancel the registration of above registered Team Member before the cliff is passed

      const registryBalance = await bablToken.balanceOf(timeLockRegistry.address);

      const newRegistrySignerBalance = registryBalance.add(userSigner1LockedBalance);
      const newUserSigner1Balance = userSigner1Balance.sub(userSigner1LockedBalance);

      await timeLockRegistry.cancelDeliveredTokens(signer1.address);

      // console.log(`%s is the new balance of the registry, %s is the old balance`, newRegistrySignerBalance, registryBalance);
      // console.log(`%s is the new balance of the signer user1, %s is its old balance`, newUserSigner1Balance, userSigner1Balance);

      expect(await bablToken.balanceOf(timeLockRegistry.address)).to.equal(newRegistrySignerBalance);
      expect(await bablToken.balanceOf(signer1.address)).to.equal(newUserSigner1Balance);

      await expect(timeLockRegistry.cancelRegistration(signer1.address)).to.be.revertedWith('Not registered');
    });
  });

  describe('Minting', function () {
    it('Should fail a try of minting new tokens by an address that is not the owner', async function () {
      try {
        const totalSupply = await bablToken.totalSupply();
        const value2 = ethers.utils.parseEther('1000000');
        const result = await bablToken.mint.call({ from: signer1 });
        assert.equal(result.toString(), owner);
        await expect(bablToken.connect(signer1).mint(signer1, value)).to.be.revertedWith('Only owner');

        // TOTAL_SUPPLY shouldn't have changed.
        expect(totalSupply).to.equal(value2);
      } catch (e) {
        // console.log(`%s is not owner, which is %s`, userSigner1.address, ownerSigner.address);
      }
    });

    it('Should fail when trying to mint new tokens beyond MAX_SUPPLY', async function () {
      const maxSupply = await bablToken.maxSupply();
      const totalSupply = await bablToken.totalSupply();

      // We define the the limit + 1 to overflow the mint beyond maxSupply
      const value = BigInt(maxSupply) - BigInt(totalSupply) + ethers.utils.parseEther('1');

      await expect(bablToken.mint(signer1.address, value)).to.be.revertedWith('BABLToken::mint: max supply exceeded');
      // console.log(`%s is total supply, which is equal to the max supply %s`,totalSupply , maxSupply);

      // Total_Supply shouldn't have changed.
      expect(totalSupply).to.equal(await bablToken.totalSupply());
    });
  });

  describe('MAX_SUPPLY Change', function () {
    it('Should fail a try of changing MAX_SUPPLY from an address different from the owner', async function () {
      try {
        const maxSupply = await bablToken.maxSupply();
        const NEW_MAX_SUPPLY = maxSupply + 1;
        const result = await bablToken.changeMaxSupply.call({ from: signer1 });
        assert.equal(result.toString(), owner);
        await expect(bablToken.connect(signer1).changeMaxSupply(NEW_MAX_SUPPLY, 251596800)).to.be.revertedWith(
          'Only owner',
        );

        // MAX_SUPPLY shouldn't have changed.
        expect(maxSupply).to.equal(NEW_MAX_SUPPLY);
      } catch (e) {
        // console.log(`%s is not owner, which is %s`, userSigner1.address, ownerSigner.address);
      }
    });

    it('Should fail a try of changing MAX_SUPPLY before 8 years', async function () {
      const OLD_MAX_SUPPLY = await bablToken.maxSupply();

      // Try to change MAX_SUPPLY by a new number before 8 years
      // `require` will evaluate false and revert the transaction if MAX_SUPPLY is reached.
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1100000');
      const value2 = ethers.utils.parseEther('1000000');
      await expect(bablToken.changeMaxSupply(NEW_MAX_SUPPLY, 251596800)).to.be.revertedWith(
        'BABLToken::changeMaxSupply: a change on MAX_SUPPLY not allowed until 8 years after deployment',
      );

      // MAX_SUPPLY shouldn't have changed.
      expect(OLD_MAX_SUPPLY).to.equal(value2);
    });

    it('Should fail a try of changing MAX_SUPPLY after 8 years by an amount below the current MAX_SUPPLY', async function () {
      const OLD_MAX_SUPPLY = await bablToken.maxSupply();

      // Try to change MAX_SUPPLY by a new number after 8 years by a lower amount
      // `require` will evaluate false and revert the transaction if the new value is below the current MAX_SUPPLY.
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('900000'); // 900_000e18
      const value2 = ethers.utils.parseEther('1000000');
      // Traveling on time >8 years ahead
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 365 * 8]);
      await expect(bablToken.changeMaxSupply(NEW_MAX_SUPPLY, 251596800)).to.be.revertedWith(
        'BABLToken::changeMaxSupply: changeMaxSupply should be higher than previous value',
      );

      // MAX_SUPPLY shouldn't have changed.
      expect(OLD_MAX_SUPPLY).to.equal(value2);
    });

    it('Should fail a try of changing MAX_SUPPLY after 8 years by an amount above the cap of 5%', async function () {
      const OLD_MAX_SUPPLY = await bablToken.maxSupply();

      // Try to change MAX_SUPPLY by a new number after 8 years by a lower amount
      // `require` will evaluate false and revert the transaction if the new value is above the cap (5%) the current MAX_SUPPLY.
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1150000'); // 1_150_000e18
      // Traveling on time >8 years ahead
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 365 * 8]);
      await expect(bablToken.changeMaxSupply(NEW_MAX_SUPPLY, 251596800)).to.be.revertedWith(
        'BABLToken::changeMaxSupply: exceeded of allowed 5% cap',
      );

      const value2 = await bablToken.maxSupply();

      // MAX_SUPPLY shouldn't have changed.
      expect(OLD_MAX_SUPPLY).to.equal(value2);
    });
  });
});
