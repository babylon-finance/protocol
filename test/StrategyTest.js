const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;

const addresses = require('../utils/addresses');
const { ONE_DAY_IN_SECONDS } = require('../utils/constants.js');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('Strategy', function () {
  let strategy;
  let userSigner1;

  beforeEach(async () => {
    const { signer1, strategies } = await loadFixture(deployFolioFixture);

    strategy = strategies[0];
    userSigner1 = signer1;
  });

  describe('Strategy Deployment', async function () {
    it('should deploy contract successfully', async function () {
      const deployed = await strategy.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('getStrategyDetails()', async function () {
    it('should return the expected strategy properties', async function () {
      const [
        strategist,
        integration,
        stake,
        absoluteTotalVotes,
        capitalAllocated,
        duration,
        expectedReturn,
        maxCapitalRequested,
        minRebalanceCapital,
        enteredAt,
      ] = await strategy.getStrategyDetails();

      expect(strategist).to.equal(userSigner1.address);
      expect(integration).to.equal(addresses.zero);
      expect(stake).to.equal(ethers.utils.parseEther('5'));
      expect(absoluteTotalVotes).to.equal(ethers.utils.parseEther('5'));
      expect(capitalAllocated).to.equal(ethers.BigNumber.from(0));
      expect(duration).to.equal(ethers.BigNumber.from(ONE_DAY_IN_SECONDS * 30));
      expect(expectedReturn).to.equal(ethers.utils.parseEther('0.05'));
      expect(maxCapitalRequested).to.equal(ethers.utils.parseEther('10'));
      expect(minRebalanceCapital).to.equal(ethers.utils.parseEther('1'));
      expect(enteredAt.isZero()).to.equal(false);
    });
  });

  describe('getStrategyState()', async function () {
    it('should return the expected strategy state', async function () {
      const [active, dataSet, finalized, executedAt, exitedAt] = await strategy.getStrategyState();

      expect(active).to.equal(false);
      expect(dataSet).to.equal(false);
      expect(finalized).to.equal(false);
      expect(executedAt).to.equal(ethers.BigNumber.from(0));
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));
    });
  });
});
