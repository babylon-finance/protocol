const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;

const addresses = require('../utils/addresses');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('GardenValuer', function () {
  let controller;
  let valuer;
  let garden;
  let weth;

  beforeEach(async () => {
    const { babController, gardenValuer, gardens } = await loadFixture(deployFolioFixture);
    garden = gardens.one;
    controller = babController;
    valuer = gardenValuer;
    weth = await ethers.getContractAt('IERC20', addresses.tokens.WETH);
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployedc = await controller.deployed();
      const deployed = await valuer.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedc).to.equal(true);
    });
  });

  describe('Calls GardenValuer', function () {
    it('should return 0.1 for garden1', async function () {
      const wethInGarden = await weth.balanceOf(garden.address);
      // const priceOfWeth = await garden.getPrice(
      //   addresses.tokens.WETH,
      //   addresses.tokens.DAI
      // );
      // console.log('format', ethers.utils.formatEther(100000000000000000));
      const pricePerGardenToken = await valuer.calculateGardenValuation(garden.address, addresses.tokens.WETH);
      const tokens = await garden.totalSupply();
      expect(pricePerGardenToken.mul(tokens / 1000).div(10 ** 15)).to.equal(ethers.utils.parseEther('0.1'));
    });
  });
});
