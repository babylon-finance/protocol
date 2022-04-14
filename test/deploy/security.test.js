const hre = require('hardhat');
const ethers = hre.ethers;
const { createStrategy, executeStrategy, finalizeStrategy } = require('../fixtures/StrategyHelper');
const { MAX_UINT_256, ONE_DAY_IN_SECONDS } = require('../../lib/constants');
const { setupTests } = require('../fixtures/GardenFixture');
const { createGarden } = require('../fixtures/GardenHelper');
const addresses = require('../../lib/addresses');
const { impersonateAddress } = require('../../lib/rpc');
const { increaseTime } = require('../utils/test-helpers');

describe('Security', function () {
  let aaveBorrowIntegration;
  let aaveLendIntegration;
  let signer1;
  let signer2;
  let signer3;
  let DAI;
  let WETH;
  let keeper;

  // Deploys aave oracle with changed ETH price and inject its code into real aave oracle contract
  // code is available in AaveOracle.sol
  // constructor args are dai, dai source, fallback oracle, weth, took from etherscan
  async function changeETHPriceInAaveOracle(WETH) {
    const oracles = await ethers.getContractFactory('AaveOracleMock');
    const oracle = await oracles.deploy(
      ['0x6B175474E89094C44Da98b954EedeAC495271d0F'],
      ['0x773616E4d11A78F511299002da57A0a94577F1f4'],
      '0x5B09E578cfEAa23F1b11127A658855434e4F3e09',
      WETH.address,
    );
    const code = await hre.network.provider.send('eth_getCode', [oracle.address]);
    await hre.network.provider.send('hardhat_setCode', ['0xA50ba011c48153De246E5192C8f9258A2ba79Ca9', code]);
  }

  // Health factor see aave docs
  async function getHealthFactor(lendingPool, borrower) {
    const data = await lendingPool.getUserAccountData(borrower);
    return data.healthFactor;
  }

  // useless when amount < 1
  function normalizeToken(amount) {
    return amount.div(ethers.utils.parseEther('0.001')).toNumber() / 1000;
  }

  beforeEach(async () => {
    ({ aaveLendIntegration, aaveBorrowIntegration, keeper, signer1, signer2, signer3 } = await setupTests()());
    DAI = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20', addresses.tokens.DAI);
    WETH = await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20', addresses.tokens.WETH);
  });

  describe('exploits', function () {
    it(`liquidation in AAVE borrow`, async function () {
      const token = WETH.address;
      const asset1 = WETH;
      const asset2 = DAI;
      let userBalanceBefore = await ethers.provider.getBalance(signer1.address);
      console.log('user balance ETH before: ' + normalizeToken(userBalanceBefore));
      // signer1 creates with 1 ETH contribution
      const garden = await createGarden({ reserveAsset: token, signer: signer1 });
      // Create strategy with lend and borrow operations for exploit simplicity
      const strategyContract = await createStrategy(
        'borrow',
        'dataset',
        [signer1],
        [aaveLendIntegration.address, aaveBorrowIntegration.address],
        garden,
        false,
        [asset1.address, 0, asset2.address, 0],
      );
      const deposited = userBalanceBefore.sub(await ethers.provider.getBalance(signer1.address));

      console.log(
        'user balance ETH after deposit: ' + normalizeToken(await ethers.provider.getBalance(signer1.address)),
      );
      console.log('garden balance after deposits: ' + normalizeToken(await WETH.balanceOf(garden.address)));
      const userGardenTokens = await garden.balanceOf(signer1.address);
      await strategyContract.connect(keeper).resolveVoting([signer1.address], [userGardenTokens], 0, { gasPrice: 0 });
      const lendingPool = await ethers.getContractAt('ILendingPool', '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9');

      // Set maxCollateralFactor to 80% before strategy execution, max available for WETH collateral 80%, liquidate rate is 82.5%
      const strategyAsSigner = await impersonateAddress(strategyContract.address);
      await aaveBorrowIntegration
        .connect(strategyAsSigner)
        .updateMaxCollateralFactor(ethers.utils.parseEther('0.8'), { gasPrice: 0 });

      const amount = ethers.utils.parseEther('0.994');
      await executeStrategy(strategyContract, { amount });
      console.log('garden balance after strategy exeuction: ' + normalizeToken(await WETH.balanceOf(garden.address)));

      // health factor is around 1.03
      console.log(
        'health factor just after borrow: ' +
          normalizeToken(await getHealthFactor(lendingPool, strategyContract.address)),
      );
      // modify ETH price
      // for simplicity we change WETH price
      await changeETHPriceInAaveOracle(WETH);
      // here is 0.965
      console.log(
        'health factor after ETH price change: ' +
          normalizeToken(await getHealthFactor(lendingPool, strategyContract.address)),
      );

      // Send tokens to signer2 for liquidation
      const whaleSigner = await impersonateAddress('0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643');
      await DAI.connect(whaleSigner).transfer(signer2.address, ethers.utils.parseEther('100000'), {
        gasPrice: 0,
      });

      // Liquidate CDP with health factor < 1
      await DAI.connect(signer2).approve(lendingPool.address, MAX_UINT_256, { gasPrice: 0 });

      await lendingPool
        .connect(signer2)
        .liquidationCall(WETH.address, DAI.address, strategyContract.address, MAX_UINT_256, false, { gasPrice: 0 });
      // await strategyContract.connect(signer3).sweep(DAI.address, {gasPrice: 0});
      // finalize strategy

      await finalizeStrategy(strategyContract);
      console.log('garden balance after strategy finalize: ' + normalizeToken(await WETH.balanceOf(garden.address)));
      await garden
        .connect(signer1)
        .withdraw(await garden.balanceOf(signer1.address), 1, signer1.address, false, strategyContract.address, {
          gasPrice: 0,
        });
      console.log('locked dai in strategy: ' + normalizeToken(await DAI.balanceOf(strategyContract.address)));
      const userBalanceAfter = await ethers.provider.getBalance(signer1.address);
      console.log('user balance after: ' + normalizeToken(userBalanceAfter));
      // some losses (0.16) due to gas included
      console.log('deposited: ' + normalizeToken(deposited));
      if (userBalanceAfter.lt(userBalanceBefore)) {
        const loss = userBalanceBefore.sub(userBalanceAfter);
        console.log('loss: ' + normalizeToken(loss));
      } else {
        const profit = userBalanceAfter.sub(userBalanceBefore);
        console.log('profit: ' + normalizeToken(profit));
      }
    });
  });
});
