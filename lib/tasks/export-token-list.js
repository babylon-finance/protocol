const { buildTokenList, isImageValid } = require('../scripts/tokens');

const { task } = require('hardhat/config');
const fs = require('fs');
const glob = require('glob');
const path = require('path');

task('export-token-list').setAction(async (args, { ethers }, runSuper) => {
  const LISTS = glob.sync('lib/tokens/*.json').map((file) => {
    return require(path.resolve(file));
  });

  const TOKENS = LISTS.map((list) => {
    return list.tokens;
  }).flat();

  const toProcess = TOKENS;
  const seen = {};
  let nonEth = 0;

  await toProcess.reduce(async (promise, token) => {
    await promise;

    if (token.chainId !== 1) {
      nonEth++;
      return;
    }

    const maybeDupe = seen[token.address];

    if (maybeDupe && maybeDupe.valid === true) {
      return;
    }

    const valid = token.logoURI ? await isImageValid(token.logoURI) : false;

    if (!valid) {
      token.logoURI = '';
    }

    seen[token.address] = { valid, token };
  }, Promise.resolve());

  const deduped = Object.keys(seen).map((key) => {
    return seen[key].token;
  });

  console.log(`Filtered -> Non-ETH = ${nonEth} :: Duplicates = ${toProcess.length - nonEth - deduped.length}!`);
  console.log(`Now processing ${deduped.length} tokens...`);

  const results = await buildTokenList(ethers, deduped);
  const dataOut = JSON.stringify(results);

  fs.writeFileSync('babylon-token-list.json', dataOut);
  console.log('done!');
  console.log(`Resulting list contains ${results.length} tokens!`);
});
