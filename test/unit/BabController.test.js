const { expect } = require('chai');

const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { GARDEN_PARAMS_STABLE, GARDEN_PARAMS, ADDRESS_ZERO, ONE_ETH, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { impersonateAddress } = require('lib/rpc');
const { createStrategy, executeStrategy, finalizeStrategy } = require('fixtures/StrategyHelper');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');
const { ethers } = require('hardhat');

describe('BabController', function () {
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

  async function createStrategies(strategies) {
    const retVal = [];
    for (let i = 0; i < strategies.length; i++) {
      const strategy = await createStrategy(
        'buy',
        'vote',
        [signer1, signer2, signer3],
        uniswapV3TradeIntegration.address,
        strategies[i].garden,
      );
      retVal.push(strategy);
    }

    return retVal;
  }

  async function deleteCandidateStrategies(community) {
    const garden = await ethers.getContractAt('Garden', community);
    // As the disabled garden has still 2 candidate strategies, we need to expire them before removing the garden
    const strategies = await garden.getStrategies();
    for (let i = 0; i < strategies.length; i++) {
      const strategy = await ethers.getContractAt('Strategy', strategies[i]);
      await strategy.connect(owner).deleteCandidateStrategy();
    }
  }

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
      const dai = await getERC20(addresses.tokens.DAI);
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
          [false, false, false],
          [0, 0, 0],
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
            [false, false, false],
            [0, 0, 0],
            {
              value: ethers.utils.parseEther('1'),
            },
          ),
      ).to.be.reverted;
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
    it('can NOT change BABL % share if it does not sum 100%', async function () {
      const [
        BABL_STRATEGIST_SHARE,
        BABL_STEWARD_SHARE,
        BABL_LP_SHARE,
        CREATOR_BONUS,
      ] = await babController.getBABLSharing();
      const BABL_STRATEGIST_SHARE_1 = eth('0.15');
      const BABL_STEWARD_SHARE_1 = eth('0.15');
      const BABL_LP_SHARE_1 = eth('0.15');
      const CREATOR_BONUS_1 = eth('0.15');
      await expect(
        babController
          .connect(owner)
          .setBABLShareForMiningProgram(
            BABL_STRATEGIST_SHARE_1,
            BABL_STEWARD_SHARE_1,
            BABL_LP_SHARE_1,
            CREATOR_BONUS_1,
          ),
      ).to.be.revertedWith('new sharing % does not match');
      const [
        NEW_BABL_STRATEGIST_SHARE,
        NEW_BABL_STEWARD_SHARE,
        NEW_BABL_LP_SHARE,
        NEW_CREATOR_BONUS,
      ] = await babController.getBABLSharing();
      expect(NEW_BABL_STRATEGIST_SHARE).to.equal(BABL_STRATEGIST_SHARE);
      expect(NEW_BABL_STEWARD_SHARE).to.equal(BABL_STEWARD_SHARE);
      expect(NEW_BABL_LP_SHARE).to.equal(BABL_LP_SHARE);
      expect(NEW_CREATOR_BONUS).to.equal(CREATOR_BONUS);
    });
    it('can change BABL % share ', async function () {
      const [
        BABL_STRATEGIST_SHARE,
        BABL_STEWARD_SHARE,
        BABL_LP_SHARE,
        CREATOR_BONUS,
      ] = await babController.getBABLSharing();
      const BABL_STRATEGIST_SHARE_1 = eth('0.08');
      const BABL_STEWARD_SHARE_1 = eth('0.12');
      const BABL_LP_SHARE_1 = eth('0.80');
      const CREATOR_BONUS_1 = eth('0.10');
      expect(BABL_STRATEGIST_SHARE).to.not.be.equal(BABL_STRATEGIST_SHARE_1);
      await expect(
        babController
          .connect(owner)
          .setBABLShareForMiningProgram(
            BABL_STRATEGIST_SHARE_1,
            BABL_STEWARD_SHARE_1,
            BABL_LP_SHARE_1,
            CREATOR_BONUS_1,
          ),
      ).not.to.be.reverted;
      const [
        NEW_BABL_STRATEGIST_SHARE,
        NEW_BABL_STEWARD_SHARE,
        NEW_BABL_LP_SHARE,
        NEW_CREATOR_BONUS,
      ] = await babController.getBABLSharing();
      expect(NEW_BABL_STRATEGIST_SHARE).to.equal(BABL_STRATEGIST_SHARE_1);
      expect(NEW_BABL_STEWARD_SHARE).to.equal(BABL_STEWARD_SHARE_1);
      expect(NEW_BABL_LP_SHARE).to.equal(BABL_LP_SHARE_1);
      expect(NEW_CREATOR_BONUS).to.equal(CREATOR_BONUS_1);
      console.log(
        'NEW %',
        BABL_STRATEGIST_SHARE.toString(),
        BABL_STEWARD_SHARE.toString(),
        BABL_LP_SHARE.toString(),
        CREATOR_BONUS.toString(),
      );
    });
    it('should get live strategies', async function () {
      const [long1, long2] = await createStrategies([{ garden: garden1 }, { garden: garden1 }]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      increaseTime(ONE_DAY_IN_SECONDS * 30);
      // Mining program has to be enabled before the strategy is finished
      await babController.connect(owner).enableBABLMiningProgram();
      const strategies = await babController.getLiveStrategies(2);
      expect(strategies.length).to.equal(2);
    });
    it('should get a number of live strategies below the total number of live strategies', async function () {
      const [long1, long2, long3] = await createStrategies([
        { garden: garden1 },
        { garden: garden1 },
        { garden: garden2 },
      ]);

      await executeStrategy(long1, ONE_ETH);
      await executeStrategy(long2, ONE_ETH);
      await executeStrategy(long3, ONE_ETH);

      increaseTime(ONE_DAY_IN_SECONDS * 30);
      // Mining program has to be enabled before the strategy is finished
      await babController.connect(owner).enableBABLMiningProgram();
      const strategies = await babController.getLiveStrategies(2);
      expect(strategies.length).to.equal(2);
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
        garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
        }),
      ).to.be.revertedWith('BAB#083');
    });
    it('should pause individually a garden', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await expect(babController.connect(signer1).setSomePause([garden1.address], true)).to.be.not.reverted;
      const signer1Garden2Balance = await garden2.balanceOf(signer1.address);
      await expect(
        garden2.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
        }),
      ).to.be.not.reverted;
      const signer1Garden2Balance2 = await garden2.balanceOf(signer1.address);
      expect(signer1Garden2Balance2.sub(signer1Garden2Balance)).to.equal(ethers.utils.parseEther('1'));
      await expect(
        garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
        }),
      ).to.be.revertedWith('BAB#083');
    });
    it('should pause individually a strategy', async function () {
      const [long1] = await createStrategies([{ garden: garden1 }]);
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([long1.address], true);
      await expect(executeStrategy(long1, ONE_ETH)).to.be.revertedWith('BAB#083');
    });
    it('should pause individually the reward distributor main functions', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([rewardsDistributor.address], true);
      await expect(babController.connect(owner).enableBABLMiningProgram()).to.be.revertedWith('BAB#083');
    });
    it('should pause individually the BABL Token main functions as a TimeLockedToken', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([bablToken.address], true);
      await expect(
        bablToken.connect(owner).transfer(signer1.address, ethers.utils.parseEther('1000'), {
          gasPrice: 0,
        }),
      ).to.be.revertedWith('BAB#083');
    });
    it('owner can unpause a strategy', async function () {
      const [long1] = await createStrategies([{ garden: garden1 }]);
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([long1.address], true);
      await expect(executeStrategy(long1, ONE_ETH)).to.be.revertedWith('BAB#083');
      await babController.connect(owner).setSomePause([long1.address], false);
      await expect(executeStrategy(long1, ONE_ETH)).to.not.be.reverted;
    });
    it('owner can unpause a garden', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await expect(babController.connect(signer1).setSomePause([garden1.address], true)).to.be.not.reverted;
      const signer1Garden2Balance = await garden2.balanceOf(signer1.address);
      await expect(
        garden2.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
        }),
      ).to.be.not.reverted;
      const signer1Garden2Balance2 = await garden2.balanceOf(signer1.address);
      expect(signer1Garden2Balance2.sub(signer1Garden2Balance)).to.equal(ethers.utils.parseEther('1'));
      await expect(
        garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
        }),
      ).to.be.revertedWith('BAB#083');
      await babController.connect(owner).setSomePause([garden1.address], false);
      await expect(
        garden1.connect(signer1).deposit(ethers.utils.parseEther('1'), 1, signer1.getAddress(), false, {
          value: ethers.utils.parseEther('1'),
        }),
      ).to.not.be.reverted;
    });

    it('owner can unpause the reward distributor main functions', async function () {
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([rewardsDistributor.address], true);
      await expect(babController.connect(owner).enableBABLMiningProgram()).to.be.revertedWith('BAB#083');
      await expect(babController.connect(signer1).setSomePause([rewardsDistributor.address], false)).to.be.revertedWith(
        'only admin can unpause',
      );
      const newBablToken = await impersonateAddress('0xf4dc48d260c93ad6a96c5ce563e70ca578987c74');
      await babController.connect(owner).setSomePause([rewardsDistributor.address], false);
      await expect(babController.connect(owner).enableBABLMiningProgram()).to.not.be.reverted;
    });

    it('owner can unpause the BABL Token main functions as a TimeLockedToken', async function () {
      // Enable BABL token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      await babController.connect(owner).setPauseGuardian(signer1.address);
      await babController.connect(signer1).setSomePause([bablToken.address], true);
      await expect(
        bablToken.connect(MULTISIG).transfer(signer1.address, ethers.utils.parseEther('1000'), {
          gasPrice: 0,
        }),
      ).to.be.revertedWith('BAB#083');
      await babController.connect(owner).setSomePause([bablToken.address], false);
      await expect(
        bablToken.connect(MULTISIG).transfer(signer1.address, ethers.utils.parseEther('10'), {
          gasPrice: 0,
        }),
      ).to.not.be.reverted;
    });
  });

  // TODO: Integration functions
  // TODO: add functions to update the max fees and test them
});
