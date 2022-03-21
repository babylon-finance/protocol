const { expect } = require('chai');
const { ethers, deployments, upgrades } = require('hardhat');

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

const id = '43136438228420234127439242165728406855560943995597370153579727537282848124169';

describe('BIP11', function () {
  describe('after deployment', function () {
    beforeEach(async () => {
      await deployFixture();
    });

    it('can execute bip', async () => {
      const signers = await ethers.getSigners();
      const signer = signers[0];

      const governor = await ethers.getContractAt('BabylonGovernor', '0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24');
      const timelock = await impersonateAddress('0xe6Ed0eAcB79a6e457416E4df38ed778fd6C6D193');
      const gnosis = await impersonateAddress('0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e');
      const assistant = await ethers.getContractAt('Assistant', '0x90F3923427768d6dC7970417B0F413B7DD059011', ownerV3);
      const ownerV3 = await impersonateAddress('0xaec6233a45a3866e9f1c64ab121e4ee9dbeafbff');
      const babl = await impersonateAddress('0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74');
      const bablToken = await ethers.getContractAt('BABLToken', babl.address);
      // update Assistant
      const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', gnosis);
      const assistantNewImpl = await deploy('Assistant', {
        from: signer.address,
        args: [],
        log: true,
      });
      await proxyAdmin.upgrade(assistant.address, assistantNewImpl.address);

      // Execute

      const bablGnosisBefore = await bablToken.balanceOf(gnosis.address);

      await increaseTime(ONE_DAY_IN_SECONDS);

      await governor['execute(uint256)'](id);

      const bablGnosisAfter = await bablToken.balanceOf(gnosis.address);

      await increaseTime(ONE_DAY_IN_SECONDS);

      console.log('before', bablGnosisBefore.toString());
      console.log('after', bablGnosisAfter.toString());
    });
  });
});
