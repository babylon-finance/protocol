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
      // const governor = await getGovernorMock(bablToken, deployer, 10);
      const governor = babGovernor;
      await claimTokens(bablToken, voters);

      let tokenInterface = new ethers.utils.Interface(['function enableTokensTransfers()']);
      const data = tokenInterface.encodeFunctionData('enableTokensTransfers');

      const { id, args } = await getProposal(governor, bablToken, {
        targets: [bablToken.address],
        values: [from(0)],
        calldatas: [data],
        description: 'upgrade governor to a new version',
      });

      // propose
      await governor.connect(voters[0])['propose(address[],uint256[],bytes[],string)'](...args);

      // 1 blocks to reach the block where the voting starts
      await increaseBlock(await governor.votingDelay());

      const votes = voters.map((vot) => ({ voter: vot, support: voteType.For }));
      await castVotes(id, votes, governor);

      // this is super slow but hardhat doesn't allow mine multiple blocks right
      // now should be fixed once this functionality avaiable
      // mine blocks to skip voting period
      await increaseBlock(await governor.votingPeriod());

      const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await governor.proposals(id);

      await governor.connect(deployer)['queue(uint256)'](id);

      await increaseTime(ONE_DAY_IN_SECONDS);

      await governor.connect(deployer)['execute(uint256)'](id);

      const state = await governor.state(id);
      expect(state).to.eq(proposalState.Executed);
    });
  });
});
