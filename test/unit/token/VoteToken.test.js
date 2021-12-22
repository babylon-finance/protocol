const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_DAY_IN_SECONDS } = require('lib/constants');
const { increaseTime, eth } = require('utils/test-helpers');
const { impersonateAddress } = require('lib/rpc');

const { setupTests } = require('fixtures/GardenFixture');

describe.skip('VoteToken', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let MULTISIG;

  async function delegateBySig(signer, delegatee, nonce, expiry) {
    const DOMAIN_TYPEHASH = ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes('EIP712Domain(string name,uint256 chainId,address verifyingContract)'),
    );
    const DELEGATION_TYPEHASH = ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes('Delegation(address delegatee,uint256 nonce,uint256 expiry)'),
    );
    console.log('babl token address', bablToken.address);
    const payload = ethers.utils.defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'uint256', 'address'],
      [
        DOMAIN_TYPEHASH,
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes(await bablToken.name())),
        31337,
        bablToken.address,
      ],
    );
    const domainSeparator = ethers.utils.keccak256(payload);
    const structHash = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        ['bytes32', 'address', 'uint256', 'uint256'],
        [DELEGATION_TYPEHASH, delegatee, nonce, expiry],
      ),
    );
    const digest = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(['string', 'bytes32', 'bytes32'], ['\x19\x01', domainSeparator, structHash]),
    );
    const metamaskSigned = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(['string', 'bytes32'], ['\x19Ethereum Signed Message:\n32', digest]),
    );
    const signature = await signer.signMessage(ethers.utils.arrayify(metamaskSigned));

    return ethers.utils.splitSignature(signature);
  }

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

      await bablToken.connect(MULTISIG).transfer(signer1.address, eth('10000'));
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

      await bablToken.connect(MULTISIG).transfer(signer1.address, eth('10000'));
      const votesMultisig2 = await bablToken.getCurrentVotes(MULTISIG.address);
      const votesSigner1 = await bablToken.getCurrentVotes(signer1.address);
      const signer1Balance = await bablToken.balanceOf(signer1.address);
      const multisigBalance2 = await bablToken.balanceOf(MULTISIG.address);

      await expect(multisigBalance2).to.be.equal(multisigBalance.sub(signer1Balance));
      // As there were no delegation, there are no real votes yet until they delegate in themselves using their balance
      await expect(votesMultisig1).to.be.equal(eth('23000'));
      await expect(votesMultisig2).to.be.equal(eth('13000'));
      await expect(votesSigner1).to.be.equal('0');
    });
    it('Should inherit voting power if before a transfer there was at least a delegation in itself', async function () {
      await bablToken.connect(MULTISIG).delegate(MULTISIG.address); // Own delegation - creates a checkpoint
      await bablToken.connect(signer1).delegate(signer1.address); // Own delegation - creates a checkpoint
      const votesMultisig1 = await bablToken.getCurrentVotes(MULTISIG.address);
      // Owner does not delegate in itself before transferring
      const multisigBalance = await bablToken.balanceOf(MULTISIG.address);

      await bablToken.connect(MULTISIG).transfer(signer1.address, eth('10000'));
      const votesMultisig2 = await bablToken.getCurrentVotes(MULTISIG.address);
      const votesSigner1 = await bablToken.getCurrentVotes(signer1.address);

      const signer1Balance = await bablToken.balanceOf(signer1.address);
      const multisigBalance2 = await bablToken.balanceOf(MULTISIG.address);

      await expect(multisigBalance2).to.be.equal(multisigBalance.sub(signer1Balance));
      // As there were no delegation, there are no real votes yet until they delegate in themselves using their balance
      await expect(votesMultisig1).to.be.equal(eth('23000'));
      await expect(votesMultisig2).to.be.equal(eth('13000'));
      await expect(votesSigner1).to.be.equal(eth('10000'));
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
      await bablToken.connect(MULTISIG).transfer(signer1.address, eth('10000'));
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
      await bablToken.connect(MULTISIG).transfer(signer1.address, eth('1')); // Let's give stake to have the possibility to delegate
      await bablToken.connect(MULTISIG).transfer(signer2.address, eth('2')); // Let's give stake to have the possibility to delegate

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
      await bablToken.connect(signer2).transfer(MULTISIG.address, eth('2')); // Transfers handles delegation properly
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
      await bablToken.connect(MULTISIG).transfer(signer1.address, eth('1')); // Let's give stake to have the possibility to delegate
      await bablToken.connect(MULTISIG).transfer(signer2.address, eth('2')); // Let's give stake to have the possibility to delegate

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
      await bablToken.connect(signer2).transfer(MULTISIG.address, eth('2')); // Transfers handles delegation properly
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
      // NEW VoteToken address (address(this)): 0x5081a39b8A5f0E35a8D959395a630b68B74Dd30f
      // name(): "Babylon.Finance"
      // NEW first hash: bytes32: "0x5d0c3e0c524bdef5470f03a1fe5e911b5210e5e03ddec33fbda09216630cec77"
      // expiration 1653729994 28 may 2022
      // nonce = 0
      // delegatee 0x232775eAD28F0C0c750A097bA77302E7d84efd3B
      // second hash : 0xd7ead66ff6bda9784088e2deae972d920c55438e8a76149605393615ba546a29
      // NEW Digest 0x8fc57573708a378fdb36f5b41d4290f7ad837fe0fd053ae5a3607768698a78c3
      // ethSignedMessageHash (digestHash): 0x59a7630a466378d7251a819c0577205d19cb5a5c11e0b3a296ef058eb0b7370d
      // METAMASK:
      // NEW signed message by Metamask = 0xf771e0dccf7287a7fbb97574829c07883d07bebdfd021bb8752a7a11e29f20662ed9c8789be1fb0d41ee6feabb98d8ad1cc29a501b1f8409b74ebaac906d5abe1c
      // Then splitting the signed message: Metamask
      // const v = '28';
      // const r = '0xf771e0dccf7287a7fbb97574829c07883d07bebdfd021bb8752a7a11e29f2066';
      // const s = '0x2ed9c8789be1fb0d41ee6feabb98d8ad1cc29a501b1f8409b74ebaac906d5abe';
      await bablToken.connect(MULTISIG).transfer(signer1.address, eth('100'));
      // Let's give stake to have the possibility to delegate
      const signer1Balance = await bablToken.balanceOf(signer1.address);

      const delegatee = '0x232775eAD28F0C0c750A097bA77302E7d84efd3B';
      const nonce = 0; // It was signed using 0, it only works (and just once) with 0++ = 1
      const expiry = 1653729994; // 28 may 2022
      //const sig = await delegateBySig(signer1, delegatee, nonce, expiry);
      //console.log('sig', sig.r, sig.v, sig.s);
      // new signature: 0xd961a2ca02d275ed2bc630429905e8f6b4bfff3a92ce38016c787180767abcf8604674566081714bd871966c9911caae3da7cfa66cfc1c171a3a096bc60604be1c

      // METAMASK:
      /*  const v = '28';
      const r = '0xf771e0dccf7287a7fbb97574829c07883d07bebdfd021bb8752a7a11e29f2066';
      const s = '0x2ed9c8789be1fb0d41ee6feabb98d8ad1cc29a501b1f8409b74ebaac906d5abe'; */
      const r = '0x973deb1716d2d07929d51d98db310b44b7b20c9ee264535b2fbd3f3e3aa02b15';
      const s = '0x7b121841eed800322bcc47f53f06fa04677173b0cb600ffb4a8f75db6bc7b3b1';
      const v = '27';

      /* const v = '28'; // PR contract address
      const r = '0x61ddcec5cd0ca3778e5bd282b5d5957ffd7245e9ab81a4504998ae0725c97521';
      const s = '0x08188b618a2762bd3e94f88df97afea7514065433213801d9eece33239400186'; */
      // console.log('vote token address', bablToken.address);
      await bablToken.delegateBySig(delegatee, nonce, expiry, v, r, s, true);
      // await bablToken.delegateBySig(delegatee, nonce, expiry, sig.v, sig.r, sig.s, true);

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
