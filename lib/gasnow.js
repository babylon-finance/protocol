const axios = require('axios');

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
  return (await getPrices()).rapid;
}

module.exports = {
  getPrices,
  getRapid,
};
