const axios = require('axios');

const GAS_LIMIT = process.env.GAS_LIMIT || 120000000000;
const GAS_NOW_URL = 'https://www.gasnow.org/api/v3/gas/price';
/**
 * Returns gas prices in wei
 */
async function getPrices() {
  const { data } = await axios.get(GAS_NOW_URL);
  if (data.code !== 200) throw new Error('Failed to fetch gas prices from gasnow');
  return data.data;
}

async function getRapid() {
  const gasPrice = (await getPrices()).rapid;
  if (gasPrice > GAS_LIMIT) {
    throw new Error(`Gas price is higher than ${GAS_LIMIT} gwei. Exiting.`);
  }
  return gasPrice;
}

module.exports = {
  getPrices,
  getRapid,
};
