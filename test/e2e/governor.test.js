const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { increaseTime, increaseBlock, voteType, proposalState } = require('utils/test-helpers');
const { getVoters, getGovernorMock, getProposal, castVotes, claimTokens } = require('utils/gov-helpers');

const { setupTests } = require('fixtures/GardenFixture');
const { impersonateAddress } = require('lib/rpc');

describe('governor', function () {
  let deployer;
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let babGovernor;
  let timelockController;
  let babController;
  let voters;
  let PROPOSER_ROLE;
  let EXECUTOR_ROLE;

  const votingPeriod = ONE_DAY_IN_SECONDS * 7;

  async function voteProposal(governor, { targets, values, calldatas, description }) {
    const { id, args } = await getProposal(governor, {
      targets,
      values,
      calldatas,
      description,
    });

    // propose
    await governor.connect(voters[0])['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

    // mine blocks to reach the block where the voting starts
    await increaseBlock(await governor.votingDelay());

    const votes = voters.map((vot) => ({ voter: vot, support: voteType.For }));
    await castVotes(id, votes, governor);

    // this is super slow but hardhat doesn't allow mine multiple blocks right
    // now should be fixed once this functionality avaiable
    // mine blocks to skip voting period
    await increaseBlock((await governor.votingPeriod()).add(1));

    const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await governor.proposals(id);
    return { id };
  }

  async function failProposal(governor, { targets, values, calldatas, description }) {
    const { id } = await voteProposal(governor, { targets, values, calldatas, description });

    await expect(governor.connect(deployer)['queue(uint256)'](id)).to.be.rejectedWith(
      /VM Exception while processing transaction: reverted with reason string 'AccessControl/,
    );
  }

  async function runProposal(governor, { targets, values, calldatas, description }) {
    const { id } = await voteProposal(governor, { targets, values, calldatas, description });

    await governor.connect(deployer)['queue(uint256)'](id);

    await increaseTime(ONE_DAY_IN_SECONDS);

    await governor.connect(deployer)['execute(uint256)'](id);

    const state = await governor.state(id);
    expect(state).to.eq(proposalState.Executed);
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
    voters = await getVoters();
    await claimTokens(bablToken, voters);

    PROPOSER_ROLE = await timelockController.PROPOSER_ROLE();
    EXECUTOR_ROLE = await timelockController.EXECUTOR_ROLE();
  });

  it('can enableTokensTransfers and miningProgram', async function () {
    await runProposal(babGovernor, {
      targets: [bablToken.address, babController.address],
      values: [from(0), from(0)],
      calldatas: [
        new ethers.utils.Interface(['function enableTokensTransfers()']).encodeFunctionData('enableTokensTransfers'),
        new ethers.utils.Interface(['function enableBABLMiningProgram()']).encodeFunctionData(
          'enableBABLMiningProgram',
        ),
      ],
      description: 'enable tokenTrasfers and miningProgram',
    });
  });

  it('can upgrade Governor to a new one', async function () {
    // create new governor
    const mockFactory = await ethers.getContractFactory('BabylonGovernorMock');
    const newGovernor = await mockFactory.deploy(bablToken.address, timelockController.address, 1, 10);

    // 0 grant new gov access
    // 1 remove old gov access
    await runProposal(babGovernor, {
      targets: [
        timelockController.address,
        timelockController.address,
        timelockController.address,
        timelockController.address,
      ],
      values: [from(0), from(0), from(0), from(0)],
      calldatas: [
        new ethers.utils.Interface([
          'function grantRole(bytes32 role, address account)',
        ]).encodeFunctionData('grantRole', [PROPOSER_ROLE, newGovernor.address]),
        new ethers.utils.Interface([
          'function grantRole(bytes32 role, address account)',
        ]).encodeFunctionData('grantRole', [EXECUTOR_ROLE, newGovernor.address]),
        new ethers.utils.Interface([
          'function revokeRole(bytes32 role, address account)',
        ]).encodeFunctionData('revokeRole', [PROPOSER_ROLE, babGovernor.address]),
        new ethers.utils.Interface([
          'function revokeRole(bytes32 role, address account)',
        ]).encodeFunctionData('revokeRole', [EXECUTOR_ROLE, babGovernor.address]),
      ],
      description: 'upgrade Governor to a new one',
    });

    // new gov can execute a proposal
    await runProposal(newGovernor, {
      targets: [ADDRESS_ZERO],
      values: [from(0)],
      calldatas: ['0x'],
      description: 'empty',
    });

    // old gov can NOT execute a proposal
    await failProposal(babGovernor, {
      targets: [ADDRESS_ZERO],
      values: [from(0)],
      calldatas: ['0x'],
      description: 'empty',
    });
  });
  it('can update timelock in the Governor', async function () {
    // create new governor
    const mockFactory = await ethers.getContractFactory('BabylonGovernorMock');
    const newGovernor = await mockFactory.deploy(bablToken.address, timelockController.address, 1, 10);
    // Speed up grantRole to new governor at current timelockcontroller (avoid being part of a proposal)
    await timelockController.connect(owner).grantRole(PROPOSER_ROLE, newGovernor.address);
    await timelockController.connect(owner).grantRole(EXECUTOR_ROLE, newGovernor.address);

    // create new timelockcontroller
    const timelockFactory = await ethers.getContractFactory('TimelockController');
    const newTimelock = await timelockFactory.deploy(ONE_DAY_IN_SECONDS, [babGovernor.address], [babGovernor.address]);

    expect(await newGovernor.timelock()).to.equal(timelockController.address);
    await runProposal(newGovernor, {
      targets: [newGovernor.address],
      values: [from(0)],
      calldatas: [
        new ethers.utils.Interface([
          'function updateTimelock(address newTimelock)',
        ]).encodeFunctionData('updateTimelock', [newTimelock.address]),
      ],
      description: 'update timelockcontroller to a new one',
    });
    expect(await newGovernor.timelock()).to.equal(newTimelock.address);
  });
});
