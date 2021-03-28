const { expect } = require('chai');
// const superagent = require('superagent');
const { waffle, ethers } = require('hardhat');
const { impersonateAddress } = require('../../utils/rpc');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const { createStrategy } = require('../fixtures/StrategyHelper');
const addresses = require('../../utils/addresses');
const { ONE_DAY_IN_SECONDS } = require('../../utils/constants');

const { loadFixture } = waffle;

describe('OneInchTradeIntegration', function () {
  let oneInchTradeIntegration;
  let garden1;
  let babController;
  let signer1;
  let signer2;
  let signer3;

  beforeEach(async () => {
    ({ babController, garden1, oneInchTradeIntegration, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedOne = await oneInchTradeIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedOne).to.equal(true);
    });
  });

  describe('Trading', function () {
    let daiToken;
    let usdcToken;
    let wethToken;
    let whaleSigner;
    // let oneInchExchange;
    const daiWhaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(daiWhaleAddress);
      daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
      wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
      usdcToken = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
      // oneInchExchange = await ethers.getContractAt('IOneInchExchange', addresses.oneinch.exchange);
    });

    it('trade dai to usdc', async function () {
      expect(
        await daiToken.connect(whaleSigner).transfer(garden1.address, ethers.utils.parseEther('100'), {
          gasPrice: 0,
        }),
      );
      expect(await daiToken.balanceOf(garden1.address)).to.equal(ethers.utils.parseEther('100'));
      // Get the quote
      // const quote = await superagent.get(`${addresses.api.oneinch}quote`).query({
      //   fromTokenAddress: daiToken.address,
      //   toTokenAddress: usdcToken.address,
      //   amount: 100 * 10 ** 18,
      // });
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        oneInchTradeIntegration.address,
        garden1,
      );

      await strategyContract.executeInvestment(ethers.utils.parseEther('1'), 0, {
        gasPrice: 0,
      });
      expect(await wethToken.balanceOf(strategyContract.address)).to.equal(ethers.utils.parseEther('0'));
      expect(await usdcToken.balanceOf(strategyContract.address)).to.be.gt(ethers.utils.parseEther('900') / 10 ** 12);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);
      await strategyContract.finalizeInvestment(0, { gasPrice: 0 });
      expect(await usdcToken.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
});
