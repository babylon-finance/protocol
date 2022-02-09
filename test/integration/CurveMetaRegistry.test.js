const { expect } = require('chai');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
// const { pick, getERC20, eth, from, increaseTime } = require('utils/test-helpers');

describe('CurveMetaRegistry Integration Test', function () {
  let curveMetaRegistry;
  let babController;

  beforeEach(async () => {
    ({
      babController,
      curveMetaRegistry
    } = await setupTests()());
  });


  describe('Registries are properly set up', async function () {
    it('checks a normal curve pool', async function () {
      expect(await curveMetaRegistry.isPool(addresses.curve.pools.v3.tripool)).to.equal(true);
    });

    it('checks a factory curve pool', async function () {
      expect(await curveMetaRegistry.isPool(addresses.curve.pools.factory.cvxcrv)).to.equal(true);
    });

    it('checks a crypto curve pool', async function () {
      expect(await curveMetaRegistry.isPool(addresses.curve.pools.crypto.tricrypto2)).to.equal(true);
    });

    it('checks a crypto factory curve pool', async function () {
      expect(await curveMetaRegistry.isPool(addresses.curve.pools.crypto.tricrypto2)).to.equal(true);
    });

    it('checks a non-valid curve pool', async function () {
      expect(await curveMetaRegistry.isPool('0x158079Ee67Fce2f58472A96584A73C7Ab9AC95c1')).to.equal(false);
    });
  });
});
