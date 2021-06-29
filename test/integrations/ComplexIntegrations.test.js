const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  createStrategy,
  executeStrategy,
  finalizeStrategy,
  DAI_STRATEGY_PARAMS,
} = require('../fixtures/StrategyHelper');
const { setupTests } = require('../fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('../fixtures/GardenHelper');
const addresses = require('../../lib/addresses');

describe('ComplexIntegrationsTest', function () {
  let aaveBorrowIntegration;
  let aaveLendIntegration;
  let uniswapV3TradeIntegration;
  let signer1;
  let signer2;
  let signer3;
  let USDC;
  let DAI;
  let WETH;

  beforeEach(async () => {
    ({
      aaveBorrowIntegration,
      uniswapV3TradeIntegration,
      aaveLendIntegration,
      signer1,
      signer2,
      signer3,
    } = await setupTests()());
    USDC = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
    DAI = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
    WETH = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const lendDeployed = await aaveBorrowIntegration.deployed();
      expect(!!lendDeployed).to.equal(true);
    });
  });

  describe('gets NAV', function () {
    it(`gets NAV of a leveraged op`, async function () {
      await transferFunds(DAI.address);
      const garden = await createGarden({ reserveAsset: DAI.address });
      await depositFunds(DAI.address, garden);
      const strategyContract = await createStrategy(
        'custom',
        'vote',
        [signer1, signer2, signer3],
        [aaveLendIntegration.address, aaveBorrowIntegration.address, uniswapV3TradeIntegration.address],
        garden,
        DAI_STRATEGY_PARAMS,
        [WETH.address, USDC.address, WETH.address],
        [3, 4, 0],
      );
      await executeStrategy(strategyContract);

      const nav = await strategyContract.getNAV();
      expect(nav).to.be.closeTo(ethers.utils.parseEther('1000'), ethers.utils.parseEther('20'));
    });
  });
});
