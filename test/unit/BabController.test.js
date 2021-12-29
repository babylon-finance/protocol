const { expect } = require('chai');

const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { GARDEN_PARAMS_STABLE, GARDEN_PARAMS, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { impersonateAddress } = require('lib/rpc');
const { createStrategy, executeStrategy, finalizeStrategy, getStrategy } = require('fixtures/StrategyHelper');
const { createGarden } = require('fixtures/GardenHelper');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');
const { ethers } = require('hardhat');
const { fund } = require('lib/whale');

describe.only('BabController', function () {
  let babController;
  let treasury;
  let bablToken;
  let garden1;
  let garden2;
  let garden3;
  let signer1;
  let signer2;
  let signer3;
  let uniswapV3TradeIntegration;
  let rewardsDistributor;
  let strategy11;
  let owner;
  let MULTISIG;

  beforeEach(async () => {
    ({
      babController,
      bablToken,
      owner,
      signer1,
      signer2,
      signer3,
      treasury,
      garden1,
      garden2,
      garden3,
      strategy11,
      uniswapV3TradeIntegration,
      rewardsDistributor,
    } = await setupTests()());
    const signers = await ethers.getSigners();
    MULTISIG = signers[2];
    await fund([signer1.address, signer2.address, signer3.address]);
  });

  describe('createGarden', function () {
    it('can create a new garden with DAI as the reserve asset', async function () {
      await createGarden({ reserveAsset: addresses.tokens.DAI });
    });
  });

  describe('keepers', function () {
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
      await babController.connect(owner).addReserveAsset(addresses.tokens.YFI);

      const updatedAssets = await babController.getReserveAssets();
      expect(updatedAssets.length > initialAssets.length).to.equal(true);
    });

    it('can remove a reserve asset', async function () {
      await babController.connect(owner).addReserveAsset(addresses.tokens.YFI);
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
    it('can enable token transfers after 2021', async function () {
      await expect(babController.connect(owner).enableGardenTokensTransfers()).to.be.revertedWith(
        'Transfers cannot be enabled yet',
      );
      expect(await babController.gardenTokensTransfersEnabled()).to.equal(false);
      // 1st Jan 2022
      await ethers.provider.send('evm_setNextBlockTimestamp', [1641024001]);
      await ethers.provider.send('evm_mine');
      await expect(babController.connect(owner).enableGardenTokensTransfers()).not.to.be.reverted;
      expect(await babController.gardenTokensTransfersEnabled()).to.equal(true);
    });
  });
  describe('Pause guardian', function () {
    it('can set a pause guardian from owner', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      const guardian = await babController.guardian();
      expect(guardian).to.equal(signer1.address);
    });

    it('can set a new pause guardian from current pause guardian', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setPauseGuardian(signer2.address);
      const guardian = await babController.guardian();
      expect(guardian).to.equal(signer2.address);
    });

    it('can NOT set zero address as pause guardian from current pause guardian', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await expect(babController.connect(signer1).setPauseGuardian(ADDRESS_ZERO)).to.be.revertedWith(
        'Guardian cannot remove himself',
      );
      const guardian = await babController.guardian();
      expect(guardian).to.equal(signer1.address);
    });

    it('can set zero address as pause guardian from the owner', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      const guardian = await babController.guardian();
      expect(guardian).to.equal(signer1.address);
      await expect(babController.connect(owner).setPauseGuardian(ADDRESS_ZERO)).not.to.be.reverted;
      expect(await babController.guardian()).to.equal(ADDRESS_ZERO);
    });

    it('should fail if trying to set a pause a user withour enough rights', async function () {
      await expect(babController.connect(signer2).setPauseGuardian(signer2.address)).to.be.revertedWith(
        'only pause guardian and owner can update pause guardian',
      );
      const guardian = await babController.guardian();
      expect(guardian).to.equal(ADDRESS_ZERO);
    });

    it('should pause globally the protocol principal functions', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await expect(babController.connect(signer1).setGlobalPause(true)).to.be.not.reverted;
      await expect(
        garden1.connect(signer1).deposit(eth(), 1, signer1.getAddress(), false, {
          value: eth(),
        }),
      ).to.be.revertedWith('BAB#083');
    });

    it('should pause individually a garden', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await expect(babController.connect(signer1).setSomePause([garden1.address], true)).to.be.not.reverted;
      const signer1Garden2Balance = await garden2.balanceOf(signer1.address);
      await expect(
        garden2.connect(signer1).deposit(eth(), 1, signer1.getAddress(), false, {
          value: eth(),
        }),
      ).to.be.not.reverted;
      const signer1Garden2Balance2 = await garden2.balanceOf(signer1.address);
      expect(signer1Garden2Balance2.sub(signer1Garden2Balance)).to.equal(eth());
      await expect(
        garden1.connect(signer1).deposit(eth(), 1, signer1.getAddress(), false, {
          value: eth(),
        }),
      ).to.be.revertedWith('BAB#083');
    });

    it('should pause individually a strategy', async function () {
      const long1 = await getStrategy({ garden: garden1 });
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([long1.address], true);
      await expect(executeStrategy(long1, eth())).to.be.revertedWith('BAB#083');
    });

    it('should pause individually the reward distributor main functions', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([rewardsDistributor.address], true);
    });

    it('should pause individually the BABL Token main functions as a TimeLockedToken', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([bablToken.address], true);
      await expect(
        bablToken.connect(owner).transfer(signer1.address, eth('1000'), {
          gasPrice: 0,
        }),
      ).to.be.revertedWith('BAB#083');
    });

    it('owner can unpause a strategy', async function () {
      const long1 = await getStrategy({ garden: garden1, state: 'vote' });

      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([long1.address], true);

      await expect(executeStrategy(long1, eth())).to.be.revertedWith('BAB#083');

      await babController.connect(owner).setSomePause([long1.address], false);
      await executeStrategy(long1, eth());
    });

    it('owner can unpause a garden', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await expect(babController.connect(signer1).setSomePause([garden1.address], true)).to.be.not.reverted;
      const signer1Garden2Balance = await garden2.balanceOf(signer1.address);
      await expect(
        garden2.connect(signer1).deposit(eth(), 1, signer1.getAddress(), false, {
          value: eth(),
        }),
      ).to.be.not.reverted;
      const signer1Garden2Balance2 = await garden2.balanceOf(signer1.address);
      expect(signer1Garden2Balance2.sub(signer1Garden2Balance)).to.equal(eth());
      await expect(
        garden1.connect(signer1).deposit(eth(), 1, signer1.getAddress(), false, {
          value: eth(),
        }),
      ).to.be.revertedWith('BAB#083');
      await babController.connect(owner).setSomePause([garden1.address], false);
      await expect(
        garden1.connect(signer1).deposit(eth(), 1, signer1.getAddress(), false, {
          value: eth(),
        }),
      ).to.not.be.reverted;
    });

    it('owner can unpause the reward distributor main functions', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([rewardsDistributor.address], true);
      await expect(babController.connect(signer1).setSomePause([rewardsDistributor.address], false)).to.be.revertedWith(
        'only admin can unpause',
      );
      const newBablToken = await impersonateAddress('0xf4dc48d260c93ad6a96c5ce563e70ca578987c74');
      await babController.connect(owner).setSomePause([rewardsDistributor.address], false);
    });

    it('owner can unpause the BABL Token main functions as a TimeLockedToken', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([bablToken.address], true);
      await expect(
        bablToken.connect(MULTISIG).transfer(signer1.address, eth('1000'), {
          gasPrice: 0,
        }),
      ).to.be.revertedWith('BAB#083');
      await babController.connect(owner).setSomePause([bablToken.address], false);
      await expect(
        bablToken.connect(MULTISIG).transfer(signer1.address, eth('10'), {
          gasPrice: 0,
        }),
      ).to.not.be.reverted;
    });
  });

  // TODO: Integration functions
  // TODO: add functions to update the max fees and test them
});
