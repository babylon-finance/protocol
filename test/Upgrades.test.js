const { expect } = require('chai');

const { GARDEN_PARAMS } = require('../lib/constants.js');
const addresses = require('../lib/addresses');
const { createStrategy } = require('./fixtures/StrategyHelper.js');
const { setupTests } = require('./fixtures/GardenFixture');

describe('Upgrades', function () {
  let upgradesDeployer;
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let oneInchTradeIntegration;
  let deploy;
  let strategy11;
  let garden1;
  let babController;

  beforeEach(async () => {
    ({
      babController,
      garden1,
      strategy11,
      owner,
      signer1,
      signer2,
      signer3,
      oneInchTradeIntegration,
      upgradesDeployer,
      deployments,
    } = await setupTests()());
    ({ deploy } = deployments);
  });

  describe('StrategyBeacon', function () {
    it('has correct owner', async () => {
      const deployment = await deployments.get('StrategyBeacon');
      const beacon = new ethers.Contract(deployment.address, deployment.abi);

      expect(await beacon.connect(owner).owner()).to.eq(owner.address);
    });

    it('can upgrade to a v2 existing and new strategies', async () => {
      const deployment = await deployments.get('StrategyBeacon');
      const beacon = new ethers.Contract(deployment.address, deployment.abi);

      const v2 = await deploy('StrategyV2Mock', {
        from: owner.address,
        args: [],
        log: true,
      });

      await beacon.connect(owner).upgradeTo(v2.address);

      // check that old strategies have changed
      const existingStrategy = new ethers.Contract(strategy11, v2.abi);

      expect(await existingStrategy.connect(owner).newMethod()).to.eq('foobar');
      expect(await existingStrategy.connect(owner).newVar()).to.eq('0');
      expect(await existingStrategy.connect(owner).duration()).to.eq('65536');

      // check that new strategies have changed
      let freshStrategy = await createStrategy(
        'buy',
        'dataset',
        [signer1, signer2, signer3],
        oneInchTradeIntegration.address,
        garden1,
      );

      freshStrategy = new ethers.Contract(freshStrategy.address, v2.abi);
      expect(await freshStrategy.connect(owner).newMethod()).to.eq('foobar');
      expect(await freshStrategy.connect(owner).newVar()).to.eq('42');
      expect(await freshStrategy.connect(owner).duration()).to.eq('0');
    });
  });

  describe('Garden Beacon', function () {
    it('has correct owner', async () => {
      const deployment = await deployments.get('GardenBeacon');
      const beacon = new ethers.Contract(deployment.address, deployment.abi);

      expect(await beacon.connect(owner).owner()).to.eq(owner.address);
    });

    it('can upgrade to a v2 existing and new gardens', async () => {
      const deployment = await deployments.get('GardenBeacon');
      const beacon = new ethers.Contract(deployment.address, deployment.abi);

      const v2 = await deploy('GardenV2Mock', {
        from: owner.address,
        args: [],
        log: true,
      });

      await beacon.connect(owner).upgradeTo(v2.address);

      // check that old strategies have changed
      const garden = new ethers.Contract(garden1.address, v2.abi);
      expect(await garden.connect(owner).newMethod()).to.eq('foobar');
      expect(await garden.connect(owner).newVar()).to.eq('0');
      expect(await garden.connect(owner).name()).to.eq('Absolute ETH Return [beta]');

      // check that new strategies have changed
      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.WETH,
          'Absolute ETH Return [beta]',
          'EYFA',
          'http...',
          0,
          GARDEN_PARAMS,
          ethers.utils.parseEther('1'),
          {
            value: ethers.utils.parseEther('1'),
          },
        );

      const gardens = await babController.connect(owner).getGardens();

      freshGarden = new ethers.Contract(gardens[4], v2.abi);

      expect(await freshGarden.connect(owner).newMethod()).to.eq('foobar');
      expect(await freshGarden.connect(owner).newVar()).to.eq('42');
      expect(await freshGarden.connect(owner).name()).to.eq('');
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
