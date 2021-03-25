const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;

const addresses = require('../utils/addresses');
const { ONE_DAY_IN_SECONDS, EMPTY_BYTES } = require('../utils/constants.js');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('Investment Idea', function () {
  let signer1;
  let signer3;
  let strategy1;
  let strategyContract;
  let weth;

  beforeEach(async () => {
    ({ signer1, signer3, strategy1 } = await loadFixture(deployFolioFixture));

    strategyContract = await ethers.getContractAt('Strategy', strategy1);
    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await strategyContract.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('Ideator can change the duration', function () {
    it('strategist should be able to change the duration of an investment strategy', async function () {
      await expect(strategyContract.connect(signer1).changeInvestmentDuration(ONE_DAY_IN_SECONDS)).to.not.be.reverted;
    });

    it('other member should be able to change the duration of an investment strategy', async function () {
      await expect(strategyContract.connect(signer3).changeInvestmentDuration(ONE_DAY_IN_SECONDS)).to.be.reverted;
    });
  });
});
