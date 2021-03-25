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
  let strategy1;
  let strategy2;

  beforeEach(async () => {
    ({ signer1, garden1, strategy1, strategy2, signer2, signer3 } = await loadFixture(deployFolioFixture));

    strategyDataset = await ethers.getContractAt('Strategy', strategy1);
    strategyCandidate = await ethers.getContractAt('Strategy', strategy2);
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
      expect(absoluteTotalVotes).to.equal(5000000);
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

      const user2GardenBalance = await garden1.balanceOf(signer2.getAddress());
      const user3GardenBalance = await garden1.balanceOf(signer3.getAddress());

      await strategyCandidate.executeInvestment(
        ethers.utils.parseEther('1'),
        [signer2.getAddress(), signer3.getAddress()],
        [user2GardenBalance, user3GardenBalance],
        user2GardenBalance.add(user3GardenBalance).toString(),
        user2GardenBalance.add(user3GardenBalance).toString(),
        {
          gasPrice: 0,
        },
      );
    });
  });
});
