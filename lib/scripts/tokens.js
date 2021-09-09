const addresses = require('../addresses.js');
const { from } = require('../helpers');

const fs = require('fs');
const glob = require('glob');
const path = require('path');

const MIN_LIQUIDITY_USD = 1 * 1000 * 1000;
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

async function _sourceIntegration(address) {
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
  } catch {}
  try {
    const maybeDAI = await curveRegistry['find_pool_for_coins(address,address)'](addresses.tokens.DAI, address);
    if (maybeDAI) {
      return true;
    }
  } catch {}
  try {
    const maybeUSDC = await curveRegistry['find_pool_for_coins(address,address)'](addresses.tokens.USDC, address);
    if (maybeUSDC) {
      return true;
    }
  } catch {}
  try {
    const maybeWBTC = await curveRegistry['find_pool_for_coins(address,address)'](addresses.tokens.WBTC, address);
    if (maybeWBTC) {
      return true;
    }
  } catch {}

  console.log(`No curve pool found for token: ${address}`);
  return false;
}

async function _getUniPool(address, priceOracle) {
  // UniV3
  try {
    const maybeWETHV3 = await priceOracle.getUNIV3Price(addresses.tokens.WETH, address);

    if (maybeWETHV3) {
      return Protocol.uniV3;
    }
  } catch {}

  // UniV2
  try {
    const maybeWETHV2 = await priceOracle.getUNIV2Price(addresses.tokens.WETH, address);

    if (maybeWETHV2) {
      return Protocol.uniV2;
    }
  } catch {}

  console.log(`No Uniswap pool found for token: ${address}`);
  return undefined;
}

async function _dedupeAndGetBestImage(tokens) {
  // consider adding a fetch and store to this
  // mutate object with best image
  const seen = new Set();

  return tokens.filter((token) => {
    const dupe = seen.has(token.address.toLowerCase());
    seen.add(token.address.toLowerCase());
    return !dupe;
  });
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

async function _hasMinimumLiquidity(address, babylonViewer) {
  try {
    const maybeWETH = await babylonViewer.getPriceAndLiquidity(addresses.tokens.WETH, address);
    if (maybeWETH) {
      return maybeWETH[1];
    }
  } catch {}
  try {
    const maybeDAI = await babylonViewer.getPriceAndLiquidity(addresses.tokens.DAI, address);
    if (maybeDAI) {
      return maybeDAI[1];
    }
  } catch {}
  try {
    const maybeUSDC = await babylonViewer.getPriceAndLiquidity(addresses.tokens.USDC, address);
    if (maybeUSDC) {
      return maybeUSDC[1];
    }
  } catch {}
  try {
    const maybeWBTC = await babylonViewer.getPriceAndLiquidity(addresses.tokens.WBTC, address);
    if (maybeWBTC) {
      return maybeWBTC[1];
    }
  } catch {}

  console.log(`No liquidity data found for token: ${address}`);
  return undefined;
}

// Contract helpers
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

// Main
async function exportTokenList(ethers) {
  const curveRegistry = await _getCurveRegistry(ethers);
  const babylonViewer = await _getBabylonViewer(ethers);
  const priceOracle = await _getPriceOracle(ethers);
  const deduped = await _dedupeAndGetBestImage(TOKENS);

  // drop the slice before commit
  const promises = deduped.map(async (token) => {
    // Check for source integration, if no match check UniV3/V2 else undefined and will be filtered
    const maybeIntegration = await _sourceIntegration(token.address);
    const liquidity = await _hasMinimumLiquidity(token.address, babylonViewer);
    let finalIntegration = maybeIntegration;

    // Skip and return undefined if there is no liquidity
    if (!liquidity) {
      return undefined;
    }

    if (!maybeIntegration) {
      const maybeUniPool = await _getUniPool(token.address, priceOracle);

      if (!maybeUniPool) {
        return undefined;
      }

      finalIntegration = Protocol.uniV3;
    }

    return {
      ...token,
      integration: finalIntegration,
      liquidity: liquidity.toString(),
      swappable: finalIntegration ? await _isSwappable(finalIntegration, token.address, curveRegistry) : false,
    };
  });

  // Filter anything without an integration
  return (await Promise.all(promises)).filter((item) => item !== undefined);
}

module.exports = {
  exportTokenList,
};
