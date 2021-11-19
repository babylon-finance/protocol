const { expect } = require('chai');
const { ethers, deployments } = require('hardhat');

const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { fund } = require('lib/whale');
const addresses = require('lib/addresses');
const { getContracts, deployFixture } = require('lib/deploy');
const { deploy } = deployments;

const { increaseTime, increaseBlock, voteType, proposalState } = require('utils/test-helpers');
const { getVoters, getGovernorMock, getProposal, castVotes, claimTokens } = require('utils/gov-helpers');

const { setupTests } = require('fixtures/GardenFixture');
const { impersonateAddress } = require('lib/rpc');
const { finalizeStrategy, finalizeStrategyImmediate } = require('fixtures/StrategyHelper');
const { executeStrategy } = require('../fixtures/StrategyHelper');

const id = '101114191999043486697736420869088395356011912576891508818550663031478128389980';

describe('BIP3', function () {
  let owner;
  let gov;
  let keeper;
  let gardens;
  let strategyNft;
  let valuer;
  let gardensNAV;

  describe('after deployment', function () {
    beforeEach(async () => {
      ({ owner, gov, keeper, gardens, gardensNAV, strategyNft, valuer } = await deployFixture());
    });

    it.only('can execute bip3', async () => {
      const governor = await ethers.getContractAt('BabylonGovernor', '0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24');
      const timelock = '0xe6Ed0eAcB79a6e457416E4df38ed778fd6C6D193';
      const ownerV2 = await impersonateAddress('0x0B892EbC6a4bF484CDDb7253c6BD5261490163b9');

      await increaseBlock(await governor.votingPeriod());

      await governor['queue(uint256)'](id);

      await increaseTime(ONE_DAY_IN_SECONDS);

      await governor['execute(uint256)'](id);
    });
  });
});
