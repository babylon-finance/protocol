const { buildTokenList } = require('../scripts/tokens');
const { task } = require('hardhat/config');

task('export-token-list').setAction(async (args, { ethers }, runSuper) => {
  const results = await buildTokenList(ethers);
  console.log(results);
  console.log('done!');
});
