const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO } = require('lib/constants');
const { fund } = require('lib/whale');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const {
  pick,
  increaseTime,
  normalizeDecimals,
  getERC20,
  getContract,
  parse,
  from,
  eth,
} = require('utils/test-helpers');

const SIGS = ['0xaaaaaaaa', '0xbbbbbbbb', '0xcccccccc'];
const IMPL = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';
const NEW_IMPL = '0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF';

describe.only('VTableBeacon', function () {
  let vTableBeacon;
  let owner;

  beforeEach(async () => {
    [, , owner] = await ethers.getSigners();
    const vTableBeaconFactory = await ethers.getContractFactory('VTableBeacon');
    vTableBeacon = await vTableBeaconFactory.deploy();
    await vTableBeacon.transferOwnership(owner.address);
  });

  describe('updateVTable', async function () {
    it('set many modules at once', async function () {
      await vTableBeacon.connect(owner).updateVTable([
        [IMPL, SIGS],
        [IMPL, SIGS],
        [IMPL, SIGS],
        [IMPL, SIGS],
        [IMPL, SIGS],
        [IMPL, SIGS],
        [IMPL, SIGS],
      ]);
    });

    it('remove module', async function () {
      await vTableBeacon.connect(owner).updateVTable([[IMPL, SIGS]]);
      await vTableBeacon.connect(owner).updateVTable([[ADDRESS_ZERO, SIGS]]);

      for (const sig of SIGS) {
        expect(await vTableBeacon.delegates(sig)).to.eq(ADDRESS_ZERO);
      }
    });

    it('update module', async function () {
      await vTableBeacon.connect(owner).updateVTable([[IMPL, SIGS]]);
      await vTableBeacon.connect(owner).updateVTable([[NEW_IMPL, SIGS]]);

      for (const sig of SIGS) {
        expect(await vTableBeacon.delegates(sig)).to.eq(NEW_IMPL);
      }
    });

    it('add new module', async function () {
      await vTableBeacon.connect(owner).updateVTable([[IMPL, SIGS]]);

      for (const sig of SIGS) {
        expect(await vTableBeacon.delegates(sig)).to.eq(IMPL);
      }
    });

    it('only owner can update', async function () {
      await expect(vTableBeacon.updateVTable([])).to.be.revertedWith('Ownable: caller is not the owner');
    });
  });
});
