const axios = require('axios');

const BLOCKNATIVE_API_URL = 'https://api.blocknative.com';
const GAS_SPEED = {
  fast: 'fast',
  standard: 'standard',
  safe: 'safe',
};

/**
 * Returns gas prices in wei
 */
async function getPrices() {
  function getFees(prices, confidence) {
    const price = prices.find((ep) => ep.confidence === confidence);
    return {
      maxPriorityFeePerGas: Math.round(price.maxPriorityFeePerGas * 10 ** 9),
      maxFeePerGas: Math.round(price.maxFeePerGas * 10 ** 9),
    };
  }

  const config = {
    headers: {
      Authorization: process.env.BLOCKNATIVE_API_KEY,
    },
  };

  const { data } = await axios.get(`${BLOCKNATIVE_API_URL}/gasprices/blockprices`, config);

  const prices = data.blockPrices[0].estimatedPrices;
  // Grab prices and convert to wei for backwards compatibility
  return {
    fast: getFees(prices, 99),
    standard: getFees(prices, 95),
    safe: getFees(prices, 70),
    baseFeePerGas: data.blockPrices[0].baseFeePerGas * 10 ** 9,
  };
}

export async function getGasPrice(speed) {
  return (await getPrices())[speed || GAS_SPEED.fast];
}

module.exports = {
  getPrices,
  getGasPrice,
  GAS_SPEED,
};
