#! /bin/sh
contract=StrategyV24;
echo 'Deploying 🚀' $contract 'by' $(whoami) 'on' $(date) ;
while ! GAS_LIMIT=2500000000 npx hardhat deploy-contract --contract $contract --network mainnet; 
    do echo 'Trying to deploy again 🤖' $contract 'on' $(date);
done; 
echo $contract 'Deployed 🚀' $contract 'by' $(whoami) 'on' $(date) ;