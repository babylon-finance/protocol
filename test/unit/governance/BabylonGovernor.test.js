const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { increaseTime, increaseBlock, voteType, proposalState } = require('utils/test-helpers');

const { setupTests } = require('fixtures/GardenFixture');
const { impersonateAddress } = require('lib/rpc');

describe.only('BabylonGovernor', function () {
  let owner;
  let deployer;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let babGovernor;
  let timelockController;
  let babController;

  const version = '1';
  const tokenName = 'Babylon.Finance';
  const tokenSymbol = 'BABL';
  const value = from(0);

  let voter1;
  let voter2;
  let voter3;
  let voter4;

  // period and delay is in blocks
  async function getGovernorMock(period = 1, delay = 1) {
    // We deploy a mock contract with a custom period and delay
    const timelockFactory = await ethers.getContractFactory('TimelockController');
    const timelock = await timelockFactory.deploy(ONE_DAY_IN_SECONDS, [], []);

    const mockFactory = await ethers.getContractFactory('BabylonGovernorMock');
    const governor = await mockFactory.deploy(bablToken.address, timelock.address, delay, period);

    await timelock.connect(deployer).grantRole(await timelock.PROPOSER_ROLE(), governor.address);
    await timelock.connect(deployer).grantRole(await timelock.EXECUTOR_ROLE(), governor.address);

    return governor;
  }

  async function claimTokens(voters) {
    for (const voter of voters) {
      await bablToken.connect(voter.voter).claimMyTokens();
    }
  }

  async function selfDelegation(voters) {
    for (const voter of voters) {
      await bablToken.connect(voter.voter).delegate(voter.voter.address);
    }
  }

  async function castVotes(id, voters, governor) {
    for (const voter of voters) {
      await governor.connect(voter.voter).castVote(id, ethers.BigNumber.from(voter.support));
    }
  }

  async function getProposal(governor, { voters } = {}) {
    voters = voters || [
      { voter: voter1, support: voteType.For, reason: 'This is nice' },
      { voter: voter2, support: voteType.For },
      { voter: voter3, support: voteType.Against },
      { voter: voter4, support: voteType.Abstain },
    ];

    const description = '<proposal description>';
    const descriptionHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('<proposal description>'));

    const id = await governor.hashProposal([ADDRESS_ZERO], [value], ['0x'], descriptionHash);

    const proposalObject = {
      id,
      args: [[ADDRESS_ZERO], [value], ['0x'], description],
      voters,
    };

    await claimTokens(voters);
    await selfDelegation(voters);

    return proposalObject;
  }

  beforeEach(async () => {
    ({
      deployer,
      owner,
      signer1,
      signer2,
      signer3,
      bablToken,
      babGovernor,
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
      expect(await babGovernor.name()).to.be.equal('BabylonGovernor');
      expect(await babGovernor.version()).to.be.equal(version);
      expect(await babGovernor.token()).to.be.equal(bablToken.address);
      expect(await babGovernor.votingDelay()).to.be.equal('1');
      expect(await babGovernor.votingPeriod()).to.be.equal(45818);
      expect(await babGovernor.quorum(0)).to.be.equal(tokenSupply.div(25)); // 4% of totalSupply BABL
      expect(await babGovernor.proposalThreshold()).to.be.equal(tokenSupply.div(200)); // 0.5% of totalSupply BABL
      expect(await babGovernor.COUNTING_MODE()).to.be.equal('support=bravo&quorum=bravo');
      expect(await babGovernor.timelock()).to.be.equal(timelockController.address);

      // Check the linked BABL Token
      expect(await bablToken.name()).to.be.equal(tokenName);
      expect(await bablToken.symbol()).to.be.equal(tokenSymbol);
    });
  });

  describe('hashProposal', function () {
    it('can hash', async function () {
      const { id } = await getProposal(babGovernor);
      expect(id.toString()).to.equal('24740913560950340129913657040082387925746871334254749356616935491669344289396');
    });
  });

  describe('propose', function () {
    it('can NOT propose below a proposal threshold', async function () {
      const { args } = await getProposal(babGovernor);
      // propose
      await expect(
        babGovernor.connect(signer1)['propose(address[],uint256[],bytes[],string)'](...args),
      ).to.be.revertedWith('GovernorCompatibilityBravo: proposer votes below proposal threshold');
    });
    it('can NOT propose with invalid proposal length (targets vs. values)', async function () {
      const { args } = await getProposal(babGovernor);
      const args1 = [[ADDRESS_ZERO], [value, value], ['0x'], '<proposal description>'];
      // propose
      await expect(
        babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args1),
      ).to.be.revertedWith('Governor: invalid proposal length');
    });
    it('can NOT propose with invalid proposal length (targets vs. calldatas)', async function () {
      const { args } = await getProposal(babGovernor);
      const args1 = [[ADDRESS_ZERO], [value], ['0x', '0x'], '<proposal description>'];
      // propose
      await expect(
        babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args1),
      ).to.be.revertedWith('Governor: invalid proposal length');
    });
    it('can NOT propose an empty proposal', async function () {
      const { args } = await getProposal(babGovernor);
      const args1 = [[], [], [], '<proposal description>'];
      // propose
      await expect(
        babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args1),
      ).to.be.revertedWith('Governor: empty proposal');
    });
    it('can NOT repeat a proposal', async function () {
      const { args } = await getProposal(babGovernor);
      // propose
      await expect(babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args)).to.be.not
        .reverted;
      await expect(
        babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args),
      ).to.be.revertedWith('Governor: proposal already exists');
    });

    it('make a valid proposal', async function () {
      const { id, args } = await getProposal(babGovernor);

      // propose
      await babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

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
      ] = await babGovernor.proposals(id);

      expect(proposalId).to.be.equal(id);
      expect(proposerAddress).to.be.equal(voter1.address);
      expect(eta).to.be.equal(0);
      expect(startBlock).to.be.equal(await babGovernor.proposalSnapshot(id));
      expect(endBlock).to.be.equal(await babGovernor.proposalDeadline(id));
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
      const { id, args, voters } = await getProposal(babGovernor);

      // propose
      await babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      // 4 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, babGovernor);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await babGovernor.proposals(id);

      // Check all voters have voted
      expect(await babGovernor.hasVoted(id, voter1.address)).to.be.equal(true);
      expect(await babGovernor.hasVoted(id, voter2.address)).to.be.equal(true);
      expect(await babGovernor.hasVoted(id, voter3.address)).to.be.equal(true);
      expect(await babGovernor.hasVoted(id, voter4.address)).to.be.equal(true);

      // Check all votes are counted for For, Against and Abstain
      expect(forVotes).to.eq(eth(35000));
      expect(againstVotes).to.eq(eth(24750));
      expect(abstainVotes).to.eq(eth(17000));

      // Other params
      expect(eta).to.be.eq(0);
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      expect(await babGovernor.state(id)).to.eq(1);
    });

    it('can NOT cast a vote before votes start', async function () {
      const mockGovernor = await getGovernorMock(10, 10);
      const { id, args } = await getProposal(mockGovernor);

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      await expect(mockGovernor.connect(voter1).castVote(id, voteType.For)).to.be.revertedWith(
        'Governor: vote not currently active',
      );
      expect(await mockGovernor.proposalDeadline(id)).to.be.gt((await ethers.provider.getBlock()).number);
    });

    it('can NOT cast a vote after voting period ends', async function () {
      const mockGovernor = await getGovernorMock(10);
      const { id, args } = await getProposal(mockGovernor);

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      // We vote after the deadline
      await increaseBlock(11);

      await expect(mockGovernor.connect(voter1).castVote(id, voteType.For)).to.be.revertedWith(
        'Governor: vote not currently active',
      );
      expect(await mockGovernor.proposalDeadline(id)).to.be.lte((await ethers.provider.getBlock()).number);
    });
  });

  describe('queue', function () {
    it('can queue proposal', async function () {
      const mockGovernor = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For },
          { voter: voter4, support: voteType.For },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(10);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);

      await mockGovernor.connect(deployer)['queue(uint256)'](id);

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Queued);
    });
    it.only('can NOT queue a proposal if defeated', async function () {
      const mockGovernor = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.Against },
          { voter: voter3, support: voteType.Against },
          { voter: voter4, support: voteType.Against },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(10);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);

      await expect(mockGovernor.connect(deployer)['queue(uint256)'](id)).to.be.revertedWith(
        'Governor: proposal not successful',
      );
      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Defeated);
    });
  });

  describe('execute', function () {
    it('can execute proposal', async function () {
      const mockGovernor = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For },
          { voter: voter4, support: voteType.For },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(10);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);

      await mockGovernor.connect(deployer)['queue(uint256)'](id);

      await increaseTime(ONE_DAY_IN_SECONDS);

      await mockGovernor.connect(deployer)['execute(uint256)'](id);

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Executed);
    });
    it.only('can NOT execute proposal if defeated', async function () {
      const mockGovernor = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.Against },
          { voter: voter3, support: voteType.Against },
          { voter: voter4, support: voteType.Against },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(10);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);

      await increaseTime(ONE_DAY_IN_SECONDS);

      await expect(mockGovernor.connect(deployer)['execute(uint256)'](id)).to.be.revertedWith(
        'Governor: proposal not successful',
      );

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Defeated);
    });
  });
  describe('cancel', function () {
    it('can cancel a proposal by the proposer if threshold not reached', async function () {
      const mockGovernor = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For },
          { voter: voter4, support: voteType.For },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(10);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);

      await mockGovernor.connect(deployer)['queue(uint256)'](id);

      await increaseTime(ONE_DAY_IN_SECONDS);

      await mockGovernor.connect(deployer)['execute(uint256)'](id);

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Executed);
    });
    it('can NOT cancel a proposal by anyone different from proposer if threshold not reached', async function () {
      const mockGovernor = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For },
          { voter: voter4, support: voteType.For },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args);

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(10);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);

      await mockGovernor.connect(deployer)['queue(uint256)'](id);

      await increaseTime(ONE_DAY_IN_SECONDS);

      await mockGovernor.connect(deployer)['execute(uint256)'](id);

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Executed);
    });
  });

  describe('timelock', function () {
    it('timelock check ', async function () {
      // TODO
      // .timelock()
    });
    it('can update timelock by timelockcontroller', async function () {
      // TODO
      // .timelock()
      // _executor
    });
    it('can NOT update timelock by anyone different from timelockcontroller', async function () {
      // TODO
    });
  });
  describe('state ', function () {
    it('state defeated', async function () {
      // TODO
    });
  });
  describe('proposalEta ', function () {
    it('proposalEta if done', async function () {
      // TODO
    });
    it('proposalEta if NOT done', async function () {
      // TODO
    });
  });
  describe('getVotes ', function () {
    it('can get votes', async function () {
      // TODO
    });
  });
  describe('counting mode ', function () {
    it('bravo counting mode', async function () {
      // TODO
    });
  });
  describe('getActions ', function () {
    it('getActions', async function () {
      // TODO
    });
  });
  describe('proposals ', function () {
    it('proposals', async function () {
      // TODO
    });
  });
  describe('getReceipt ', function () {
    it('getReceipt', async function () {
      // TODO
    });
  });
  describe('quorumVotes ', function () {
    it('quorumVotes', async function () {
      // TODO
    });
  });
  describe('hasVoted ', function () {
    it('hasVotes', async function () {
      // TODO
    });
  });
});
