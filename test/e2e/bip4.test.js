const { expect } = require('chai');
const { ethers, deployments } = require('hardhat');

const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { fund } = require('lib/whale');
const addresses = require('lib/addresses');
const { getContracts, deployFixture } = require('lib/deploy');
const { deploy } = deployments;

const { increaseTime, increaseBlock, voteType, proposalState, getERC20 } = require('utils/test-helpers');
const { getVoters, getGovernorMock, getProposal, castVotes, claimTokens } = require('utils/gov-helpers');

const { setupTests } = require('fixtures/GardenFixture');
const { impersonateAddress } = require('lib/rpc');
const { finalizeStrategy, finalizeStrategyImmediate } = require('fixtures/StrategyHelper');
const { executeStrategy } = require('../fixtures/StrategyHelper');

const id = '32156439968584618709935706941284187564699780275842591571726595721389081057467';

describe('BIP4', function () {
  describe('after deployment', function () {
    beforeEach(async () => {
      await deployFixture();
    });

    it.only('can execute bip', async () => {
      const governor = await ethers.getContractAt('BabylonGovernor', '0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24');
      const timelock = await impersonateAddress('0xe6Ed0eAcB79a6e457416E4df38ed778fd6C6D193');
      const ownerV2 = await impersonateAddress('0x0B892EbC6a4bF484CDDb7253c6BD5261490163b9');

      await increaseTime(ONE_DAY_IN_SECONDS);

      await governor['execute(uint256)'](id);

      await increaseTime(ONE_DAY_IN_SECONDS);

      const treasury = await ethers.getContractAt('Treasury', '0xD7AAf4676F0F52993cb33aD36784BF970f0E1259');
      await treasury
        .connect(timelock)
        .sendTreasuryFunds('0xf19f91d7889668a533f14d076adc187be781a458', eth(), ownerV2.address);

      const visor = await getERC20('0xf19f91d7889668a533f14d076adc187be781a458');
      expect(await visor.balanceOf(ownerV2.address)).to.eq(eth());
    });
  });
});
