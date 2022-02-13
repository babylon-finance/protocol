const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO } = require('lib/constants');
const { fund } = require('lib/whale');
const { getSigs } = require('lib/web3');
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

describe('VTableBeacon', function () {
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
        [vTableBeacon.address, getSigs(vTableBeacon)],
        [vTableBeacon.address, getSigs(vTableBeacon)],
        [vTableBeacon.address, getSigs(vTableBeacon)],
        [vTableBeacon.address, getSigs(vTableBeacon)],
        [vTableBeacon.address, getSigs(vTableBeacon)],
        [vTableBeacon.address, getSigs(vTableBeacon)],
        [vTableBeacon.address, getSigs(vTableBeacon)],
      ]);
    });

    it('remove module', async function () {
      await vTableBeacon.connect(owner).updateVTable([[vTableBeacon.address, getSigs(vTableBeacon)]]);
      await vTableBeacon.connect(owner).updateVTable([[ADDRESS_ZERO, getSigs(vTableBeacon)]]);
    });

    it('update module', async function () {
      await vTableBeacon.connect(owner).updateVTable([[vTableBeacon.address, getSigs(vTableBeacon)]]);
      await vTableBeacon.connect(owner).updateVTable([[vTableBeacon.address, getSigs(vTableBeacon)]]);
    });

    it('add new module', async function () {
      await vTableBeacon.connect(owner).updateVTable([[vTableBeacon.address, getSigs(vTableBeacon)]]);
    });

    it('only owner can update', async function () {
      await expect(vTableBeacon.updateVTable([])).to.be.revertedWith('Ownable: caller is not the owner');
    });
  });
});
