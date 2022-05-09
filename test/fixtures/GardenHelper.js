const { ethers } = require('hardhat');

const addresses = require('lib/addresses');
const { impersonateAddress } = require('lib/rpc');
const { fund, getWhaleSigner } = require('lib/whale');

const {
  ADDRESS_ZERO,
  GARDEN_PARAMS,
  DAI_GARDEN_PARAMS,
  USDC_GARDEN_PARAMS,
  WBTC_GARDEN_PARAMS,
  BABL_GARDEN_PARAMS,
} = require('lib/constants');
const { increaseTime, normalizeDecimals, getERC20, getContract, parse, from, eth } = require('utils/test-helpers');

const NFT_URI = 'https://babylon.mypinata.cloud/ipfs/QmcL826qNckBzEk2P11w4GQrrQFwGvR6XmUCuQgBX9ck1v';
const NFT_SEED = '504592746';

const GARDEN_PARAMS_MAP = {
  [addresses.tokens.WETH]: GARDEN_PARAMS,
  [addresses.tokens.DAI]: DAI_GARDEN_PARAMS,
  [addresses.tokens.USDC]: USDC_GARDEN_PARAMS,
  [addresses.tokens.WBTC]: WBTC_GARDEN_PARAMS,
  [addresses.tokens.BABL]: BABL_GARDEN_PARAMS,
  [addresses.tokens.AAVE]: BABL_GARDEN_PARAMS,
};

const CONTRIBUTORS_MAP = {
  [addresses.tokens.WETH]: eth(),
  [addresses.tokens.DAI]: eth(10000),
  [addresses.tokens.USDC]: from(10000 * 1e6),
  [addresses.tokens.WBTC]: from(1e8),
  [addresses.tokens.BABL]: eth(100),
  [addresses.tokens.AAVE]: eth(100),
};

async function createGarden({
  reserveAsset = addresses.tokens.WETH,
  name = 'garden',
  symbol = 'GRDN',
  nftUri = NFT_URI,
  nftSeed = NFT_SEED,
  signer,
  params,
  publicGardenStrategistsStewards = [false, false, false],
  publicSharing = [0, 0, 0],
  customIntegrationsEnabled = false
} = {}) {
  const [deployer, keeper, , signer1, signer2, signer3] = await ethers.getSigners();
  signer = signer || signer1;
  const ishtarGate = await getContract('IshtarGate');
  const babController = await getContract('BabController', 'BabControllerProxy');
  params = params || GARDEN_PARAMS_MAP[reserveAsset];
  if (customIntegrationsEnabled) {
    params[12] = 1;
  }
  const contribution = CONTRIBUTORS_MAP[reserveAsset];
  const erc20 = await getERC20(reserveAsset);
  for (const sig of [signer1, signer2, signer3]) {
    await erc20.connect(sig).approve(babController.address, params[0], {
      gasPrice: 0,
    });
  }

  await babController
    .connect(signer)
    .createGarden(
      reserveAsset,
      name,
      symbol,
      nftUri,
      nftSeed,
      params,
      contribution,
      publicGardenStrategistsStewards,
      publicSharing,
      {
        value: reserveAsset === addresses.tokens.WETH ? contribution : 0,
      },
    );
  const gardens = await babController.getGardens();
  const garden = await ethers.getContractAt('IGarden', gardens.slice(-1)[0]);
  await ishtarGate
    .connect(signer)
    .grantGardenAccessBatch(garden.address, [signer1.address, signer2.address, signer3.address], [3, 3, 3], {
      gasPrice: 0,
    });
  return garden;
}

