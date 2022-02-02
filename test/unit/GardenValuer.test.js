const { expect } = require('chai');

const { fund } = require('lib/whale');
const { from, eth, parse } = require('lib/helpers');
const { impersonateAddress, setCode } = require('lib/rpc');
const addresses = require('lib/addresses');
const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS, STRATEGY_EXECUTE_MAP } = require('lib/constants.js');
const { setupTests } = require('fixtures/GardenFixture');
const { createStrategy, finalizeStrategy, executeStrategy } = require('fixtures/StrategyHelper.js');

describe('GardenValuer', function () {
  let dai;
  let weth;
  let priceOracle;
  let babController;
  let tokenIdentifier;
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
      babController,
      gardenValuer,
      tokenIdentifier,
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
      const { maxPriorityFeePerGas } = await getGasPrice();
      const contract = 'GardenValuer';
      await expect(
        deploy(contract, {
          from: deployer,
          args: [ADDRESS_ZERO],
          log: true,
          maxPriorityFeePerGas,
        }),
      ).to.be.revertedWith('Incorrect address');
    });
  });

  describe('calculateGardenValuation', function () {
    it('gets correct value for the garden with unallocated capital', async function () {
      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(eth())).to.equal(eth());
    });

    it('gets correct value for the garden with many deposits', async function () {
      // add 4 ETH to the garden
      await createStrategy('buy', 'deposit', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden1);

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(eth())).to.equal(eth().mul(5));
    });

    it('gets correct value for the garden with active strategy', async function () {
      // add 4 ETH to the garden and trade them for a token
      await createStrategy('buy', 'active', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden1);

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(eth())).to.closeTo(eth().mul(5), eth().div(10));
    });

    it('gets correct value for the garden with finished strategy', async function () {
      // add 4 ETH to the garden, trade them for a token, and finish strategy
      await createStrategy('buy', 'final', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden1);

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(pricePerGardenToken.mul(totalSupply).div(eth())).to.closeTo(eth().mul(5), eth().div(10));
    });

    it('accounts for the keeper debt', async function () {
      // add 4 ETH to the garden and trade them for a token
      const strategy = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        garden1,
      );

      await executeStrategy(strategy, { fee: eth(1), amount: eth(4), time: ONE_DAY_IN_SECONDS });

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const totalSupply = await garden1.totalSupply();

      expect(await garden1.keeperDebt()).to.equal(eth());
      expect(pricePerGardenToken.mul(totalSupply).div(eth())).to.closeTo(eth().mul(4), eth().div(10));
    });

    it('gets correct value for the garden 0 price asset', async function () {
      const revertOracleFactory = await ethers.getContractFactory('RevertOracle');
      const revertOracle = await revertOracleFactory.deploy(tokenIdentifier.address, babController.address);

      // add 4 ETH to the garden, trade them for a token, and finish strategy
      await createStrategy('buy', 'active', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, garden1);

      await setCode(priceOracle.address, revertOracle.address);

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);

      expect(pricePerGardenToken.mul(await garden1.totalSupply()).div(eth())).to.closeTo(eth().mul(4), eth().div(10));
    });
  });
});
