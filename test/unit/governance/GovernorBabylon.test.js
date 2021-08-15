const { expect } = require('chai');
const { ethers } = require('hardhat');
const EthCrypto = require('eth-crypto');

const { ONE_ETH, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { increaseTime, increaseBlock, voteType, proposalState } = require('utils/test-helpers');

const { setupTests } = require('fixtures/GardenFixture');
const { impersonateAddress } = require('lib/rpc');

describe.only('Governor Babylon contract', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let governorBabylon;
  let timelockController;
  let babController;

  const name = 'Governor Babylon';
  const version = '1';
  const tokenName = 'Babylon.Finance';
  const tokenSymbol = 'BABL';
  const value = ethers.utils.parseEther('0');
  const votingPeriod = ONE_DAY_IN_SECONDS * 7;

  let voter1;
  let voter2;
  let voter3;
  let voter4;

  async function createProposal(proposer, target, value, encodedData, description) {
    const settings = {
      proposal: [[target], [value], [encodedData], description],
      proposer: proposer,
      tokenHolder: owner,
      voters: [
        { voter: voter1, support: voteType.For, reason: 'This is nice' },
        { voter: voter2, support: voteType.For },
        { voter: voter3, support: voteType.Against },
        { voter: voter4, support: voteType.Abstain },
      ],
    };
    return settings;
  }

  async function claimTokens(settings) {
    for (const voter of settings.voters) {
      await bablToken.connect(voter.voter).claimMyTokens();
    }
  }

  async function selfDelegation(settings) {
    for (const voter of settings.voters) {
      await bablToken.connect(voter.voter).delegate(voter.voter.address);
      await increaseTime(100);
    }
  }

  async function castVotes(settings, id) {
    for (const voter of settings.voters) {
      await governorBabylon.connect(voter.voter).castVote(id, ethers.BigNumber.from(voter.support));
    }
  }

  async function governanceFixture(proposer) {
    const ABI = ['function enableBABLMiningProgram()'];
    const iface = new ethers.utils.Interface(ABI);
    const encodedData = iface.encodeFunctionData('enableBABLMiningProgram');
    const proposalDescription = '<proposal description>';
    const proposalDescriptionHash = EthCrypto.hash.keccak256([{ type: 'string', value: '<proposal description>' }]);
    const proposalObject = await createProposal(
      proposer,
      babController.address,
      value,
      encodedData,
      proposalDescription,
    );
    const proposalObjectHashed = await createProposal(
      proposer,
      babController.address,
      value,
      encodedData,
      proposalDescriptionHash,
    );
    const id = await governorBabylon.hashProposal(...proposalObjectHashed.proposal);
    await claimTokens(proposalObject);
    await increaseTime(ONE_DAY_IN_SECONDS);
    await selfDelegation(proposalObject);
    return [proposalObject, id];
  }

  beforeEach(async () => {
    ({
      owner,
      signer1,
      signer2,
      signer3,
      bablToken,
      governorBabylon,
      timelockController,
      babController,
    } = await setupTests()());

    voter1 = await impersonateAddress('0x3E7c4E57A1dc4dD4bBE81bEFBe3E437f69619DaB'); // 20K
    voter2 = await impersonateAddress('0x06601571AA9D3E8f5f7CDd5b993192618964bAB5'); // 15K
    voter3 = await impersonateAddress('0x83f4622A18e38bE297e089fB055Dd5123bb0b279'); // Team 24K
    voter4 = await impersonateAddress('0x232775eAD28F0C0c750A097bA77302E7d84efd3B'); // Team 17K
  });

  describe('deployment', function () {
    it('should successfully deploy Governor Babylon contract', async function () {
      const tokenSupply = await bablToken.totalSupply();
      expect(await governorBabylon.name()).to.be.equal(name);
      expect(await governorBabylon.version()).to.be.equal(version);
      expect(await governorBabylon.token()).to.be.equal(bablToken.address);
      expect(await governorBabylon.votingDelay()).to.be.equal('4');
      expect(await governorBabylon.votingPeriod()).to.be.equal(votingPeriod);
      expect(await governorBabylon.quorum(0)).to.be.equal(tokenSupply.div(25)); // 4% of totalSupply BABL
      expect(await governorBabylon.proposalThreshold()).to.be.equal(tokenSupply.div(200)); // 0.5% of totalSupply BABL
      expect(await governorBabylon.COUNTING_MODE()).to.be.equal('support=bravo&quorum=bravo');
      expect(await governorBabylon.timelock()).to.be.equal(timelockController.address);

      // Check the linked BABL Token
      expect(await bablToken.name()).to.be.equal(tokenName);
      expect(await bablToken.symbol()).to.be.equal(tokenSymbol);
    });
  });

  describe('hashProposal', function () {
    it('can hash', async function () {
      const [, id] = await governanceFixture(voter1);
      expect(id.toString()).to.equal('31592073516640214093428763406121273246927507816899979568469470593665780044126');
    });
  });

  describe('propose', function () {
    it('can NOT propose below a proposal threshold', async function () {
      const [proposalObject] = await governanceFixture(signer1);
      // propose
      await expect(
        governorBabylon
          .connect(proposalObject.proposer)
          ['propose(address[],uint256[],bytes[],string)'](...proposalObject.proposal),
      ).to.be.revertedWith('GovernorCompatibilityBravo: proposer votes below proposal threshold');
    });

    it('make a valid proposal', async function () {
      const [proposalObject, id] = await governanceFixture(voter1);

      // propose
      await governorBabylon.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...proposalObject.proposal);

      const [
        proposalId,
        proposerAddress,
        eta,
        startBlock,
        endBlock,
        forVotes,
        againstVotes,
        abstainVotes,
        canceled,
        executed,
      ] = await governorBabylon.proposals(id);

      expect(proposalId).to.be.equal(id);
      expect(proposerAddress).to.be.equal(voter1.address);
      expect(eta).to.be.equal(0);
      expect(startBlock).to.be.equal(await governorBabylon.proposalSnapshot(id));
      expect(endBlock).to.be.equal(await governorBabylon.proposalDeadline(id));
      expect(forVotes).to.be.equal(0);
      expect(againstVotes).to.be.equal(0);
      expect(abstainVotes).to.be.equal(0);
      expect(canceled).to.be.equal(false);
      expect(executed).to.be.equal(false);
    });
  });

  describe('castVoteWithReason', function () {});

  describe('castVoteBySig', function () {
    it.skip('can cast a vote by sig', async function () {
      // TODO
    });
  });

  describe('castVote', function () {
    it('can cast a vote', async function () {
      const [proposalObject, id] = await governanceFixture(voter1);

      // propose
      await governorBabylon.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...proposalObject.proposal);

      // 4 blocks to reach the block where the voting starts
      await increaseBlock(4);

      await castVotes(proposalObject, id);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await governorBabylon.proposals(id);

      // Check all voters have voted
      expect(await governorBabylon.hasVoted(id, voter1.address)).to.be.equal(true);
      expect(await governorBabylon.hasVoted(id, voter2.address)).to.be.equal(true);
      expect(await governorBabylon.hasVoted(id, voter3.address)).to.be.equal(true);
      expect(await governorBabylon.hasVoted(id, voter4.address)).to.be.equal(true);

      // Check all votes are counted for For, Against and Abstain
      expect(forVotes).to.be.equal(ethers.utils.parseEther('35000'));
      expect(againstVotes).to.be.equal(ethers.utils.parseEther('24750'));
      expect(abstainVotes).to.be.equal(ethers.utils.parseEther('17000'));

      // Other params
      expect(eta).to.be.equal(0);
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      expect(await governorBabylon.state(id)).to.be.equal(1);
    });

    it('can NOT cast a vote before votes start', async function () {
      const [proposalObject, id] = await governanceFixture(voter1);

      // propose
      await governorBabylon.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...proposalObject.proposal);
      await increaseTime(100);

      await expect(governorBabylon.connect(voter1).castVote(id, voteType.For)).to.be.revertedWith(
        'Governor: vote not currently active',
      );
    });
  });

  describe('execute', function () {});

  describe('queue', function () {
    it.skip('can queue proposal', async function () {
      // TODO
    });
  });
});
