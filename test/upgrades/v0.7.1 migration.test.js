const { expect } = require('chai');
const { deployments } = require('hardhat');

const { impersonateAddress } = require('lib/rpc');
const { ONE_DAY_IN_SECONDS } = require('lib/constants.js');
const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const { increaseTime, getERC20 } = require('utils/test-helpers');

const { deploy } = deployments;

const upgradeFixture = deployments.createFixture(async (hre, options) => {
  const { ethers } = hre;

  const owner = await impersonateAddress('0xeA4E1d01Fad05465a84bAd319c93B73Fa12756fB');
  const deployer = await impersonateAddress('0x040cC3AF8455F3c34D1df1D2a305e047a062BeBf');
  const keeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');
  const dai = await getERC20(addresses.tokens.DAI);

  const controller = await ethers.getContractAt('BabController', '0xd4a5b5fcb561daf3adf86f8477555b92fba43b5f', owner);
  const ishtarGate = await ethers.getContractAt('MardukGate', '0x77d200eca7fd0a3db27e96d7b24cf7613b0a2a12', owner);
  const distributor = await ethers.getContractAt(
    'RewardsDistributor',
    '0x40154ad8014df019a53440a60ed351dfba47574e',
    owner,
  );

  await fund([owner.address, deployer.address], {
    tokens: [addresses.tokens.ETH],
  });

  const signers = await ethers.getSigners();
  const signer = signers[0];
  //
  // upgrade controller
  const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', owner);

  const controllerNewImpl = await deploy('BabController', {
    from: signer.address,
  });

  await proxyAdmin.upgrade(controller.address, controllerNewImpl.address);

  const mardukGate = await deploy('MardukGate', {
    from: signer.address,
    args: [controller.address, ishtarGate.address],
    log: true,
  });

  // edit marduk gate
  await controller.editMardukGate(mardukGate.address);

  // upgrade rewards distributor
  const distributorNewImpl = await deploy('RewardsDistributor', {
    from: signer.address,
  });

  await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address);

  // deploy new contracts
  for (const { contract, type, operation, args } of [
    {
      contract: 'ConvexStakeIntegration',
      type: 'integration',
      args: [controller.address],
    },
    {
      contract: 'CurvePoolIntegration',
      type: 'integration',
      args: [controller.address],
    },
    {
      contract: 'CurveTradeIntegration',
      type: 'integration',
      args: [controller.address],
    },
    {
      contract: 'SynthetixTradeIntegration',
      type: 'integration',
      args: [controller.address],
    },
    {
      contract: 'UniswapV2TradeIntegration',
      type: 'integration',
      args: [controller.address],
    },
    {
      contract: 'UniswapV3TradeIntegration',
      type: 'integration',
      args: [controller.address],
    },

    { contract: 'AddLiquidityOperation', type: 'operation', operation: 1, args: ['lp', controller.address] },
    { contract: 'DepositVaultOperation', type: 'operation', operation: 2, args: ['vault', controller.address] },
    { contract: 'LendOperation', type: 'operation', operation: 3, args: ['lend', controller.address] },
    { contract: 'BuyOperation', type: 'operation', operation: 0, args: ['buy', controller.address] },
  ]) {
    const deployment = await deploy(contract, {
      from: signer.address,
      args,
    });
    if (type === 'integration') {
    }
    if (type === 'operation') {
      await controller.setOperation(operation, deployment.address);
    }
  }

  // deploy MasterSwapper
  const masterSwapper = await deploy('MasterSwapper', {
    from: signer.address,
    args: [
      controller.address,
      (await deployments.get('CurveTradeIntegration')).address,
      (await deployments.get('UniswapV3TradeIntegration')).address,
      (await deployments.get('SynthetixTradeIntegration')).address,
      (await deployments.get('UniswapV2TradeIntegration')).address,
    ],
  });

  // deploy PriceOracle
  const priceOracle = await deploy('PriceOracle', {
    from: signer.address,
    args: [],
  });

  await controller.setMasterSwapper(masterSwapper.address);
  await controller.editPriceOracle(priceOracle.address);

  // upgrade strategy
  const strategyBeacon = await ethers.getContractAt(
    'UpgradeableBeacon',
    '0x31946680978CEFB010e5f5Fa8b8134c058cba7dC',
    deployer,
  );

  const strategyNewImpl = await deploy('Strategy', {
    from: signer.address,
    args: [],
    log: true,
  });

  await strategyBeacon.connect(deployer).upgradeTo(strategyNewImpl.address);

  // upgrade garden
  const gardenBeacon = await ethers.getContractAt(
    'UpgradeableBeacon',
    '0xc8f44C560efe396a6e57e48fF07205bD28AF5E75',
    deployer,
  );

  const gardenNewImpl = await deploy('Garden', {
    from: signer.address,
    args: [],
    log: true,
  });

  await gardenBeacon.connect(deployer).upgradeTo(gardenNewImpl.address);

  return { controller, owner, deployer, keeper, dai, distributor };
});

