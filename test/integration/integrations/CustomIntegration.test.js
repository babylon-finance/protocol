const { expect } = require('chai');
const { ethers, deployments } = require('hardhat');
const { deploy } = deployments;
const { GARDENS, ONE_DAY_IN_SECONDS, STRATEGY_EXECUTE_MAP } = require('lib/constants.js');
const { setupTests } = require('fixtures/GardenFixture');
const { createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { createGarden, transferFunds, depositFunds } = require('fixtures/GardenHelper');
const { getERC20, pick, increaseTime } = require('utils/test-helpers');
const { fund } = require('lib/whale');
// const addresses = require('lib/addresses');

describe('CustomIntegration', function () {
  let babController;
  let yearnVaultRegistry;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ signer1, signer2, signer3, yearnVaultRegistry, babController } = await setupTests()());
  });

  describe('testing custom yearn example', function () {
    pick(GARDENS).forEach(({ token, name }) => {
      it(`uses test custom integration in a ${name} garden`, async function () {
        await transferFunds(token);
        await fund([signer1.address], { tokens: [token] });
        // Enable custom integrations
        const garden = await createGarden({ reserveAsset: token, customIntegrationsEnabled: true });
        expect(await garden.customIntegrationsEnabled()).to.equal(true);
        const gardenReserveAsset = await getERC20(token);
        await depositFunds(token, garden);

        const deployment = await deploy('CustomIntegrationYearn', {
          from: signer1.address,
          args: [babController.address, yearnVaultRegistry.address],
        });

        // USDT vault
        const param = '0x7Da96a3891Add058AdA2E826306D812C638D87a7';
        const integrations = deployment.address;
        const integrationParams = [param, 0];
        const strategyKind = 'custom';
        const ops = [5];

        const strategyContract = await createStrategy(
          strategyKind,
          'vote',
          [signer1, signer2, signer3],
          integrations,
          garden,
          false,
          integrationParams,
          ops,
        );
        const amount = STRATEGY_EXECUTE_MAP[token];
        const balanceBeforeExecuting = await gardenReserveAsset.balanceOf(garden.address);
        await executeStrategy(strategyContract, { amount });
        const integrationInstance = await ethers.getContractAt('ICustomIntegration', deployment.address);
        const resultToken = await getERC20(await integrationInstance.getResultToken(param));
        // Check NAV
        const nav = await strategyContract.getNAV();
        expect(nav).to.be.closeTo(amount, amount.div(30));
        expect(await resultToken.balanceOf(strategyContract.address)).to.gt(0);
        // Check reward after a week
        await increaseTime(ONE_DAY_IN_SECONDS * 7);
        expect(await strategyContract.getNAV()).to.be.gte(nav);

        const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
        await finalizeStrategy(strategyContract, { gasLimit: 99900000 });
        expect(await strategyContract.getNAV()).to.eq(0);

        expect(await resultToken.balanceOf(strategyContract.address)).to.equal(0);

        expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gte(balanceBeforeExiting);
        expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.closeTo(
          balanceBeforeExecuting,
          balanceBeforeExecuting.div(30),
        );
      });
    });
  });
});
