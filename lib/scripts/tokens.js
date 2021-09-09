const addresses = require('../addresses.js');
const { from, eth, formatNumber } = require('../helpers');

const fs = require('fs');
const glob = require('glob');
const path = require('path');

const LISTS = glob.sync('lib/tokens/*.json').map((file) => {
  return require(path.resolve(file));
});

const TOKENS = LISTS.map((list) => {
  return list.tokens;
}).flat();

const Protocol = {
  aave: 'aave',
  compound: 'compound',
  cream: 'cream',
  curve: 'curve',
  lido: 'lido',
  synthetix: 'synthetix',
  yearn: 'yearn',
  uniV2: 'uniV2',
  uniV3: 'uniV3',
};

async function _sourceIntegration(address, yearnVaults) {
  const formattedAddress = address.toLowerCase();

  // Aave
  if (addresses.aave.atokens.map((t) => t.atoken.toLowerCase()).includes(formattedAddress)) {
    return Protocol.aave;
  }

  // Compound
  if (addresses.compound.ctokens.map((t) => t.ctoken.toLowerCase()).includes(formattedAddress)) {
    return Protocol.compound;
  }

  // Cream
  if (addresses.cream.crtokens.map((t) => t.ctoken.toLowerCase()).includes(formattedAddress)) {
    return Protocol.cream;
  }

  // Curve
  if (
    Object.values(addresses.curve.pools.v3)
      .map((t) => t.toLowerCase())
      .includes(formattedAddress)
  ) {
    return Protocol.curve;
  }

  // Lido
  if (
    Object.values(addresses.lido)
      .map((t) => t.toLowerCase())
      .includes(formattedAddress)
  ) {
    return Protocol.lido;
  }

  // Synthetix
  if (addresses.synthetix.synths.map((t) => t.synth.toLowerCase()).includes(formattedAddress)) {
    return Protocol.synthetix;
  }

  // Yearn
  // check the vault registry and filter disabled

  // If no matches return undefined
  return undefined;
}

async function _hasCurvePool(address, curveRegistry) {
  try {
    const maybeWETH = await curveRegistry['find_pool_for_coins(address,address)'](addresses.tokens.WETH, address);
    if (maybeWETH) {
      return true;
    }
    const maybeDAI = await curveRegistry['find_pool_for_coins(address,address)'](addresses.tokens.DAI, address);
    if (maybeDAI) {
      return true;
    }
    const maybeUSDC = await curveRegistry['find_pool_for_coins(address,address)'](addresses.tokens.USDC, address);
    if (maybeUSDC) {
      return true;
    }
    const maybeWBTC = await curveRegistry['find_pool_for_coins(address,address)'](addresses.tokens.WBTC, address);
    if (maybeWBTC) {
      return true;
    }

    return false;
  } catch (error) {
    console.log(`Encountered an error fetching curve pool details for token: ${address}, skipping...`);
    return false;
  }
}

async function _getUniPool(address, priceOracle) {
  try {
    const maybeWETH = await priceOracle.getPrice(addresses.tokens.WETH, address);
    console.log(maybeWETH);
    return Protocol.uniV3;
  } catch (error) {
    console.log(`Encountered an error fetching details from PriceOracle for token: ${address}, skipping...`);
    return undefined;
  }
}

async function _dedupeAndGetBestImage(tokens) {
  // check for a duplicate
  // consider adding a fetch and store to this
  // mutate object with best image
  return tokens;
}

async function _isSwappable(integration, address, curveRegistry) {
  switch (integration) {
    case Protocol.aave:
    case Protocol.compound:
    case Protocol.cream:
    case Protocol.yearn:
      return await _hasCurvePool(address, curveRegistry);
    case Protocol.curve:
      return false;
    case Protocol.lido:
      return true;
    case Protocol.synthetix:
      return true;
    default:
      return false;
  }
}

async function _findValidImageURI() {}

// Note: Might be worth spliting out these calls into separate try/catch blocks so the code can fall through
async function _hasMinimumLiquidity(address, babylonViewer) {
  try {
    const maybeWETH = await babylonViewer.getPriceAndLiquidity(address, addresses.tokens.WETH);
    if (maybeWETH[1].gte(from(1000))) {
      return maybeWETH[1];
    }
    const maybeDAI = await babylonViewer.getPriceAndLiquidity(address, addresses.tokens.DAI);
    if (maybeDAI[1].gte(from(1000))) {
      return maybeDAI[1];
    }
    const maybeUSDC = await babylonViewer.getPriceAndLiquidity(address, addresses.tokens.USDC);
    if (maybeUSDC[1].gte(from(1000))) {
      return maybeUSDC[1];
    }
    const maybeWBTC = await babylonViewer.getPriceAndLiquidity(address, addresses.tokens.WBTC);
    if (maybeWBTC[1].gte(from(1000))) {
      return maybeWBTC[1];
    }
    return undefined;
  } catch (error) {
    console.log(error);
    return undefined;
  }
}

async function _getCurveRegistry(ethers) {
  const curveAddressProvider = await ethers.getContractAt('ICurveAddressProvider', addresses.curve.addressProvider);
  const curveRegistryAddress = await curveAddressProvider.get_registry();

  return await ethers.getContractAt('ICurveRegistry', curveRegistryAddress);
}

async function _getBabylonViewer(ethers) {
  const contractObj = JSON.parse(fs.readFileSync(`./deployments/artifacts/mainnet/BabylonViewer.json`));
  return await ethers.getContractAt('BabylonViewer', contractObj.address);
}

async function _getPriceOracle(ethers) {
  const contractObj = JSON.parse(fs.readFileSync(`./deployments/artifacts/mainnet/PriceOracle.json`));
  return await ethers.getContractAt('PriceOracle', contractObj.address);
}

async function exportTokenList(ethers) {
  const curveRegistry = await _getCurveRegistry(ethers);
  const babylonViewer = await _getBabylonViewer(ethers);
  const priceOracle = await _getPriceOracle(ethers);
  const deduped = await _dedupeAndGetBestImage(TOKENS);

  // drop the slice before commit
  const promises = deduped.slice(0, 10).map(async (token) => {
    // Check for source integration, if no match check UniV3/V2 else undefined and will be filtered
    const integration = (await _sourceIntegration(token.address)) || (await _getUniPool(token.address, priceOracle));
    const liquidity = (await _hasMinimumLiquidity(token.address, babylonViewer)) || 0;

    return {
      ...token,
      integration,
      liquidity: liquidity.toString(),
      swappable: await _isSwappable(integration, token.address, curveRegistry),
    };
  });

  return Promise.all(promises);
}

module.exports = {
  exportTokenList,
};
