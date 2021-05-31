const { expect } = require('chai');

const { setupTests } = require('./fixtures/GardenFixture');

describe.only('Upgrades', function () {
  let upgradesDeployer;
  let owner;

  beforeEach(async () => {
    ({ owner, upgradesDeployer, deployments } = await setupTests()());
  });

  describe('StrategyBeacon', function () {
    it('has correct owner', async () => {
      const deployment = await deployments.get('StrategyBeacon');
      const beacon = new ethers.Contract(deployment.address, deployment.abi);

      expect(await beacon.connect(owner).owner()).to.eq(owner.address);
    });
  });

  describe('Garden Beacon', function () {
    it('has correct owner', async () => {
      const deployment = await deployments.get('GardenBeacon');
      const beacon = new ethers.Contract(deployment.address, deployment.abi);

      expect(await beacon.connect(owner).owner()).to.eq(owner.address);
    });
  });

  describe('ProxyAdmin', function () {
    it('has correct owner', async () => {
      const deployment = await deployments.get('ProxyAdmin');
      const proxyAdmin = new ethers.Contract(deployment.address, deployment.abi);

      expect(await proxyAdmin.connect(owner).owner()).to.eq(owner.address);
    });
  });

  describe('BabController', function () {
    it('can upgrade', async () => {
      const proxy = await upgradesDeployer.deployOrUpgrade(
        'BabController',
        { from: owner.address, log: true },
        {
          upgrades: ['BabControllerV2Mock'],
        },
      );

      const upgradedContract = await ethers.getContractAt('BabControllerV2Mock', proxy.address);

      expect(await upgradedContract.newVar()).to.equal(false);
      expect(await upgradedContract.newMethod()).to.equal('foobar');

      // check that state is maintained
      expect(await upgradedContract.uniswapFactory()).to.equal('0x1F98431c8aD98523631AE4a59f267346ea31F984');
    });
  });

  describe('RewardsDistributor', function () {
    it('can upgrade', async () => {
      const proxy = await upgradesDeployer.deployOrUpgrade(
        'RewardsDistributor',
        { from: owner.address, log: true },
        {
          upgrades: ['RewardsDistributorV2Mock'],
        },
      );

      const v2Contract = await ethers.getContractAt('RewardsDistributorV2Mock', proxy.address);

      // check new method
      expect(await v2Contract.newMethod()).to.equal('foobar');

      // check that state is maintained
      expect(await v2Contract.controller()).to.equal('0xc3e53F4d16Ae77Db1c982e75a937B9f60FE63690');
    });
  });
});
