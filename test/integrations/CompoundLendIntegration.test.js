const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  createStrategy,
  executeStrategy,
  DEFAULT_STRATEGY_PARAMS,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const { setupTests } = require('../fixtures/GardenFixture');
const addresses = require('../../lib/addresses');
const { increaseTime } = require('../utils/test-helpers');
const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('../../lib/constants');

describe('CompoundLendIntegrationTest', function () {
  let compoundLendIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let USDC;
  let WETH;
  let CETH;
  let CUSDC;

  beforeEach(async () => {
    ({ garden1, compoundLendIntegration, signer1, signer2, signer3 } = await setupTests()());
    CETH = await ethers.getContractAt('IERC20', addresses.tokens.CETH);
    USDC = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
    CUSDC = await ethers.getContractAt('IERC20', addresses.tokens.CUSDC);
    WETH = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const compoundLendDeployed = await compoundLendIntegration.deployed();
      expect(!!compoundLendDeployed).to.equal(true);
    });
  });

  describe('Compound Lend', function () {
    it('can supply to valid cToken', async function () {
      expect(await compoundLendIntegration.isInvestment(addresses.tokens.USDC)).to.equal(true);
    });

    it('0x is a valid address (ETH)', async function () {
      expect(await compoundLendIntegration.isInvestment(ADDRESS_ZERO)).to.equal(true);
    });
    it('fails when providing an invalid address', async function () {
      expect(await compoundLendIntegration.isInvestment('0xf1cE2ca79D49B431652F9597947151cf21efB9C3')).to.equal(false);
    });

    it('gets the reward token', async function () {
      expect(await compoundLendIntegration.getRewardToken()).to.equal('0xc00e94Cb662C3520282E6f5717214004A7f26888');
    });

    it('can get the amount of rewards', async function () {
      expect(await compoundLendIntegration.getRewardsAccrued(compoundLendIntegration.address)).to.equal(0);
    });

    it('can supply and redeem tokens from Compound', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'vote',
        [signer1, signer2, signer3],
        compoundLendIntegration.address,
        garden1,
      );

      await executeStrategy(strategyContract);
      expect(await USDC.balanceOf(strategyContract.address)).to.be.equal(0);
      expect(await CUSDC.balanceOf(strategyContract.address)).to.be.gte(0);
      const beforeCusdc = await CUSDC.balanceOf(strategyContract.address);
      await finalizeStrategy(strategyContract);
      expect(await USDC.balanceOf(strategyContract.address)).to.equal(0);
      expect(await CUSDC.balanceOf(strategyContract.address)).to.be.lt(beforeCusdc.div(1000));
      expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
    });

    it('can supply and redeem eth from Compound', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'vote',
        [signer1, signer2, signer3],
        compoundLendIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [0, ADDRESS_ZERO], // ETH
      );

      await executeStrategy(strategyContract);
      expect(await WETH.balanceOf(strategyContract.address)).to.be.equal(0);
      expect(await CETH.balanceOf(strategyContract.address)).to.be.gt(0);
      await finalizeStrategy(strategyContract);
      expect(await CETH.balanceOf(strategyContract.address)).to.be.closeTo(
        ethers.utils.parseEther('0'),
        ethers.utils.parseEther('0.01'),
      );
      expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
      expect(await strategyContract.capitalReturned()).to.be.closeTo(
        ethers.utils.parseEther('1'),
        ethers.utils.parseEther('0.01'),
      );
    });

    it('can supply and get NAV including rewards', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'vote',
        [signer1, signer2, signer3],
        compoundLendIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [0, ADDRESS_ZERO], // ETH
      );
      await executeStrategy(strategyContract);
      expect(await WETH.balanceOf(strategyContract.address)).to.be.equal(0);
      expect(await CETH.balanceOf(strategyContract.address)).to.be.gt(0);
      increaseTime(ONE_DAY_IN_SECONDS);
      const NAV = await strategyContract.getNAV();
      const compAccrued = await compoundLendIntegration.getRewardsAccrued(strategyContract.address);
      expect(NAV.sub(compAccrued)).to.be.closeTo(ethers.utils.parseEther('1'), ethers.utils.parseEther('1').div(100));
    });
  });
});
