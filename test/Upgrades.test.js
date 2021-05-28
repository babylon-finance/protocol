const { expect } = require('chai');

const { setupTests } = require('./fixtures/GardenFixture');

describe.only('Upgrades', function () {
  let upgradesDeployer;
  let owner;

  beforeEach(async () => {
    ({ owner, upgradesDeployer } = await setupTests()());
  });

  it('can upgrade BabController', async () => {
    const upgraded = await upgradesDeployer.deployOrUpgrade(
      'BabController',
      { from: owner.address, log: true },
      {
        upgrades: ['BabControllerV2Mock'],
      },
    );

    const upgradedContract = await ethers.getContractAt('BabControllerV2Mock', upgraded.address);

    expect(await upgradedContract.newVar()).to.equal(false);
    expect(await upgradedContract.newMethod()).to.equal('foobar');
    expect(await upgradedContract.uniswapFactory()).to.equal('0x1F98431c8aD98523631AE4a59f267346ea31F984');
  });
});
