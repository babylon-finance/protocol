const { expect } = require('chai');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { pick, getERC20, eth, from, increaseTime } = require('utils/test-helpers');

const AAVE_POOL = '0xDeBF20617708857ebe4F679508E7b7863a8A8EeE';

describe('CurveMetaRegistry', function () {
  let curveMetaRegistry;

  beforeEach(async () => {
    const registryFactory = await ethers.getContractFactory('CurveMetaRegistry');
    curveMetaRegistry = await registryFactory.deploy('0xD4a5b5fcB561dAF3aDF86F8477555B92FBa43b5F');
  });

  describe('getCoinIndices', async function () {
    it('aave pool', async function () {
      const [from, to, ret] = await curveMetaRegistry.getCoinIndices(
        AAVE_POOL,
        '0x6b175474e89094c44da98b954eedeac495271d0f',
        '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
      );
      expect(from.toNumber()).to.eq(0);
      expect(to.toNumber()).to.eq(1);
      expect(ret).to.eq(true);
    });
  });

  describe('findPoolForCoins', async function () {
    it('aave pool', async function () {
      expect(
        await curveMetaRegistry.findPoolForCoins(
          '0x6b175474e89094c44da98b954eedeac495271d0f',
          '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
          0,
        ),
      ).to.eq('0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7');
    });
  });

  describe('getUnderlyingAndRate', async function () {
    it('aave pool', async function () {
      const [coin, rate] = await curveMetaRegistry.getUnderlyingAndRate(AAVE_POOL, 0);
      expect(coin).to.eq('0x6B175474E89094C44Da98b954EedeAC495271d0F');
      expect(rate).to.eq(eth());
    });
  });

  describe('getVirtualPriceFromLpToken', async function () {
    it('aave pool', async function () {
      expect(
        await curveMetaRegistry.getVirtualPriceFromLpToken('0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900'),
      ).to.closeTo(from('1084477391888198085'), eth(0.1));
    });
  });

  describe('isMeta', async function () {
    it('aave pool', async function () {
      expect(await curveMetaRegistry.isMeta(AAVE_POOL)).to.eq(false);
    });
  });

  describe('getPoolFromLpToken', async function () {
    it('aave pool', async function () {
      expect(await curveMetaRegistry.getPoolFromLpToken('0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900')).to.eq(AAVE_POOL);
    });
  });

  describe('getLpToken', async function () {
    it('aave pool', async function () {
      expect(await curveMetaRegistry.getLpToken(AAVE_POOL)).to.eq('0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900');
    });
  });

  describe('getNCoins', async function () {
    it('aave pool', async function () {
      expect(await curveMetaRegistry.getNCoins(AAVE_POOL)).to.eq(3);
    });
  });

  describe('getCoinAddresses', async function () {
    it('aave pool', async function () {
      expect(await curveMetaRegistry.getCoinAddresses(AAVE_POOL, false)).deep.to.eq([
        '0x028171bCA77440897B824Ca71D1c56caC55b68A3',
        '0xBcca60bB61934080951369a648Fb03DF4F96263C',
        '0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
        '0x0000000000000000000000000000000000000000',
      ]);
    });
  });

  describe('isPool', async function () {
    it('checks a normal Curve pool', async function () {
      expect(await curveMetaRegistry.isPool(addresses.curve.pools.v3.tripool)).to.equal(true);
    });

    it('checks a factory Curve pool', async function () {
      expect(await curveMetaRegistry.isPool(addresses.curve.pools.factory.cvxcrv)).to.equal(true);
    });

    it('checks a crypto Curve pool', async function () {
      expect(await curveMetaRegistry.isPool(addresses.curve.pools.crypto.tricrypto2)).to.equal(true);
    });

    it('checks a crypto factory Curve pool', async function () {
      expect(await curveMetaRegistry.isPool(addresses.curve.pools.crypto.tricrypto2)).to.equal(true);
    });

    it('checks a non-valid Curve pool', async function () {
      expect(await curveMetaRegistry.isPool('0x158079Ee67Fce2f58472A96584A73C7Ab9AC95c1')).to.equal(false);
    });
  });
});
