const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_DAY_IN_SECONDS } = require('lib/constants');
const { increaseTime } = require('utils/test-helpers');
const { impersonateAddress } = require('lib/rpc');

const { setupTests } = require('fixtures/GardenFixture');

describe('VoteToken contract', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let MULTISIG;

  beforeEach(async () => {
    ({ bablToken, owner, signer1, signer2, signer3 } = await setupTests()());
    await bablToken.connect(owner).enableTokensTransfers();
    const signers = await ethers.getSigners();
    MULTISIG = signers[2];
  });

  describe('Votes', function () {
    it('Should not get voting power by transfers if there is no delegation in themselves', async function () {
      // Enable BABL token transfers
      const votesMultisig1 = await bablToken.getCurrentVotes(MULTISIG.address);
      // Owner does not delegate in itself before transferring
      const multisigBalance = await bablToken.balanceOf(MULTISIG.address);

      await bablToken.connect(MULTISIG).transfer(signer1.address, ethers.utils.parseEther('10000'));
      const votesMultisig2 = await bablToken.getCurrentVotes(MULTISIG.address);
      const votesSigner1 = await bablToken.getCurrentVotes(signer1.address);
      const signer1Balance = await bablToken.balanceOf(signer1.address);
      const multisigBalance2 = await bablToken.balanceOf(MULTISIG.address);

      await expect(multisigBalance2).to.be.equal(multisigBalance.sub(signer1Balance));
      // As there were no delegation, there are no real votes yet until they delegate in themselves using their balance
      await expect(votesMultisig1).to.be.equal('0');
      await expect(votesMultisig2).to.be.equal('0');
      await expect(votesSigner1).to.be.equal('0');
    });

    it('Should not inherit voting power if before a transfer there was not at least a delegation in itself', async function () {
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address); // Own delegation
      const votesMultisig1 = await bablToken.getCurrentVotes(MULTISIG.address);
      // Owner does not delegate in itself before transferring
      const multisigBalance = await bablToken.balanceOf(MULTISIG.address);

      await bablToken.connect(MULTISIG).transfer(signer1.address, ethers.utils.parseEther('10000'));
      const votesMultisig2 = await bablToken.getCurrentVotes(MULTISIG.address);
      const votesSigner1 = await bablToken.getCurrentVotes(signer1.address);
      const signer1Balance = await bablToken.balanceOf(signer1.address);
      const multisigBalance2 = await bablToken.balanceOf(MULTISIG.address);

      await expect(multisigBalance2).to.be.equal(multisigBalance.sub(signer1Balance));
      // As there were no delegation, there are no real votes yet until they delegate in themselves using their balance
      await expect(votesMultisig1).to.be.equal(ethers.utils.parseEther('23000'));
      await expect(votesMultisig2).to.be.equal(ethers.utils.parseEther('13000'));
      await expect(votesSigner1).to.be.equal('0');
    });
    it('Should inherit voting power if before a transfer there was at least a delegation in itself', async function () {
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address); // Own delegation - creates a checkpoint
      await bablToken.connect(signer1).delegate(signer1.address); // Own delegation - creates a checkpoint
      const votesMultisig1 = await bablToken.getCurrentVotes(MULTISIG.address);
      // Owner does not delegate in itself before transferring
      const multisigBalance = await bablToken.balanceOf(MULTISIG.address);

      await bablToken.connect(MULTISIG).transfer(signer1.address, ethers.utils.parseEther('10000'));
      const votesMultisig2 = await bablToken.getCurrentVotes(MULTISIG.address);
      const votesSigner1 = await bablToken.getCurrentVotes(signer1.address);

      const signer1Balance = await bablToken.balanceOf(signer1.address);
      const multisigBalance2 = await bablToken.balanceOf(MULTISIG.address);

      await expect(multisigBalance2).to.be.equal(multisigBalance.sub(signer1Balance));
      // As there were no delegation, there are no real votes yet until they delegate in themselves using their balance
      await expect(votesMultisig1).to.be.equal(ethers.utils.parseEther('23000'));
      await expect(votesMultisig2).to.be.equal(ethers.utils.parseEther('13000'));
      await expect(votesSigner1).to.be.equal(ethers.utils.parseEther('10000'));
    });
    it('Should fail if trying to get prior voting power within the same block', async function () {
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address); // Own delegation - does not create checkpoint
      const block = await ethers.provider.getBlock();
      await expect(bablToken.getPriorVotes(MULTISIG.address, block.number)).to.be.revertedWith(
        'BABLToken::getPriorVotes: not yet determined',
      );
    });
    it('Should get priorVoting from a past checkpoint', async function () {
      const multisigBalance = await bablToken.balanceOf(MULTISIG.address);
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address); // Own delegation - does not create checkpoint
      const block = await ethers.provider.getBlock();
      await increaseTime(ONE_DAY_IN_SECONDS);
      await bablToken.connect(MULTISIG).transfer(signer1.address, ethers.utils.parseEther('10000'));
      const signer1Balance = await bablToken.balanceOf(signer1.address);

      const block2 = await ethers.provider.getBlock();
      await increaseTime(ONE_DAY_IN_SECONDS);
      const votesMultisig2 = await bablToken.getCurrentVotes(MULTISIG.address);

      expect(await bablToken.getPriorVotes(MULTISIG.address, block.number)).to.be.equal(multisigBalance);
      expect(await bablToken.getPriorVotes(MULTISIG.address, block2.number)).to.be.equal(
        multisigBalance.sub(signer1Balance),
      );
      expect(await bablToken.getPriorVotes(MULTISIG.address, block2.number)).to.be.equal(votesMultisig2);
    });
    it('Should get a delegatee from msg.sender', async function () {
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address); // Own delegation - does not create checkpoint
      const delegatee = await bablToken.connect(MULTISIG).getMyDelegatee();
      await bablToken.connect(MULTISIG).delegate(signer1.address); // External delegation - creates a checkpoint
      const delegatee2 = await bablToken.connect(MULTISIG).getMyDelegatee();
      expect(delegatee).to.be.equal(MULTISIG.address);
      expect(delegatee2).to.be.equal(signer1.address);
    });
    it('Should get a delegatee from any account', async function () {
      await bablToken.connect(MULTISIG).delegate(signer1.address); // External delegation - creates a checkpoint
      const multisigDelegatee = await bablToken.connect(signer1).getDelegatee(MULTISIG.address);
      await bablToken.connect(signer1).delegate(signer1.address); // Own delegation - does not create checkpoint
      const signer1Delegatee = await bablToken.connect(MULTISIG).getDelegatee(signer1.address);
      expect(multisigDelegatee).to.be.equal(signer1.address);
      expect(signer1Delegatee).to.be.equal(signer1.address);
    });
    it('Should get the number of checkpoints of 2 users crossing delegations', async function () {
      await bablToken.connect(MULTISIG).delegate(signer1.address); // External delegation
      const multisigCheckpoints = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 0
      const signer1Checkpoints = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 1

      await bablToken.connect(MULTISIG).delegate(MULTISIG.address); // Own delegation
      const multisigCheckpoints2 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 1
      const signer1Checkpoints2 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 2

      await bablToken.connect(signer1).delegate(signer1.address); // Own delegation - no checkpoint as it has no balance
      const multisigCheckpoints3 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 1
      const signer1Checkpoints3 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 2

      expect(multisigCheckpoints.toString()).to.be.equal('0');
      expect(signer1Checkpoints.toString()).to.be.equal('1');
      expect(multisigCheckpoints2.toString()).to.be.equal('1');
      expect(signer1Checkpoints2.toString()).to.be.equal('2');
      expect(multisigCheckpoints3.toString()).to.be.equal('1');
      expect(signer1Checkpoints3.toString()).to.be.equal('2');
    });

    it('Should get the right number of checkpoints and votes despite different transfers and delegations between 3 users (w/o increasing time)', async function () {
      await bablToken.connect(MULTISIG).transfer(signer1.address, ethers.utils.parseEther('1')); // Let's give stake to have the possibility to delegate
      await bablToken.connect(MULTISIG).transfer(signer2.address, ethers.utils.parseEther('2')); // Let's give stake to have the possibility to delegate

      // FIRST (OWN) DELEGATION
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address);
      const multisigCheckpoints = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 1
      const signer1Checkpoints = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 0

      // SECOND DELEGATION
      await bablToken.connect(MULTISIG).delegate(signer1.address);
      const signer1Checkpoints2 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 2
      const multisigCheckpoints2 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 2

      // THIRD DELEGATION
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address);
      const multisigCheckpoints3 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 3
      const signer1Checkpoints3 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 2

      // FOURTH DELEGATION
      await bablToken.connect(signer1).delegate(signer1.address);
      const multisigCheckpoints4 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 3
      const signer1Checkpoints4 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 3

      // FIFTH Try to exploit sub96 vs. balanceOf over a previous delegation with higher balance
      await bablToken.connect(MULTISIG).delegate(signer1.address);
      await bablToken.connect(signer2).transfer(MULTISIG.address, ethers.utils.parseEther('2')); // Transfers handles delegation properly
      const multisigCheckpoints5 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 4
      const signer1Checkpoints5 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 5

      // SIXTH Try to Uunderflow but the transfer function includes a movedelegates to handover signer 1 points directly to signer 1 despite the transfer is from signer 2 to owner.
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address);
      const multisigCheckpoints6 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 5
      const signer1Checkpoints6 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 6

      expect(multisigCheckpoints.toString()).to.be.equal('1');
      expect(signer1Checkpoints.toString()).to.be.equal('0');
      expect(multisigCheckpoints2.toString()).to.be.equal('2');
      expect(signer1Checkpoints2.toString()).to.be.equal('1');
      expect(multisigCheckpoints3.toString()).to.be.equal('3');
      expect(signer1Checkpoints3.toString()).to.be.equal('2');
      expect(multisigCheckpoints4.toString()).to.be.equal('3');
      expect(signer1Checkpoints4.toString()).to.be.equal('3');
      expect(multisigCheckpoints5.toString()).to.be.equal('4');
      expect(signer1Checkpoints5.toString()).to.be.equal('5');
      expect(multisigCheckpoints6.toString()).to.be.equal('5');
      expect(signer1Checkpoints6.toString()).to.be.equal('6');
    });
    it('Should get the right number of checkpoints and votes despite different transfers and delegations between 3 users (increasing time)', async function () {
      await bablToken.connect(MULTISIG).transfer(signer1.address, ethers.utils.parseEther('1')); // Let's give stake to have the possibility to delegate
      await bablToken.connect(MULTISIG).transfer(signer2.address, ethers.utils.parseEther('2')); // Let's give stake to have the possibility to delegate

      // FIRST (OWN) DELEGATION
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address);
      const multisigCheckpoints = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 1
      const signer1Checkpoints = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 0

      // SECOND DELEGATION
      await bablToken.connect(MULTISIG).delegate(signer1.address);
      const signer1Checkpoints2 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 2
      const multisigCheckpoints2 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 2

      await increaseTime(ONE_DAY_IN_SECONDS);

      // THIRD DELEGATION
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address);
      const multisigCheckpoints3 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 3
      const signer1Checkpoints3 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 2

      await increaseTime(ONE_DAY_IN_SECONDS);

      // FOURTH DELEGATION
      await bablToken.connect(signer1).delegate(signer1.address);
      const multisigCheckpoints4 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 3
      const signer1Checkpoints4 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 3

      // FIFTH Try to exploit sub96 vs. balanceOf over a previous delegation with higher balance
      await bablToken.connect(MULTISIG).delegate(signer1.address);
      await bablToken.connect(signer2).transfer(MULTISIG.address, ethers.utils.parseEther('2')); // Transfers handles delegation properly
      const multisigCheckpoints5 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 4
      const signer1Checkpoints5 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 5

      // SIXTH Try to Uunderflow but the transfer function includes a movedelegates to handover signer 1 points directly to signer 1 despite the transfer is from signer 2 to owner.
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address);
      const multisigCheckpoints6 = await bablToken.connect(signer1).getNumberOfCheckpoints(MULTISIG.address); // 5
      const signer1Checkpoints6 = await bablToken.connect(MULTISIG).getNumberOfCheckpoints(signer1.address); // 6

      expect(multisigCheckpoints.toString()).to.be.equal('1');
      expect(signer1Checkpoints.toString()).to.be.equal('0');
      expect(multisigCheckpoints2.toString()).to.be.equal('2');
      expect(signer1Checkpoints2.toString()).to.be.equal('1');
      expect(multisigCheckpoints3.toString()).to.be.equal('3');
      expect(signer1Checkpoints3.toString()).to.be.equal('2');
      expect(multisigCheckpoints4.toString()).to.be.equal('3');
      expect(signer1Checkpoints4.toString()).to.be.equal('3');
      expect(multisigCheckpoints5.toString()).to.be.equal('4');
      expect(signer1Checkpoints5.toString()).to.be.equal('5');
      expect(multisigCheckpoints6.toString()).to.be.equal('5');
      expect(signer1Checkpoints6.toString()).to.be.equal('6');
    });
    it('Should get the checkpoint details', async function () {
      const multisigBalance = await bablToken.balanceOf(MULTISIG.address);
      await bablToken.connect(MULTISIG).delegate(signer1.address); // External delegation
      await increaseTime(ONE_DAY_IN_SECONDS);

      //Try to re-delegate
      await bablToken.connect(MULTISIG).delegate(signer1.address); // External delegation
      await increaseTime(ONE_DAY_IN_SECONDS);

      await bablToken.connect(MULTISIG).delegate(MULTISIG.address); // Own delegation
      await increaseTime(ONE_DAY_IN_SECONDS);

      await bablToken.connect(signer1).delegate(signer1.address); // Own delegation

      const [, multisigCheckpointVotes] = await bablToken.getCheckpoints(MULTISIG.address, 0);
      const [, signer1CheckpointVotes] = await bablToken.getCheckpoints(signer1.address, 0);
      const [, signer1CheckpointVotes1] = await bablToken.getCheckpoints(signer1.address, 1);

      expect(multisigCheckpointVotes.toString()).to.be.equal(multisigBalance);
      expect(signer1CheckpointVotes.toString()).to.be.equal(multisigBalance);
      expect(signer1CheckpointVotes1.toString()).to.be.equal('0');
    });
    it('Should admit a delegation vote by a valid signature', async function () {
      // Signature (signed by signer1.address) 0x90F79bf6EB2c4f870365E785982E1f101E93b906
      // getChainId: 31337
      // NEW VoteToken address (address(this)): 0x809d550fca64d94Bd9F66E60752A544199cfAC3D
      // name(): "Babylon.Finance"
      // NEW first hash: 0x5d0c3e0c524bdef5470f03a1fe5e911b5210e5e03ddec33fbda09216630cec77
      // expiration 1653729994 28 may 2022
      // nonce = 0
      // delegatee 0x232775eAD28F0C0c750A097bA77302E7d84efd3B
      // second hash : 0xd7ead66ff6bda9784088e2deae972d920c55438e8a76149605393615ba546a29
      // NEW Digest 0x627795d6dc266ed0a64c14deb4674cf0f4eb9912c7f97e45d35b8443dc9d99aa
      // ethSignedMessageHash (digestHash): 0x59a7630a466378d7251a819c0577205d19cb5a5c11e0b3a296ef058eb0b7370d
      // METAMASK:
      // NEW signed message by Metamask = 0x2c957a96a5f511fa74efa7f6f261718439309e1b763b1e5ee7f3c27f524f711d20b36a779f1ead53e3de10ccbcae8d30290cb68558189ecf34ba8d03ab52fc381c
      // Then splitting the signed message: Metamask
      // const v = '28';
      // const r = "0x2c957a96a5f511fa74efa7f6f261718439309e1b763b1e5ee7f3c27f524f711d";
      // const s = "0x20b36a779f1ead53e3de10ccbcae8d30290cb68558189ecf34ba8d03ab52fc38";
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
      await bablToken.connect(MULTISIG).transfer(signer1.address, ethers.utils.parseEther('100')); // Let's give stake to have the possibility to delegate
      const signer1Balance = await bablToken.balanceOf(signer1.address);

      const delegatee = '0x232775eAD28F0C0c750A097bA77302E7d84efd3B';
      const nonce = 0; // It was signed using 0, it only works (and just once) with 0++ = 1
      const expiry = 1653729994; // 28 may 2022
      // METAMASK:
      const v = '28';
      const r = '0x2c957a96a5f511fa74efa7f6f261718439309e1b763b1e5ee7f3c27f524f711d';
      const s = '0x20b36a779f1ead53e3de10ccbcae8d30290cb68558189ecf34ba8d03ab52fc38';

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
