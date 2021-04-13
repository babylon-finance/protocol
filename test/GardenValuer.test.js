const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;

const addresses = require('../utils/addresses');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('GardenValuer', function () {
  let babController;
  let gardenValuer;
  let garden1;
  let weth;

  beforeEach(async () => {
    ({ babController, gardenValuer, garden1 } = await loadFixture(deployFolioFixture));
    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployedc = await babController.deployed();
      const deployed = await gardenValuer.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Calls GardenValuer', function () {
    it('should return 0.1 for garden1', async function () {
      // const wethInGarden = await weth.balanceOf(garden1.address);
      // const priceOfWeth = await garden.getPrice(
      //   addresses.tokens.WETH,
      //   addresses.tokens.DAI
      // );
      // console.log('format', ethers.utils.formatEther(100000000000000000));
      const pricePerGardenToken = await gardenValuer.calculateGardenValuation(garden1.address, addresses.tokens.WETH);
      const tokens = await garden1.totalSupply();
      expect(pricePerGardenToken.mul(tokens / 1000).div(10 ** 15)).to.equal(ethers.utils.parseEther('0.1'));
    });

    // TODO: check gardens with active strategies
  });
});
