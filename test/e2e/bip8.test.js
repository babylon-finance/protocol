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

const id = '109344422653955248538795393396780479297640603841439438135853586337408509937165';

describe('BIP8', function () {
  describe('after deployment', function () {
    beforeEach(async () => {
      await deployFixture();
    });

    it('can execute bip', async () => {
      const signers = await ethers.getSigners();
      const signer = signers[0];

      const governor = await ethers.getContractAt('BabylonGovernor', '0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24');
      const timelock = await impersonateAddress('0xe6Ed0eAcB79a6e457416E4df38ed778fd6C6D193');
      const ownerV2 = await impersonateAddress('0x0B892EbC6a4bF484CDDb7253c6BD5261490163b9');
      const gnosis = await impersonateAddress('0x97FcC2Ae862D03143b393e9fA73A32b563d57A6e');
      const assistant = await ethers.getContractAt('Assistant', '0x90F3923427768d6dC7970417B0F413B7DD059011', ownerV3);
      const ownerV3 = await impersonateAddress('0xaec6233a45a3866e9f1c64ab121e4ee9dbeafbff');
      const visorOwner = await impersonateAddress('0xC40cCdE9C951AcE468154D1d39917d8f8D11b38c');
      const visor = await ethers.getContractAt('IHypervisor', '0x5e6c481dE496554b66657Dd1CA1F70C61cf11660', visorOwner);
      // Visor didnt whitelisted Assistant before the test, but now it is, we do on behalf
      await visor.connect(visorOwner).appendList(['0x90F3923427768d6dC7970417B0F413B7DD059011'], { gasPrice: 0 });

      // update Assistant
      const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', gnosis);
      const assistantNewImpl = await deploy('Assistant', {
        from: signer.address,
        args: [],
        log: true,
      });
      await proxyAdmin.upgrade(assistant.address, assistantNewImpl.address);

      // Execute

      await increaseTime(ONE_DAY_IN_SECONDS);

      await governor['execute(uint256)'](id);

      await increaseTime(ONE_DAY_IN_SECONDS);

      const treasury = await ethers.getContractAt('Treasury', '0xD7AAf4676F0F52993cb33aD36784BF970f0E1259');
      console.log('Visor Balance after BIP-8', (await visor.balanceOf(treasury.address)).toString());
      expect(await visor.balanceOf(treasury.address)).to.gt(eth());
    });
  });
});
