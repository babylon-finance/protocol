const { expect } = require('chai');

const { impersonateAddress } = require('../lib/rpc');
const { ONE_DAY_IN_SECONDS, GARDEN_PARAMS } = require('../lib/constants.js');
const addresses = require('../lib/addresses');
const { increaseTime } = require('./utils/test-helpers');
const { createStrategy, executeStrategy } = require('./fixtures/StrategyHelper.js');
const { setupTests } = require('./fixtures/GardenFixture');

describe('Upgrades', function () {
  let upgradesDeployer;
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let deploy;
  let strategy11;
  let garden1;
  let babController;

  async function upgradeFixture() {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    const signer = await getSigner(deployer);
    const gasPrice = await getRapid();

    const contract1 = 'UniswapPoolIntegration';
    const contract2 = 'SushiswapPoolIntegration';
    const contract3 = 'OneInchPoolIntegration';
    const contract4 = 'BuyOperation';
    const contract5 = 'AddLiquidityOperation';
    const contract6 = 'DepositVaultOperation';
    const contract7 = 'BorrowOperation';
    const contract8 = 'LendOperation';

    const controller = await deployments.get('BabControllerProxy');
    const controllerContract = await ethers.getContractAt('BabController', controller.address, signer);

    const deploymentUni = await deploy(contract1, {
      from: deployer,
      args: [controller.address, addresses.uniswap.router],
      log: true,
      gasPrice,
    });

    const deploymentSushi = await deploy(contract2, {
      from: deployer,
      args: [controller.address, addresses.sushiswap.router],
      log: true,
      gasPrice,
    });

    const deploymentInch = await deploy(contract3, {
      from: deployer,
      args: [controller.address, addresses.oneinch.factory],
      log: true,
      gasPrice,
    });

    const deploymentBuyOp = await deploy(contract4, {
      from: deployer,
      args: ['buy', controller.address],
      log: true,
      gasPrice,
    });

    const deploymentAddOp = await deploy(contract5, {
      from: deployer,
      args: ['lp', controller.address],
      log: true,
      gasPrice,
    });

    const deploymentVaultOp = await deploy(contract6, {
      from: deployer,
      args: ['vault', controller.address],
      log: true,
      gasPrice,
    });

    const deploymentBorrowOp = await deploy(contract7, {
      from: deployer,
      args: ['borrow', controller.address],
      log: true,
      gasPrice,
    });

    const deploymentLendOp = await deploy(contract8, {
      from: deployer,
      args: ['lend', controller.address],
      log: true,
      gasPrice,
    });

    if (
      deploymentUni.newlyDeployed &&
      deploymentSushi.newlyDeployed &&
      deploymentInch.newlyDeployed &&
      deploymentBuyOp.newlyDeployed &&
      deploymentAddOp.newlyDeployed &&
      deploymentVaultOp.newlyDeployed &&
      deploymentBorrowOp.newlyDeployed &&
      deploymentLendOp.newlyDeployed
    ) {
      await (
        await controllerContract.addIntegration(
          await (await ethers.getContractAt(contract1, deploymentUni.address)).getName(),
          deploymentUni.address,
          { gasPrice },
        )
      ).wait();
      await (
        await controllerContract.addIntegration(
          await (await ethers.getContractAt(contract2, deploymentSushi.address)).getName(),
          deploymentSushi.address,
          { gasPrice },
        )
      ).wait();
      await (
        await controllerContract.addIntegration(
          await (await ethers.getContractAt(contract3, deploymentInch.address)).getName(),
          deploymentInch.address,
          { gasPrice },
        )
      ).wait();

      await (await controllerContract.setOperation(0, deploymentBuyOp.address, { gasPrice })).wait();
      await (await controllerContract.setOperation(1, deploymentAddOp.address, { gasPrice })).wait();
      await (await controllerContract.setOperation(2, deploymentVaultOp.address, { gasPrice })).wait();
      await (await controllerContract.setOperation(4, deploymentBorrowOp.address, { gasPrice })).wait();
      await (await controllerContract.setOperation(3, deploymentLendOp.address, { gasPrice })).wait();
    }

    const deployment = await deployments.get('StrategyBeacon');
    const beacon = new ethers.Contract(deployment.address, deployment.abi);

    const newImpl = await deploy('Strategy', {
      from: owner.address,
      args: [],
      log: true,
    });

    await beacon.connect(owner).upgradeTo(newImpl.address);
    const mainnetKeeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');
    await increaseTime(ONE_DAY_IN_SECONDS * 120);
    return mainnetKeeper;
  }

  beforeEach(async () => {
    ({
      babController,
      garden1,
      strategy11,
      owner,
      signer1,
      signer2,
      signer3,
      uniswapV3TradeIntegration,
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

    it('can upgrade to a new impl existing and new strategies', async () => {
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
        uniswapV3TradeIntegration.address,
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
          [false, false, false],
          [0, 0, 0],
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
    it.skip('can upgrade', async () => {
      const proxy = await upgradesDeployer.deployAdminProxy(
        'BabControllerV3',
        'BabControllerProxy',
        { from: owner.address, log: true },
        {
          upgrades: ['BabControllerV2Mock'],
        },
      );

      const upgradedContract = await ethers.getContractAt('IBabController', proxy.address);

      expect(await upgradedContract.newVar()).to.equal(false);
      expect(await upgradedContract.newMethod()).to.equal('foobar');

      // check that state is maintained
      expect(await upgradedContract.uniswapFactory()).to.equal('0x1F98431c8aD98523631AE4a59f267346ea31F984');
    });
  });

  describe('RewardsDistributor', function () {
    it.skip('can upgrade', async () => {
      const proxy = await upgradesDeployer.deployAdminProxy(
        'RewardsDistributor',
        'RewardsDistributorProxy',
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
