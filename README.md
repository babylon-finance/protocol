# Babylon Finance

**Community-led Asset Management. Powered by DeFi.**

![CI](https://github.com/babylon-finance/protocol/actions/workflows/ci.yml/badge.svg)
Will CI work?

## Quick Start

Git clone

```bash
git clone https://github.com/babylon-finance/protocol.git
```

Install dependencies

```bash
yarn
```

Fix Uniswap Solidity version issue by replacing:

```diff
-pragma solidity =0.6.6;
+pragma solidity 0.7.4;
```

at `@uniswap/v2-periphery/contracts/libraries/SafeMath.sol` file.

Run

```bash
yarn compile
```

to compile Solidity contracts.

Run

```bash
yarn generate
```

to generate mnemonic.txt file.

## Test

Run

```bash
yarn test
```

## Deploy
