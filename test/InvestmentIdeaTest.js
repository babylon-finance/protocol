const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;

const addresses = require('../utils/addresses');
const { ONE_DAY_IN_SECONDS, EMPTY_BYTES } = require('../utils/constants.js');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('Investment Idea', function () {
  let controller;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let garden1;
  let strategiesC;
  let balancerIntegration;
  let strategy;
  let weth;

  beforeEach(async () => {
    const { babController, signer1, signer2, signer3, gardens, integrations, strategies, owner } = await loadFixture(
      deployFolioFixture,
    );

    balancerIntegration = integrations.balancerIntegration;
    controller = babController;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    garden1 = gardens.one;
    strategiesC = strategies;
    strategy = await ethers.getContractAt('Strategy', strategiesC[0]);
    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await strategy.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('Ideator can change the duration', function () {
    it('strategist should be able to change the duration of an investment strategy', async function () {
      await expect(strategy.connect(userSigner1).changeInvestmentDuration(ONE_DAY_IN_SECONDS)).to.not.be.reverted;
    });

    it('other member should be able to change the duration of an investment strategy', async function () {
      await expect(strategy.connect(userSigner3).changeInvestmentDuration(ONE_DAY_IN_SECONDS)).to.be.reverted;
    });
  });
});
