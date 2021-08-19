const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { increaseTime, increaseBlock, voteType, proposalState } = require('utils/test-helpers');
const { getVoters, getGovernorMock, getProposal, castVotes, claimTokens } = require('utils/gov-helpers');

const { setupTests } = require('fixtures/GardenFixture');
const { impersonateAddress } = require('lib/rpc');

describe.only('governor', function () {
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

  const votingPeriod = ONE_DAY_IN_SECONDS * 7;

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
  });

  describe('upgrades', function () {
    it('can change governor to a new one', async function () {
      const mockGovernor = await getGovernorMock(bablToken, deployer, 10);
      await claimTokens(bablToken, voters);

      const { id, args } = await getProposal(mockGovernor, bablToken, {
        targets: [ADDRESS_ZERO],
        values: [from(0)],
        calldatas: ['0x'],
        description: 'upgrade governor to a new version',
      });

      // propose
      await mockGovernor.connect(voters[0])['propose(address[],uint256[],bytes[],string)'](...args);

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(1);

      const votes = voters.map((vot) => ({ voter: vot, support: voteType.For }));
      await castVotes(id, votes, mockGovernor);

      // 10 block to skip voting period
      await increaseBlock(10);

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await mockGovernor.proposals(id);

      await mockGovernor.connect(deployer)['queue(uint256)'](id);

      await increaseTime(ONE_DAY_IN_SECONDS);

      await mockGovernor.connect(deployer)['execute(uint256)'](id);

      const state = await mockGovernor.state(id);
      expect(state).to.eq(proposalState.Executed);
    });
  });
});
