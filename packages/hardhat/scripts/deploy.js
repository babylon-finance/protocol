require("@nomiclabs/hardhat-ethers");

const fs = require("fs");
const chalk = require("chalk");

const _wethAddress = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"; // WETH ERC20 Address
const _defaultManagerAddress = "0xfc9da5D8b594B8fD7021C6B0eE5a00Ec2C4c132d"; // ScaffoldBurner address for local testing

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

const isSolidity = (fileName) =>
  fileName.indexOf(".sol") >= 0 && fileName.indexOf(".swp.") < 0;

function readArgumentsFile(contractName) {
  let args = [];
  try {
    const argsFile = `./args/${contractName}.args`;
    if (fs.existsSync(argsFile)) {
      args = JSON.parse(fs.readFileSync(argsFile));
    }
  } catch (e) {
    console.log(e);
  }

  return args;
}

async function autoDeploy() {
  const contractList = fs.readdirSync(config.paths.sources);
  return contractList
    .filter((fileName) => isSolidity(fileName))
    .reduce((lastDeployment, fileName) => {
      const contractName = fileName.replace(".sol", "");
      const args = readArgumentsFile(contractName);

      // Wait for last deployment to complete before starting the next
      return lastDeployment.then((resultArrSoFar) =>
        deploy(contractName, args).then((result) => [...resultArrSoFar, result])
      );
    }, Promise.resolve([]));
}

async function main() {
  const folioController = await deploy(
    "FolioController",
    readArgumentsFile("FolioController")
  );
  const fundValuer = await deploy("FundValuer", [folioController.address]);

  const priceOracle = await deploy("PriceOracle", [
    folioController.address,
    ...readArgumentsFile("PriceOracle"),
  ]);

  await folioController.editFundValuer(fundValuer.address);
  await folioController.editPriceOracle(priceOracle.address);

  const aaveI = await deploy("AaveIntegration", [
    folioController.address,
    ...readArgumentsFile("AaveIntegration"),
  ]);

  const compoundI = await deploy("CompoundIntegration", [
    folioController.address,
    ...readArgumentsFile("CompoundIntegration"),
  ]);

  await folioController.addIntegration("AaveIntegration", aaveI.address);
  await folioController.addIntegration("CompundIntegration", compoundI.address);
  await folioController.createFund(
    [aaveI.address],
    _wethAddress,
    _wethAddress,
    _defaultManagerAddress,
    _defaultManagerAddress,
    "Fund Number One",
    "FNON",
    ethers.utils.parseEther("1")
  );
  await folioController.createFund(
    [compoundI.address],
    _wethAddress,
    _wethAddress,
    _defaultManagerAddress,
    _defaultManagerAddress,
    "Fund Number TWO",
    "FNTW",
    ethers.utils.parseEther("1")
  );
  await folioController.createFund(
    [aaveI.address, compoundI.address],
    _wethAddress,
    _wethAddress,
    _defaultManagerAddress,
    _defaultManagerAddress,
    "Fund Number Three",
    "FNTH",
    ethers.utils.parseEther("10")
  );

  console.log("📡 Deploy complete! \n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
