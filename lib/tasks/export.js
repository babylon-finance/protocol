const fs = require('fs-extra');

const { task } = require('hardhat/config');
const { exportContracts } = require('../scripts/export');

task('export').setAction(async (args, hre, runSuper) => {
  await runSuper(args);

  await exportContracts(
    [
      'gardens/Garden.sol/Garden.json',
      'strategies/Strategy.sol/Strategy.json',
      'strategies/operations/BuyOperation.sol/BuyOperation.json',
      'strategies/operations/LendOperation.sol/LendOperation.json',
      'strategies/operations/AddLiquidityOperation.sol/AddLiquidityOperation.json',
      'strategies/operations/DepositVaultOperation.sol/DepositVaultOperation.json',
      'interfaces/external/weth/IWETH.sol/IWETH.json',
    ],
    hre,
  );
  // Check if dApp in the sibling folder then copy `contracts.json` to it.
  const exists = await fs.pathExists('../dapp/');
  if (exists) {
    await fs.copy('contracts.json', '../dapp/src/contracts.json');
    await fs.copy('contracts.json', '../dapp/lambda/contracts.json');
  }
});
