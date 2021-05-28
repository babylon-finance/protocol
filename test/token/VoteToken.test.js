const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_ETH, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('../../lib/constants');
const { increaseTime } = require('../utils/test-helpers');

const { setupTests } = require('../fixtures/GardenFixture');

describe('VoteToken contract', function () {
  let owner;
  let signer1;
  let signer2;
  let bablToken;

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

  describe('Votes', function () {
    it('Should get current votes of owner', async function () {
      const ownerBalance = await bablToken.balanceOf(owner.address);
      const votesOwner = await bablToken.getCurrentVotes(owner.address);
      await bablToken.connect(owner).delegate(owner.address); // Own delegation
      const votesOwner2 = await bablToken.getCurrentVotes(owner.address);
      await expect(votesOwner).to.be.equal('0');
      await expect(ownerBalance).to.be.equal(votesOwner2);
    });
    it('Should not get voting power by transfers if there is no delegation in themselves', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      const votesOwner1 = await bablToken.getCurrentVotes(owner.address);
      // Owner does not delegate in itself before transferring
      const ownerBalance = await bablToken.balanceOf(owner.address);

      await bablToken.connect(owner).transfer(signer1.address, ethers.utils.parseEther('10000'));
      const votesOwner2 = await bablToken.getCurrentVotes(owner.address);
      const votesSigner1 = await bablToken.getCurrentVotes(signer1.address);

      //await bablToken.connect(signer1).delegate(signer1.address); // Own delegation

      const signer1Balance = await bablToken.balanceOf(signer1.address);
      const ownerBalance2 = await bablToken.balanceOf(owner.address);

      await expect(ownerBalance2).to.be.equal(ownerBalance.sub(signer1Balance));
      // As there were no delegation, there are no real votes yet until they delegate in themselves using their balance
      await expect(votesOwner1).to.be.equal('0');
      await expect(votesOwner2).to.be.equal('0');
      await expect(votesSigner1).to.be.equal('0');
    });
    it('Should not inherit voting power if before a transfer there was not at least a delegation in itself', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await bablToken.connect(owner).delegate(owner.address); // Own delegation
      const votesOwner1 = await bablToken.getCurrentVotes(owner.address);
      // Owner does not delegate in itself before transferring
      const ownerBalance = await bablToken.balanceOf(owner.address);

      await bablToken.connect(owner).transfer(signer1.address, ethers.utils.parseEther('10000'));
      const votesOwner2 = await bablToken.getCurrentVotes(owner.address);
      const votesSigner1 = await bablToken.getCurrentVotes(signer1.address);

      //await bablToken.connect(signer1).delegate(signer1.address); // Own delegation

      const signer1Balance = await bablToken.balanceOf(signer1.address);
      const ownerBalance2 = await bablToken.balanceOf(owner.address);

      await expect(ownerBalance2).to.be.equal(ownerBalance.sub(signer1Balance));
      // As there were no delegation, there are no real votes yet until they delegate in themselves using their balance
      await expect(votesOwner1).to.be.equal(ethers.utils.parseEther('16000'));
      await expect(votesOwner2).to.be.equal(ethers.utils.parseEther('6000'));
      await expect(votesSigner1).to.be.equal('0');
    });
    it('Should inherit voting power if before a transfer there was at least a delegation in itself', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await bablToken.connect(owner).delegate(owner.address); // Own delegation - creates a checkpoint
      await bablToken.connect(signer1).delegate(signer1.address); // Own delegation - creates a checkpoint
      const votesOwner1 = await bablToken.getCurrentVotes(owner.address);
      // Owner does not delegate in itself before transferring
      const ownerBalance = await bablToken.balanceOf(owner.address);

      await bablToken.connect(owner).transfer(signer1.address, ethers.utils.parseEther('10000'));
      const votesOwner2 = await bablToken.getCurrentVotes(owner.address);
      const votesSigner1 = await bablToken.getCurrentVotes(signer1.address);

      //await bablToken.connect(signer1).delegate(signer1.address); // Own delegation

      const signer1Balance = await bablToken.balanceOf(signer1.address);
      const ownerBalance2 = await bablToken.balanceOf(owner.address);

      await expect(ownerBalance2).to.be.equal(ownerBalance.sub(signer1Balance));
      // As there were no delegation, there are no real votes yet until they delegate in themselves using their balance
      await expect(votesOwner1).to.be.equal(ethers.utils.parseEther('16000'));
      await expect(votesOwner2).to.be.equal(ethers.utils.parseEther('6000'));
      await expect(votesSigner1).to.be.equal(ethers.utils.parseEther('10000'));
    });
    it('Should fail if trying to get prior voting power within the same block', async function () {
      await bablToken.connect(owner).delegate(owner.address); // Own delegation - does not create checkpoint
      const block = await ethers.provider.getBlock();
      now = block.timestamp;
      //await increaseTime(ONE_DAY_IN_SECONDS);
      await expect(bablToken.getPriorVotes(owner.address, block.number)).to.be.revertedWith(
        'revert BABLToken::getPriorVotes: not yet determined',
      );
    });
    it('Should get priorVoting from a past checkpoint', async function () {
      const ownerBalance = await bablToken.balanceOf(owner.address);
      await bablToken.connect(owner).delegate(owner.address); // Own delegation - does not create checkpoint
      const block = await ethers.provider.getBlock();
      await increaseTime(ONE_DAY_IN_SECONDS);
      await bablToken.connect(owner).enableTokensTransfers();
      await bablToken.connect(owner).transfer(signer1.address, ethers.utils.parseEther('10000'));
      const signer1Balance = await bablToken.balanceOf(signer1.address);

      const block2 = await ethers.provider.getBlock();
      await increaseTime(ONE_DAY_IN_SECONDS);
      const votesOwner2 = await bablToken.getCurrentVotes(owner.address);

      expect(await bablToken.getPriorVotes(owner.address, block.number)).to.be.equal(ownerBalance);
      expect(await bablToken.getPriorVotes(owner.address, block2.number)).to.be.equal(ownerBalance.sub(signer1Balance));
      expect(await bablToken.getPriorVotes(owner.address, block2.number)).to.be.equal(votesOwner2);
    });
    it('Should get a delegatee from msg.sender', async function () {
      await bablToken.connect(owner).delegate(owner.address); // Own delegation - does not create checkpoint
      const delegatee = await bablToken.connect(owner).getMyDelegatee();
      await bablToken.connect(owner).delegate(signer1.address); // External delegation - creates a checkpoint
      const delegatee2 = await bablToken.connect(owner).getMyDelegatee();
      expect(delegatee).to.be.equal(owner.address);
      expect(delegatee2).to.be.equal(signer1.address);
    });
    it('Should get a delegatee from any account', async function () {
      await bablToken.connect(owner).delegate(signer1.address); // External delegation - creates a checkpoint
      const ownerDelegatee = await bablToken.connect(signer1).getDelegatee(owner.address);
      await bablToken.connect(signer1).delegate(signer1.address); // Own delegation - does not create checkpoint
      const signer1Delegatee = await bablToken.connect(owner).getDelegatee(signer1.address);
      expect(ownerDelegatee).to.be.equal(signer1.address);
      expect(signer1Delegatee).to.be.equal(signer1.address);
    });
    it('Should get the number of checkpoints of 2 users crossing delegations', async function () {
      await bablToken.connect(owner).delegate(signer1.address); // External delegation
      const ownerCheckpoints = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 0
      const signer1Checkpoints = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 1

      await bablToken.connect(owner).delegate(owner.address); // Own delegation
      const ownerCheckpoints2 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 1
      const signer1Checkpoints2 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 2

      await bablToken.connect(signer1).delegate(signer1.address); // Own delegation - no checkpoint as it has no balance
      const ownerCheckpoints3 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 1
      const signer1Checkpoints3 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 2

      expect(ownerCheckpoints.toString()).to.be.equal('0');
      expect(signer1Checkpoints.toString()).to.be.equal('1');
      expect(ownerCheckpoints2.toString()).to.be.equal('1');
      expect(signer1Checkpoints2.toString()).to.be.equal('2');
      expect(ownerCheckpoints3.toString()).to.be.equal('1');
      expect(signer1Checkpoints3.toString()).to.be.equal('2');
    });

    it('Should get the right number of checkpoints and votes despite different transfers and delegations between 3 users (w/o increasing time)', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await bablToken.connect(owner).transfer(signer1.address, ethers.utils.parseEther('1')); // Let's give stake to have the possibility to delegate
      await bablToken.connect(owner).transfer(signer2.address, ethers.utils.parseEther('2')); // Let's give stake to have the possibility to delegate

      // FIRST (OWN) DELEGATION
      await bablToken.connect(owner).delegate(owner.address);
      const ownerCheckpoints = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 1
      const signer1Checkpoints = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 0

      // SECOND DELEGATION
      await bablToken.connect(owner).delegate(signer1.address);
      const signer1Checkpoints2 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 2
      const ownerCheckpoints2 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 2

      // THIRD DELEGATION
      await bablToken.connect(owner).delegate(owner.address);
      const ownerCheckpoints3 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 3
      const signer1Checkpoints3 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 2

      // FOURTH DELEGATION
      await bablToken.connect(signer1).delegate(signer1.address);
      const ownerCheckpoints4 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 3
      const signer1Checkpoints4 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 3

      // FIFTH Try to exploit sub96 vs. balanceOf over a previous delegation with higher balance
      await bablToken.connect(owner).delegate(signer1.address);
      await bablToken.connect(signer2).transfer(owner.address, ethers.utils.parseEther('2')); // Transfers handles delegation properly
      const ownerCheckpoints5 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 4
      const signer1Checkpoints5 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 5

      // SIXTH Try to Uunderflow but the transfer function includes a movedelegates to handover signer 1 points directly to signer 1 despite the transfer is from signer 2 to owner.
      await bablToken.connect(owner).delegate(owner.address);
      const ownerCheckpoints6 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 5
      const signer1Checkpoints6 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 6

      expect(ownerCheckpoints.toString()).to.be.equal('1');
      expect(signer1Checkpoints.toString()).to.be.equal('0');
      expect(ownerCheckpoints2.toString()).to.be.equal('2');
      expect(signer1Checkpoints2.toString()).to.be.equal('1');
      expect(ownerCheckpoints3.toString()).to.be.equal('3');
      expect(signer1Checkpoints3.toString()).to.be.equal('2');
      expect(ownerCheckpoints4.toString()).to.be.equal('3');
      expect(signer1Checkpoints4.toString()).to.be.equal('3');
      expect(ownerCheckpoints5.toString()).to.be.equal('4');
      expect(signer1Checkpoints5.toString()).to.be.equal('5');
      expect(ownerCheckpoints6.toString()).to.be.equal('5');
      expect(signer1Checkpoints6.toString()).to.be.equal('6');
    });
    it('Should get the right number of checkpoints and votes despite different transfers and delegations between 3 users (increasing time)', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await bablToken.connect(owner).transfer(signer1.address, ethers.utils.parseEther('1')); // Let's give stake to have the possibility to delegate
      await bablToken.connect(owner).transfer(signer2.address, ethers.utils.parseEther('2')); // Let's give stake to have the possibility to delegate

      // FIRST (OWN) DELEGATION
      await bablToken.connect(owner).delegate(owner.address);
      const ownerCheckpoints = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 1
      const signer1Checkpoints = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 0

      // SECOND DELEGATION
      await bablToken.connect(owner).delegate(signer1.address);
      const signer1Checkpoints2 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 2
      const ownerCheckpoints2 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 2

      await increaseTime(ONE_DAY_IN_SECONDS);

      // THIRD DELEGATION
      await bablToken.connect(owner).delegate(owner.address);
      const ownerCheckpoints3 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 3
      const signer1Checkpoints3 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 2

      await increaseTime(ONE_DAY_IN_SECONDS);

      // FOURTH DELEGATION
      await bablToken.connect(signer1).delegate(signer1.address);
      const ownerCheckpoints4 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 3
      const signer1Checkpoints4 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 3

      // FIFTH Try to exploit sub96 vs. balanceOf over a previous delegation with higher balance
      await bablToken.connect(owner).delegate(signer1.address);
      await bablToken.connect(signer2).transfer(owner.address, ethers.utils.parseEther('2')); // Transfers handles delegation properly
      const ownerCheckpoints5 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 4
      const signer1Checkpoints5 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 5

      // SIXTH Try to Uunderflow but the transfer function includes a movedelegates to handover signer 1 points directly to signer 1 despite the transfer is from signer 2 to owner.
      await bablToken.connect(owner).delegate(owner.address);
      const ownerCheckpoints6 = await bablToken.connect(signer1).getNumberOfCheckpoints(owner.address); // 5
      const signer1Checkpoints6 = await bablToken.connect(owner).getNumberOfCheckpoints(signer1.address); // 6

      expect(ownerCheckpoints.toString()).to.be.equal('1');
      expect(signer1Checkpoints.toString()).to.be.equal('0');
      expect(ownerCheckpoints2.toString()).to.be.equal('2');
      expect(signer1Checkpoints2.toString()).to.be.equal('1');
      expect(ownerCheckpoints3.toString()).to.be.equal('3');
      expect(signer1Checkpoints3.toString()).to.be.equal('2');
      expect(ownerCheckpoints4.toString()).to.be.equal('3');
      expect(signer1Checkpoints4.toString()).to.be.equal('3');
      expect(ownerCheckpoints5.toString()).to.be.equal('4');
      expect(signer1Checkpoints5.toString()).to.be.equal('5');
      expect(ownerCheckpoints6.toString()).to.be.equal('5');
      expect(signer1Checkpoints6.toString()).to.be.equal('6');
    });
    it('Should get the checkpoint details', async function () {
      const ownerBalance = await bablToken.balanceOf(owner.address);
      await bablToken.connect(owner).delegate(signer1.address); // External delegation
      await increaseTime(ONE_DAY_IN_SECONDS);

      //Try to re-delegate
      await bablToken.connect(owner).delegate(signer1.address); // External delegation
      await increaseTime(ONE_DAY_IN_SECONDS);

      await bablToken.connect(owner).delegate(owner.address); // Own delegation
      await increaseTime(ONE_DAY_IN_SECONDS);

      await bablToken.connect(signer1).delegate(signer1.address); // Own delegation

      const [, ownerCheckpointVotes] = await bablToken.getCheckpoints(owner.address, 0);
      const [, signer1CheckpointVotes] = await bablToken.getCheckpoints(signer1.address, 0);
      const [, signer1CheckpointVotes1] = await bablToken.getCheckpoints(signer1.address, 1);

      expect(ownerCheckpointVotes.toString()).to.be.equal(ownerBalance);
      expect(signer1CheckpointVotes.toString()).to.be.equal(ownerBalance);
      expect(signer1CheckpointVotes1.toString()).to.be.equal('0');
    });
  });
});
