const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { increaseTime, increaseBlock, voteType, proposalState } = require('utils/test-helpers');

const { setupTests } = require('fixtures/GardenFixture');
const { impersonateAddress } = require('lib/rpc');
const { ONE_YEAR_IN_SECONDS } = require('lib/constants');

describe('BabylonGovernor', function () {
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
  let voter5;
  let voter6;

  // period and delay is in blocks
  async function getGovernorMock(period = 1, delay = 1) {
    // We deploy a mock contract with a custom period and delay
    const timelockFactory = await ethers.getContractFactory('TimelockController');
    const timelock = await timelockFactory.deploy(ONE_DAY_IN_SECONDS, [], []);

    const mockFactory = await ethers.getContractFactory('BabylonGovernorMock');
    const governor = await mockFactory.deploy(bablToken.address, timelock.address, delay, period);

    await timelock.connect(deployer).grantRole(await timelock.PROPOSER_ROLE(), governor.address);
    await timelock.connect(deployer).grantRole(await timelock.EXECUTOR_ROLE(), governor.address);

    return [governor, timelock];
  }

  async function claimTokens(voters) {
    for (const voter of voters) {
      await bablToken.connect(voter.voter).claimMyTokens({ gasPrice: 0 });
    }
  }

  async function selfDelegation(voters) {
    for (const voter of voters) {
      await bablToken.connect(voter.voter).delegate(voter.voter.address, { gasPrice: 0 });
    }
  }

  async function castVotes(id, voters, governor) {
    for (const voter of voters) {
      await governor.connect(voter.voter).castVote(id, ethers.BigNumber.from(voter.support), { gasPrice: 0 });
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
    const id = await governor.hashProposal([ADDRESS_ZERO], [value], ['0x'], descriptionHash, { gasPrice: 0 });
    const proposalObject = {
      id,
      args: [[ADDRESS_ZERO], [value], ['0x'], description],
      voters,
    };

    await claimTokens(voters);
    await selfDelegation(voters);

    return proposalObject;
  }

  async function castVoteBySig(id, support, signer) {
    const BALLOT_TYPEHASH = ethers.utils.keccak256(
      ethers.utils.toUtf8Bytes('Ballot(uint256 proposalId,uint8 support)'),
    );
    let payload = ethers.utils.defaultAbiCoder.encode(['bytes32', 'uint256', 'uint8'], [BALLOT_TYPEHASH, id, support]);
    let payloadHash = ethers.utils.keccak256(payload);
    let signature = await signer.signMessage(ethers.utils.arrayify(payloadHash));

    return ethers.utils.splitSignature(signature);
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
    voter3 = await impersonateAddress('0x83f4622A18e38bE297e089fB055Dd5123bb0b279'); // Team 24.7K
    voter4 = await impersonateAddress('0x232775eAD28F0C0c750A097bA77302E7d84efd3B'); // Team 17K
    voter5 = await impersonateAddress('0xfc7470c14bAEF608dC316F5702790eefee9cc258'); // 2.5K
    voter6 = await impersonateAddress('0x605f3e3e5adb86dedf3966daa9ca671199c27f44'); // 5K
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
        babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args1, { gasPrice: 0 }),
      ).to.be.revertedWith('Governor: invalid proposal length');
    });
    it('can NOT propose with invalid proposal length (targets vs. calldatas)', async function () {
      const { args } = await getProposal(babGovernor);
      const args1 = [[ADDRESS_ZERO], [value], ['0x', '0x'], '<proposal description>'];
      // propose
      await expect(
        babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args1, { gasPrice: 0 }),
      ).to.be.revertedWith('Governor: invalid proposal length');
    });
    it('can NOT propose an empty proposal', async function () {
      const { args } = await getProposal(babGovernor);
      const args1 = [[], [], [], '<proposal description>'];
      // propose
      await expect(
        babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args1, { gasPrice: 0 }),
      ).to.be.revertedWith('Governor: empty proposal');
    });
    it('can NOT repeat a proposal', async function () {
      const { args } = await getProposal(babGovernor);
      // propose
      await expect(babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 }))
        .to.be.not.reverted;
      await expect(
        babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 }),
      ).to.be.revertedWith('Governor: proposal already exists');
    });

    it('proposals - make a valid proposal', async function () {
      const { id, args } = await getProposal(babGovernor);

      // propose
      await babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

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
      // TODO change signature process into EIP712 signature
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For },
          { voter: voter4, support: voteType.For },
        ],
      });
      // Enable BABL token transfers to use signer1 account as voter
      await increaseTime(ONE_YEAR_IN_SECONDS * 4); // get out of vesting
      await bablToken.connect(owner).enableTokensTransfers();
      await bablToken.connect(voter1).transfer(signer1.address, ethers.utils.parseEther('100'));

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      const sig = await castVoteBySig(id, voteType.For, signer1);
      await mockGovernor.connect(voter2).castVoteBySig(id, voteType.For, sig.v, sig.r, sig.s);
      await increaseBlock(1);
      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);
      expect(await bablToken.balanceOf(signer1.address).toString()).to.equal(forVotes);
      expect(await mockGovernor.hasVoted(id, signer1.address)).to.be.equal(true);
    });
  });

  describe('castVote', function () {
    it('can cast a vote', async function () {
      const { id, args, voters } = await getProposal(babGovernor);

      // propose
      await babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // 4 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, babGovernor);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await babGovernor.proposals(id);

      // Check all votes are counted for For, Against and Abstain
      expect(forVotes).to.eq(eth(35000));
      expect(againstVotes).to.eq(eth(24750));
      expect(abstainVotes).to.eq(eth(17000));

      // Other params
      expect(eta).to.be.eq(0);
      // state 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      expect(await babGovernor.state(id)).to.eq(1);
    });
    it('hasVoted', async function () {
      const { id, args, voters } = await getProposal(babGovernor);

      // propose
      await babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // 4 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, babGovernor);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await babGovernor.proposals(id);

      // Check all voters have voted
      expect(await babGovernor.hasVoted(id, voter1.address)).to.be.equal(true);
      expect(await babGovernor.hasVoted(id, voter2.address)).to.be.equal(true);
      expect(await babGovernor.hasVoted(id, voter3.address)).to.be.equal(true);
      expect(await babGovernor.hasVoted(id, voter4.address)).to.be.equal(true);

      // Other params
      expect(eta).to.be.eq(0);
      // state 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      expect(await babGovernor.state(id)).to.eq(1);
    });

    it('can NOT cast a vote before votes start', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10, 10);
      const { id, args } = await getProposal(mockGovernor);

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      await expect(mockGovernor.connect(voter1).castVote(id, voteType.For, { gasPrice: 0 })).to.be.revertedWith(
        'Governor: vote not currently active',
      );
      expect(await mockGovernor.proposalDeadline(id)).to.be.gt((await ethers.provider.getBlock()).number);
    });

    it('can NOT cast a vote after voting period ends', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args } = await getProposal(mockGovernor);

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // We vote after the deadline
      await increaseBlock(11);

      await expect(mockGovernor.connect(voter1).castVote(id, voteType.For, { gasPrice: 0 })).to.be.revertedWith(
        'Governor: vote not currently active',
      );
      expect(await mockGovernor.proposalDeadline(id)).to.be.lte((await ethers.provider.getBlock()).number);
    });
  });

  describe('queue', function () {
    it('can queue proposal', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For },
          { voter: voter4, support: voteType.For },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(10);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);

      await mockGovernor.connect(deployer)['queue(uint256)'](id);

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Queued);
    });
    it('can NOT queue a proposal if defeated', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.Against },
          { voter: voter3, support: voteType.Against },
          { voter: voter4, support: voteType.Against },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

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
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For },
          { voter: voter4, support: voteType.For },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(10);

      await mockGovernor.connect(deployer)['queue(uint256)'](id);

      await increaseTime(ONE_DAY_IN_SECONDS);

      await mockGovernor.connect(deployer)['execute(uint256)'](id);

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Executed);
    });
    it('can NOT execute proposal if defeated', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.Against },
          { voter: voter3, support: voteType.Against },
          { voter: voter4, support: voteType.Against },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(10);

      await increaseTime(ONE_DAY_IN_SECONDS);

      await expect(mockGovernor.connect(deployer)['execute(uint256)'](id)).to.be.revertedWith(
        'Governor: proposal not successful',
      );

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Defeated);
    });
  });
  describe('cancel', function () {
    it('can cancel an active proposal by the proposer', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(5);

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Active);

      await mockGovernor.connect(voter1)['cancel(uint256)'](id, { gasPrice: 0 });

      const state2 = await mockGovernor.state(id);
      expect(state2).to.eq(proposalState.Canceled);
    });
    it('can cancel a defeated proposal by the proposer', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(10);

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Defeated);

      await mockGovernor.connect(voter1)['cancel(uint256)'](id, { gasPrice: 0 });

      const state2 = await mockGovernor.state(id);
      expect(state2).to.eq(proposalState.Canceled);
    });

    it('can cancel an active proposal by anyone if the proposer is running low on BABL tokens', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(3);

      // Time travel to avoid vesting lock for transfer tokens despite blocks are not traveling equally
      await increaseTime(ONE_YEAR_IN_SECONDS * 4);
      expect(await bablToken.balanceOf(voter1.address)).to.equal(ethers.utils.parseEther('20000'));

      const voter1Balance = await bablToken.balanceOf(voter1.address);
      // Enable BABL token transfers to remove tokens from proposer running low on babl tokens
      await bablToken.connect(owner).enableTokensTransfers();
      await bablToken.connect(voter1).transfer(voter2.address, voter1Balance, { gasPrice: 0 });

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Active);
      expect(await bablToken.balanceOf(voter1.address)).to.equal(0);
      // voter 2 is different from proposer voter 1
      await mockGovernor.connect(voter2)['cancel(uint256)'](id);

      const state2 = await mockGovernor.state(id);
      expect(state2).to.eq(proposalState.Canceled);
    });
    it('can NOT cancel an active proposal by anyone different from proposer if still above threshold', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(5);

      await expect(mockGovernor.connect(deployer)['cancel(uint256)'](id)).to.be.revertedWith(
        'GovernorBravo: proposer above threshold',
      );

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Active);
    });
    it('can NOT cancel a defeated proposal by anyone different from proposer if above threshold', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
        ],
      });

      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      await castVotes(id, voters, mockGovernor);

      await increaseBlock(10);

      await expect(mockGovernor.connect(deployer)['cancel(uint256)'](id)).to.be.revertedWith(
        'GovernorBravo: proposer above threshold',
      );

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Defeated);
    });
  });

  describe('timelock', function () {
    it('timelock check ', async function () {
      expect(await babGovernor.timelock()).to.equal(timelockController.address);
    });
    it('can NOT update timelock by anyone different from timelockcontroller', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const mockTimelockAddress = await mockGovernor.timelock();
      await expect(mockGovernor.connect(signer1).updateTimelock(ADDRESS_ZERO)).to.be.revertedWith(
        'Governor: onlyGovernance',
      );
      expect(await mockGovernor.timelock()).to.equal(mockTimelockAddress);
    });
  });
  describe('state ', function () {
    it('state unknown proposal', async function () {
      const { id, args, voters } = await getProposal(babGovernor);
      await expect(babGovernor.state(id)).to.be.revertedWith('Governor: unknown proposal id');
    });
    it('state pending', async function () {
      const { id, args, voters } = await getProposal(babGovernor);
      // propose
      await babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      // 0: pending state
      const state = await babGovernor.state(id);
      expect(state).to.eq(proposalState.Pending);
    });
    it('state active', async function () {
      const { id, args, voters } = await getProposal(babGovernor);
      // propose
      await babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      // 1 block to reach the block where the voting starts
      await increaseBlock(1);
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      // 1: active state
      const state = await babGovernor.state(id);
      expect(state).to.eq(proposalState.Active);
    });
    it('state canceled', async function () {
      const { id, args, voters } = await getProposal(babGovernor);
      // propose
      await babGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      // 1 block to reach the block where the voting starts
      await increaseBlock(1);
      await babGovernor.connect(voter1)['cancel(uint256)'](id, { gasPrice: 0 });
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      // 2: canceled state
      const state = await babGovernor.state(id);
      expect(state).to.eq(proposalState.Canceled);
    });
    it('state defeated due to not getting votes on time', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is cool' },
          { voter: voter2, support: voteType.Against },
          { voter: voter3, support: voteType.Against, reason: 'This is bad for the community' },
        ],
      });
      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      // 15 blocks to pass the voting deadline
      await increaseBlock(15);
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      // 3: Defeated state
      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Defeated);
    });
    it('state defeated due to not reaching quorum', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is cool' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.Against, reason: 'This is bad' },
          { voter: voter4, support: voteType.Abstain, reason: 'Not sure a good idea' },
        ],
      });
      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await increaseBlock(1);
      await castVotes(id, voters, mockGovernor);
      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);
      expect(forVotes).to.be.lte(await mockGovernor.quorumVotes());
      // 15 blocks to pass the voting deadline
      await increaseBlock(15);
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      // 3: Defeated state
      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Defeated);
    });
    it('state defeated due to not suceeded (more against than for votes)', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.Against, reason: 'This is bad' },
          { voter: voter2, support: voteType.Against },
          { voter: voter3, support: voteType.For, reason: 'This is cool' },
          { voter: voter4, support: voteType.For, reason: 'Best thing' },
          { voter: voter5, support: voteType.Against, reason: 'You do not have my support' },
          { voter: voter6, support: voteType.Against, reason: 'You do not have my support' },
        ],
      });
      // propose
      await mockGovernor.connect(voter3)['propose(address[],uint256[],bytes[],string)'](...args);
      await increaseBlock(1);
      await castVotes(id, voters, mockGovernor);
      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);
      expect(forVotes).to.be.gte(await mockGovernor.quorumVotes());
      expect(forVotes).to.be.lte(againstVotes);
      // 15 blocks to pass the voting deadline
      await increaseBlock(15);
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      // 3: Defeated state
      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Defeated);
    });
    it('state succeeded', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is cool' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For, reason: 'This is nice' },
          { voter: voter4, support: voteType.Abstain, reason: 'Not sure a good idea' },
          { voter: voter5, support: voteType.For, reason: 'You have my support' },
        ],
      });
      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await increaseBlock(1);
      await castVotes(id, voters, mockGovernor);
      // increase blocks to reach the voting deadline
      await increaseBlock(5);

      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      // 4: suceeded state
      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Succeeded);
    });
    it('state queued', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is cool' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For, reason: 'This is nice' },
          { voter: voter4, support: voteType.Abstain, reason: 'Not sure a good idea' },
          { voter: voter5, support: voteType.For, reason: 'You have my support' },
        ],
      });
      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await increaseBlock(1);
      await castVotes(id, voters, mockGovernor);
      // increase blocks to reach the voting deadline
      await increaseBlock(5);
      // Anyone can queue
      await mockGovernor.connect(voter2)['queue(uint256)'](id);
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      // 5: queued state
      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Queued);
    });
    it.skip('state expired', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is cool' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For, reason: 'This is nice' },
          { voter: voter4, support: voteType.Abstain, reason: 'Not sure a good idea' },
          { voter: voter5, support: voteType.For, reason: 'You have my support' },
        ],
      });
      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await increaseBlock(1);
      // await castVotes(id, voters, mockGovernor);
      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);

      // increase blocks to reach the voting deadline
      await increaseBlock(15);
      // Anyone can queue
      // await mockGovernor.connect(voter2)['queue(uint256)'](id);
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      // 6: Expired state
      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Expired);
    });
    it('state executed', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is cool' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For, reason: 'This is nice' },
          { voter: voter4, support: voteType.Abstain, reason: 'Not sure a good idea' },
          { voter: voter5, support: voteType.For, reason: 'You have my support' },
        ],
      });
      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await increaseBlock(1);
      await castVotes(id, voters, mockGovernor);
      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);
      // increase blocks to reach the voting deadline
      await increaseBlock(5);
      // Anyone can queue
      await mockGovernor.connect(voter2)['queue(uint256)'](id);
      await increaseTime(ONE_DAY_IN_SECONDS);

      await mockGovernor.connect(voter2)['execute(uint256)'](id);
      // 0:'Pending', 1:'Active', 2:'Canceled', 3:'Defeated', 4:'Succeeded', 5:'Queued', 6:'Expired', 7:'Executed')
      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Executed);
    });
  });
  describe('proposalEta ', function () {
    it('get 0 for unset operation', async function () {
      // timestamp at with an operation becomes ready (0 for unset operations, 1 for done operations)
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
        ],
      });
      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      expect(await mockGovernor.proposalEta(id)).to.be.equal(0);
    });
    it('get timestamp for schedule operation', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is cool' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For, reason: 'This is nice' },
          { voter: voter4, support: voteType.Abstain, reason: 'Not sure a good idea' },
          { voter: voter5, support: voteType.For, reason: 'You have my support' },
        ],
      });
      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await increaseBlock(1);
      await castVotes(id, voters, mockGovernor);
      // increase blocks to reach the voting deadline
      await increaseBlock(5);
      const minDelay = await mockTimelock.getMinDelay();
      const blockTimestamp = (await ethers.provider.getBlock()).timestamp;
      const executionTime = ethers.BigNumber.from(blockTimestamp).add(minDelay);
      // Anyone can queue
      await mockGovernor.connect(voter2)['queue(uint256)'](id);
      expect(await mockGovernor.proposalEta(id)).to.be.closeTo(
        ethers.BigNumber.from(executionTime),
        600, // 10 mins
      );
    });
    it('get again 0 for done operation but eta == 1 AND controller getTimestamp == 1', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is cool' },
          { voter: voter2, support: voteType.For },
          { voter: voter3, support: voteType.For, reason: 'This is nice' },
          { voter: voter4, support: voteType.Abstain, reason: 'Not sure a good idea' },
          { voter: voter5, support: voteType.For, reason: 'You have my support' },
        ],
      });
      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await increaseBlock(1);
      await castVotes(id, voters, mockGovernor);

      // We calculate the id used in TimelockController which is different from Governor proposalId:
      // bytes32 id = hashOperationBatch(targets, values, datas, predecessor, salt);
      const descriptionHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('<proposal description>'));
      const AbiCoder = ethers.utils.AbiCoder;
      const abiCoder = new AbiCoder();
      const predecessor = abiCoder.encode(['uint256'], [0]); // 0x00 (32 bytes)
      const newArgs = [[ADDRESS_ZERO], [value], ['0x'], predecessor, descriptionHash];
      const timelockId = await mockTimelock.hashOperationBatch(...newArgs);
      // increase blocks to reach the voting deadline
      await increaseBlock(5);
      expect(await await mockTimelock.isOperation(timelockId)).to.equal(false);
      expect(await await mockTimelock.isOperationPending(timelockId)).to.equal(false);
      expect(await await mockTimelock.isOperationReady(timelockId)).to.equal(false);
      expect(await await mockTimelock.isOperationDone(timelockId)).to.equal(false);

      // Anyone can queue
      await mockGovernor.connect(voter2)['queue(uint256)'](id);
      // queue calls _timelock.scheduleBatch(targets, values, calldatas, 0, descriptionHash, delay);
      expect(await await mockTimelock.isOperation(timelockId)).to.equal(true);
      expect(await await mockTimelock.isOperationPending(timelockId)).to.equal(true);
      expect(await await mockTimelock.isOperationReady(timelockId)).to.equal(false);
      expect(await await mockTimelock.isOperationDone(timelockId)).to.equal(false);

      await increaseTime(ONE_DAY_IN_SECONDS * 7);
      // operation ready
      expect(await await mockTimelock.isOperation(timelockId)).to.equal(true);
      expect(await await mockTimelock.isOperationPending(timelockId)).to.equal(true);
      expect(await await mockTimelock.isOperationReady(timelockId)).to.equal(true);
      expect(await await mockTimelock.isOperationDone(timelockId)).to.equal(false);

      await mockGovernor.connect(voter2)['execute(uint256)'](id);
      // operation executed
      expect(await await mockTimelock.isOperation(timelockId)).to.equal(true);
      expect(await await mockTimelock.isOperationPending(timelockId)).to.equal(false);
      expect(await await mockTimelock.isOperationReady(timelockId)).to.equal(false);
      expect(await await mockTimelock.isOperationDone(timelockId)).to.equal(true);

      expect(await mockGovernor.proposalEta(id)).to.be.equal(0);
      expect(await mockTimelock.getTimestamp(timelockId)).to.be.equal(1);
    });
  });
  describe('getVotes ', function () {
    it('can get votes', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor, {
        voters: [
          { voter: voter1, support: voteType.For, reason: 'This is nice' },
          { voter: voter2, support: voteType.For },
        ],
      });
      const voter1Balance = await bablToken.balanceOf(voter1.address);
      const voter1VotingPower = await mockGovernor.getVotes(
        voter1.address,
        (await ethers.provider.getBlock()).number - 1,
      );
      await expect(mockGovernor.getVotes(voter1.address, (await ethers.provider.getBlock()).number)).to.be.revertedWith(
        'BABLToken::getPriorVotes: not yet determined',
      );
      await expect(voter1VotingPower).to.be.equal(voter1Balance);
      await increaseBlock(10);
      const voter1VotingPower2 = await mockGovernor.getVotes(
        voter1.address,
        (await ethers.provider.getBlock()).number - 1,
      );
      await expect(mockGovernor.getVotes(voter1.address, (await ethers.provider.getBlock()).number)).to.be.revertedWith(
        'BABLToken::getPriorVotes: not yet determined',
      );
      await expect(voter1VotingPower2).to.be.equal(voter1Balance);
    });
  });
  describe('counting mode ', function () {
    it('bravo counting mode', async function () {
      await expect(await babGovernor.COUNTING_MODE()).to.be.equal('support=bravo&quorum=bravo');
    });
  });
  describe('getActions ', function () {
    it('getActions', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args } = await getProposal(mockGovernor);
      const [targets, values, signatures, calldatas] = await mockGovernor.getActions(id);
      // empty as still not proposed
      expect(targets.toString()).to.equal('');
      expect(values.toString()).to.equal('');
      expect(signatures.toString()).to.equal('');
      expect(calldatas.toString()).to.equal('');
      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await increaseBlock(1);
      // Proposal proposed and registered, not empty
      const [targets2, values2, signatures2, calldatas2] = await mockGovernor.getActions(id);
      expect(targets2.toString()).to.equal(ADDRESS_ZERO);
      expect(values2.toString()).to.equal('0');
      expect(signatures2.toString()).to.equal('');
      expect(calldatas2.toString()).to.equal('0x');
    });
  });
  describe('getReceipt ', function () {
    it('getReceipt', async function () {
      const [mockGovernor, mockTimelock] = await getGovernorMock(10);
      const { id, args, voters } = await getProposal(mockGovernor);
      // propose
      await mockGovernor.connect(voter1)['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });
      await increaseBlock(1);

      const [voter1HasVoted, voter1Support, voter1Votes] = await mockGovernor.getReceipt(id, voter1.address);
      const [voter2HasVoted, voter2Support, voter2Votes] = await mockGovernor.getReceipt(id, voter2.address);
      const [voter3HasVoted, voter3Support, voter3Votes] = await mockGovernor.getReceipt(id, voter3.address);
      const [voter4HasVoted, voter4Support, voter4Votes] = await mockGovernor.getReceipt(id, voter4.address);

      expect(voter1HasVoted).to.equal(false);
      expect(voter1Support).to.equal(0);
      expect(voter1Votes).to.equal(0);
      expect(voter2HasVoted).to.equal(false);
      expect(voter2Support).to.equal(0);
      expect(voter2Votes).to.equal(0);
      expect(voter3HasVoted).to.equal(false);
      expect(voter3Support).to.equal(0);
      expect(voter3Votes).to.equal(0);
      expect(voter4HasVoted).to.equal(false);
      expect(voter4Support).to.equal(0);
      expect(voter4Votes).to.equal(0);

      await castVotes(id, voters, mockGovernor);
      await increaseBlock(1);
      const [voter1HasVoted2, voter1Support2, voter1Votes2] = await mockGovernor.getReceipt(id, voter1.address);
      const [voter2HasVoted2, voter2Support2, voter2Votes2] = await mockGovernor.getReceipt(id, voter2.address);
      const [voter3HasVoted2, voter3Support2, voter3Votes2] = await mockGovernor.getReceipt(id, voter3.address);
      const [voter4HasVoted2, voter4Support2, voter4Votes2] = await mockGovernor.getReceipt(id, voter4.address);

      expect(voter1HasVoted2).to.equal(true);
      expect(voter1Support2).to.equal(1);
      expect(voter1Votes2).to.equal(await bablToken.balanceOf(voter1.address));
      expect(voter2HasVoted2).to.equal(true);
      expect(voter2Support2).to.equal(1);
      expect(voter2Votes2).to.equal(await bablToken.balanceOf(voter2.address));
      expect(voter3HasVoted2).to.equal(true);
      expect(voter3Support2).to.equal(0); // voted against
      expect(voter3Votes2).to.equal(await bablToken.balanceOf(voter3.address));
      expect(voter4HasVoted2).to.equal(true);
      expect(voter4Support2).to.equal(2); // abstain vote
      expect(voter4Votes2).to.equal(await bablToken.balanceOf(voter4.address));
    });
  });
  describe('quorumVotes ', function () {
    it('quorumVotes', async function () {
      // 4% 40K BABL Tokens for quorum reached
      await expect(await babGovernor.quorumVotes()).to.equal(ethers.utils.parseEther('40000'));
    });
    it('quorum', async function () {
      const block = await ethers.provider.getBlock();
      // 4% 40K BABL Tokens for quorum reached
      await expect(await babGovernor.quorum(block.number)).to.equal(ethers.utils.parseEther('40000'));
    });
  });
});
