const { sleep, from, eth, formatNumber } = require('lib/helpers');
const axios = require('axios');

export async function getUsers(garden) {
  let data;
  while (!data) {
    try {
      ({ data } = await axios.get(`https://api.ethplorer.io/getTopTokenHolders/${garden}?apiKey=freekey&limit=100`));
    } catch (e) {
      console.log('failed to fetch data from API');
      await sleep(1000);
    }
  }
  return data.holders;
}
