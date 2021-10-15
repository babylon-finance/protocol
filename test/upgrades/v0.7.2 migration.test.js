const { expect } = require('chai');
const { deployments, ethers } = require('hardhat');
const { from, eth } = require('lib/helpers');

const { impersonateAddress } = require('lib/rpc');
const { ONE_DAY_IN_SECONDS, ADDRESS_ZERO } = require('lib/constants.js');
const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const { increaseTime, getERC20 } = require('utils/test-helpers');
const { depositFunds } = require('fixtures/GardenHelper');

const { deploy } = deployments;

const upgradeFixture = deployments.createFixture(async (hre, options) => {
  const { ethers } = hre;
  // This test needs block number = 13423675 to check previous migrations, so the owner should be 0x0B89
  /*   const owner = await impersonateAddress('0xeA4E1d01Fad05465a84bAd319c93B73Fa12756fB');*/
  const owner = await impersonateAddress('0x0B892EbC6a4bF484CDDb7253c6BD5261490163b9');
  let deployer = await impersonateAddress('0x040cC3AF8455F3c34D1df1D2a305e047a062BeBf');
  const keeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');
  const dai = await getERC20(addresses.tokens.DAI);
  const weth = await getERC20(addresses.tokens.WETH);
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
  deployer = owner;
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
  return { controller, owner, deployer, keeper, dai, weth, distributor, gardens, ishtarGate };
});

