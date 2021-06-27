const { expect } = require('chai');
const { ethers } = require('hardhat');
const { setupTests } = require('../fixtures/GardenFixture');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO, ONE_ETH } = require('../../lib/constants');

describe.only('BalancerV2IntegrationTest', function () {
  let balancerV2Integration;
  let babController;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  const authorizerAddress = '0xA331D84eC860Bf466b4CdCcFb4aC09a1B43F3aE6';

  beforeEach(async () => {
    ({ balancerV2Integration, babController, garden1, signer1, signer2, signer3 } = await setupTests()());
  });

  describe.only('Balancer V2 Pool Integration Deployment', function () {
    it('should successfully deploy the contract V2', async function () {
      const deployed = await babController.deployed();
      const deployedBalancer = await balancerV2Integration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedBalancer).to.equal(true);
    });
  });
});
