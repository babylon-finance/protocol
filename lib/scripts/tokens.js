const addresses = require('../addresses.js');

const { GraphQLClient, gql } = require('graphql-request');
const Promise = require('bluebird');
const fs = require('fs');
const glob = require('glob');
const path = require('path');

const MIN_LIQUIDITY_USD = 1 * 1000 * 1000;

const Reserves = {
  ETH: {
    decimals: 18,
    address: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2',
  },
  WETH: {
    decimals: 18,
    address: addresses.tokens.WETH,
  },
  DAI: {
    decimals: 18,
    address: addresses.tokens.DAI,
  },
  USDC: {
    decimals: 6,
    address: addresses.tokens.USDC,
  },
  WBTC: {
    decimals: 8,
    address: addresses.tokens.WBTC,
  },
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

const gqlClient = new GraphQLClient('https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v2');

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
  if (
    Object.values(addresses.yearn.outputTokens)
      .map((t) => t.toLowerCase())
      .includes(formattedAddress)
  ) {
    return Protocol.yearn;
  }

  // If no matches return undefined
  return undefined;
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

async function _hasCurvePool(address, curveRegistry) {
  const formattedAddress = address.toLowerCase();

  const promises = Object.entries(Reserves).map(async (reserve) => {
    const [, details] = reserve;

    if (formattedAddress !== details.address.toLowerCase()) {
      const maybePoolA = await curveRegistry['find_pool_for_coins(address,address)'](details.address, address);
      const maybePoolB = await curveRegistry['find_pool_for_coins(address,address)'](address, details.address);

      return (maybePoolA && maybePoolA !== addresses.zero) || (maybePoolB && maybePoolB !== addresses.zero);
    } else {
      return false;
    }
  });

  const results = await Promise.all(promises);
  return results.includes(true);
}

async function _getV3Liquidity(address, babylonViewer) {
  const formattedAddress = address.toLowerCase();

  const promises = Object.entries(Reserves).map(async (reserve) => {
    const [, details] = reserve;

    if (formattedAddress !== details.address.toLowerCase()) {
      try {
        // Note: Bug in contract here that needs to be resolved
        const result = await babylonViewer.getPriceAndLiquidity(address, details.address);

        if (result) {
          return { value: result[1], reserve: details };
        }
      } catch {}
    }
  });

  const results = await Promise.all(promises);

  return results.filter((item) => item !== undefined).sort((a, b) => a.value.sub(b.value))[0];
}

async function _getBestV2Liquidity(token, uniV2Factory, priceOracle, ethers) {
  const formattedAddress = token.address.toLowerCase();

  const promises = Object.entries(Reserves).map(async (reserve) => {
    const [symbol, details] = reserve;

    if (formattedAddress !== details.address.toLowerCase()) {
      try {
        const maybePairAddress1 = await uniV2Factory.getPair(token.address, details.address);

        if (maybePairAddress1 && maybePairAddress1 !== addresses.zero) {
          const query = gql`
            query getPair($id: ID!) {
              pairs(where: { id: $id }) {
                id
                reserveUSD
              }
            }
          `;

          const variables = { id: maybePairAddress1.toLowerCase() };
          const result = await gqlClient.request(query, variables).then((data) => {
            return data.pairs[0].reserveUSD;
          });

          return { value: result, reserve: details };
        }
      } catch (error) {
        console.log(`Error fetching v2 liquidity for pair: ${token.address} :: ${symbol}`, error);
      }
    }
  });

  const results = await Promise.all(promises);

  return results.filter((item) => item !== undefined).sort((a, b) => a.value - b.value)[0];
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

async function _getUniV2Factory(ethers) {
  const factoryAddress = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
  return await ethers.getContractAt('IUniswapV2Factory', factoryAddress);
}

async function processToken(token, curveRegistry, priceOracle, babylonViewer, uniV2Factory) {
  // Check for source integration, if no match check UniV3/V2 else undefined and will be filtered
  const priceDecimals = 18;
  const maybeIntegration = await _sourceIntegration(token.address);

  let finalIntegration = maybeIntegration;
  let finalLiquidity = MIN_LIQUIDITY_USD;

  // If no explicit integration defined check uniV3 then uniV2
  if (!maybeIntegration) {
    const maybeV3Liquidity = await _getV3Liquidity(token.address, babylonViewer);

    // If we found v3 liquidity use it
    if (maybeV3Liquidity) {
      const priceInUSDC = await priceOracle.getPrice(maybeV3Liquidity.reserve.address, addresses.tokens.USDC);
      const priceFloat = parseFloat(ethers.utils.formatUnits(priceInUSDC, priceDecimals));
      const liquidityFloat = parseFloat(
        ethers.utils.formatUnits(maybeV3Liquidity.value, maybeV3Liquidity.reserve.decimals),
      );

      finalIntegration = Protocol.uniV3;
      finalLiquidity = parseInt(liquidityFloat * priceFloat);
    } else {
      finalLiquidity = 0;
    }

    // If not enough V3 liquidity look for liquidity in V2
    if (finalLiquidity < MIN_LIQUIDITY_USD) {
      const maybeV2Liquidity = await _getBestV2Liquidity(token, uniV2Factory, priceOracle, ethers);

      if (maybeV2Liquidity) {
        finalIntegration = Protocol.uniV2;
        finalLiquidity = parseInt(maybeV2Liquidity.value);
      }
    }

    if (finalLiquidity < MIN_LIQUIDITY_USD) {
      return undefined;
    }
  }

  // Note: that if we get a match for an integration that is not uniswap we set the liquidity to MIN_LIQUIDITY_USD since we
  // do not want to filter them.
  return {
    logoURI: '', // Some lists don't conform, so we initialize and overwrite if token has the field
    integration: finalIntegration,
    liquidity: finalLiquidity,
    swappable: finalIntegration ? await _isSwappable(finalIntegration, token.address, curveRegistry) : false,
    ...token,
  };
}

async function _dedupeAndGetBestImage(tokens) {
  const toProcess = tokens;
  const seen = new Set();

  const filtered = toProcess.filter((token) => {
    const dupe = seen.has(token.address.toLowerCase());
    seen.add(token.address.toLowerCase());
    return !dupe && token.chainId === 1;
  });

  console.log(`Filtered ${toProcess.length - filtered.length} of ${toProcess.length} as duplicates!`);
  console.log(`Now processing ${filtered.length} tokens...`);
  return filtered;
}

// Main
async function buildTokenList(ethers) {
  const deduped = await _dedupeAndGetBestImage(TOKENS);

  const curveRegistry = await _getCurveRegistry(ethers);
  const priceOracle = await _getPriceOracle(ethers);
  const babylonViewer = await _getBabylonViewer(ethers);
  const uniV2Factory = await _getUniV2Factory(ethers);

  const results = Promise.map(
    deduped,
    function (token) {
      return processToken(token, curveRegistry, priceOracle, babylonViewer, uniV2Factory);
    },
    { concurrency: 5 },
  ).then((output) => {
    return output;
  });

  return (await results)
    .filter((item) => item !== undefined)
    .filter((item) => item.integration !== undefined)
    .filter((item) => item.liquidity >= MIN_LIQUIDITY_USD);
}

module.exports = {
  buildTokenList,
};
