const { ethers } = require("hardhat");
const fs = require("fs");
const chalk = require("chalk");
const argsUtil = require("../utils/arguments.js");
const addresses = require("../utils/addresses");

async function deploy(name, _args) {
  const args = _args || [];

  console.log(`📄 ${name}`);
  const contractArtifacts = await ethers.getContractFactory(name);
  const contract = await contractArtifacts.deploy(...args);
  console.log(
    chalk.cyan(name),
    "deployed to:",
    chalk.magenta(contract.address)
  );
  fs.writeFileSync(`artifacts/${name}.address`, contract.address);
  console.log("\n");
  return contract;
}

const isSolidity = fileName =>
  fileName.indexOf(".sol") >= 0 && fileName.indexOf(".swp.") < 0;

async function autoDeploy() {
  const contractList = fs.readdirSync(config.paths.sources);
  return contractList
    .filter(fileName => isSolidity(fileName))
    .reduce((lastDeployment, fileName) => {
      const contractName = fileName.replace(".sol", "");
      const args = arguments.readArgumentsFile(contractName);

      // Wait for last deployment to complete before starting the next
      return lastDeployment.then(resultArrSoFar =>
        deploy(contractName, args).then(result => [...resultArrSoFar, result])
      );
    }, Promise.resolve([]));
}

async function main() {
  const folioController = await deploy(
    "FolioController",
    argsUtil.readArgumentsFile("FolioController")
  );

  const fundValuer = await deploy("FundValuer", [folioController.address]);

  const priceOracle = await deploy("PriceOracle", [
    folioController.address,
    addresses.compound.OpenOracle,
    []
  ]);

  await folioController.editFundValuer(fundValuer.address);
  await folioController.editPriceOracle(priceOracle.address);

  const aaveI = await deploy("AaveIntegration", [
    folioController.address,
    addresses.tokens.WETH,
    50
  ]);

  const compoundI = await deploy("CompoundIntegration", [
    folioController.address,
    addresses.tokens.WETH,
    50
  ]);

  const oneInchTradeI = await deploy("OneInchTradeIntegration", [
    folioController.address,
    addresses.tokens.WETH,
    addresses.oneinch.exchange
  ]);

  const kyberTradeI = await deploy("KyberTradeIntegration", [
    folioController.address,
    addresses.tokens.WETH,
    addresses.kyber.proxy
  ]);

  const integrationsList = [aaveI, compoundI, kyberTradeI, oneInchTradeI];

  const integrationsAddressList = integrationsList.map(iter => iter.address);

  await folioController.addIntegration("AaveIntegration", aaveI.address);
  await folioController.addIntegration("CompundIntegration", compoundI.address);
  await folioController.addIntegration(
    "KyberTradeIntegration",
    kyberTradeI.address
  );
  await folioController.addIntegration(
    "OnceInchTradeIntegration",
    oneInchTradeI.address
  );

  await folioController.createFund(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.WETH,
    addresses.users.hardhat1,
    addresses.users.hardhat1,
    "Fund Number One",
    "FNON",
    ethers.utils.parseEther("1")
  );

  await folioController.createFund(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.WETH,
    addresses.users.hardhat1,
    addresses.users.hardhat1,
    "Fund Number TWO",
    "FNTW",
    ethers.utils.parseEther("1")
  );

  await folioController.createFund(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.WETH,
    addresses.users.hardhat1,
    addresses.users.hardhat1,
    "Fund Number Three",
    "FNTH",
    ethers.utils.parseEther("10")
  );

  const fundAddressesList = await folioController.getFunds();

  // Initialize fund integrations
  fundAddressesList.forEach(fundIter => {
    integrationsAddressList.forEach(async integration => {
      await folioController.initializeIntegration(integration, fundIter);
    });
  });

  // Initialize each fund
  const fund1 = await ethers.getContractAt("ClosedFund", fundAddressesList[0]);
  const managerSigner = await ethers.getSigner(addresses.users.hardhat1);

  // NOTE: below does not deploy successfully

  //await fund1
  //  .connect(managerSigner)
  //  .initialManagerDeposit({ value: ethers.utils.parseEther("0.01") });

  //await fund1.initialize(
  //  0,
  //  0,
  //  0,
  //  0,
  //  1,
  //  ethers.utils.getAddress(addresses.zero),
  //  ethers.utils.getAddress(addresses.zero)
  //);

  //const fund2 = await ethers.getContractAt("ClosedFund", fundAddressesList[1]);
  //await fund2.initialManagerDeposit({ value: ethers.utils.parseEther("0.01") });
  //await fund2.initialize(
  //  0,
  //  0,
  //  0,
  //  0,
  //  1,
  //  ethers.utils.getAddress(addresses.zero),
  //  ethers.utils.getAddress(addresses.zero)
  //);

  //const fund3 = await ethers.getContractAt("ClosedFund", fundAddressesList[2]);
  //await fund3.initialManagerDeposit({ value: ethers.utils.parseEther("0.01") });
  //await fund3.initialize(
  //  0,
  //  0,
  //  0,
  //  0,
  //  1,
  //  ethers.utils.getAddress(addresses.zero),
  //  ethers.utils.getAddress(addresses.zero)
  //);

  console.log("📡 Deploy complete! \n");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
