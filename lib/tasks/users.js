const chalk = require('chalk');
const axios = require('axios');
const { task } = require('hardhat/config');
const { sleep, from, eth, formatNumber } = require('lib/helpers');
const { getUsers } = require('lib/web3');

task('users').setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
  const [deployer, owner] = await ethers.getSigners();

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const gardens = await babController.getGardens();

  const usersPerGarden = {};
  let users = [];
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('Garden', garden);
    const strategies = await gardenContract.getStrategies();

    const gardenUsers = [
      ...new Set(
        (await getUsers(garden)).map((holder) => {
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
