const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { increaseTime, voteType, proposalState } = require('utils/test-helpers');

const { setupTests } = require('fixtures/GardenFixture');
const { impersonateAddress } = require('lib/rpc');

describe('governor', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let babGovernor;
  let timelockController;
  let babController;

  const votingPeriod = ONE_DAY_IN_SECONDS * 7;

  beforeEach(async () => {
    ({
      owner,
      signer1,
      signer2,
      signer3,
      bablToken,
      babGovernor,
      timelockController,
      babController,
    } = await setupTests()());
  });
  describe('upgrades', function () {
    it('can change governor to a v2', async function () {
      // propose
      await babGovernor
        .connect(proposer)
        ['propose(address[],uint256[],bytes[],string)']([target], [value], [encodedData], description);
      // cast vote
      await babGovernor.connect(voter).castVote(proposalId, support);
      // execute
      await babGovernor.connect(executor).execute(targets, values, calldatas, descriptionHash);
      // verify
    });
  });
});
