const { expect } = require('chai');

const { fund } = require('lib/whale');
const { from, eth, parse } = require('lib/helpers');
const { impersonateAddress, setCode } = require('lib/rpc');
const addresses = require('lib/addresses');
const { ONE_ETH, ADDRESS_ZERO } = require('lib/constants');
const { setupTests } = require('fixtures/GardenFixture');
const { createStrategy } = require('fixtures/StrategyHelper.js');

describe.only('GardenValuer', function () {
  let dai;
  let weth;
  let priceOracle;
  let gardenValuer;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let uniswapV3TradeIntegration;

  beforeEach(async () => {
    ({
      dai,
      weth,
      priceOracle,
      gardenValuer,
      garden1,
      signer1,
      signer2,
      signer3,
      uniswapV3TradeIntegration,
    } = await setupTests()());
  });

  describe('deployment', function () {
    it('should NOT allow zero address for controller during deployment', async function () {
      const { deploy } = deployments;
      const { deployer, owner } = await getNamedAccounts();
      const gasPrice = await getRapid();
      const contract = 'GardenValuer';
      await expect(
        deploy(contract, {
          from: deployer,
          args: [ADDRESS_ZERO],
          log: true,
          gasPrice,
        }),
      ).to.be.revertedWith('Incorrect address');
    });
  });

  describe('calculateGardenValuation', function () {
    it('gets correct value for the garden with unallocated capital', async function () {
      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(ONE_ETH)).to.equal(ONE_ETH);
    });

    it('gets correct value for the garden with many deposits', async function () {
      // add 4 ETH to the garden
      await createStrategy('buy', 'deposit', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden1);

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(ONE_ETH)).to.equal(ONE_ETH.mul(5));
    });

    it('gets correct value for the garden with active strategy', async function () {
      // add 4 ETH to the garden and trade them for a token
      await createStrategy('buy', 'active', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden1);

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(ONE_ETH)).to.closeTo(ONE_ETH.mul(5), ONE_ETH.div(10));
    });

    it('gets correct value for the garden with finished strategy', async function () {
      // add 4 ETH to the garden, trade them for a token, and finish strategy
      await createStrategy('buy', 'final', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden1);

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(ONE_ETH)).to.closeTo(ONE_ETH.mul(5), ONE_ETH.div(10));
    });

    it.only('gets correct value for the garden 0 price asset', async function () {
      const revertOracleFactory = await ethers.getContractFactory('RevertOracle');
      const revertOracle = await revertOracleFactory.deploy();

      let pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      console.log('pricePerGardenToken', pricePerGardenToken.toString());

      // add 4 ETH to the garden, trade them for a token, and finish strategy
      await createStrategy('buy', 'active', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden1);

      await setCode(priceOracle.address, revertOracle.address);

      pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      console.log('pricePerGardenToken', pricePerGardenToken.toString());

      expect(pricePerGardenToken.mul(await garden1.totalSupply()).div(eth())).to.closeTo(eth().mul(4), eth().div(10));
    });
  });
});
