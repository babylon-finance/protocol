const { buildTokenList } = require('../scripts/tokens');
const { task } = require('hardhat/config');

task('export-token-list').setAction(async (args, { ethers }, runSuper) => {
  const results = await buildTokenList(ethers);
  console.log(results);
  // Write this to file when we want to use it
  console.log('done!');
  console.log(`Resulting list contains ${results.length} tokens!`);
});
