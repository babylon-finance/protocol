const { expect } = require('chai');
const { deployments, ethers } = require('hardhat');
const { from, eth } = require('lib/helpers');

const { impersonateAddress } = require('lib/rpc');
const { ONE_DAY_IN_SECONDS, ADDRESS_ZERO } = require('lib/constants.js');
const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const { increaseTime, getERC20 } = require('utils/test-helpers');

const { deploy } = deployments;

const upgradeFixture = deployments.createFixture(async (hre, options) => {
  const { ethers } = hre;

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
  return { controller, owner, deployer, keeper, dai, weth, distributor, gardens };
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

  beforeEach(async () => {
    ({ owner, keeper, priceOracle, dai, weth, distributor, gardens, deployer } = await upgradeFixture());
  });

  describe('after upgrade', function () {
    describe('Backward compatibility with beta users and gardens after removing migration logic from RD', function () {
      it.only('should successfully get contributor data of Arkad Garden after removing migration logic', async function () {
        const arkadGarden = await ethers.getContractAt('Garden', '0xd42B3A30ca89155d6C3499c81F0C4e5A978bE5c2'); // Arkad
        const contributor = await impersonateAddress('0xc31C4549356d46c37021393EeEb6f704B38061eC');
        const contributor2 = await impersonateAddress('0x166D00d97AF29F7F6a8cD725F601023b843ade66');

        await fund([contributor.address, contributor2.address, deployer.address], {
          tokens: [addresses.tokens.DAI],
          amounts: [ethers.utils.parseEther('500'), ethers.utils.parseEther('200'), ethers.utils.parseEther('500')],
        });

        await dai.connect(contributor).approve(arkadGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
        await dai.connect(contributor2).approve(arkadGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
        await dai.connect(deployer).approve(arkadGarden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });

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
        expect(contributorDataAfter1[0]).to.equal(contributorDataAfter1[9]);

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
        expect(contributorDataAfter2[4]).to.equal(0);

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

        await arkadGarden.connect(deployer).deposit(ethers.utils.parseEther('200'), 1, deployer.address, false);
        const [deployerDataAfter, deployerBoolDataAfter] = await distributor.getContributorPerGarden(
          arkadGarden.address,
          deployer.address,
        );
        expect(deployerDataAfter[0]).to.gt(0);
        // initial deposit = last deposit
        expect(deployerDataAfter[0]).to.equal(deployerDataAfter[1]);
        expect(deployerBoolDataAfter[0]).to.equal(true);
        // it was not a beta user
        expect(deployerBoolDataAfter[1]).to.equal(false);
        await arkadGarden
          .connect(deployer)
          .withdraw(await arkadGarden.balanceOf(deployer.address), 1, deployer.getAddress(), false, ADDRESS_ZERO, {
            gasPrice: 0,
          });
        const [deployerDataAfter1, deployerBoolDataAfter1] = await distributor.getContributorPerGarden(
          arkadGarden.address,
          deployer.address,
        );
        expect(deployerDataAfter1[0]).to.equal(0);
        expect(deployerDataAfter1[1]).to.equal(0);
        expect(deployerDataAfter1[3]).to.equal(0);
        expect(deployerDataAfter1[4]).to.equal(0);
        expect(deployerBoolDataAfter1[0]).to.equal(true);
        // it was not a beta user
        expect(deployerBoolDataAfter1[1]).to.equal(false);
      });
    });
    describe.skip('can remove migration logic from all gardens', function () {
      it('should successfully remove migration data keeping all beta creators and their beta gardens intact', async function () {
        for (let i = 0; i < gardens.length; i++) {
          const garden = await ethers.getContractAt('Garden', gardens[i]);
          const creator = await garden.creator();
          console.log('NEW GARDEN CHECK ---- ', garden.address, creator);
          await fund([deployer.address, deployer.address], {
            tokens: [addresses.tokens.DAI, addresses.tokens.WETH],
            amounts: [ethers.utils.parseEther('500'), ethers.utils.parseEther('200'), ethers.utils.parseEther('500')],
          });
          await dai.connect(deployer).approve(garden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });
          await weth.connect(deployer).approve(garden.address, ethers.utils.parseEther('500'), { gasPrice: 0 });

          await garden.connect(deployer).deposit(ethers.utils.parseEther('200'), 1, deployer.address, false);

          const [contributorDataAfter, contributorBoolDataAfter] = await distributor.getContributorPerGarden(
            garden.address,
            creator,
          );

          const creatorBeforeUpdate = await garden.getContributor(creator);
          if (contributorBoolDataAfter[1] === false || contributorBoolDataAfter[0] === false) {
            // new garden created after migration
            console.log('NEW GARDEN WAS CREATED', garden.address, creator);
          } else {
            expect(contributorBoolDataAfter[0]).to.equal(true); // pending migration of the garden
            expect(contributorBoolDataAfter[1]).to.equal(true); // pending migration of the creator
          }

          expect(contributorDataAfter[0]).to.be.gt(0);
          expect(contributorDataAfter[1]).to.be.gt(0);

          const creatorAfterUpdate = await garden.getContributor(creator);
          expect(creatorBeforeUpdate[0].toString()).to.equal(creatorAfterUpdate[0].toString());
          expect(creatorBeforeUpdate[1].toString()).to.equal(creatorAfterUpdate[1].toString());
          expect(creatorBeforeUpdate[2].toString()).to.equal(creatorAfterUpdate[2].toString());
          expect(creatorBeforeUpdate[3].toString()).to.equal(creatorAfterUpdate[3].toString());

          expect(creatorBeforeUpdate[4].toString()).to.equal(creatorAfterUpdate[4].toString());
          expect(creatorBeforeUpdate[5].toString()).to.equal(creatorAfterUpdate[5].toString());
          expect(creatorBeforeUpdate[6].toString()).to.equal(creatorAfterUpdate[6].toString());
          expect(creatorBeforeUpdate[7].toString()).to.equal(creatorAfterUpdate[7].toString());
          // Contributor power might be higher or lower depending on the position the user is getting in the garden along the time. As there are some seconds of difference between measures, it is not equal.
          expect(from(creatorBeforeUpdate[8])).to.closeTo(
            from(creatorAfterUpdate[8]),
            from(creatorBeforeUpdate[8].div(100)),
          );

          expect(creatorBeforeUpdate[9].toString()).to.equal(creatorAfterUpdate[9].toString());
        }
      });
    });
  });
});
