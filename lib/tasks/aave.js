const { ethers } = require('ethers');
const { task } = require('hardhat/config');
const chalk = require('chalk');
const { from, parse, eth, formatNumber, formatUnit } = require('../helpers');

task('aave')
  .addVariadicPositionalParam('accounts', 'AAVE accounts to fetch data', [])
  .setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
    const { accounts } = args;
    const [deployer, owner] = await ethers.getSigners();
    const pool = new ethers.Contract(
      '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9',
      [
        'function getUserAccountData(address user) external view returns ( uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor)',
      ],
      deployer,
    );

    for (const acc of accounts) {
      console.log(`Stats for account ${acc}`);
      const {
        totalCollateralETH,
        totalDebtETH,
        availableBorrowsETH,
        currentLiquidationThreshold,
        ltv,
        healthFactor,
      } = await pool.getUserAccountData(acc);

      console.log(`  totalCollateralETH: ${formatUnit(totalCollateralETH)} ETH`);
      console.log(`  totalDebtETH: ${formatUnit(totalDebtETH)} ETH`);
      console.log(`  availableBorrowsETH: ${formatUnit(availableBorrowsETH)} ETH`);
      console.log(`  currentLiquidationThreshold: ${currentLiquidationThreshold}`);
      console.log(`  ltv: ${ltv.div(100)}%`);
      console.log(`  healthFactor: ${formatUnit(healthFactor)}`);
      console.log('');
    }
  });
