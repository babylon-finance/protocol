const { expect } = require('chai');
const { waffle, ethers } = require('hardhat');
const { impersonateAddress } = require('../../utils/rpc');
const { deployFolioFixture } = require('../fixtures/ControllerFixture');
const addresses = require('../../utils/addresses');
const { ADDRESS_ZERO } = require('../../utils/constants');

const { loadFixture } = waffle;

describe('UniswapPoolIntegrationTest', function () {
  let uniswapPoolIntegration;
  let garden1;
  let uniAbi;
  let signer3;
  let babController;

  beforeEach(async () => {
    ({ babController, garden1, uniswapPoolIntegration, signer3 } = await loadFixture(deployFolioFixture));
    uniAbi = uniswapPoolIntegration.interface;
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      const deployedUni = await uniswapPoolIntegration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedUni).to.equal(true);
    });
  });

  describe('Liquidity Pools', function () {
    let daiToken;
    let wethToken;
    let whaleSigner;
    let whaleWeth;
    let daiWethPair;

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(addresses.holders.DAI);
      whaleWeth = await impersonateAddress(addresses.holders.WETH);
      daiToken = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
      wethToken = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
      daiWethPair = await ethers.getContractAt('IUniswapV2PairB', addresses.uniswap.pairs.wethdai);
    });

    it('check that a valid pool is valid', async function () {
      expect(await uniswapPoolIntegration.isPool(addresses.uniswap.pairs.wethdai)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      await expect(uniswapPoolIntegration.isPool(ADDRESS_ZERO)).to.be.reverted;
    });

    it('can enter and exit the weth dai pool', async function () {
      await garden1.connect(signer3).deposit(ethers.utils.parseEther('5'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('5'),
      });

      const dataEnter = uniAbi.encodeFunctionData(uniAbi.functions['joinPool(address,uint256,address[],uint256[])'], [
        addresses.uniswap.pairs.wethdai,
        ethers.utils.parseEther('20'),
        [addresses.tokens.DAI, addresses.tokens.WETH],
        [ethers.utils.parseEther('1000'), ethers.utils.parseEther('1.5')],
      ]);

      // await garden.callIntegration(
      //   uniswapIntegration.address,
      //   ethers.utils.parseEther("0"),
      //   dataEnter,
      //   [daiToken.address],
      //   [ethers.utils.parseEther("1000")],
      //   {
      //     gasPrice: 0
      //   }
      // );
      //
      // expect(await daiWethPair.balanceOf(garden.address)).to.be.gt(
      //   ethers.utils.parseEther("19")
      // );
      //
      // const dataExit = uniAbi.encodeFunctionData(
      //   uniAbi.functions["exitPool(address,uint256,address[],uint256[])"],
      //   [
      //     addresses.uniswap.pairs.wethdai,
      //     await daiWethPair.balanceOf(garden.address),
      //     [addresses.tokens.DAI, addresses.tokens.WETH],
      //     [ethers.utils.parseEther("900"), ethers.utils.parseEther("0.2")]
      //   ]
      // );
      //
      // await garden.callIntegration(
      //   uniswapIntegration.address,
      //   ethers.utils.parseEther("0"),
      //   dataExit,
      //   [],
      //   [],
      //   {
      //     gasPrice: 0
      //   }
      // );
      // expect(await daiWethPair.balanceOf(garden.address)).to.equal(0);
      // expect(await daiToken.balanceOf(garden.address)).to.be.gt(
      //   ethers.utils.parseEther("999")
      // );
      // expect(await wethToken.balanceOf(garden.address)).to.be.gt(
      //   ethers.utils.parseEther("4")
      // );
    });
  });
});
