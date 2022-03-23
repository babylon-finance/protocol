const { expect } = require('chai');
const { ethers } = require('hardhat');
const { createStrategy, getStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { increaseTime, getERC20, pick, eth } = require('utils/test-helpers');
const { STRATEGY_EXECUTE_MAP, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');

describe('GammaIntegrationTest', function () {
  let gammaIntegration;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ gammaIntegration, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('Gamma Integration Multigarden multiasset', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      { token: addresses.tokens.DAI, name: 'DAI' },
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(async ({ token, name }) => {
      pick(addresses.gamma.visors).forEach((visor) => {
        it(`can enter into ${visor.name} from a ${name} garden`, async function () {
          await depositIntoGamma(visor.address, token, visor);
        });
      });
    });
    it(`cannot enter an invalid pool`, async function () {
      await expect(tryDepositIntoGamma(ADDRESS_ZERO, addresses.tokens.WETH)).to.be.reverted;
    });
  });

  async function depositIntoGamma(visorAddress, token, visorObj) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await getERC20(token);
    await depositFunds(token, garden);
    const visor = await ethers.getContractAt('IHypervisor', visorAddress);

    const strategyContract = await createStrategy(
      'lp',
      'vote',
      [signer1, signer2, signer3],
      gammaIntegration.address,
      garden,
      false,
      [visorAddress, 0],
      { maxTradeSlippagePercentage: eth(0.1) },
    );

    const amount = STRATEGY_EXECUTE_MAP[token];
    const balanceBeforeExecuting = await gardenReserveAsset.balanceOf(garden.address);
    await executeStrategy(strategyContract, { amount });
    // Check NAV
    const nav = await strategyContract.getNAV();
    expect(nav).to.be.gt(amount.sub(amount.div(35)));
    expect(await visor.balanceOf(strategyContract.address)).to.gt(0);
    // Check reward after a week
    await increaseTime(ONE_DAY_IN_SECONDS * 7);
    expect(await strategyContract.getNAV()).to.be.gte(nav);
    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract, { gasLimit: 99900000 });
    expect(await visor.balanceOf(strategyContract.address)).to.equal(0);

    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gte(balanceBeforeExiting);
    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.closeTo(
      balanceBeforeExecuting,
      balanceBeforeExecuting.div(35),
    );
  }

  async function tryDepositIntoGamma(visorAddress, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    await depositFunds(token, garden);
    const strategyContract = await getStrategy({
      kind: 'lp',
      state: 'vote',
      integrations: gammaIntegration.address,
      garden,
      specificParams: [visorAddress, 0],
    });

    await executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] });
  }
});
