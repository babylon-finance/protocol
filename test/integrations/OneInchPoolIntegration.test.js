const { expect } = require('chai');
const { waffle, ethers } = require('hardhat');
const { impersonateAddress } = require('../../lib/rpc');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO } = require('../../lib/constants');

const { loadFixture } = waffle;

describe('OneInchPoolIntegrationTest', function () {
  let oneInchPoolIntegration;
  let garden1;
  let signer1;
  let signer2;
  let signer3;
  let babController;

  beforeEach(async () => {
    ({ babController, garden1, oneInchPoolIntegration, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedUni = await oneInchPoolIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedUni).to.equal(true);
    });
  });

  describe('Liquidity Pools', function () {
    let daiWethPair;
    let daiToken;
    let whaleSigner;
    const daiWhaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(daiWhaleAddress);
      daiWethPair = await ethers.getContractAt('IMooniswap', addresses.oneinch.pools.wethdai);
      daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
    });

    it('check that a valid pool is valid', async function () {
      expect(await oneInchPoolIntegration.isPool(addresses.oneinch.pools.wethdai)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      expect(await oneInchPoolIntegration.isPool(ADDRESS_ZERO)).to.equal(false);
    });

    it('tests mooniswap directly', async function () {
      expect(
        await daiToken.connect(whaleSigner).transfer(signer1.address, ethers.utils.parseEther('500'), {
          gasPrice: 0,
        }),
      );

      // Approve
      await daiToken.connect(signer1).approve(daiWethPair.address, ethers.utils.parseEther('500'));
      // Deposit
      await daiWethPair
        .connect(signer1)
        .deposit(
          [ethers.utils.parseEther('0.1'), ethers.utils.parseEther('100')],
          [ethers.utils.parseEther('0'), ethers.utils.parseEther('95')],
          {
            value: ethers.utils.parseEther('0.1'),
          },
        );
      expect(await daiWethPair.balanceOf(signer1.address)).to.be.gt(0);
    });

    it('can enter and exit the eth dai pool', async function () {
      const strategyContract = await createStrategy(
        'pool',
        'vote',
        [signer1, signer2, signer3],
        oneInchPoolIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        [daiWethPair.address],
      );

      await executeStrategy(strategyContract);
      expect(await daiWethPair.balanceOf(strategyContract.address)).to.be.gt(0);

      await finalizeStrategy(strategyContract);
      expect(await daiWethPair.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
});
