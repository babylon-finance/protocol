const { ethers } = require('hardhat');

const { getContract, parse, from } = require('../utils/test-helpers');
const addresses = require('../../lib/addresses');
const { GARDEN_PARAMS, DAI_GARDEN_PARAMS, USDC_GARDEN_PARAMS, WBTC_GARDEN_PARAMS } = require('../../lib/constants');

const NFT_URI = 'https://babylon.mypinata.cloud/ipfs/QmcL826qNckBzEk2P11w4GQrrQFwGvR6XmUCuQgBX9ck1v';
const NFT_SEED = '504592746';

const reserveAssetGarden = {
  [addresses.tokens.WETH]: GARDEN_PARAMS,
  [addresses.tokens.DAI]: DAI_GARDEN_PARAMS,
  [addresses.tokens.USDC]: USDC_GARDEN_PARAMS,
  [addresses.tokens.WBTC]: WBTC_GARDEN_PARAMS,
};

const contributions = {
  [addresses.tokens.WETH]: parse('1'),
  [addresses.tokens.DAI]: parse('100'),
  [addresses.tokens.USDC]: from(100 * 1e6),
  [addresses.tokens.WBTC]: from(1e6),
};

async function createGarden({
  reserveAsset = addresses.tokens.WETH,
  name = 'garden',
  symbol = 'GRDN',
  nftUri = NFT_URI,
  nftSeed = NFT_SEED,
  params = reserveAssetGarden[reserveAsset],
  contribution = contributions[reserveAsset],
  signer,
} = {}) {
  const [deployer, keeper, owner, signer1, signer2, signer3] = await ethers.getSigners();
  signer = signer || signer1;
  const ishtarGate = await getContract('IshtarGate');
  const babController = await getContract('BabController', 'BabControllerProxy');

  console.log('approve');

  const erc20 = await ethers.getContractAt('IERC20', reserveAsset);
  for (const sig of [signer1, signer2, signer3]) {
    await erc20.connect(sig).approve(babController.address, params[0], {
      gasPrice: 0,
    });
  }
  console.log('create');

  await babController.connect(signer).createGarden(reserveAsset, name, symbol, nftUri, nftSeed, params, contribution, {
    value: reserveAsset === addresses.tokens.WETH ? contribution : 0,
  });
  console.log('getGardens');
  const gardens = await babController.getGardens();
  const garden = await ethers.getContractAt('Garden', gardens.slice(-1)[0]);
  await ishtarGate
    .connect(signer1)
    .grantGardenAccessBatch(
      garden.address,
      [owner.address, signer1.address, signer2.address, signer3.address],
      [3, 3, 3, 3],
      {
        gasPrice: 0,
      },
    );
  return garden;
}

module.exports = {
  createGarden,
};
