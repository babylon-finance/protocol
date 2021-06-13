const { expect } = require('chai');
const { ethers } = require('hardhat');

const addresses = require('../lib/addresses');
const { ONE_DAY_IN_SECONDS, ONE_ETH, NOW } = require('../lib/constants.js');
const { increaseTime } = require('./utils/test-helpers');
const { createGarden } = require('./fixtures/GardenHelper');
const { impersonateAddress } = require('../lib/rpc');

const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  getStrategy,
  executeStrategy,
  finalizeStrategy,
  injectFakeProfits,
} = require('./fixtures/StrategyHelper');

const { setupTests } = require('./fixtures/GardenFixture');

describe('Keeper', function () {
  let babController;
  let rewardsDistributor;
  let owner;
  let keeper;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let ishtarGate;
  let weth;
  let dai;
  let balancerIntegration;
  let kyberTradeIntegration;
  let daiGarden;
  let usdcGarden;
  let usdc;
  let gardenNFT;

  beforeEach(async () => {
    ({
      babController,
      rewardsDistributor,
      gardenNFT,
      keeper,
      owner,
      signer1,
      signer2,
      signer3,
      garden1,
      ishtarGate,
      balancerIntegration,
      kyberTradeIntegration,
    } = await setupTests()());

    usdc = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
    dai = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
    wbtc = await ethers.getContractAt('IERC20', addresses.tokens.WBTC);
  });

  describe.only('gets paid', function () {
    [
      { token: addresses.tokens.WETH, name: 'WETH' },
      { token: addresses.tokens.DAI, name: 'DAI' },
      { token: addresses.tokens.USDC, name: 'USDC' },
      { token: addresses.tokens.WBTC, name: 'WBTC' },
    ].forEach(({ token, name }) => {
      it(`for calling resolveVoting on ${name} garden`, async function () {
        const garden = await createGarden({ reserveAsset: token });
        const tokenContract = await ethers.getContractAt('IERC20', token);

        console.log('strategy');
        const strategy = await getStrategy({ state: 'deposit', specificParams: addresses.tokens.COMP });

        const signer1Balance = await garden.balanceOf(signer1.getAddress());
        const signer2Balance = await garden.balanceOf(signer2.getAddress());

        console.log('resolve');
        await strategy
          .connect(keeper)
          .resolveVoting([signer1.getAddress(), signer2.getAddress()], [signer1Balance, signer2Balance], 42, {
            gasPrice: 0,
          });

        // Keeper gets paid
        expect(await tokenContract.balanceOf(await keeper.getAddress())).to.equal(42);
      });
    });
  });
});
