const addresses = require('../addresses.js');

const { GraphQLClient, gql } = require('graphql-request');
const axios = require('axios');
const Promise = require('bluebird');
const fs = require('fs');

const LIST_URLS = [
  { name: 'uniswap', url: 'https://tokens.coingecko.com/uniswap/all.json' },
  {
    name: 'compound',
    url: 'https://raw.githubusercontent.com/compound-finance/token-list/master/compound.tokenlist.json',
  },
  { name: 'tryroll', url: 'https://app.tryroll.com/tokens.json' },
  { name: 'set', url: 'https://raw.githubusercontent.com/SetProtocol/uniswap-tokenlist/main/set.tokenlist.json' },
  { name: 'zapper', url: 'https://zapper.fi/api/token-list' },
  { name: 'zerion', url: 'http://tokenlist.zerion.eth.link' },
  { name: 'oneinch', url: 'https://wispy-bird-88a7.uniswap.workers.dev/?url=http://tokens.1inch.eth.link' },
];

const MIN_LIQUIDITY_USD = 10 * 1000; // 10,000 USD

const Reserves = {
  ETH: {
    decimals: 18,
    address: addresses.tokens.ETH2,
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
    case Protocol.lido:
    case Protocol.yearn:
      return await _hasCurvePool(address, curveRegistry);
    case Protocol.curve:
      return false;
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

    // Note: Ignore if trying to find a pair of the same 2 tokens
    if (formattedAddress !== details.address.toLowerCase()) {
      const maybePool = await curveRegistry['find_pool_for_coins(address,address)'](details.address, address);

      // Note: find_pool_for_coins returns address(0) if there is a pool but the pair is not swappable
      return maybePool && maybePool !== addresses.zero;
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

  return results.filter((item) => item !== undefined).sort((a, b) => b.value.sub(a.value))[0];
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

  return results.filter((item) => item !== undefined).sort((a, b) => b.value - a.value)[0];
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

async function _processToken(token, curveRegistry, priceOracle, babylonViewer, uniV2Factory, progress) {
  // Check for source integration, if no match check UniV3/V2 else undefined and will be filtered
  try {
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
    const newToken = {
      lastUpdatedAt: Date.now(),
      logoURI: '', // Some lists don't conform, so we initialize and overwrite if token has the field
      integration: finalIntegration,
      liquidity: finalLiquidity,
      swappable: finalIntegration ? await _isSwappable(finalIntegration, token.address, curveRegistry) : false,
      ...token,
    };

    return newToken.logoURI.startsWith('ipfs://') ? { ...newToken, logoURI: '' } : newToken;
  } catch (error) {
    return {};
  } finally {
    progress.increment();
  }
}

async function isImageValid(logoURI) {
  let url;

  try {
    url = new URL(logoURI);
    if (url.protocol === 'ipfs:') {
      return false;
    }
  } catch (_) {
    return false;
  }

  const result = await axios
    .head(url.toString(), { timeout: 1000 })
    .then((response) => {
      if (response.status === 200) {
        return true;
      } else {
        return false;
      }
    })
    .catch((_) => {
      console.log(`Error fetching valid image: ${url.toString()}`);
      return false;
    });

  return result;
}

// Main
async function buildTokenList(ethers, tokens, progress) {
  const curveRegistry = await _getCurveRegistry(ethers);
  const priceOracle = await _getPriceOracle(ethers);
  const babylonViewer = await _getBabylonViewer(ethers);
  const uniV2Factory = await _getUniV2Factory(ethers);

  const processTokenWrapped = async (token) => {
    try {
      return await _processToken(token, curveRegistry, priceOracle, babylonViewer, uniV2Factory, progress).catch(() => {
        console.error('Error processing token', token);
        errors.push(token);
      });
    } catch (error) {
      console.error('Error processing token', token);
      errors.push(token);
      return {};
    }
  };

  console.log(`Processing ${tokens.length} tokens...`);
  progress.start(tokens.length, 0, {});

  const errors = [];
  let results = await Promise.map(tokens, processTokenWrapped, { concurrency: 75 }).then((output) => output);

  progress.stop();
  console.log('Processing tokens complete!');

  if (errors.length > 0) {
    console.log(`Retrying ${errors.length} tokens...`);
    progress.start(errors.length, 0, {});

    console.log('Retrying tokens...', errors.toString());
    const retries = await Promise.map(errors, processTokenWrapped).then((output) => output);
    results = results.concat(retries);

    progress.stop();
    console.log('Retries complete!');
  }

  return results
    .filter((item) => item !== undefined)
    .filter((item) => item.integration !== undefined)
    .filter((item) => item.liquidity >= MIN_LIQUIDITY_USD);
}

async function fetchNewLists() {
  const promises = LIST_URLS.map(async (item) => {
    return await axios.get(item.url).then((res) => {
      return res.data.tokens;
    });
  });
  return (await Promise.all(promises)).flat();
}

module.exports = {
  buildTokenList,
  fetchNewLists,
  isImageValid,
};
