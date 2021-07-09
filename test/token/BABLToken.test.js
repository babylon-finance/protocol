const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_ETH, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('../../lib/constants');
const { increaseTime } = require('../utils/test-helpers');

const { setupTests } = require('../fixtures/GardenFixture');

const OWNER_BALANCE = ONE_ETH.mul(23000);
const REGISTRY_BALANCE = ONE_ETH.mul(305000);

describe('BABLToken contract', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let timeLockRegistry;
  let now;
  let future;

  beforeEach(async () => {
    ({ owner, bablToken, timeLockRegistry, signer1, signer2, signer3 } = await setupTests()());
    const block = await ethers.provider.getBlock();
    now = block.timestamp;
    future = now + ONE_DAY_IN_SECONDS * 365 * 9.01; // newMAxSupplyAllowedAfter has to be at least 365days ahead of previous time (previous time was 8 years ahead of first mint)
  });

  describe('Deployment', function () {
    it('should successfully deploy BABLToken contract', async function () {
      const deployedc = await bablToken.deployed();
      expect(!!deployedc).to.equal(true);
    });

    it('should successfully deploy TimeLockRegistry contract', async function () {
      const deployedc2 = await timeLockRegistry.deployed();
      expect(!!deployedc2).to.equal(true);
    });

    it('should successfully have assigned the TimeLockRegistry address to BABLToken contract', async function () {
      const addressRegistry = await bablToken.timeLockRegistry();
      expect(timeLockRegistry.address).to.equal(addressRegistry);
    });

    it('Should set the right owner to BABL', async function () {
      expect(await bablToken.owner()).to.equal(owner.address);
    });

    it('Should set the right owner to Registry', async function () {
      expect(await timeLockRegistry.owner()).to.equal(owner.address);
    });

    it('multisig should have 16k tokens after deployment', async function () {
      const ownerBalance = await bablToken.balanceOf(owner.address);
      expect(ownerBalance).to.equal(ONE_ETH.mul(23000));
    });
  });

  describe('Transfers', function () {
    it('should fail if trying to transfer any tokens between addresses which is not TimeLockRegistry', async function () {
      const ownerBalance = await bablToken.balanceOf(owner.address);
      expect(ownerBalance).to.equal(OWNER_BALANCE);

      const value = ethers.utils.parseEther('1000');
      await expect(bablToken.connect(owner).transfer(signer1.address, value)).to.be.revertedWith('revert BAB#062');
      await expect(bablToken.connect(owner).transfer(signer2.address, value)).to.be.revertedWith('revert BAB#062');

      // It should work if from/to is the TimeLockRegistry
      await expect(bablToken.connect(owner).transfer(timeLockRegistry.address, value)).not.to.be.reverted;
    });

    it('can"t transfer to zero address', async function () {
      const value = ethers.utils.parseEther('260000');
      await expect(bablToken.connect(owner).transfer(ADDRESS_ZERO, value)).to.be.revertedWith(
        'revert TimeLockedToken:: _transfer: cannot transfer to the zero address',
      );
    });

    it('Should transfer tokens to TimeLockRegistry without the boolean activated', async function () {
      const value = ethers.utils.parseEther('1000');

      await expect(bablToken.connect(owner).transfer(timeLockRegistry.address, value)).not.to.be.reverted;

      const timeLockRegistryBalance = await bablToken.balanceOf(timeLockRegistry.address);

      expect(timeLockRegistryBalance).to.be.equal(value.add(REGISTRY_BALANCE));
    });

    it('can enable transfers', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      const value = ethers.utils.parseEther('100');
      await bablToken.connect(owner).transfer(signer1.address, value);
      const signer1Balance = await bablToken.balanceOf(signer1.address);
      expect(signer1Balance).to.equal(ethers.utils.parseEther('100'));
    });

    it('can NOT disabled BABL transfers after enabling them', async function () {
      await bablToken.connect(owner).enableTokensTransfers();
      await expect(bablToken.connect(owner).disableTokensTransfers()).to.be.revertedWith('BABL must flow');

      const value = ethers.utils.parseEther('1000');
      await bablToken.connect(owner).transfer(signer1.address, value);
      const signer1Balance = await bablToken.balanceOf(signer1.address);
      expect(signer1Balance).to.equal(ethers.utils.parseEther('1000'));
    });

    it('Should transfer tokens between accounts', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      const value = ethers.utils.parseEther('1000');
      await bablToken.connect(owner).transfer(signer1.address, value);

      const addr1Balance = await bablToken.balanceOf(signer1.address);
      expect(addr1Balance).to.equal(value);

      const value2 = ethers.utils.parseEther('500');
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
      const value = ethers.utils.parseEther('1000');

      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await bablToken.connect(owner).transfer(signer1.address, value);
      const value2 = ethers.utils.parseEther('2000');
      await bablToken.connect(owner).transfer(signer2.address, value2);

      // Check balances.
      const totalsent = ethers.utils.parseEther('3000');
      const finalOwnerBalance = await bablToken.balanceOf(owner.address);
      const differenceBalance = BigInt(initialOwnerBalance) - BigInt(totalsent);
      expect(finalOwnerBalance).to.equal(differenceBalance);

      const addr1Balance = await bablToken.balanceOf(signer1.address);
      expect(addr1Balance).to.equal(value);

      const addr2Balance = await bablToken.balanceOf(signer2.address);
      expect(addr2Balance).to.equal(value2);
    });

    it('Should fail it trying to approve the zero address', async function () {
      await expect(bablToken.approve(ADDRESS_ZERO, ethers.utils.parseEther('305000'))).to.be.revertedWith(
        'TimeLockedToken::approve: spender cannot be zero address',
      );
    });

    it('Should fail it trying to approve itself', async function () {
      await expect(
        bablToken.connect(owner).approve(owner.address, ethers.utils.parseEther('305000')),
      ).to.be.revertedWith('TimeLockedToken::approve: spender cannot be the msg.sender');
    });

    it('Should fail if trying to increase allowance to an address above the unlocked balance', async function () {
      await expect(
        bablToken.connect(owner).increaseAllowance(signer2.address, ethers.utils.parseEther('305000')),
      ).to.be.revertedWith('TimeLockedToken::increaseAllowance:Not enough unlocked tokens');
    });
    it('Should fail if trying to increase allowance to an address above the unlocked balance in small chunks', async function () {
      await timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('10'), false, now);
      await bablToken.connect(signer1).claimMyTokens();
      await increaseTime(ONE_DAY_IN_SECONDS * 366);
      await expect(
        bablToken.connect(signer1).increaseAllowance(signer2.address, ethers.utils.parseEther('4')),
      ).to.be.revertedWith('TimeLockedToken::increaseAllowance:Not enough unlocked tokens');
      await expect(bablToken.connect(signer1).increaseAllowance(signer2.address, ethers.utils.parseEther('2'))).not.to
        .be.reverted;
      await expect(
        bablToken.connect(signer1).increaseAllowance(signer2.address, ethers.utils.parseEther('2')),
      ).to.be.revertedWith('TimeLockedToken::increaseAllowance:Not enough unlocked tokens');
    });

    it('Should fail if trying to increase allowance to the zero address', async function () {
      await expect(
        bablToken.connect(owner).increaseAllowance(ADDRESS_ZERO, ethers.utils.parseEther('16000')),
      ).to.be.revertedWith('TimeLockedToken::increaseAllowance:Spender cannot be zero address');
    });

    it('Should fail if trying to increase allowance to itself', async function () {
      await expect(
        bablToken.connect(owner).increaseAllowance(owner.address, ethers.utils.parseEther('16000')),
      ).to.be.revertedWith('TimeLockedToken::increaseAllowance:Spender cannot be the msg.sender');
    });

    it('Should increase allowance properly', async function () {
      await bablToken.connect(owner).increaseAllowance(signer1.address, ethers.utils.parseEther('16000'));
      const allowSigner1 = await bablToken.allowance(owner.address, signer1.address);
      expect(allowSigner1).to.equal(ethers.utils.parseEther('16000'));
    });

    it('Should fail if trying to decrease allowance to the zero address', async function () {
      await expect(bablToken.decreaseAllowance(ADDRESS_ZERO, ethers.utils.parseEther('16000'))).to.be.revertedWith(
        'TimeLockedToken::decreaseAllowance:Spender cannot be zero address',
      );
    });

    it('Should fail if trying to decrease allowance below 0 (underflow condition)', async function () {
      await bablToken.connect(owner).increaseAllowance(signer1.address, ethers.utils.parseEther('16000'));
      await expect(
        bablToken.connect(owner).decreaseAllowance(signer1.address, ethers.utils.parseEther('305001')),
      ).to.be.revertedWith('TimeLockedToken::decreaseAllowance:Underflow condition');
    });

    it('Should fail if trying to decrease allowance to itself', async function () {
      await bablToken.connect(owner).increaseAllowance(signer1.address, ethers.utils.parseEther('16000'));
      await expect(
        bablToken.connect(owner).connect(signer1).decreaseAllowance(signer1.address, ethers.utils.parseEther('16000')),
      ).to.be.revertedWith('TimeLockedToken::decreaseAllowance:Spender cannot be the msg.sender');
    });

    it('Should fail if trying to decrease allowance to Time Lock Registry', async function () {
      await bablToken.connect(owner).increaseAllowance(timeLockRegistry.address, ethers.utils.parseEther('16000'));
      await expect(
        bablToken.connect(owner).decreaseAllowance(timeLockRegistry.address, ethers.utils.parseEther('16000')),
      ).to.be.revertedWith('TimeLockedToken::decreaseAllowance:cannot decrease allowance to timeLockRegistry');
    });

    it('Should properly decrease allowance to an address allowed earlier which is not timelockregistry', async function () {
      await bablToken.connect(owner).increaseAllowance(signer1.address, ethers.utils.parseEther('16000'));
      const allowSigner1 = await bablToken.allowance(owner.address, signer1.address);
      expect(allowSigner1).to.equal(ethers.utils.parseEther('16000'));
      await bablToken.connect(owner).decreaseAllowance(signer1.address, ethers.utils.parseEther('16000'));
      const allowSigner2 = await bablToken.allowance(owner.address, signer1.address);
      expect(allowSigner2).to.equal(ethers.utils.parseEther('0'));
    });

    it('Should fail a transfer to the zero address', async function () {
      await expect(bablToken.transfer(ADDRESS_ZERO, ethers.utils.parseEther('1'))).to.be.revertedWith(
        'TimeLockedToken:: _transfer: cannot transfer to the zero address',
      );
    });

    it('Should fail a transfer to the BABL Smartcontract itself', async function () {
      await expect(bablToken.transfer(bablToken.address, ethers.utils.parseEther('1'))).to.be.revertedWith(
        'TimeLockedToken:: _transfer: do not transfer tokens to the token contract itself',
      );
    });

    it('Should fail a transfer without enough balance', async function () {
      await expect(bablToken.transfer(signer1.address, ethers.utils.parseEther('1000001'))).to.be.revertedWith(
        'TimeLockedToken:: _transfer: insufficient balance',
      );
    });

    it('Should fail a transfer without enough unlocked balance', async function () {
      await timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('26000'), true, now);
      await bablToken.connect(signer1).claimMyTokens();
      await expect(
        bablToken.connect(signer1).transfer(signer2.address, ethers.utils.parseEther('1000')),
      ).to.be.revertedWith('TimeLockedToken:: _transfer: attempting to transfer locked funds');
    });
  });

  describe('Voting Power for Governance', function () {
    it('Should get voting power equivalent to its balance if it delegates in itself', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();

      await bablToken.connect(owner).transfer(signer1.address, ethers.utils.parseEther('16000'));

      await bablToken.connect(signer1).delegate(signer1.address); // Own delegation

      const signer1Balance = await bablToken.balanceOf(signer1.address);

      const votesSigner1 = await bablToken.getCurrentVotes(signer1.address);

      await expect(signer1Balance).to.be.equal(votesSigner1);
    });

    it('Should update voting power when transferring tokens between accounts', async function () {
      await bablToken.connect(signer1).delegate(signer1.address); // Own delegation
      await bablToken.connect(signer2).delegate(signer2.address); // Own delegation
      //
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await bablToken.connect(owner).transfer(signer1.address, ethers.utils.parseEther('16000'));

      const signer1Balance = await bablToken.balanceOf(signer1.address);
      const votesSigner1 = await bablToken.getCurrentVotes(signer1.address);

      expect(signer1Balance).to.equal(votesSigner1.toString());

      await bablToken.connect(signer1).transfer(signer2.address, ethers.utils.parseEther('10000'));
      const votesSigner12 = await bablToken.getCurrentVotes(signer1.address);
      const value = ethers.utils.parseEther('10000');
      await expect(votesSigner12).to.equal(votesSigner1.sub(value));
      const signer2Balance = await bablToken.balanceOf(signer2.address);
      const votesSigner2 = await bablToken.getCurrentVotes(signer2.address);

      expect(signer2Balance).to.equal(votesSigner2);
      expect(signer2Balance).to.equal(ethers.utils.parseEther('10000'));
    });
  });

  describe('Time Lock Registry for Vesting', function () {
    it('Should fail as Time Lock Registry cannot registry the zero address', async function () {
      // Try to register a zero address
      await expect(
        timeLockRegistry.connect(owner).register(ADDRESS_ZERO, ethers.utils.parseEther('26000'), true, now),
      ).to.be.revertedWith('TimeLockRegistry::register: cannot register the zero address');
    });
    it('Should get 0 lockedAmount for a non vested user', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await bablToken.connect(owner).transfer(signer2.address, ethers.utils.parseEther('1'));
      await expect((await bablToken.viewLockedBalance(signer2.address)).toString()).to.be.equal('0');
      await expect((await bablToken.balanceOf(signer2.address)).toString()).to.equal(ethers.utils.parseEther('1'));
    });
    it('Should fail as Time Lock Registry contract address cannot be registered itself', async function () {
      await expect(
        timeLockRegistry.connect(owner).register(timeLockRegistry.address, ethers.utils.parseEther('26000'), true, now),
      ).to.be.revertedWith('TimeLockRegistry::register: Time Lock Registry contract cannot be an investor');
    });

    it('should fail if the distribution amount to register equals 0', async function () {
      await expect(
        timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('0'), true, now),
      ).to.be.revertedWith('TimeLockRegistry::register: Distribution = 0');
    });

    it('should fail if the account is already registered', async function () {
      const registeredDistribution = await timeLockRegistry.checkRegisteredDistribution(signer1.address);
      expect(registeredDistribution.toString()).to.equal(ethers.utils.parseEther('0'));
      await timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('26000'), true, now);

      await expect(
        timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('26000'), true, now),
      ).to.be.revertedWith('TimeLockRegistry::register:Distribution for this address is already registered');
    });

    it('should fail if the transfer fails', async function () {
      await timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('26000'), true, now);

      await expect(
        timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('1000001'), true, now),
      ).to.be.revertedWith('TimeLockRegistry::register:Distribution for this address is already registered');
    });

    it('Should fail when trying to cancel a registration that is not registered', async function () {
      await expect(timeLockRegistry.connect(owner).cancelRegistration(signer2.address)).to.be.revertedWith(
        'Not registered',
      );
    });

    it('Should cancel a registration of an Advisor before tokens are claimed', async function () {
      // Register 1 Advisor with 2_000 BABL 4Y of Vesting
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await timeLockRegistry.connect(owner).register(signer2.address, ethers.utils.parseEther('2000'), true, now);

      // Cancel the registration of above registered Advisor before the claim is done
      await timeLockRegistry.connect(owner).cancelRegistration(signer2.address);

      const [isTeam, vestingBegins, vestingEnds] = await timeLockRegistry.connect(owner).checkVesting(signer1.address);

      expect(isTeam).to.equal(false);
      expect(vestingBegins).to.equal(0);
      expect(vestingEnds).to.equal(0);
    });

    it('Time Lock Registry should properly register 1 Team Member, 1 Advisor and 1 Investor with its own vesting conditions', async function () {
      await timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('16000'), true, now);

      let [isTeam, vestingBegins, vestingEnds] = await timeLockRegistry.connect(owner).checkVesting(signer1.address);

      expect(isTeam).to.equal(true);
      expect(vestingBegins).to.equal(now);
      expect(vestingEnds).to.equal(now + ONE_DAY_IN_SECONDS * 365 * 4);
      await timeLockRegistry.connect(owner).register(signer2.address, ethers.utils.parseEther('2000'), true, now);

      [isTeam, vestingBegins, vestingEnds] = await timeLockRegistry.checkVesting(signer2.address);

      expect(isTeam).to.equal(true);
      expect(vestingBegins).to.equal(now);
      expect(vestingEnds).to.equal(now + ONE_DAY_IN_SECONDS * 365 * 4);

      await timeLockRegistry.connect(owner).register(signer3.address, ethers.utils.parseEther('10000'), false, now);

      [isTeam, vestingBegins, vestingEnds] = await timeLockRegistry.checkVesting(signer3.address);

      expect(isTeam).to.equal(false);
      expect(vestingBegins).to.equal(now);
      expect(vestingEnds).to.equal(now + ONE_DAY_IN_SECONDS * 365 * 3);
    });

    it('Should cancel all delivered tokens after a Team Member left', async function () {
      await timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('1000'), true, now);

      // Tokens are claimed by the Team Member and the registration is deleted in Time Lock Registry
      await bablToken.connect(signer1).claimMyTokens();
      // We move ahead 30 days
      await increaseTime(ONE_DAY_IN_SECONDS * 30);

      const userSigner1LockedBalance = await bablToken.viewLockedBalance(signer1.address);

      expect(userSigner1LockedBalance).to.equal(ethers.utils.parseEther('1000'));

      // Cancel the registration of above registered Team Member
      await timeLockRegistry.connect(owner).cancelDeliveredTokens(signer1.address);

      expect(await bablToken.balanceOf(timeLockRegistry.address)).to.equal(REGISTRY_BALANCE);
      expect(await bablToken.balanceOf(signer1.address)).to.equal(0);
    });

    it('Should fail trying to cancel delivered tokens to an investor', async function () {
      await timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('26000'), false, now);

      // Tokens are claimed by the Team Member and the registration is deleted in Time Lock Registry
      await bablToken.connect(signer1).claimMyTokens();
      // We move ahead 30 days
      await increaseTime(ONE_DAY_IN_SECONDS * 30);

      const userSigner1LockedBalance = await bablToken.viewLockedBalance(signer1.address);

      expect(userSigner1LockedBalance).to.equal(ethers.utils.parseEther('26000'));

      // Try to cancel the registration of above registered Investor
      await expect(timeLockRegistry.connect(owner).cancelDeliveredTokens(signer1.address)).to.be.revertedWith(
        'TimeLockedToken::cancelTokens:cannot cancel locked tokens to Investors',
      );
    });

    it('Should fail if a cancel on delivered tokens is from the owner', async function () {
      await timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('26000'), true, now);

      // Tokens are claimed by the Team Member and the registration is deleted in Time Lock Registry
      await bablToken.connect(signer1).claimMyTokens();
      // We move ahead 30 days
      await increaseTime(ONE_DAY_IN_SECONDS * 30);

      const userSigner1LockedBalance = await bablToken.viewLockedBalance(signer1.address);

      expect(userSigner1LockedBalance).to.equal(ethers.utils.parseEther('26000'));

      // Cancel the registration of above registered Team Member
      await expect(bablToken.cancelVestedTokens(signer1.address)).to.be.revertedWith(
        'TimeLockedToken:: onlyTimeLockRegistry: can only be executed by TimeLockRegistry',
      );
    });

    it('Should fail if a cancel on delivered tokens is from a malicious address', async function () {
      // Register 1 Team Member with 26_000 BABL 4Y of Vesting
      await timeLockRegistry.connect(owner).register(signer1.address, ethers.utils.parseEther('26000'), true, now);

      // Tokens are claimed by the Team Member and the registration is deleted in Time Lock Registry
      await bablToken.connect(signer1).claimMyTokens();
      // We move ahead 30 days
      await increaseTime(ONE_DAY_IN_SECONDS * 30);

      const userSigner1LockedBalance = await bablToken.viewLockedBalance(signer1.address);

      expect(userSigner1LockedBalance).to.equal(ethers.utils.parseEther('26000'));

      // Cancel the registration of above registered Team Member
      await expect(bablToken.connect(signer2).cancelVestedTokens(signer1.address)).to.be.revertedWith(
        'TimeLockedToken:: onlyTimeLockRegistry: can only be executed by TimeLockRegistry',
      );
    });
  });

  describe('Minting', function () {
    it('Should fail a try of minting new tokens by an address that is not the owner', async function () {
      try {
        const totalSupply = await bablToken.totalSupply();
        const value2 = ethers.utils.parseEther('1000000');
        await bablToken.mint.call({ from: signer1 });

        await expect(bablToken.connect(signer1).mint(signer1, value2)).to.be.revertedWith('Only owner');

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
      const value = maxSupply[0].sub(totalSupply).add(ONE_ETH);

      await expect(bablToken.connect(owner).mint(signer1.address, value)).to.be.revertedWith(
        'BABLToken::mint: max supply exceeded',
      );

      // Total_Supply shouldn't have changed.
      expect(totalSupply).to.equal(await bablToken.totalSupply());
    });

    it('Should fail when trying to mint new tokens before the first epoch (8 years)', async function () {
      await bablToken.maxSupply();
      await bablToken.totalSupply();

      await expect(bablToken.connect(owner).mint(signer1.address, 0)).to.be.revertedWith(
        'BABLToken::mint: minting not allowed after the FIRST_EPOCH_MINT has passed >= 8 years',
      );
    });

    it('Should fail when trying to mint 0 tokens', async function () {
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);

      await expect(bablToken.connect(owner).mint(signer1.address, 0)).to.be.revertedWith(
        'BABLToken::mint: mint should be higher than zero',
      );
    });

    it('Should fail when trying to mint before mintingAllowedAfter', async function () {
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1050000'); // 1_150_000e18
      // Traveling on time >8 years ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);

      await bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future);

      await expect(bablToken.connect(owner).mint(signer1.address, 1)).to.be.not.reverted;
      await expect(bablToken.connect(owner).mint(signer1.address, 1)).to.be.revertedWith(
        'BABLToken::mint: minting not allowed yet because mintingAllowedAfter',
      );
    });

    it('Should fail when trying to mint to the 0 (zero) address', async function () {
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1050000'); // 1_150_000e18
      // Traveling on time >8 years ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);
      await expect(bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future));
      await expect(bablToken.connect(owner).mint(ADDRESS_ZERO, ethers.utils.parseEther('1'))).to.be.revertedWith(
        'BABLToken::mint: cannot transfer to the zero address',
      );
    });

    it('Should fail when trying to mint to the address of the own BABL Token smartcontract', async function () {
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1050000'); // 1_150_000e18
      // Traveling on time >8 years ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);
      await expect(bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future));

      await expect(bablToken.connect(owner).mint(bablToken.address, ethers.utils.parseEther('1'))).to.be.revertedWith(
        'BABLToken::mint: cannot mint to the address of this contract',
      );
    });

    it('Should fail when trying to mint above Cap limit of 2%', async function () {
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1050000'); // 1_150_000e18
      // Traveling on time >8 years ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);
      await expect(bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future));

      await expect(bablToken.connect(owner).mint(signer1.address, ethers.utils.parseEther('21000'))).to.be.revertedWith(
        'BABLToken::mint: exceeded mint cap of 2% of total supply',
      );
    });

    it('Should mint new tokens after 8 years equals to the Cap limit of 2%', async function () {
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1050000'); // 1_150_000e18
      // Traveling on time >8 years ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);
      await expect(bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future));

      await expect(bablToken.connect(owner).mint(signer1.address, ethers.utils.parseEther('20000'))).to.be.not.reverted;
      const signer1Balance = await bablToken.balanceOf(signer1.address);
      expect(signer1Balance).to.equal(ethers.utils.parseEther('20000'));
    });
  });

  describe('MAX_SUPPLY Change', function () {
    it('Should fail a try of changing MAX_SUPPLY from an address different from the owner', async function () {
      try {
        const maxSupply = await bablToken.maxSupply();
        const NEW_MAX_SUPPLY = maxSupply + 1;
        await bablToken.connect(signer1).changeMaxSupplyl();
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
      await expect(bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, 251596800)).to.be.revertedWith(
        'BABLToken::changeMaxSupply: a change on maxSupplyAllowed not allowed until 8 years after deployment',
      );

      // MAX_SUPPLY shouldn't have changed.
      expect(OLD_MAX_SUPPLY[0]).to.equal(value2);
    });

    it('Should fail a try of changing MAX_SUPPLY before MaxSupplyAllowedAfter', async function () {
      // Try to change MAX_SUPPLY by a new number after 8 years by a lower amount
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1050000'); // 1_150_000e18
      // Traveling on time >8 years ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);
      await expect(bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future)); // June 2030 the 1st

      await expect(bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY + 100, future + 10)).to.be.revertedWith(
        'BABLToken::changeMaxSupply: a change on maxSupplyAllowed not allowed yet',
      );
    });

    it('Should fail a try of changing MAX_SUPPLY after 8 years by an amount below the current MAX_SUPPLY', async function () {
      const OLD_MAX_SUPPLY = await bablToken.maxSupply();

      // Try to change MAX_SUPPLY by a new number after 8 years by a lower amount
      // `require` will evaluate false and revert the transaction if the new value is below the current MAX_SUPPLY.
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('900000'); // 900_000e18
      const value2 = ethers.utils.parseEther('1000000');
      // Traveling on time >8 years ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);
      await expect(bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future)).to.be.revertedWith(
        'BABLToken::changeMaxSupply: changeMaxSupply should be higher than previous value',
      );

      // MAX_SUPPLY shouldn't have changed.
      expect(OLD_MAX_SUPPLY[0]).to.equal(value2);
    });

    it('Should fail a try of changing MAX_SUPPLY after 8 years by an amount above the cap of 5%', async function () {
      const OLD_MAX_SUPPLY = await bablToken.maxSupply();

      // Try to change MAX_SUPPLY by a new number after 8 years by a lower amount
      // `require` will evaluate false and revert the transaction if the new value is above the cap (5%) the current MAX_SUPPLY.
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1150000'); // 1_150_000e18
      // Traveling on time >8 years ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);
      await expect(bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future)).to.be.revertedWith(
        'BABLToken::changeMaxSupply: exceeded of allowed 5% cap',
      );

      const value2 = await bablToken.maxSupply();

      // MAX_SUPPLY shouldn't have changed.
      expect(OLD_MAX_SUPPLY[0]).to.equal(value2[0]);
    });

    it('Should fail a try of changing MAX_SUPPLY allowed after in less than a year from this moment', async function () {
      const OLD_MAX_SUPPLY = await bablToken.maxSupply();

      // Try to change MAX_SUPPLY by a new number after 8 years by a lower amount
      // `require` will evaluate false and revert the transaction if the new value is above the cap (5%) the current MAX_SUPPLY.
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1050000'); // 1_150_000e18
      // Traveling on time >8 years ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);
      await expect(
        bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future - 5 * ONE_DAY_IN_SECONDS),
      ).to.be.revertedWith(
        'BABLToken::changeMaxSupply: the newMaxSupplyAllowedAfter should be at least 1 year in the future',
      );

      const value2 = await bablToken.maxSupply();

      // MAX_SUPPLY shouldn't have changed.
      expect(OLD_MAX_SUPPLY[0]).to.equal(value2[0]);
    });

    it('Should change MAX_SUPPLY allowed and set-up a newMaxSupplyAllowedAfter', async function () {
      // Try to change MAX_SUPPLY by a new number after 8 years by a lower amount
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1050000'); // 1_150_000e18
      // Traveling on time >8 years ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);
      await expect(bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future));

      const value = await bablToken.maxSupply();

      // MAX_SUPPLY should have changed and its newMaxSupplyAllowedAfter accordingly.
      expect(value[0].toString()).to.equal(ethers.utils.parseEther('1050000'));
      expect(value[1]).to.equal(future);
    });

    it('Should fail when trying to change the MAX_SUPPLY after the FIRST EPOCH 8 years but before allowed after', async function () {
      // Traveling on time >8 years ahead
      await increaseTime(ONE_DAY_IN_SECONDS * 365 * 8);

      // Try to change MAX_SUPPLY by a new number after 8 years by a lower amount
      const NEW_MAX_SUPPLY = ethers.utils.parseEther('1050000'); // 1_150_000e18
      await expect(bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future)); // June 2030 the 1st
      await expect(
        bablToken.connect(owner).changeMaxSupply(NEW_MAX_SUPPLY, future + ONE_DAY_IN_SECONDS),
      ).to.be.revertedWith('BABLToken::changeMaxSupply: a change on maxSupplyAllowed not allowed yet');
    });
  });
});
