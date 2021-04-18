const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');

const { loadFixture } = waffle;
const addresses = require('../utils/addresses');
const { deployFolioFixture } = require('./fixtures/ControllerFixture');

describe('IshtarGate', function () {
  let signer1;
  let signer2;
  let signer3;
  let ishtarGate;
  let babController;
  let gardenParams;
  let owner;

  beforeEach(async () => {
    ({ owner, babController, gardenParams, signer1, signer2, signer3, ishtarGate } = await loadFixture(
      deployFolioFixture,
    ));
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await ishtarGate.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('create garden', async function () {
    it('succeeds with the gate NFT awarded', async function () {
      await ishtarGate.connect(owner).setCreatorPermissions(signer2.address, true, { gasPrice: 0 });
      await expect(
        babController
          .connect(signer2)
          .createGarden(addresses.tokens.WETH, 'TEST Ishtar', 'AAA', gardenParams, 'http:', {
            value: ethers.utils.parseEther('0.1'),
          }),
      ).to.not.be.reverted;
    });

    it('succeeds with the gate NFT awarded through batch creation', async function () {
      await ishtarGate.connect(owner).grantCreatorsInBatch([signer2.address], [true], { gasPrice: 0 });
      await expect(
        babController
          .connect(signer2)
          .createGarden(addresses.tokens.WETH, 'TEST Ishtar', 'AAA', gardenParams, 'http...', {
            value: ethers.utils.parseEther('0.1'),
          }),
      ).to.not.be.reverted;
    });

    it('fails with the gate NFT awarded through batch creation with different elements', async function () {
      await expect(ishtarGate.connect(owner).grantCreatorsInBatch([signer2.address], [true, false], { gasPrice: 0 })).to
        .be.reverted;
    });

    it('only owner can give creator permissions', async function () {
      await expect(ishtarGate.connect(signer2).setCreatorPermissions(signer2, true, { gasPrice: 0 })).to.be.reverted;
    });

    it('fails without the gate NFT', async function () {
      await expect(
        babController
          .connect(signer2)
          .createGarden(addresses.tokens.WETH, 'TEST Ishtar', 'AAA', gardenParams, 'http...', {
            value: ethers.utils.parseEther('0.1'),
          }),
      ).to.be.reverted;
    });
  });

  describe('join a garden', async function () {
    it('succeeds with the gate NFT awarded', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(addresses.tokens.WETH, 'TEST Ishtar', 'AAA', gardenParams, 'http...', {
            value: ethers.utils.parseEther('0.1'),
          }),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();

      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);

      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, newGarden.address, 1, { gasPrice: 0 });

      await newGarden.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
    });

    it('fails without the gate NFT', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(addresses.tokens.WETH, 'TEST Ishtar', 'AAA', gardenParams, 'http...', {
            value: ethers.utils.parseEther('0.1'),
          }),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();

      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);

      await expect(
        newGarden.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
          value: ethers.utils.parseEther('1'),
        }),
      ).to.be.reverted;
    });

    it('only creator can grant access to a garden', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(addresses.tokens.WETH, 'TEST Ishtar', 'AAA', gardenParams, 'http...', {
            value: ethers.utils.parseEther('0.1'),
          }),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();

      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);

      await expect(ishtarGate.connect(signer3).setGardenAccess(signer3.address, newGarden.address, 1, { gasPrice: 0 }))
        .to.be.reverted;
    });

    it('can grant access through batch method', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(addresses.tokens.WETH, 'TEST Ishtar', 'AAA', gardenParams, 'http...', {
            value: ethers.utils.parseEther('0.1'),
          }),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();

      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);

      await ishtarGate
        .connect(signer1)
        .grantGardenAccessBatch(newGarden.address, [signer3.address], [1], { gasPrice: 0 });

      await newGarden.connect(signer3).deposit(ethers.utils.parseEther('1'), 1, signer3.getAddress(), {
        value: ethers.utils.parseEther('1'),
      });
    });
  });
});
