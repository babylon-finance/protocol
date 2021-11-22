const { task } = require('hardhat/config');
const fs = require('fs');
const path = require('path');
const chalk = require('chalk');

function* walkSync(dir) {
  const files = fs.readdirSync(dir, { withFileTypes: true });
  for (const file of files) {
    if (file.isDirectory()) {
      yield* walkSync(path.join(dir, file.name));
    } else {
      yield path.join(dir, file.name);
    }
  }
}

task('diff').setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
  await hre.run('compile');
  const arts = Array.from(walkSync('./artifacts/contracts/')).filter(
    (path) => path.includes('.json') && !path.includes('.dbg.json'),
  );
  const deployments = Array.from(walkSync('./deployments/artifacts/mainnet/')).filter(
    (path) => path.includes('.json') && !path.includes('.dbg.json'),
  );

  for (const art of arts) {
    const dep = deployments.filter((dep) => dep.split('/').pop() === art.split('/').pop()).pop();
    if (!!dep && !!art) {
      const depObj = JSON.parse(fs.readFileSync(dep));
      const artObj = JSON.parse(fs.readFileSync(art));
      console.log(
        `${dep.split('/').pop()} is ${
          depObj.bytecode === artObj.bytecode ? chalk.green('up to date') : chalk.red('different')
        }`,
      );
    }
  }
});
