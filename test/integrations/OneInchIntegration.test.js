const { expect } = require('chai');
// const superagent = require('superagent');
const { waffle, ethers } = require('hardhat');
const { impersonateAddress } = require('../../utils/rpc');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
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
  let strategy11;
  let strategyContract;

  beforeEach(async () => {
    ({ babController, garden1, oneInchTradeIntegration, signer1, signer2, signer3 } = await loadFixture(
      deployFolioFixture,
    ));
    strategyContract = await ethers.getContractAt('LongStrategy', strategy11);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedKyber = await oneInchTradeIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedKyber).to.equal(true);
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
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('2'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('2'),
      });
      await garden1.connect(signer1).deposit(ethers.utils.parseEther('2'), 1, signer1.getAddress(), {
        value: ethers.utils.parseEther('2'),
      });
      await garden1.connect(signer2).deposit(ethers.utils.parseEther('2'), 1, signer2.getAddress(), {
        value: ethers.utils.parseEther('2'),
      });
      expect(await wethToken.balanceOf(garden1.address)).to.equal(ethers.utils.parseEther('6.1'));

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 2]);

      const user2GardenBalance = await garden1.balanceOf(signer2.getAddress());
      const user3GardenBalance = await garden1.balanceOf(signer3.getAddress());

      await strategyContract.resolveVoting(
        [signer2.getAddress(), signer3.getAddress()],
        [user2GardenBalance, user3GardenBalance],
        user2GardenBalance.add(user3GardenBalance).toString(),
        user2GardenBalance.add(user3GardenBalance).toString(),
        0,
        {
          gasPrice: 0,
        },
      );

      await strategyContract.executeInvestment(ethers.utils.parseEther('1'), 0, {
        gasPrice: 0,
      });

      expect(await wethToken.balanceOf(strategyContract.address)).to.equal(ethers.utils.parseEther('0'));
      expect(await usdcToken.balanceOf(strategyContract.address)).to.be.gt(ethers.utils.parseEther('97') / 10 ** 12);

      ethers.provider.send('evm_increaseTime', [ONE_DAY_IN_SECONDS * 90]);

      await strategyContract.finalizeInvestment(0, { gasPrice: 0 });
      expect(await usdcToken.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
});
