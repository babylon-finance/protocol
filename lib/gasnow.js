const axios = require('axios');

const GAS_LIMIT = process.env.GAS_LIMIT || 60000000000;
const BLOCKNATIVE_API_URL = 'https://api.blocknative.com';

/**
 * Returns gas prices in wei
 */
export async function getPrices() {
  const config = {
    headers: {
      Authorization: process.env.BLOCKNATIVE_API_KEY,
    },
  };

  const { data } = await axios.get(`${BLOCKNATIVE_API_URL}/gasprices/blockprices`, config);

  const prices = data.blockPrices[0].estimatedPrices;
  // Grab prices and convert to wei for backwards compatibility
  const fast = prices.find((ep) => ep.confidence === 95).price * 10 ** 9;
  const rapid = prices.find((ep) => ep.confidence === 99).price * 10 ** 9;
  const standard = prices.find((ep) => ep.confidence === 70).price * 10 ** 9;

  if (!!fast && !!rapid && !!standard) {
    return {
      fast,
      rapid,
      standard,
    };
  } else {
    throw new Error('Gas prices missing from Blocknative payload');
  }
}

export async function getGasPrice(speed) {
  speed = speed || GAS_SPEED.fast;
  const gasPrice = (await getPrices())[speed];
  if (gasPrice > GAS_LIMIT) {
    throw new Error(`Gas price is higher than ${GAS_LIMIT} gwei. Exiting.`);
  }
  console.log('gasPrice', gasPrice.toString());
  return gasPrice;
}

module.exports = {
  getPrices,
  getGasPrice,
};