describe('v0.7.2', function () {
  let owner;
  let keeper;
  let priceOracle;
  let dai;
  let weth;
  let distributor;
  let gardens;
  let deployer;
  let ishtarGate;

  beforeEach(async () => {
    ({ owner, keeper, priceOracle, dai, weth, distributor, gardens, deployer, ishtarGate } = await upgradeFixture());
  });

  describe('after upgrade', function () {
    describe('Backward compatibility with beta users and gardens after removing migration logic from RD', function () {
      it('should successfully get contributor data of Arkad Garden after removing migration logic', async function () {
        const arkadGarden = await ethers.getContractAt('Garden', '0xd42B3A30ca89155d6C3499c81F0C4e5A978bE5c2'); // Arkad
        const contributor = await impersonateAddress('0xc31C4549356d46c37021393EeEb6f704B38061eC');
        const contributor2 = await impersonateAddress('0x166D00d97AF29F7F6a8cD725F601023b843ade66');
        const contributor3 = await impersonateAddress('0xa0Ee7A142d267C1f36714E4a8F75612F20a79720');
        await ishtarGate
          .connect(contributor)
          .setGardenAccess(contributor3.address, arkadGarden.address, 1, { gasPrice: 0 });

        await fund([contributor.address, contributor2.address, contributor3.address], {
          tokens: [addresses.tokens.DAI],
          amounts: [ethers.utils.parseEther('500'), ethers.utils.parseEther('200'), ethers.utils.parseEther('500')],
        });

        await dai.connect(contributor).approve(arkadGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
        await dai.connect(contributor2).approve(arkadGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
        await dai.connect(contributor3).approve(arkadGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });

        const [, contributorBoolData] = await distributor.getContributorPerGarden(
          arkadGarden.address,
          contributor2.address,
        );
        expect(contributorBoolData[0]).to.equal(true);
        expect(contributorBoolData[1]).to.equal(true);

        await arkadGarden.connect(contributor2).deposit(ethers.utils.parseEther('200'), 1, contributor2.address, false);

        const [contributorDataAfter1] = await distributor.getContributorPerGarden(
          arkadGarden.address,
          contributor2.address,
        );
        // las garden deposit = new user deposit
        expect(contributorDataAfter1[0]).to.equal(contributorDataAfter1[10]);

        await arkadGarden
          .connect(contributor2)
          .withdraw(
            await arkadGarden.balanceOf(contributor2.address),
            1,
            contributor2.getAddress(),
            false,
            ADDRESS_ZERO,
            {
              gasPrice: 0,
            },
          );

        const [contributorDataAfter2] = await distributor.getContributorPerGarden(
          arkadGarden.address,
          contributor2.address,
        );
        expect(contributorDataAfter2[0]).to.equal(0);
        expect(contributorDataAfter2[1]).to.equal(0);
        expect(contributorDataAfter2[3]).to.equal(0);
        expect(contributorDataAfter2[5]).to.equal(0);

        await arkadGarden.connect(contributor2).deposit(ethers.utils.parseEther('200'), 1, contributor2.address, false);

        await arkadGarden
          .connect(contributor2)
          .withdraw(
            await arkadGarden.balanceOf(contributor2.address),
            1,
            contributor2.getAddress(),
            false,
            ADDRESS_ZERO,
            {
              gasPrice: 0,
            },
          );

        await arkadGarden.connect(contributor3).deposit(ethers.utils.parseEther('200'), 1, contributor3.address, false);
        const [contributor3DataAfter, contributor3BoolDataAfter] = await distributor.getContributorPerGarden(
          arkadGarden.address,
          contributor3.address,
        );
        expect(contributor3DataAfter[0]).to.gt(0);
        // initial deposit = last deposit
        expect(contributor3DataAfter[0]).to.equal(contributor3DataAfter[1]);
        expect(contributor3BoolDataAfter[0]).to.equal(true);
        // it was not a beta user
        expect(contributor3BoolDataAfter[1]).to.equal(false);
        await arkadGarden
          .connect(contributor3)
          .withdraw(
            await arkadGarden.balanceOf(contributor3.address),
            1,
            contributor3.getAddress(),
            false,
            ADDRESS_ZERO,
            {
              gasPrice: 0,
            },
          );
        const [contributor3DataAfter1, contributor3BoolDataAfter1] = await distributor.getContributorPerGarden(
          arkadGarden.address,
          contributor3.address,
        );
        expect(contributor3DataAfter1[0]).to.equal(0);
        expect(contributor3DataAfter1[1]).to.equal(0);
        expect(contributor3DataAfter1[3]).to.equal(0);
        expect(contributor3DataAfter1[5]).to.equal(0);
        expect(contributor3BoolDataAfter1[0]).to.equal(true);
        // it was not a beta user
        expect(contributor3BoolDataAfter1[1]).to.equal(false);
      });
    });
    describe('can remove migration logic from all gardens', function () {
      it('should successfully remove migration data keeping all beta creators and their beta gardens intact', async function () {
        for (let i = 0; i < gardens.length; i++) {
          const garden = await ethers.getContractAt('Garden', gardens[i]);
          const creator = await garden.creator();
          const contributor = await impersonateAddress('0xa0Ee7A142d267C1f36714E4a8F75612F20a79720');
          const creatorWallet = await impersonateAddress(creator);
          await ishtarGate
            .connect(creatorWallet)
            .setGardenAccess(contributor.address, garden.address, 1, { gasPrice: 0 });

          await fund([contributor.address, contributor.address], {
            tokens: [addresses.tokens.DAI, addresses.tokens.WETH],
            amounts: [ethers.utils.parseEther('3000'), ethers.utils.parseEther('3')],
          });
          await dai.connect(contributor).approve(garden.address, ethers.utils.parseEther('3000'), { gasPrice: 0 });
          await weth.connect(contributor).approve(garden.address, ethers.utils.parseEther('3'), { gasPrice: 0 });
          const asset = await garden.reserveAsset();
          if (asset === addresses.tokens.DAI) {
            await garden
              .connect(contributor)
              .deposit(ethers.utils.parseEther('3000'), 1, contributor.address, false, { gasPrice: 0 });
          } else {
            // WETH Garden
            await garden
              .connect(contributor)
              .deposit(ethers.utils.parseEther('3'), 1, contributor.address, false, { gasPrice: 0 });
          }

          const [, contributorBoolDataAfter] = await distributor.getContributorPerGarden(
            garden.address,
            contributor.address,
          );
          const [creatorDataAfter, creatorBoolDataAfter] = await distributor.getContributorPerGarden(
            garden.address,
            creator,
          );
          /* 
          contributorData[0] = contributor.lastDepositAt;
          contributorData[1] = contributor.initialDepositAt;
          contributorData[2] = contributor.pid;
          contributorData[3] = contributorDetail.avgBalance;
          contributorData[4] = ERC20(garden).balanceOf(contributor);
          contributorData[5] = contributorDetail.power;
          contributorData[6] = contributorDetail.timestamp;
          contributorData[7] = contributorDetail.timePointer;
          contributorData[8] = gardenPid[_garden];
          contributorData[9] = garden.avgGardenBalance;
          contributorData[10] = garden.lastDepositAt;
          contributorData[11] = garden.accGardenPower;
          contributorBool[0] = betaGardenMigrated[_garden];
          contributorBool[1] = betaUserMigrated[_garden][_contributor]; */

          expect(contributorBoolDataAfter[0]).to.equal(true); // garden
          expect(contributorBoolDataAfter[1]).to.equal(false); // new user (not beta user)
          // Some creators left from their gardens before migration, they have 0 balance, no need (and not recommended) to migrate
          if (creator !== ADDRESS_ZERO && creatorDataAfter[4] > 0) {
            expect(creatorBoolDataAfter[1]).to.equal(true); // creator
          }
        }
      });
    });
  });
});
