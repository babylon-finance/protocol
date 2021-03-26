const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;

const { createStrategy } = require('./fixtures/StrategyHelper.js');

const addresses = require('../utils/addresses');
const { ONE_DAY_IN_SECONDS } = require('../utils/constants.js');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('Strategy', function () {
  let strategyDataset;
  let strategyCandidate;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let garden2;
  let strategy11;
  let strategy21;
  let kyberTradeIntegration;

  beforeEach(async () => {
    ({ signer1, garden1, garden2, strategy11, strategy21, signer2, signer3, kyberTradeIntegration } = await loadFixture(
      deployFolioFixture,
    ));

    strategyDataset = await ethers.getContractAt('Strategy', strategy11);
    strategyCandidate = await ethers.getContractAt('Strategy', strategy21);
  });

  describe('Strategy Deployment', async function () {
    it('should deploy contract successfully', async function () {
      const deployed = await strategyDataset.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('getStrategyDetails', async function () {
    it('should return the expected strategy properties', async function () {
      const [
        address,
        strategist,
        integration,
        stake,
        absoluteTotalVotes,
        totalVotes,
        capitalAllocated,
        duration,
        expectedReturn,
        maxCapitalRequested,
        minRebalanceCapital,
        enteredAt,
      ] = await strategyDataset.getStrategyDetails();

      expect(address).to.equal(strategyDataset.address);
      expect(strategist).to.equal(signer1.address);
      expect(integration).to.not.equal(addresses.zero);
      expect(stake).to.equal(ethers.utils.parseEther('5'));
      expect(absoluteTotalVotes).to.equal(ethers.utils.parseEther('5'));
      expect(totalVotes).to.equal(ethers.utils.parseEther('5'));
      expect(capitalAllocated).to.equal(ethers.BigNumber.from(0));
      expect(duration).to.equal(ethers.BigNumber.from(ONE_DAY_IN_SECONDS * 30));
      expect(expectedReturn).to.equal(ethers.utils.parseEther('0.05'));
      expect(maxCapitalRequested).to.equal(ethers.utils.parseEther('10'));
      expect(minRebalanceCapital).to.equal(ethers.utils.parseEther('1'));
      expect(enteredAt.isZero()).to.equal(false);
    });
  });

  describe('getStrategyState', async function () {
    it('should return the expected strategy state', async function () {
      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyDataset.getStrategyState();

      expect(address).to.equal(strategyDataset.address);
      expect(active).to.equal(false);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.equal(ethers.BigNumber.from(0));
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));
    });
  });

  describe('executeInvestment', async function () {
    it('should execute investemnet idea', async function () {
      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      const signer1Balance = await garden2.balanceOf(signer1.getAddress());
      const signer2Balance = await garden2.balanceOf(signer2.getAddress());

      await strategyCandidate.executeInvestment(
        ethers.utils.parseEther('1'),
        [signer1.getAddress(), signer2.getAddress()],
        [signer1Balance, signer2Balance],
        signer1Balance.add(signer2Balance).toString(),
        signer1Balance.add(signer2Balance).toString(),
        {
          gasPrice: 0,
        },
      );

      const [, , , , absoluteTotalVotes, totalVotes] = await strategyCandidate.getStrategyDetails();

      expect(absoluteTotalVotes).to.equal(ethers.utils.parseEther('9.1'));
      expect(totalVotes).to.equal(ethers.utils.parseEther('9.1'));

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyCandidate.getStrategyState();

      expect(address).to.equal(strategyCandidate.address);
      expect(active).to.equal(true);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(false);
      expect(executedAt).to.equal(ethers.BigNumber.from(1614783309));
      expect(exitedAt).to.equal(ethers.BigNumber.from(0));
    });
  });

  describe.only('finalizeInvestment', async function () {
    it('should finalize investemnet idea', async function () {
      const strategyContract = await createStrategy(
        'active',
        [signer1, signer2, signer3],
        kyberTradeIntegration,
        garden1,
      );

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);

      await strategyContract.finalizeInvestment({ gasPrice: 0 });

      const [address, active, dataSet, finalized, executedAt, exitedAt] = await strategyContract.getStrategyState();

      expect(address).to.equal(strategyContract.address);
      expect(active).to.equal(false);
      expect(dataSet).to.equal(true);
      expect(finalized).to.equal(true);
      expect(executedAt).to.equal(ethers.BigNumber.from(1614783309));
      expect(exitedAt).to.equal(ethers.BigNumber.from(1622559310));
    });
  });
});