async function depositFunds(asset, garden, amount = eth(3)) {
  const [, , , signer1, , signer3] = await ethers.getSigners();
  const whaleSigner = await getWhaleSigner(asset);
  const ishtarGate = await getContract('IshtarGate');

  switch (asset.toLowerCase()) {
    case addresses.tokens.DAI.toLowerCase():
      const DAI = await getERC20(addresses.tokens.DAI);
      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, garden.address, 1, { gasPrice: 0 });
      await DAI.connect(signer3).approve(garden.address, eth('10000'), { gasPrice: 0 });
      await garden.connect(signer3).deposit(eth(10000), 1, signer3.getAddress(), ADDRESS_ZERO);
      break;
    case addresses.tokens.USDC.toLowerCase():
      const USDC = await getERC20(addresses.tokens.USDC);
      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, garden.address, 1, { gasPrice: 0 });
      await USDC.connect(signer3).approve(garden.address, from(1e5 * 1e6), { gasPrice: 0 });
      await garden.connect(signer3).deposit(from(1e5 * 1e6), 1, signer3.getAddress(), ADDRESS_ZERO);
      break;
    case addresses.tokens.WETH.toLowerCase():
      const WETH = await getERC20(addresses.tokens.WETH);
      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, garden.address, 1, { gasPrice: 0 });
      await WETH.connect(signer3).approve(garden.address, amount, { gasPrice: 0 });
      await garden.connect(signer3).deposit(amount, 1, signer3.address, ADDRESS_ZERO);
      await ishtarGate.connect(signer1).setGardenAccess(whaleSigner.address, garden.address, 1, { gasPrice: 0 });
      await WETH.connect(whaleSigner).approve(garden.address, amount, { gasPrice: 0 });
      await garden.connect(whaleSigner).deposit(amount, 1, whaleSigner.address, ADDRESS_ZERO);
      break;
    case addresses.tokens.WBTC.toLowerCase():
      const WBTC = await getERC20(addresses.tokens.WBTC);
      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, garden.address, 1, { gasPrice: 0 });
      await WBTC.connect(signer3).approve(garden.address, from(1e8), { gasPrice: 0 });
      await garden.connect(signer3).deposit(from(1e8), 1, signer3.getAddress(), ADDRESS_ZERO);
      break;
    case addresses.tokens.BABL.toLowerCase():
      const BABL = await getERC20(addresses.tokens.BABL);
      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, garden.address, 1, { gasPrice: 0 });
      await BABL.connect(signer3).approve(garden.address, eth('100'), { gasPrice: 0 });
      await garden.connect(signer3).deposit(eth('100'), 1, signer3.getAddress(), ADDRESS_ZERO);
      break;
    case addresses.tokens.AAVE.toLowerCase():
      const AAVE = await getERC20(addresses.tokens.AAVE);
      await ishtarGate.connect(signer1).setGardenAccess(signer3.address, garden.address, 1, { gasPrice: 0 });
      await AAVE.connect(signer3).approve(garden.address, eth('100'), { gasPrice: 0 });
      await garden.connect(signer3).deposit(eth('100'), 1, signer3.getAddress(), ADDRESS_ZERO);
      break;
  }
}

async function transferFunds(address) {
  const [, , , signer1, signer2, signer3] = await ethers.getSigners();
  let whaleAddress;
  let whaleSigner;
  switch (address.toLowerCase()) {
    case addresses.tokens.AAVE.toLowerCase():
      whaleAddress = '0x4da27a545c0c5b758a6ba100e3a049001de870f5';
      whaleSigner = await impersonateAddress(whaleAddress);
      const AAVE = await getERC20(addresses.tokens.AAVE);

      await AAVE.connect(whaleSigner).transfer(signer1.address, eth('30'), {
        gasPrice: 0,
      });
      await AAVE.connect(whaleSigner).transfer(signer2.address, eth('30'), {
        gasPrice: 0,
      });
      await AAVE.connect(whaleSigner).transfer(signer3.address, eth('30'), {
        gasPrice: 0,
      });
      break;
    case addresses.tokens.BABL.toLowerCase():
      whaleAddress = '0x40154ad8014df019a53440a60ed351dfba47574e';
      whaleSigner = await impersonateAddress(whaleAddress);
      const BABL = await getERC20(addresses.tokens.BABL);

      await BABL.connect(whaleSigner).transfer(signer1.address, eth('30'), {
        gasPrice: 0,
      });
      await BABL.connect(whaleSigner).transfer(signer2.address, eth('30'), {
        gasPrice: 0,
      });
      await BABL.connect(whaleSigner).transfer(signer3.address, eth('30'), {
        gasPrice: 0,
      });
      break;
    case addresses.tokens.DAI.toLowerCase():
      whaleAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
      whaleSigner = await impersonateAddress(whaleAddress);
      const DAI = await getERC20(addresses.tokens.DAI);

      await DAI.connect(whaleSigner).transfer(signer1.address, eth('20000'), {
        gasPrice: 0,
      });
      await DAI.connect(whaleSigner).transfer(signer2.address, eth('10000'), {
        gasPrice: 0,
      });
      await DAI.connect(whaleSigner).transfer(signer3.address, eth('10000'), {
        gasPrice: 0,
      });
      break;
    case addresses.tokens.USDC.toLowerCase():
      whaleAddress = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503';
      whaleSigner = await impersonateAddress(whaleAddress);
      const USDC = await getERC20(addresses.tokens.USDC);

      await USDC.connect(whaleSigner).transfer(signer1.address, from(1e6 * 1e6), {
        gasPrice: 0,
      });
      await USDC.connect(whaleSigner).transfer(signer2.address, from(1e6 * 1e6), {
        gasPrice: 0,
      });
      await USDC.connect(whaleSigner).transfer(signer3.address, from(1e6 * 1e6), {
        gasPrice: 0,
      });
      break;
    case addresses.tokens.WETH.toLowerCase():
      whaleAddress = '0x2f0b23f53734252bda2277357e97e1517d6b042a';
      whaleSigner = await impersonateAddress(whaleAddress);
      const WETH = await getERC20(addresses.tokens.WETH);

      await WETH.connect(whaleSigner).transfer(signer1.address, eth(100), {
        gasPrice: 0,
      });
      await WETH.connect(whaleSigner).transfer(signer2.address, eth(100), {
        gasPrice: 0,
      });
      await WETH.connect(whaleSigner).transfer(signer3.address, eth(100), {
        gasPrice: 0,
      });
      break;
    case addresses.tokens.WBTC.toLowerCase():
      whaleAddress = '0x9ff58f4ffb29fa2266ab25e75e2a8b3503311656';
      whaleSigner = await impersonateAddress(whaleAddress);
      const WBTC = await getERC20(addresses.tokens.WBTC);

      await WBTC.connect(whaleSigner).transfer(signer1.address, from(10e8), {
        gasPrice: 0,
      });
      await WBTC.connect(whaleSigner).transfer(signer2.address, from(10e8), {
        gasPrice: 0,
      });
      await WBTC.connect(whaleSigner).transfer(signer3.address, from(10e8), {
        gasPrice: 0,
      });
      break;
  }
}

