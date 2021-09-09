const { exportTokenList } = require('../scripts/tokens');
const { task } = require('hardhat/config');

task('export-token-list').setAction(async (args, { ethers }, runSuper) => {
  const results = await exportTokenList(ethers);
  //console.log(results);
  console.log('done!');
});
