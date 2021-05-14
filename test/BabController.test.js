const { expect } = require('chai');

const addresses = require('../lib/addresses');
const { setupTests } = require('./fixtures/GardenFixture');
const { GARDEN_PARAMS_STABLE, GARDEN_PARAMS } = require('../lib/constants');
const { impersonateAddress } = require('../lib/rpc');

describe('BabController', function () {
  let babController;
  let treasury;
  let garden1;
  let garden2;
  let garden3;
  let signer1;
  let owner;

  beforeEach(async () => {
    ({ babController, owner, signer1, treasury, garden1, garden2, garden3 } = await setupTests()());
  });

  describe('Deployment', function () {
    it('should successfully deploy the contract', async function () {
      const deployed = await babController.deployed();
      expect(!!deployed).to.equal(true);
    });
  });

  describe('Interacting with Communities', function () {
    it('should start with 3 gardens', async function () {
      const gardens = await babController.getGardens();
      expect(gardens.length).to.equal(4);
    });

    it('should set the protocol manager address', async function () {
      expect(await babController.treasury()).to.equal(treasury.address);
    });

    it('can create gardens', async function () {
      expect(!!garden1).to.equal(true);
      expect(!!garden2).to.equal(true);
      expect(!!garden3).to.equal(true);
    });

    it('can create a new garden with DAI as the reserve asset', async function () {
      const dai = await ethers.getContractAt('IERC20', addresses.tokens.DAI);
      const whaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F'; // Has DAI
      const whaleSigner = await impersonateAddress(whaleAddress);
      await dai.connect(whaleSigner).transfer(signer1.address, ethers.utils.parseEther('1000'), {
        gasPrice: 0,
      });
      await dai.connect(signer1).approve(babController.address, ethers.utils.parseEther('1000'), {
        gasPrice: 0,
      });
      await babController
        .connect(signer1)
        .createGarden(
          addresses.tokens.DAI,
          'Absolute DAI Return [beta]',
          'EYFA',
          'http...',
          0,
          GARDEN_PARAMS_STABLE,
          ethers.utils.parseEther('100'),
          {
            value: ethers.utils.parseEther('100'),
          },
        );
      const gardens = await babController.getGardens();
      expect(gardens.length).to.equal(5);
    });

    it('cannot create a new garden with YFI as the reserve asset', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.YFI,
            'Absolute YFI Return [beta]',
            'EYFA',
            'http...',
            0,
            GARDEN_PARAMS,
            ethers.utils.parseEther('1'),
            {
              value: ethers.utils.parseEther('1'),
            },
          ),
      ).to.be.reverted;
    });

    it('cannot disable an inactive garden', async function () {
      const initialCommunities = await babController.getGardens();

      await expect(babController.connect(owner).disableGarden(initialCommunities[0])).to.not.be.reverted;
      await expect(babController.connect(owner).disableGarden(initialCommunities[0])).to.be.reverted;
    });

    it('can remove a disabled garden', async function () {
      const initialCommunities = await babController.getGardens();
      expect(initialCommunities.length).to.equal(4);
      await expect(babController.connect(owner).disableGarden(initialCommunities[0])).to.not.be.reverted;
      await babController.connect(owner).removeGarden(initialCommunities[0]);

      const updatedCommunities = await babController.getGardens();
      expect(updatedCommunities.length).to.equal(3);
    });

    it('can enable and disable a garden', async function () {
      const initialCommunities = await babController.getGardens();

      await expect(babController.connect(owner).disableGarden(initialCommunities[0])).to.not.be.reverted;
      await expect(babController.connect(owner).enableGarden(initialCommunities[0])).to.not.be.reverted;
    });
  });

  describe('Keeper List', function () {
    it('can add new keepers', async function () {
      await babController.connect(owner).addKeeper(addresses.users.hardhat3);

      const valid = await babController.isValidKeeper(addresses.users.hardhat3);
      expect(valid).to.equal(true);
    });

    it('can remove keepers', async function () {
      await babController.connect(owner).addKeeper(addresses.users.hardhat3);
      await babController.connect(owner).removeKeeper(addresses.users.hardhat3);

      const valid = await babController.isValidKeeper(addresses.users.hardhat3);
      expect(valid).to.equal(false);
    });

    it('can add keepers in bulk', async function () {
      await babController.connect(owner).addKeepers([addresses.users.hardhat3, addresses.users.hardhat2]);

      expect(await babController.isValidKeeper(addresses.users.hardhat3)).to.equal(true);
      expect(await babController.isValidKeeper(addresses.users.hardhat2)).to.equal(true);
    });
  });

  describe('Protocol operations', function () {
    it('can add a reserve asset', async function () {
      const initialAssets = await babController.getReserveAssets();
      await babController.connect(owner).addReserveAsset(addresses.tokens.USDC);

      const updatedAssets = await babController.getReserveAssets();
      expect(updatedAssets.length > initialAssets.length).to.equal(true);
    });

    it('can remove a reserve asset', async function () {
      await babController.connect(owner).addReserveAsset(addresses.tokens.USDC);
      const initialAssets = await babController.getReserveAssets();

      await babController.connect(owner).removeReserveAsset(initialAssets[0]);

      const updatedAssets = await babController.getReserveAssets();
      expect(updatedAssets.length < initialAssets.length).to.equal(true);
    });

    it('can edit a price oracle', async function () {
      // Note: This is just the wETH address and is testing that the oracle address can be changed
      await expect(babController.connect(owner).editPriceOracle(addresses.tokens.WETH)).to.not.be.reverted;
      const oracle2 = await babController.connect(owner).priceOracle();
      expect(oracle2).to.equal(addresses.tokens.WETH);
    });

    it('can edit a garden valuer', async function () {
      // Note: This is just the wETH address and is testing that the gardenValuer address can be changed
      await expect(babController.connect(owner).editGardenValuer(addresses.tokens.WETH)).to.not.be.reverted;

      const valuer2 = await babController.gardenValuer();
      expect(valuer2).to.equal(addresses.tokens.WETH);
    });

    it('can edit the protocol fee recipient', async function () {
      await babController.connect(owner).editTreasury(addresses.users.hardhat3);

      const recipient = await babController.treasury();
      // TODO(tylerm): Use checksumed addresses
      expect(recipient.toLowerCase()).to.equal(addresses.users.hardhat3);
    });
  });

  // TODO: Integration functions
  // TODO: add functions to update the max fees and test them
});
