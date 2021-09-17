const fs = require('fs-extra');

const { task } = require('hardhat/config');
const { exportContracts } = require('../scripts/export');

task('export').setAction(async (args, hre, runSuper) => {
  await runSuper(args);

  await exportContracts([
    'gardens/Garden.sol/Garden.json',
    'strategies/Strategy.sol/Strategy.json',
    'interfaces/external/weth/IWETH.sol/IWETH.json',
  ]);
  await exportContracts(['token/ERC20/IERC20.sol/IERC20.json'], '/@openzeppelin/contracts/');
  // Check if dApp in the sibling folder then copy `contracts.json` to it.
  const exists = await fs.pathExists('../dapp/');

  if (exists) {
    await fs.copy('babylon-token-list.json', '../src/babylon-token-list.json');
    await fs.copy('contracts.json', '../dapp/src/contracts.json');
    await fs.copy('contracts.json', '../dapp/lambda/shared/contracts.json');
  }
});
