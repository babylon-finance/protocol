const { expect } = require('chai');
// const superagent = require('superagent');
const { waffle, ethers } = require('hardhat');
const { impersonateAddress } = require('../../utils/rpc');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const { createStrategy, executeStrategy, finalizeStrategy } = require('../fixtures/StrategyHelper');
const addresses = require('../../utils/addresses');

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
    const daiWhaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(daiWhaleAddress);
      daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
      wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
      usdcToken = await ethers.getContractAt('IERC20', addresses.tokens.USDC);
    });

    it('trade WETH to USDC', async function () {
      expect(
        await daiToken.connect(whaleSigner).transfer(garden1.address, ethers.utils.parseEther('100'), {
          gasPrice: 0,
        }),
      );
      expect(await daiToken.balanceOf(garden1.address)).to.equal(ethers.utils.parseEther('100'));
      const strategyContract = await createStrategy(
        0,
        'vote',
        [signer1, signer2, signer3],
        oneInchTradeIntegration.address,
        garden1,
      );

      await executeStrategy(garden1, strategyContract);
      expect(await usdcToken.balanceOf(strategyContract.address)).to.be.gt(ethers.utils.parseEther('900') / 10 ** 12);

      await finalizeStrategy(garden1, strategyContract, 0);
      expect(await usdcToken.balanceOf(strategyContract.address)).to.equal(0);
      expect(await wethToken.balanceOf(garden1.address)).to.equal('1085000000000000000'); // 1.085 ETH
    });
  });
});
