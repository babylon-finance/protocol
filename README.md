# Babylon Finance

**Community-led Asset Management. Powered by DeFi.**

[![CI](https://github.com/babylon-finance/protocol/actions/workflows/ci.yml/badge.svg)](https://github.com/babylon-finance/protocol/actions)

<!-- [![Coverage Status](https://codecov.io/gh/babylon-finance/protocol/graph/badge.svg)](https://codecov.io/gh/babylon-finance/protocol) -->

## Quick Start

Git clone

```bash
git clone https://github.com/babylon-finance/protocol.git
```

Install dependencies

```bash
yarn
```

Compile contracts

```bash
yarn compile
```

## Development

⛽️ Gas Report

```bash
yarn gas-report
```

🛡 Coverae

```bash
yarn coverage
```

🤖 Prettier

```bash
yarn prettier
```

💪 Solhint

```bash
yarn lint:contracts
```

📏 Contract Size

```bash
yarn estimate-size
```

🧪 Test

```bash
yarn test
```

Or watch test 👁

```bash
yarn test:watch
```

## Deploy

To deploy SCs you need to have `.env` file configured for the selected network, e.g., `mainnet`.
The file should have the following entries.

```bash
  ALCHEMY_KEY=XXXXXXXX
  DEPLOYER_PRIVATE_KEY=XXXXXXXX
  OWNER_PRIVATE_KEY=XXXXXXXX
  BLOCKNATIVE_API_KEY=XXXXXXXX
  ETHERSCAN_KEY=XXXXXXXX
  DEFENDER_API_KEY=XXXXXXXX
  DEFENDER_API_SECRET=XXXXXXXX
```

For non-upgradeable contracts use named scripts from the `deployments/migrations/` folder, e.g., `040-univ2-trade.js`
would deploy `UniswapV2TradeIntegration`. To invoke the script use the following command.

```bash
  GAS_LIMIT=1000000000000 npx hardhat deploy --network mainnet --tags UniV2Trade
```

`GAS_LIMIT` is in wei. `tags` value can be found inside a deployment script.

To deploy a new implementation for an upgradeable contract use `deploy-contract.js` script, e.g., to deploy a new
implementation for the Strategy contract use the following command:

```bash
  GAS_LIMIT=100000000000 npx hardhat deploy-contract --contract StrategyV16 --network mainnet
```

`contract` is the name of the new implementation.

## Upgrade

To upgrade Babylon Protocol use `upgrade-multisig.js` script. It will create a batch tx for Gnosis Multisig to upgrade
all the proxies in the protocol. The command bellow upgrades BabController, RewardsDistributor, Strategy, and Garden to
the appropriate implementations. The implementations have to be deployed beforehand using `deploy-contrat` script.

```bash
  npx hardhat upgrade-multisig --network mainnet --controller BabControllerV11 --distributor RewardsDistributorV11 --strategy StrategyV14 --garden GardenV15
```

All the arguments are optional meaning only required proxies should be upgraded.

This script will create a proposal at [Defender Admin](https://defender.openzeppelin.com/#/admin). It has to be signed
and executed to upgrade the protocol.
