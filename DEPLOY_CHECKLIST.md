# DEPLOY CHECKLIST

- [ ] Add `DEPLOYER_PRIVATE_KEY` key to the `.env` file with a private key on correct network and with a sufficient balance.
- [ ] Add `KEEPER` key to the `.env` file with an address of a keeper to run tasks.
- [ ] Run `yarn deploy:network` where network is `mainnet | rinkeby`.
- [ ] Transfer ownershipt to a multisig from deployer.
  - [ ] ProxyAdmin for BabController
  - [ ] Ownership of BabController

## Notes

- If deploy process fails it can be just restarted with the same command and it would not redeploy already deployed contracts.
- It is possible to deploy to a certain point using `--tags` option, e.g., `yarn deploy:hardhat --tags 'Token'`
- All the deployed contracts information is save at `deployments/network` folder.
