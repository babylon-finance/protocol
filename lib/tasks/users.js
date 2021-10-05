const chalk = require('chalk');
const axios = require('axios');
const { task } = require('hardhat/config');
const { sleep, from, eth, formatNumber } = require('../helpers');

task('users').setAction(async (args, { getContract, ethers, getRapid }, runSuper) => {
  const [deployer, owner] = await ethers.getSigners();

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const gardens = await babController.getGardens();

  const usersPerGarden = {};
  let users = [];
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('Garden', garden);
    const strategies = await gardenContract.getStrategies();

    let data;
    while (!data) {
      try {
        ({ data } = await axios.get(`https://api.ethplorer.io/getTopTokenHolders/${garden}?apiKey=freekey&limit=100`));
      } catch (e) {
        console.log('failed to fetch data from API');
        await sleep(1000);
      }
    }

    const gardenUsers = [
      ...new Set(
        data.holders.map((holder) => {
          return holder.address;
        }),
      ),
    ];
    users = [...users, ...gardenUsers];
    usersPerGarden[garden] = gardenUsers;
    console.log(`${await gardenContract.name()} ${garden}`);
    console.log('users', gardenUsers);
  }
  console.log('Total Users', users.length);
  console.log('Total Unique Users', new Set(users).size);
});
