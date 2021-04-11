const { ethers, upgrades } = require('hardhat');
const { expect } = require('chai');

describe('Upgrades', function () {
  it('can upgrade BabController', async () => {
    const BabController = await ethers.getContractFactory('BabController');
    const BabControllerV2Mock = await ethers.getContractFactory('BabControllerV2Mock');

    const instance = await upgrades.deployProxy(BabController, [
      '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      '0xfc9da5D8b594B8fD7021C6B0eE5a00Ec2C4c132d',
      '0xfc9da5D8b594B8fD7021C6B0eE5a00Ec2C4c132d',
      '0xfc9da5D8b594B8fD7021C6B0eE5a00Ec2C4c132d',
      '0xfc9da5D8b594B8fD7021C6B0eE5a00Ec2C4c132d',
      '0xfc9da5D8b594B8fD7021C6B0eE5a00Ec2C4c132d',
    ]);
    const upgraded = await upgrades.upgradeProxy(instance.address, BabControllerV2Mock);

    expect(await upgraded.newVar()).to.equal(false);
    expect(await upgraded.newMethod()).to.equal('foobar');
  });
});
