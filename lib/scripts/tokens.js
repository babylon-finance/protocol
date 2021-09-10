const addresses = require('../addresses.js');
const { from, formatNumber } = require('../helpers');

const fs = require('fs');
const glob = require('glob');
const path = require('path');

const MIN_LIQUIDITY_USD = 1 * 1000 * 1000;

const Decimals = {
  WETH: 18,
  DAI: 18,
  USDC: 6,
  WBTC: 8,
};

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
    const maybeWETHV3 = await priceOracle.getUniswapPoolWithHighestLiquidity(address, addresses.tokens.WETH);

    if (maybeWETHV3) {
      return Protocol.uniV3;
    }
  } catch {}

  console.log(`No Uniswap pool found for token: ${address}`);
  return undefined;
}

async function _dedupeAndGetBestImage(tokens) {
  // consider adding a fetch and store to this
  const seen = new Set();

  const filtered = tokens.filter((token) => {
    const dupe = seen.has(token.address.toLowerCase());
    seen.add(token.address.toLowerCase());
    return !dupe && token.chainId === 1;
  });

  console.log(`Filtered ${tokens.length - filtered.length} of ${tokens.length} as duplicates!`);
  return filtered;
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
    case Protocol.uniV3:
    case Protocol.uniV2:
      return true;
    default:
      return false;
  }
}

async function _getV3Liquidity(address, babylonViewer) {
  const formattedAddress = address.toLowerCase();

  if (formattedAddress !== addresses.tokens.WETH.toLowerCase()) {
    try {
      const maybeWETH = await babylonViewer.getPriceAndLiquidity(address, addresses.tokens.WETH);
      if (maybeWETH) {
        return { value: maybeWETH[1], reserve: { address: addresses.tokens.WETH, decimals: Decimals.WETH } };
      }
    } catch {}
  }

  if (formattedAddress !== addresses.tokens.DAI.toLowerCase()) {
    try {
      const maybeDAI = await babylonViewer.getPriceAndLiquidity(address, addresses.tokens.DAI);
      if (maybeDAI) {
        return { value: maybeDAI[1], reserve: { address: addresses.tokens.DAI, decimals: Decimals.DAI } };
      }
    } catch {}
  }

  if (formattedAddress !== addresses.tokens.USDC.toLowerCase()) {
    try {
      const maybeUSDC = await babylonViewer.getPriceAndLiquidity(address, addresses.tokens.USDC);
      if (maybeUSDC) {
        return { value: maybeUSDC[1], reserve: { address: addresses.tokens.USDC, decimals: Decimals.USDC } };
      }
    } catch {}
  }

  if (formattedAddress !== addresses.tokens.WBTC.toLowerCase()) {
    try {
      const maybeWBTC = await babylonViewer.getPriceAndLiquidity(address, addresses.tokens.WBTC);
      if (maybeWBTC) {
        return { value: maybeWBTC[1], reserve: { address: addresses.tokens.WBTC, decimals: Decimals.WBTC } };
      }
    } catch {}
  }

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
async function buildTokenList(ethers) {
  const curveRegistry = await _getCurveRegistry(ethers);
  const priceOracle = await _getPriceOracle(ethers);
  const babylonViewer = await _getBabylonViewer(ethers);
  const deduped = await _dedupeAndGetBestImage(TOKENS);

  // drop the slice before merge!!!!!!!!!!!!!!!!!!!!!!!!
  const promises = deduped.slice(0, 100).map(async (token) => {
    // Check for source integration, if no match check UniV3/V2 else undefined and will be filtered
    const maybeIntegration = await _sourceIntegration(token.address);
    let finalIntegration = maybeIntegration;
    let finalLiquidity = 1000000;

    // If still no integration defined but there is liquidity it is UniV3
    if (!maybeIntegration) {
      const maybeV3Liquidity = await _getV3Liquidity(token.address, babylonViewer);

      if (maybeV3Liquidity) {
        finalIntegration = Protocol.uniV3;

        const priceDecimals = 18;
        const priceInUSDC = await priceOracle.getPrice(maybeV3Liquidity.reserve.address, addresses.tokens.USDC);
        const priceFloat = parseFloat(ethers.utils.formatUnits(priceInUSDC, priceDecimals));
        const liquidityFloat = parseFloat(
          ethers.utils.formatUnits(maybeV3Liquidity.value, maybeV3Liquidity.reserve.decimals),
        );

        finalLiquidity = (liquidityFloat * priceFloat).toFixed(0);
      }

      // const maybeV2Liquidity = await _getV2Liquidity(token.address, uniV2Router);
      // if (maybeV2Liquidity) {}

      return undefined;
    }

    return {
      ...token,
      integration: finalIntegration,
      liquidity: finalLiquidity,
      swappable: finalIntegration ? await _isSwappable(finalIntegration, token.address, curveRegistry) : false,
    };
  });

  // Final filter
  return (await Promise.all(promises)).filter((item) => item !== undefined);
}

module.exports = {
  buildTokenList,
};
