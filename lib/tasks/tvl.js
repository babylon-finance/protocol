const { ethers } = require('ethers');
const chalk = require('chalk');
const { task } = require('hardhat/config');
const { from, parse, eth, formatNumber } = require('../helpers');

task('tvl').setAction(async (args, { getContract, ethers, getRapid }, runSuper) => {
  const [deployer] = await ethers.getSigners();

  const DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  const babController = await getContract('BabController', 'BabControllerProxy', deployer);
  const gardens = await babController.getGardens();

  const valuer = await getContract('GardenValuer', undefined, deployer);
  let tvl = from(0);
  for (const garden of gardens) {
    const gardenContract = await ethers.getContractAt('IERC20', garden);
    const gardenNAV = (await valuer.calculateGardenValuation(garden, DAI))
      .mul(await gardenContract.totalSupply())
      .div(eth());
    tvl = tvl.add(gardenNAV);
  }
  console.log(`TVL: $${chalk.green(formatNumber(ethers.utils.formatUnits(tvl, 'ether')))} 🤑`);
});