describe('v0.7.1', function () {
  let owner;
  let keeper;
  let priceOracle;
  let dai;
  let distributor;

  beforeEach(async () => {
    ({ owner, keeper, priceOracle, dai, distributor } = await upgradeFixture());
  });

  describe('after upgrade', function () {
    describe.skip('can finalizeStrategy', function () {
      for (const [name, strategy] of [
        ['Leverage long ETH', '0x49567812f97369a05e8D92462d744EFd00d7Ea42'],
        ['lend eth, borrow dai, harvest dai', '0xcd4fD2a8426c86067836d077eDA7FA2A1dF549dD'],
        ['Leverage BED', '0x0f4b1585ed506986d3a14436034D1D52704e5b56'],
        ['Stake ETH - Lido', '0xD8BAdcC27Ecb72F1e88b95172E7DeeeF921883C8'],
        ['Yearn USDC Vault', '0xa29b722f9D021FE435475b344355521Fa580940F'],
        ['Lend DAI on Aave', '0x4C449D3C878A6CabaD3f606A4978837Ac5196D5B'],
        ['Stake ETH', '0x07DEbD22bCa7d010E53fc8ec23E8ADc3a516eC08'],
        ['end eth, borrow dai, yearn da', '0x27cdbC334cF2dc7Aa720241e9a98Adbc8cc41254'],
        ['Stable Coin Farm Strategy', '0x40A561a3457F6EFDb8f80cDe3D55D280cce45f3a'],
        ['ETH-LINK LP', '0xc80C2f1c170fBD793845e67c58e2469569174EA2'],
        ['WETH-LINK', '0xe3bBF21574E18363733255ba56862E721CD2F3a4'],
        ['Long BED', '0xE064ad71dc506130A4C1C85Fb137606BaaCDe9c0'],
        ['Lend weth, borrow dai, farm yearn dai', '0xFDeA6F30F3dadD60382bAA07252923Ff6007c35d'],
        ['Lend wbtc, borrow dai, yield yearn dai', '0x81b1C6A04599b910e33b1AB549DE4a19E5701838'],
        ['Yearn - DAI Vault', '0x23E6E7B35E9E117176799cEF885B9D4a97D42df9'],
        ['ETHficient Stables', '0x3d4c6303E8E6ad9F4697a5c3deAe9827217439Ae'],
        ['long DAI', '0xB0147911b9d584618eB8F3BF63AD1AB858085101'],
        ['RAI/ETH UNI LP', '0x884957Fd342993A748c82aC608043859F1482126'],
      ]) {
        it(name, async () => {
          const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);

          await increaseTime(ONE_DAY_IN_SECONDS * 360);
          console.log('NAV', (await strategyContract.getNAV()).toString());
          console.log('CAPITAL ALLOCATED', (await strategyContract.capitalAllocated()).toString());
          await strategyContract.connect(keeper).finalizeStrategy(0, '');
          const [, active, , finalized, , exitedAt] = await strategyContract.getStrategyState();

          expect(active).eq(false);
          expect(finalized).eq(true);
          expect(exitedAt).gt(0);
        });
      }
    });
    describe('Backward compatibility with beta users and gardens after optimizing gas at RD', function () {
      it('should successfully migrate historic data from a Beta user of Arkad Garden and update / move power logic w/o checkpoints', async function () {
        const arkadGarden = await ethers.getContractAt('Garden', '0xd42B3A30ca89155d6C3499c81F0C4e5A978bE5c2'); // Arkad
        const contributor = await impersonateAddress('0xc31C4549356d46c37021393EeEb6f704B38061eC');
        const contributor2 = await impersonateAddress('0x166D00d97AF29F7F6a8cD725F601023b843ade66');

        await fund([contributor.address, contributor2.address], {
          tokens: [addresses.tokens.DAI],
          amounts: [ethers.utils.parseEther('500'), ethers.utils.parseEther('200')],
        });

        await dai.connect(contributor).approve(arkadGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
        await dai.connect(contributor2).approve(arkadGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
        const contributorBeforeUpdate = await arkadGarden.getContributor(contributor.address);

        const [betaPowerBefore, betaPowerBeforeBool] = await distributor.getBetaMigration(
          arkadGarden.address,
          contributor.address,
        );
        await arkadGarden.connect(contributor).deposit(ethers.utils.parseEther('200'), 1, contributor.address, false);

        const contributorAfterUpdate1 = await arkadGarden.getContributor(contributor.address);
        const [betaPowerAfter1, betaPowerBoolAfter1] = await distributor.getBetaMigration(
          arkadGarden.address,
          contributor.address,
        );

        await arkadGarden.connect(contributor).deposit(ethers.utils.parseEther('200'), 1, contributor.address, false);
        const [betaPowerAfter2, betaPowerBoolAfter2] = await distributor.getBetaMigration(
          arkadGarden.address,
          contributor.address,
        );

        const contributorAfterUpdate2 = await arkadGarden.getContributor(contributor.address);

        expect(contributorBeforeUpdate[8]).to.be.closeTo(
          ethers.utils.parseEther('0.037118723422909827'),
          contributorBeforeUpdate[8].div(50),
        ); // power before update from rewards distributor
        expect(betaPowerBefore[3]).to.equal(1624231155); // last deposit timestamp of Arkad
        expect(betaPowerBefore[4]).to.equal(ethers.utils.parseEther('311542600.000000000000000000')); // Arkad accumulated power
        expect(betaPowerBefore[5]).to.equal(ethers.utils.parseEther('200.000650163041324820')); // avg Balance
        expect(betaPowerBeforeBool[1]).to.equal(false); // pending migration
        expect(betaPowerBefore[0]).to.equal(1630918928); // last deposit timestamp of Arkad
        expect(betaPowerBefore[1]).to.equal(ethers.utils.parseEther('190745068890.174805973843135454')); // Arkad garden accumulated power
        expect(betaPowerBefore[2]).to.equal(ethers.utils.parseEther('200.521941033020828562')); // avg Balance
        expect(betaPowerBeforeBool[0]).to.equal(false); // pending migration

        // after update by first deposit
        expect(contributorAfterUpdate1[8]).to.be.closeTo(
          ethers.utils.parseEther('0.037118721112759008'),
          contributorAfterUpdate1[8].div(100),
        );
        expect(betaPowerAfter1[3]).to.be.closeTo(ethers.BigNumber.from(1630924367), 1000); // last deposit timestamp of Arkad
        expect(betaPowerAfter1[4]).to.equal(betaPowerBefore[4]); // Arkad accumulated power
        expect(betaPowerAfter1[5]).to.equal(betaPowerBefore[5]); // avg Balance
        expect(betaPowerBoolAfter1[1]).to.equal(true); // migration done during deposit
        expect(betaPowerAfter1[0]).to.equal(betaPowerAfter1[3]); // last deposit timestamp of Arkad
        expect(betaPowerAfter1[1]).to.equal(betaPowerBefore[1]); // Arkad garden accumulated power
        expect(betaPowerAfter1[2]).to.equal(betaPowerBefore[2]); // avg Balance
        expect(betaPowerBoolAfter1[0]).to.equal(true); // migration completed during deposit

        // after update by second deposit
        expect(contributorAfterUpdate2[8]).to.be.closeTo(
          ethers.utils.parseEther('0.037118717837723536'),
          contributorAfterUpdate2[8].div(100),
        );
        expect(betaPowerAfter2[3]).to.closeTo(ethers.BigNumber.from(1630924368), 1000); // last deposit timestamp of Arkad
        expect(betaPowerAfter2[4]).to.equal(betaPowerBefore[4]); // Arkad accumulated power
        expect(betaPowerAfter2[5]).to.equal(betaPowerBefore[5]); // avg Balance
        expect(betaPowerBoolAfter2[1]).to.equal(true); // migration done during deposit

        const [beta2PowerBefore, beta2PowerBeforeBool] = await distributor.getBetaMigration(
          arkadGarden.address,
          contributor2.address,
        );
        expect(beta2PowerBeforeBool[0]).to.equal(true); // migration of the garden completed during previous user deposit
        expect(beta2PowerBeforeBool[1]).to.equal(false); // migration of the contributor 2 pending

        const contributor2BeforeUpdate = await arkadGarden.getContributor(contributor2.address);
        expect(contributor2BeforeUpdate[8]).to.be.closeTo(
          ethers.utils.parseEther('0.029699513056892754'),
          contributor2BeforeUpdate[8].div(100),
        );

        await arkadGarden.connect(contributor2).deposit(ethers.utils.parseEther('200'), 1, contributor2.address, false);
        const [beta2PowerAfter1, beta2PowerAfter1Bool] = await distributor.getBetaMigration(
          arkadGarden.address,
          contributor2.address,
        );
        const contributor2AfterUpdate = await arkadGarden.getContributor(contributor2.address);

        expect(beta2PowerAfter1Bool[1]).to.equal(true); // user migration completed
        expect(contributor2AfterUpdate[8]).to.be.closeTo(
          ethers.utils.parseEther('0.029699513583252261'),
          contributor2AfterUpdate[8].div(100),
        );
        expect(beta2PowerBefore[1]).to.equal(beta2PowerAfter1[1]); // migration snapshot is kept (no change)
        expect(beta2PowerBefore[2]).to.equal(beta2PowerAfter1[2]); // migration snapshot is kept (no change)
        expect(beta2PowerBefore[4]).to.equal(beta2PowerAfter1[4]); // migration snapshot is kept (no change)
        expect(beta2PowerBefore[5]).to.equal(beta2PowerAfter1[5]); // migration snapshot is kept (no change)

        expect(beta2PowerAfter1[0]).to.equal(beta2PowerAfter1[3]); // last checkpoints are the same (garden vs. user)
      });
    });
  });
});
