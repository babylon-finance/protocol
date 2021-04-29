const { expect } = require('chai');

const addresses = require('../lib/addresses');
const { ONE_ETH } = require('../lib/constants');
const { setupTests } = require('./fixtures/GardenFixture');
const { createStrategy } = require('./fixtures/StrategyHelper.js');

describe('GardenValuer', function () {
  let babController;
  let gardenValuer;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let kyberTradeIntegration;

  beforeEach(async () => {
    ({ babController, gardenValuer, garden1, signer1, signer2, signer3, kyberTradeIntegration } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployedc = await babController.deployed();
      const deployed = await gardenValuer.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Calls GardenValuer', function () {
    it('gets correct value for the garden with unallocated capital', async function () {
      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(ONE_ETH)).to.equal(ONE_ETH);
    });

    it('gets correct value for the garden with many deposits', async function () {
      // add 4 ETH to the garden
      await createStrategy('long', 'deposit', [signer1, signer2, signer3], kyberTradeIntegration.address, garden1);

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(ONE_ETH)).to.equal(ONE_ETH.mul(5));
    });

    it('gets correct value for the garden with active strategy', async function () {
      // add 4 ETH to the garden and trade them for a token
      await createStrategy('long', 'active', [signer1, signer2, signer3], kyberTradeIntegration.address, garden1);

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(ONE_ETH)).to.closeTo(ONE_ETH.mul(5), ONE_ETH.div(10));
    });

    it('gets correct value for the garden with finished strategy', async function () {
      // add 4 ETH to the garden, trade them for a token, and finish strategy
      await createStrategy('long', 'final', [signer1, signer2, signer3], kyberTradeIntegration.address, garden1);

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(ONE_ETH)).to.closeTo(ONE_ETH.mul(5), ONE_ETH.div(10));
    });
  });
});
