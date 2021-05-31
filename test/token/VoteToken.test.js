const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_ETH, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('../../lib/constants');
const { increaseTime } = require('../utils/test-helpers');
const { impersonateAddress } = require('../../lib/rpc');

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
    it('Should admit a delegation vote by a valid signature', async function () {
      // Signature (signed by signer1.address)
      // getChainId: 31337
      // VoteToken address (address(this)): 0x84eA74d481Ee0A5332c457a4d796187F6Ba67fEB
      // name(): "Babylon.Finance"
      // first hash: 0xc537366b6ef095dd13d57267f21209ecbfd22b5fb33030965870eefad22bc2df"
      // expiration 1653729994 28 may 2022
      // nonce = 0
      // delegatee 0x232775eAD28F0C0c750A097bA77302E7d84efd3B
      // second hash : 0xd7ead66ff6bda9784088e2deae972d920c55438e8a76149605393615ba546a29
      // third HASH: 0xab9f914973c2fc969ad6333b24425b6ad18a2e2196efc62d317ba823c1f7fe57
      // Digest = 0x297270268e4d1336f372fd9e5bedb193732205a6ba2be6ef06ae9edaeb4ece59
      // ethSignedMessageHash (digestHash): 0xbebc4bc5916106fa2c548dc168127011ac043e8d41c889ae8f3f1104a6c85fbb
      // METAMASK:
      // Signed message by Metamask = 0x4e302ab97d84f720d480d2fce8723158863f30c8557d14989d332966a41c1a5f7e2d62adc8c00d1c84f80fb75b2fcd38a934fad69c3091a5406d67b8c42db57a1b
      // Then splitting the signed message: Metamask
      // bytes32: r 0x4e302ab97d84f720d480d2fce8723158863f30c8557d14989d332966a41c1a5f
      // bytes32: s 0x7e2d62adc8c00d1c84f80fb75b2fcd38a934fad69c3091a5406d67b8c42db57a
      // uint8: v 27
      // LEDGER + METAMASK:
      // LEDGER signed: 0x3e9140970233a167713ba23429c8ecc48272a60dd6e422cf6f1cead2bbee87af27ca269d6b4e98d3220f62d9f5b99caf75003e7b88d66ab77000a48537fd9b0901
      // LEDGER signer: 0x232775eAD28F0C0c750A097bA77302E7d84efd3B
      // LEDGER message hash: 764B2DA7FCBD5AD5F4EF2F1E5AAE23944EC984FD9AAEE7338237255EE96758D7
      // LEDGER message hash website: 47CCC7A49206F6F21AEEC9928F4AD5F7513304B08180BE46BBD46B65941D0F8F
      // LEDGER signed split:
      // bytes32: r 0x3e9140970233a167713ba23429c8ecc48272a60dd6e422cf6f1cead2bbee87af
      // bytes32: s 0x27ca269d6b4e98d3220f62d9f5b99caf75003e7b88d66ab77000a48537fd9b09
      // uint8: v 1
      // TREZOR:
      // Signer: 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd
      // Signed message: dbf6a54764d0aa63a21c5ca49aed69195c3531dde0755490817db0764e1a76d44e32366a19416b58cedbb014c4cc67c76294e51f03443f89ae958f77631915121b
      // bytes32: r 0xdbf6a54764d0aa63a21c5ca49aed69195c3531dde0755490817db0764e1a76d4
      // bytes32: s 0x4e32366a19416b58cedbb014c4cc67c76294e51f03443f89ae958f7763191512
      // uint8: v 27
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await bablToken.connect(owner).transfer(signer1.address, ethers.utils.parseEther('100')); // Let's give stake to have the possibility to delegate
      const signer1Balance = await bablToken.balanceOf(signer1.address);

      const delegatee = '0x232775eAD28F0C0c750A097bA77302E7d84efd3B';
      const nonce = 0; // It was signed using 0, it only works (and just once) with 0++ = 1
      const expiry = 1653729994; // 28 may 2022
      // METAMASK:
      const v = '27';
      const r = '0x4e302ab97d84f720d480d2fce8723158863f30c8557d14989d332966a41c1a5f';
      const s = '0x7e2d62adc8c00d1c84f80fb75b2fcd38a934fad69c3091a5406d67b8c42db57a';
      // LEDGER + METAMASK
      //const v = '1';
      //const r = '0x3e9140970233a167713ba23429c8ecc48272a60dd6e422cf6f1cead2bbee87af';
      //const s = '0x27ca269d6b4e98d3220f62d9f5b99caf75003e7b88d66ab77000a48537fd9b09';
      // TREZOR
      //const v = '27';
      //const r = '0xdbf6a54764d0aa63a21c5ca49aed69195c3531dde0755490817db0764e1a76d4';
      //const s = '0x4e32366a19416b58cedbb014c4cc67c76294e51f03443f89ae958f7763191512';
      await bablToken.delegateBySig(delegatee, nonce, expiry, v, r, s, true);
      const walletDelegatee = await impersonateAddress(delegatee);

      const [, walletDelegateCheckpointVotes] = await bablToken.getCheckpoints(walletDelegatee.address, 0);
      const signer1Delegatee = await bablToken.connect(signer1).getMyDelegatee();
      const votesDelegatee = await bablToken.getCurrentVotes(walletDelegatee.address);

      expect(signer1Delegatee).to.equal(delegatee);
      expect(votesDelegatee).to.be.equal(signer1Balance);
      expect(walletDelegateCheckpointVotes.toString()).to.be.equal(signer1Balance);
    });
  });
});
