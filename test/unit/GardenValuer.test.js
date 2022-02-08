const { expect } = require('chai');

const { fund } = require('lib/whale');
const { from, eth, parse } = require('lib/helpers');
const { impersonateAddress, setCode } = require('lib/rpc');
const addresses = require('lib/addresses');
const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS, STRATEGY_EXECUTE_MAP } = require('lib/constants.js');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden } = require('fixtures/GardenHelper');
const { getStrategy, createStrategy, finalizeStrategy, executeStrategy } = require('fixtures/StrategyHelper.js');

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
    await fund([signer1.address, signer2.address, signer3.address]);
  });

  describe('deployment', function () {
    it('should NOT allow zero address for controller during deployment', async function () {
      const { deploy } = deployments;
      const { deployer, owner } = await getNamedAccounts();
      const contract = 'GardenValuer';
      await expect(
        deploy(contract, {
          from: deployer,
          args: [ADDRESS_ZERO],
          log: true,
    ...await getGasPrice()
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
      console.log('createGarden');
      const garden = await createGarden({ reserveAsset: addresses.tokens.DAI });
      console.log('getStrategy');
      const strategy = await getStrategy({ garden, state: 'vote', specificParams: [addresses.tokens.USDT, 0] });

      console.log('execute');
      await executeStrategy(strategy, { fee: eth(2000), amount: eth(12000), time: ONE_DAY_IN_SECONDS });

      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden.address, addresses.tokens.DAI);
      const totalSupply = await garden.totalSupply();

      expect(await garden.keeperDebt()).to.equal(eth(2000));
      expect(pricePerGardenToken.mul(totalSupply).div(eth())).to.closeTo(eth(12000), eth(100));
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
