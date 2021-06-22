const { ethers } = require('ethers');
const { task } = require('hardhat/config');
const { from, parse, eth } = require('../helpers');

function formatNumber(num) {
  // String with formatted number
  var totalStr = '';
  // Convert number to string
  var numStr = num + '';
  // Separate number on before point and after
  var parts = numStr.split('.');
  // Save length of rounded number
  var numLen = parts[0].length;
  // Start iterating numStr chars
  for (var i = 0; i < numLen; i++) {
    // Position of digit from end of string
    var y = numLen - i;

    // If y is divided without remainder on 3...
    if (i > 0 && y % 3 == 0) {
      // add aposrtoph when greater than 6 digit
      // or add point when smaller than 6 digit
      totalStr += y >= 6 ? "'" : ',';
    }

    // Append current position digit to total string
    totalStr += parts[0].charAt(i);
  }
  return `${totalStr}.00`;
}

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
  console.log('\x1b[32m', `TVL: $${formatNumber(ethers.utils.formatUnits(tvl, 'ether'))} 🤑`);
});
