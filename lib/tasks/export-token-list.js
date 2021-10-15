const { buildTokenList, fetchNewLists } = require('../scripts/tokens');

const { task } = require('hardhat/config');
const fs = require('fs');
const cliProgress = require('cli-progress');

// create new progress bar
const progressBar = new cliProgress.SingleBar({
  barCompleteChar: '\u2588',
  barIncompleteChar: '\u2591',
  hideCursor: true,
});

task('export-token-list').setAction(async (args, { ethers }, runSuper) => {
  const ALL_TOKENS = await fetchNewLists();

  const seen = {};
  let nonEth = 0;

  console.log('Deduping tokens...');
  progressBar.start(ALL_TOKENS.length, 0, {});

  await ALL_TOKENS.reduce(async (promise, token) => {
    await promise;

    if (token.chainId !== 1) {
      nonEth++;
      return;
    }

    const maybeDupe = seen[token.address];

    if (maybeDupe !== undefined && maybeDupe.best === true) {
      return;
    }

    let best = false;

    if (token.logoURI && token.logoURI.startsWith('https://assets.coingecko.com')) {
      best = true;
    }

    seen[token.address] = { best, token };
    progressBar.increment();
  }, Promise.resolve());

  progressBar.stop();
  console.log('Deduping complete!');

  const deduped = Object.keys(seen).map((key) => {
    return seen[key].token;
  });

  console.log(`Filtered -> Non-ETH = ${nonEth} :: Duplicates = ${ALL_TOKENS.length - nonEth - deduped.length}!`);
  console.log(`Now processing ${deduped.length} tokens...`);

  const results = await buildTokenList(ethers, deduped, progressBar);
  const dataOut = JSON.stringify(results);

  fs.writeFileSync('babylon-token-list.json', dataOut);
  console.log('done!');
  console.log(`Resulting list contains ${results.length} tokens!`);
});
