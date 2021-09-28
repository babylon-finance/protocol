const { expect } = require('chai');
const { deployments, ethers } = require('hardhat');
const { from, eth } = require('lib/helpers');

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

  const gardens = await controller.getGardens();

  return { owner, keeper };
});

describe('v0.7.2', function () {
  let owner;
  let keeper;


  beforeEach(async () => {
    ({ owner, keeper } = await upgradeFixture());
  });

  describe('after upgrade', function () {
    describe.only('can calculate NAV and finalize strategies', function () {
      for (const [name, strategy] of [
        ['Leverage long ETH curve++', '0xcd9498b4160568DeEAb0fE3A0De739EbF152CB48'],
        ['Strategy 🏓 ETH Rebound DPI', '0x69ef15D3a4910EDc47145f6A88Ae60548F5AbC2C'],
        ['Leverage BED', '0x0f4b1585ed506986d3a14436034D1D52704e5b56'],
        ['Strategy crv strat', '0x208D1C629a41B7d24EB9B6d0989dfdB5a9b47d5d'],
        ['Strategy Stake ETH - Lido', '0xD8BAdcC27Ecb72F1e88b95172E7DeeeF921883C8'],
        ['Strategy Staked ETH Liquidity', '0x3FeaD42999D537477CE39335aA7b4951e8e78233'],
        ['Strategy Convex-boosted 3pool', '0x9D78319EDA31663B487204F0CA88A046e742eE16'],
        ['Strategy Stake ETH', '0x07DEbD22bCa7d010E53fc8ec23E8ADc3a516eC08'],
        ['Strategy Staked ETH Liquidity', '0x4f85dD417d19058cA81564f41572fb90D2F7e935'],
        ['Strategy Stable Coin Farm Strategy', '0x40A561a3457F6EFDb8f80cDe3D55D280cce45f3a'],
        ['Strategy ETH-LINK LP', '0xc80C2f1c170fBD793845e67c58e2469569174EA2'],
        ['Strategy WETH-LINK Pool', '0xe3bBF21574E18363733255ba56862E721CD2F3a4'],
        ['Strategy Long BED', '0xE064ad71dc506130A4C1C85Fb137606BaaCDe9c0'],
        ['Strategy Lend weth, borrow dai, farm yearn dai', '0xFDeA6F30F3dadD60382bAA07252923Ff6007c35d'],
        [' Strategy Lend wbtc, borrow dai, yield yearn dai', '0x81b1C6A04599b910e33b1AB549DE4a19E5701838'],
        ['Strategy Long DAI @ Curve Compound Convex', '0x9f794DD83E2C815158Fc290c3c2b20f8B6605746'],
        ['Strategy ETHficient Stables', '0x3d4c6303E8E6ad9F4697a5c3deAe9827217439Ae'],
      ]) {
        it(name, async () => {
          const strategyContract = await ethers.getContractAt('IStrategy', strategy, owner);

          await increaseTime(ONE_DAY_IN_SECONDS * 360);
          console.log('NAV', (await strategyContract.getNAV()).toString());
          console.log('CAPITAL ALLOCATED', (await strategyContract.capitalAllocated()).toString());
          await strategyContract.connect(keeper).finalizeStrategy(0, '');
          // const [, active, , finalized, , exitedAt] = await strategyContract.getStrategyState();

          // expect(active).eq(false);
          // expect(finalized).eq(true);
          // expect(exitedAt).gt(0);
        });
      }
    });
  });
});
