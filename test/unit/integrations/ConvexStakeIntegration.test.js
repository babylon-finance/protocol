const { expect } = require('chai');
const { ethers } = require('hardhat');
const { createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { setupTests } = require('fixtures/GardenFixture');
const { createGarden, depositFunds, transferFunds } = require('fixtures/GardenHelper');
const addresses = require('lib/addresses');
const { STRATEGY_EXECUTE_MAP } = require('lib/constants');

describe('ConvexStakeIntegrationTest', function () {
  let convexStakeIntegration;
  let curvePoolIntegration;
  let signer1;
  let signer2;
  let signer3;

  async function depositAndStakeStrategy(crvpool, cvxpool, token) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    const gardenReserveAsset = await ethers.getContractAt(
      '@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20',
      token,
    );
    await depositFunds(token, garden);
    console.log('after deposit');
    const crvAddressProvider = await ethers.getContractAt(
      'ICurveAddressProvider',
      '0x0000000022d53366457f9d5e68ec105046fc4383',
    );
    const crvRegistry = await ethers.getContractAt('ICurveRegistry', await crvAddressProvider.get_registry());
    const convexBooster = await ethers.getContractAt('IBooster', '0xF403C135812408BFbE8713b5A23a04b3D48AAE31');
    const crvLpToken = await ethers.getContractAt(
      '@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20',
      await crvRegistry.get_lp_token(crvpool),
    );
    const pid = (await convexStakeIntegration.getPid(cvxpool))[1].toNumber();
    const poolInfo = await convexBooster.poolInfo(pid);
    const convexRewardToken = await ethers.getContractAt(
      '@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20',
      poolInfo[3],
    );

    const strategyContract = await createStrategy(
      'lpStack',
      'vote',
      [signer1, signer2, signer3],
      [curvePoolIntegration.address, convexStakeIntegration.address],
      garden,
      false,
      [crvpool, 0, cvxpool, 0],
    );
    const amount = STRATEGY_EXECUTE_MAP[token];
    console.log('execute strategy');
    await executeStrategy(strategyContract, { amount });
    console.log('after execute');
    // Check NAV
    expect(await strategyContract.getNAV()).to.be.closeTo(amount, amount.div(50));

    expect(await crvLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await convexRewardToken.balanceOf(strategyContract.address)).to.be.gt(0);

    // Check rewards
    const balanceBeforeExiting = await gardenReserveAsset.balanceOf(garden.address);
    console.log('before finalize');
    await finalizeStrategy(strategyContract);

    expect(await crvLpToken.balanceOf(strategyContract.address)).to.equal(0);
    expect(await convexRewardToken.balanceOf(strategyContract.address)).to.equal(0);

    expect(await gardenReserveAsset.balanceOf(garden.address)).to.be.gt(balanceBeforeExiting);
  }

  async function tryDepositAndStakeStrategy(crvpool, cvxpool, token, errorcode) {
    await transferFunds(token);
    const garden = await createGarden({ reserveAsset: token });
    await depositFunds(token, garden);

    const strategyContract = await createStrategy(
      'lpStack',
      'vote',
      [signer1, signer2, signer3],
      [curvePoolIntegration.address, convexStakeIntegration.address],
      garden,
      false,
      [crvpool, 0, cvxpool, 0],
    );
    await expect(executeStrategy(strategyContract, { amount: STRATEGY_EXECUTE_MAP[token] })).to.be.revertedWith(
      errorcode,
    );
  }

  beforeEach(async () => {
    ({ curvePoolIntegration, convexStakeIntegration, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const lendDeployed = await convexStakeIntegration.deployed();
      expect(!!lendDeployed).to.equal(true);
    });
  });

  describe('Convex Stake Multigarden multiasset', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      // { token: addresses.tokens.DAI, name: 'DAI' },
      // { token: addresses.tokens.USDC, name: 'USDC' },
      // { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(({ token, name }) => {
      const pools = [
        {
          crvpool: '0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7',
          cvxpool: '0x30d9410ed1d5da1f6c8391af5338c93ab8d4035c',
          name: 'tripool',
        },
      ];
      pools.forEach(({ crvpool, cvxpool, name }) => {
        it(`can enter ${name} CRV pool and stake into convex`, async function () {
          await depositAndStakeStrategy(crvpool, cvxpool, token);
        });
      });
    });
  });
});
