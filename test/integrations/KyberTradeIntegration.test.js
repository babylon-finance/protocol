const { expect } = require('chai');
const { waffle, ethers } = require('hardhat');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const addresses = require('../../utils/addresses');
const { ONE_ETH } = require('../../utils/constants');
const { from } = require('../utils/test-helpers');

const { loadFixture } = waffle;

describe.skip('KyberTradeIntegration', function () {
  let kyberTradeIntegration;
  let garden1;
  let babController;
  let signer1;
  let signer2;
  let signer3;
  let daiToken;
  let wethToken;

  beforeEach(async () => {
    ({ babController, garden1, kyberTradeIntegration, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
    daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
    wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedOne = await kyberTradeIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedOne).to.equal(true);
    });
  });

  describe('getConversionRates', function () {
    it('gets rate', async function () {
      const [expectedRate, minConversionRate] = await kyberTradeIntegration.getConversionRates(
        wethToken.address,
        daiToken.address,
        ONE_ETH,
      );
      console.log(expectedRate.toString(), minConversionRate.toString());
      expect(expectedRate).to.equal(from('1993302283513699731193'));
    });
  });

  describe('_getTradeCallData', function () {
    it('gets trade data', async function () {
      const [proxyAddress, ETH, methodData] = await kyberTradeIntegration._getTradeCallData(
        wethToken.address,
        daiToken.address,
        ONE_ETH,
      );
      console.log(proxyAddress.toString(), ETH.toString(), methodData.toString());
    });
  });
});
