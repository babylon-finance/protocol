const { expect } = require('chai');
const { ethers } = require('hardhat');
const addresses = require('lib/addresses');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');
const { GARDEN_PARAMS, ADDRESS_ZERO } = require('lib/constants');
const { setupTests } = require('fixtures/GardenFixture');
const { createStrategy } = require('fixtures/StrategyHelper.js');

describe.skip('MardukGate', function () {
  let signer1;
  let signer2;
  let signer3;
  let mardukGate;
  let babController;
  let uniswapV3TradeIntegration;
  let owner;
  let WALLET_ADDRESSES;
  let WALLET_ADDRESSES_13;

  beforeEach(async () => {
    ({ owner, babController, signer1, signer2, signer3, mardukGate, uniswapV3TradeIntegration } = await setupTests()());
    WALLET_ADDRESSES = [
      signer1.address,
      signer2.address,
      signer3.address,
      '0x8CF48E06700C64fEF96D0e6269172cC5371E2d4a',
      '0x605f3e3e5adb86dedf3966daa9ca671199c27f44',
      '0x83f4622A18e38bE297e089fB055Dd5123bb0b279',
      '0x21584Cc5a52102AbB381286a5119E3be08431CfD',
      '0x232775eAD28F0C0c750A097bA77302E7d84efd3B',
      '0x908295e2be3a36021aadaaed0bbb124fd602cbf2',
    ];
    WALLET_ADDRESSES_13 = [
      ...WALLET_ADDRESSES,
      '0xFBbA8ceA4e9835B9f304d6E69905cD9403F2b606',
      '0x7caa78e0b71095eebad77757936b7a06cf474558',
      '0xD81CE8E89DD987c8Ab630858C8f1e9DF14788c35',
      '0x7F6105aB06f5Cd2deAd20b09Ca1fe15AfB4ddf49',
    ];
  });

  describe('create garden', async function () {
    it('succeeds with the creator permission awarded', async function () {
      await mardukGate.connect(owner).setCreatorPermissions(signer2.address, true, { gasPrice: 0 });
      await expect(
        babController
          .connect(signer2)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http:',
            0,
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
    });

    it('succeeds without permissions awarded through batch creation', async function () {
      await mardukGate.connect(owner).grantCreatorsInBatch([signer2.address], [true], { gasPrice: 0 });
      await expect(
        babController
          .connect(signer2)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http...',
            1,
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
    });

    it('fails granting permissions through batch creation with different elements', async function () {
      await expect(mardukGate.connect(owner).grantCreatorsInBatch([signer2.address], [true, false], { gasPrice: 0 })).to
        .be.reverted;
    });

    it('only owner can give creator permissions', async function () {
      await expect(mardukGate.connect(signer2).setCreatorPermissions(signer2, true, { gasPrice: 0 })).to.be.reverted;
    });

    it('fails without creator permissions', async function () {
      await expect(
        babController
          .connect(signer2)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Marduk',
            'AAA',
            'http...',
            2,
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.be.reverted;
    });

    it('creator can join a garden', async function () {
      await mardukGate.connect(owner).setCreatorPermissions(signer2.address, true, { gasPrice: 0 });
      await babController
        .connect(signer2)
        .createGarden(
          addresses.tokens.WETH,
          'TEST Marduk',
          'AAA',
          'http:',
          0,
          GARDEN_PARAMS,
          eth('0.1'),
          [false, false, false],
          [0, 0, 0],
          {
            value: eth('0.1'),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);
      await newGarden.connect(signer2).deposit(eth('1'), 1, signer2.getAddress(), false, {
        value: eth('1'),
      });
    });

    it('creator can join a public garden after renouncing to 0 address', async function () {
      await mardukGate.connect(owner).setCreatorPermissions(signer2.address, true, { gasPrice: 0 });
      await babController
        .connect(signer2)
        .createGarden(
          addresses.tokens.WETH,
          'TEST Marduk',
          'AAA',
          'http:',
          0,
          GARDEN_PARAMS,
          eth('0.1'),
          [true, false, false],
          [0, 0, 0],
          {
            value: eth('0.1'),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);
      await newGarden.connect(signer2).transferCreatorRights(ADDRESS_ZERO, 0);
      await newGarden.connect(signer2).deposit(eth('1'), 1, signer2.getAddress(), false, {
        value: eth('1'),
      });
    });

    it('creator cannot renounce to 0 address if garden is private', async function () {
      await mardukGate.connect(owner).setCreatorPermissions(signer2.address, true, { gasPrice: 0 });
      await babController
        .connect(signer2)
        .createGarden(
          addresses.tokens.WETH,
          'TEST Marduk',
          'AAA',
          'http:',
          0,
          GARDEN_PARAMS,
          eth('0.1'),
          [false, false, false],
          [0, 0, 0],
          {
            value: eth('0.1'),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);
      await expect(newGarden.connect(signer2).transferCreatorRights(ADDRESS_ZERO, 0)).to.be.reverted;
    });

    it('creator can renounce to a non 0 address even if garden is private', async function () {
      await mardukGate.connect(owner).setCreatorPermissions(signer2.address, true, { gasPrice: 0 });
      await babController
        .connect(signer2)
        .createGarden(
          addresses.tokens.WETH,
          'TEST Marduk',
          'AAA',
          'http:',
          0,
          GARDEN_PARAMS,
          eth('0.1'),
          [false, false, false],
          [0, 0, 0],
          {
            value: eth('0.1'),
          },
        );
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);
      await expect(newGarden.connect(signer2).transferCreatorRights(WALLET_ADDRESSES[7], 0)).to.not.be.reverted;
    });

    it('creator can create a strategy', async function () {
      await mardukGate.connect(owner).setCreatorPermissions(signer2.address, true, { gasPrice: 0 });
      await expect(
        babController
          .connect(signer2)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http:',
            0,
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);

      await expect(
        createStrategy('buy', 'dataset', [signer2, signer1, signer3], uniswapV3TradeIntegration.address, newGarden),
      ).not.to.be.reverted;
    });
  });

  describe('garden access', async function () {
    it('number of invites initialized', async function () {
      const invites = await mardukGate.connect(owner).maxNumberOfInvites();
      expect(invites).to.equal(10);
    });

    it('can change the number of invites', async function () {
      await mardukGate.connect(owner).setMaxNumberOfInvites(25);
      const invites = await mardukGate.connect(owner).maxNumberOfInvites();
      expect(invites).to.equal(25);
    });
    it('only owner can change the number of invites', async function () {
      await expect(mardukGate.connect(signer1).setMaxNumberOfInvites(25)).to.be.reverted;
    });
  });

  describe('be a strategist', async function () {
    it('succeeds with permission 3', async function () {
      await mardukGate.connect(owner).setCreatorPermissions(signer2.address, true, { gasPrice: 0 });
      await expect(
        babController
          .connect(signer2)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http:',
            0,
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);
      await mardukGate.connect(signer2).setGardenAccess(signer1.address, newGarden.address, 3, { gasPrice: 0 });
      await newGarden.connect(signer1).deposit(eth('1'), 1, signer1.getAddress(), false, {
        value: eth('1'),
      });
      await expect(
        createStrategy('buy', 'dataset', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, newGarden),
      ).not.to.be.reverted;
    });

    it('creator can still create a strategy after renouncing and giving him permissions', async function () {
      await mardukGate.connect(owner).setCreatorPermissions(signer2.address, true, { gasPrice: 0 });
      await expect(
        babController
          .connect(signer2)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http:',
            0,
            GARDEN_PARAMS,
            eth('0.1'),
            [true, true, true],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);
      await newGarden.connect(signer2).transferCreatorRights(ADDRESS_ZERO, 0);
      await createStrategy('buy', 'dataset', [signer2, signer1, signer3], uniswapV3TradeIntegration.address, newGarden);
    });

    it('fails without the right permissions', async function () {
      await mardukGate.connect(owner).setCreatorPermissions(signer2.address, true, { gasPrice: 0 });
      await expect(
        babController
          .connect(signer2)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http:',
            0,
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();
      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);
      await mardukGate.connect(signer2).setGardenAccess(signer1.address, newGarden.address, 2, { gasPrice: 0 });
      await expect(
        createStrategy('buy', 'vote', [signer1, signer2, signer3], uniswapV3TradeIntegration.address, newGarden),
      ).to.be.reverted;
    });
  });

  describe('join a garden', async function () {
    it('succeeds with the perms awarded', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http...',
            3,
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();

      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);

      await mardukGate.connect(signer1).setGardenAccess(signer3.address, newGarden.address, 1, { gasPrice: 0 });

      await newGarden.connect(signer3).deposit(eth('1'), 1, signer3.getAddress(), false, {
        value: eth('1'),
      });
    });

    it('fails without the permissions', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http...',
            4,
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;

      const gardens = await babController.getGardens();

      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);

      await expect(
        newGarden.connect(WALLET_ADDRESSES[4]).deposit(eth('1'), 1, signer3.getAddress(), false, {
          value: eth('1'),
        }),
      ).to.be.reverted;
    });

    it('only creator can grant access to a garden', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http...',
            5,
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();

      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);

      await expect(mardukGate.connect(signer3).setGardenAccess(signer3.address, newGarden.address, 1, { gasPrice: 0 }))
        .to.be.reverted;
    });

    it('creator cannot grant access to a garden after renouncing', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http...',
            5,
            GARDEN_PARAMS,
            eth('0.1'),
            [true, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();

      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);
      await newGarden.connect(signer1).transferCreatorRights(ADDRESS_ZERO, 0);
      await expect(mardukGate.connect(signer1).setGardenAccess(signer3.address, newGarden.address, 1, { gasPrice: 0 }))
        .to.be.reverted;
    });

    it('can grant access through batch method', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http...',
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();

      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);

      await mardukGate
        .connect(signer1)
        .grantGardenAccessBatch(newGarden.address, [signer3.address], [1], { gasPrice: 0 });

      await newGarden.connect(signer3).deposit(eth('1'), 1, signer3.getAddress(), false, {
        value: eth('1'),
      });
    });
    it('should revert if we try to go beyond the max number of invitations', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http...',
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();

      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);

      // We try to set-up more than max limit 13 ADDRESSES
      await expect(
        mardukGate
          .connect(signer1)
          .grantGardenAccessBatch(newGarden.address, WALLET_ADDRESSES_13, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], {
            gasPrice: 0,
          }),
      ).to.be.revertedWith('Max Number of invites reached');
    });
    it('should give access rights to the maximum limit', async function () {
      await expect(
        babController
          .connect(signer1)
          .createGarden(
            addresses.tokens.WETH,
            'TEST Ishtar',
            'AAA',
            'http...',
            GARDEN_PARAMS,
            eth('0.1'),
            [false, false, false],
            [0, 0, 0],
            {
              value: eth('0.1'),
            },
          ),
      ).to.not.be.reverted;
      const gardens = await babController.getGardens();

      const newGarden = await ethers.getContractAt('Garden', gardens[gardens.length - 1]);

      // 9 additional addresses
      await expect(
        mardukGate
          .connect(signer1)
          .grantGardenAccessBatch(newGarden.address, WALLET_ADDRESSES, [1, 1, 1, 1, 1, 1, 1, 1, 1], { gasPrice: 0 }),
      ).not.to.be.reverted;

      // Assumes that updating is not adding new users 9 addresses (the same)
      await expect(
        mardukGate
          .connect(signer1)
          .grantGardenAccessBatch(newGarden.address, WALLET_ADDRESSES, [3, 2, 3, 2, 3, 2, 3, 2, 3], { gasPrice: 0 }),
      ).not.to.be.reverted;

      // New users mixed with previous updates
      await expect(
        mardukGate
          .connect(signer1)
          .grantGardenAccessBatch(newGarden.address, WALLET_ADDRESSES_13, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], {
            gasPrice: 0,
          }),
      ).to.be.revertedWith('Max Number of invites reached');
    });
  });
});
