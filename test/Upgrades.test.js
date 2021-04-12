const { ethers, upgrades } = require('hardhat');
const { expect } = require('chai');

describe('Upgrades', function () {
  it('can upgrade BabController', async () => {
    const BabController = await ethers.getContractFactory('BabController');
    const BabControllerV2Mock = await ethers.getContractFactory('BabControllerV2Mock');

    const instance = await upgrades.deployProxy(BabController, []);
    const upgraded = await upgrades.upgradeProxy(instance.address, BabControllerV2Mock);

    expect(await upgraded.newVar()).to.equal(false);
    expect(await upgraded.newMethod()).to.equal('foobar');
  });
});
