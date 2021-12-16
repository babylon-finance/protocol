const { expect } = require('chai');
const { createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { increaseTime, getERC20 } = require('utils/test-helpers');
const { STRATEGY_EXECUTE_MAP, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');

describe('HarvestStakeIntegrationTest', function () {
  let harvestV3StakeIntegration;
  let harvestV3VaultIntegration;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ harvestV3VaultIntegration, harvestV3StakeIntegration, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const lendDeployed = await harvestV3StakeIntegration.deployed();
      expect(!!lendDeployed).to.equal(true);
    });
  });

  describe('Harvest Stake Multigarden multiasset', function () {
    [
      { token: addresses.tokens.WETH, nameT: 'WETH' },
      // { token: addresses.tokens.DAI, nameT: 'DAI' },
      // { token: addresses.tokens.USDC, nameT: 'USDC' },
      // { token: addresses.tokens.WBTC, nameT: 'WBTC' },
    ].forEach(async ({ token, nameT }) => {
      Object.entries(addresses.harvest.v3vaults).forEach(([name, harvestLpAdd]) => {
        it(`can enter ${name} Harvest univ3 pool in ${nameT} garden and stake it`, async function () {
          console.log('name', name, harvestLpAdd, addresses.harvest.v3ToRewardPool[harvestLpAdd]);
          await depositAndStakeStrategy(harvestLpAdd, addresses.harvest.v3ToRewardPool[harvestLpAdd], token);
        });
      });
    });
    it(`cannot enter an invalid pool`, async function () {
      await expect(tryDepositAndStakeStrategy(ADDRESS_ZERO, ADDRESS_ZERO, addresses.tokens.WETH)).to.be.reverted;
    });
  });

  async function depositAndStakeStrategy(harvestLpAdd, harvestStakeAdd, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await getERC20(token);
    await depositFunds(token, garden);

    const harvestLpToken = await getERC20(harvestLpAdd);
    const harvestStakeToken = await getERC20(harvestStakeAdd);

    const strategyContract = await createStrategy(
      'lpStack',
      'vote',
      [signer1, signer2, signer3],
      [harvestV3VaultIntegration.address, harvestV3StakeIntegration.address],
      garden,
      false,
      [harvestLpAdd, 0, harvestStakeAdd, 0],
    );
    const amount = STRATEGY_EXECUTE_MAP[token];
    await executeStrategy(strategyContract, { amount });
    // Check NAV
    const nav = await strategyContract.getNAV();
    expect(nav).to.be.gt(amount.sub(amount.div(35)));

    expect(await harvestLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await harvestStakeToken.balanceOf(strategyContract.address)).to.be.gt(0);

    // Check reward after a week
    await increaseTime(ONE_DAY_IN_SECONDS * 7);
    expect(await strategyContract.getNAV()).to.be.gte(nav);
    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    await finalizeStrategy(strategyContract);
    expect(await harvestLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await harvestStakeToken.balanceOf(strategyContract.address)).to.equal(0);

    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gt(balanceBeforeExiting);
  }

  async function tryDepositAndStakeStrategy(harvestLpAdd, harvestStakeAdd, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    await depositFunds(token, garden);

    const strategyContract = await createStrategy(
      'lpStack',
      'vote',
      [signer1, signer2, signer3],
      [harvestV3VaultIntegration.address, harvestV3StakeIntegration.address],
      garden,
      false,
      [harvestLpAdd, 0, harvestStakeAdd, 0],
    );
    await expect(executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] })).to.be.reverted;
  }
});
