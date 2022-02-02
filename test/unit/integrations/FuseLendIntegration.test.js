const { expect } = require('chai');
const {
  createStrategy,
  executeStrategy,
  DEFAULT_STRATEGY_PARAMS,
  finalizeStrategy,
} = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const addresses = require('lib/addresses');
const { increaseTime, getERC20, eth } = require('utils/test-helpers');
const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');

describe('FuseLendIntegrationTest', function () {
  let fuseLendIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let DAI;
  let WETH;
  let BABL;
  let cDAI;
  let cWETH;

  beforeEach(async () => {
    ({ garden1, fuseLendIntegration, signer1, signer2, signer3 } = await setupTests()());
    DAI = await getERC20(addresses.tokens.DAI);
    WETH = await getERC20(addresses.tokens.WETH);
    BABL = await getERC20(addresses.tokens.BABL);
    cDAI = await getERC20('0xa6c25548df506d84afd237225b5b34f2feb1aa07');
    cWETH = await getERC20('0x7dbc3af9251756561ce755fcc11c754184af71f7');
  });

  describe('Fuse Lend', function () {
    it('can supply to valid cToken', async function () {
      expect(await fuseLendIntegration.isInvestment(addresses.tokens.DAI)).to.equal(true);
    });

    it('0x is a valid address (ETH)', async function () {
      expect(await fuseLendIntegration.isInvestment(ADDRESS_ZERO)).to.equal(true);
    });
    it('fails when providing an invalid address', async function () {
      expect(await fuseLendIntegration.isInvestment('0xf1cE2ca79D49B431652F9597947151cf21efB9C3')).to.equal(false);
    });

    it('gets the reward token', async function () {
      expect(await fuseLendIntegration.getRewardToken()).to.equal('0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74');
    });

    it('gets the collateral factor', async function () {
      expect(await fuseLendIntegration.getCollateralFactor('0x6b175474e89094c44da98b954eedeac495271d0f')).to.equal(
        eth('0.755'),
      );
    });

    it('can get the amount of rewards', async function () {
      expect(await fuseLendIntegration.getRewardsAccrued(fuseLendIntegration.address)).to.equal(0);
    });

    it('can supply and redeem tokens from Fuse pool', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'vote',
        [signer1, signer2, signer3],
        fuseLendIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [addresses.tokens.DAI, 0], // ETH
      );

      await executeStrategy(strategyContract);
      expect(await DAI.balanceOf(strategyContract.address)).to.be.equal(0);
      expect(await cDAI.balanceOf(strategyContract.address)).to.be.gte(0);
      const beforeCdai = await cDAI.balanceOf(strategyContract.address);
      await executeStrategy(strategyContract);
      await executeStrategy(strategyContract);
      await finalizeStrategy(strategyContract);
      expect(await cDAI.balanceOf(strategyContract.address)).to.equal(0);
      expect(await cDAI.balanceOf(strategyContract.address)).to.be.lt(beforeCdai.div(1000));
      expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
    });

    it('can supply and redeem eth from Fuse', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'vote',
        [signer1, signer2, signer3],
        fuseLendIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [ADDRESS_ZERO, 0], // ETH
      );

      await executeStrategy(strategyContract);
      expect(await WETH.balanceOf(strategyContract.address)).to.be.equal(0);
      expect(await cWETH.balanceOf(strategyContract.address)).to.be.gt(0);
      await finalizeStrategy(strategyContract);
      expect(await cWETH.balanceOf(strategyContract.address)).to.be.closeTo(eth('0'), eth('0.01'));
      expect(await WETH.balanceOf(strategyContract.address)).to.equal(0);
      expect(await strategyContract.capitalReturned()).to.be.closeTo(eth('1'), eth('0.01'));
    });

    it('can supply and get NAV including rewards', async function () {
      const strategyContract = await createStrategy(
        'lend',
        'vote',
        [signer1, signer2, signer3],
        fuseLendIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [ADDRESS_ZERO, 0], // ETH
      );
      await executeStrategy(strategyContract);
      expect(await WETH.balanceOf(strategyContract.address)).to.be.equal(0);
      expect(await cWETH.balanceOf(strategyContract.address)).to.be.gt(0);
      increaseTime(ONE_DAY_IN_SECONDS);
      const NAV = await strategyContract.getNAV();
      const compAccrued = await fuseLendIntegration.getRewardsAccrued(strategyContract.address);
      expect(NAV.sub(compAccrued)).to.be.closeTo(eth('1'), eth('1').div(100));
    });
  });
});