function getDepositSigHash(garden, amountIn, minAmountOut, nonce, maxFee, to, referrer) {
  const DEPOSIT_BY_SIG_TYPEHASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes(
      'DepositBySig(uint256 _amountIn,uint256 _minAmountOut,uint256 _nonce,uint256 _maxFee,address _to,address _referrer)',
    ),
  );

  let payload = ethers.utils.defaultAbiCoder.encode(
    ['bytes32', 'address', 'uint256', 'uint256', 'uint256', 'uint256', 'address', 'address'],
    [DEPOSIT_BY_SIG_TYPEHASH, garden, amountIn, minAmountOut, nonce, maxFee, to, referrer],
  );

  return ethers.utils.keccak256(payload);
}

async function getDepositSig(garden, signer, amountIn, minAmountOut, nonce, maxFee, to, referrer) {
  let payloadHash = getDepositSigHash(garden, amountIn, minAmountOut, nonce, maxFee, to, referrer);

  return await signer.signMessage(ethers.utils.arrayify(payloadHash));
}

function getWithdrawSigHash(garden, amountIn, minAmountOut, nonce, maxFee, withPenalty) {
  const WITHDRAW_BY_SIG_TYPEHASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes(
      'WithdrawBySig(uint256 _amountIn,uint256 _minAmountOut,uint256,_nonce,uint256 _maxFee,uint256 _withPenalty)',
    ),
  );

  let payload = ethers.utils.defaultAbiCoder.encode(
    ['bytes32', 'address', 'uint256', 'uint256', 'uint256', 'uint256', 'bool'],
    [WITHDRAW_BY_SIG_TYPEHASH, garden, amountIn, minAmountOut, nonce, maxFee, withPenalty],
  );

  return ethers.utils.keccak256(payload);
}

async function getWithdrawSig(garden, signer, amountIn, minAmountOut, nonce, maxFee, withPenalty) {
  let payloadHash = getWithdrawSigHash(garden, amountIn, minAmountOut, nonce, maxFee, withPenalty);

  return await signer.signMessage(ethers.utils.arrayify(payloadHash));
}

function getRewardsSigHash(garden, babl, profits, nonce, maxFee) {
  const REWARDS_BY_SIG_TYPEHASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes('RewardsBySig(uint256 _babl,uint256 _profits,uint256 _nonce,uint256 _maxFee)'),
  );

  let payload = ethers.utils.defaultAbiCoder.encode(
    ['bytes32', 'address', 'uint256', 'uint256', 'uint256', 'uint256'],
    [REWARDS_BY_SIG_TYPEHASH, garden, babl, profits, nonce, maxFee],
  );

  return ethers.utils.keccak256(payload);
}

async function getRewardsSig(garden, signer, babl, profits, nonce, maxFee) {
  let payloadHash = getRewardsSigHash(garden, babl, profits, nonce, maxFee);

  return await signer.signMessage(ethers.utils.arrayify(payloadHash));
}

function getStakeRewardsSigHash(garden, babl, profits, minAmountOut, nonce, nonceHeart, maxFee, to) {
  const REWARDS_BY_SIG_TYPEHASH = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes(
      'StakeRewardsBySig(uint256 _babl,uint256 _profits,uint256 _minAmountOut,uint256 _nonce,uint256 _nonceHeart,uint256 _maxFee,address _to)',
    ),
  );

  let payload = ethers.utils.defaultAbiCoder.encode(
    ['bytes32', 'address', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'address'],
    [REWARDS_BY_SIG_TYPEHASH, garden, babl, profits, minAmountOut, nonce, nonceHeart, maxFee, to],
  );

  return ethers.utils.keccak256(payload);
}

async function getStakeRewardsSig(garden, signer, babl, profits, minAmountOut, nonce, nonceHeart, maxFee, to) {
  let payloadHash = getStakeRewardsSigHash(garden, babl, profits, minAmountOut, nonce, nonceHeart, maxFee, to);

  return await signer.signMessage(ethers.utils.arrayify(payloadHash));
}

module.exports = {
  createGarden,
  depositFunds,
  transferFunds,
  getDepositSig,
  getDepositSigHash,
  getWithdrawSig,
  getWithdrawSigHash,
  getRewardsSigHash,
  getRewardsSig,
  getStakeRewardsSigHash,
  getStakeRewardsSig,
};
