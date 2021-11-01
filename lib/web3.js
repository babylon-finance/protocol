const { sleep, from, eth, formatNumber } = require('lib/helpers');
const axios = require('axios');

const ETHPLORER = process.env.ETHPLORER || '';

export async function getUsers(garden) {
  let data;
  while (!data) {
    try {
      ({ data } = await axios.get(`https://api.ethplorer.io/getTopTokenHolders/${garden}?apiKey=${ETHPLORER}&limit=1000`));
    } catch (e) {
      console.log('failed to fetch data from API');
      await sleep(1000);
    }
  }
  return data.holders;
}
