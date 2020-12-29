// const { waffle } = require("hardhat");
const { ethers } = require("hardhat");
const addresses = require("../../utils/addresses");
const argsUtil = require("../../utils/arguments.js");

// const { deployContract } = waffle;
// const provider = waffle.provider;

async function deployFolioFixture() {
  const [owner, signer1, signer2, signer3] = await ethers.getSigners();
  const FolioController = await ethers.getContractFactory(
    "FolioController",
    owner
  );
  const folioController = await FolioController.deploy(
    ...argsUtil.readArgumentsFile("FolioController")
  );

  const FundValuer = await ethers.getContractFactory("FundValuer", owner);
  const PriceOracle = await ethers.getContractFactory("PriceOracle", owner);
  // const ClosedFund = await ethers.getContractFactory("ClosedFund", owner);

  const fundValuer = await FundValuer.deploy(folioController.address);
  const priceOracle = await PriceOracle.deploy(
    folioController.address,
    ...argsUtil.readArgumentsFile("PriceOracle")
  );

  const AaveIntegration = await ethers.getContractFactory(
    "AaveIntegration",
    owner
  );
  const aaveIntegration = await AaveIntegration.deploy(
    folioController.address,
    addresses.tokens.WETH,
    50
  );

  const CompoundIntegration = await ethers.getContractFactory(
    "CompoundIntegration",
    owner
  );
  const compoundIntegration = await CompoundIntegration.deploy(
    folioController.address,
    addresses.tokens.WETH,
    50
  );

  // Adding integrations
  folioController.addIntegration(
    await aaveIntegration.getName(),
    aaveIntegration.address
  );
  folioController.addIntegration(
    await compoundIntegration.getName(),
    compoundIntegration.address
  );

  const integrationsList = [aaveIntegration, compoundIntegration];

  const integrationsAddressList = integrationsList.map(iter => iter.address);

  const fund = await folioController.createFund(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.sUSD,
    addresses.users.hardhat1,
    addresses.users.hardhat1,
    "Fund Number One",
    "FNON",
    ethers.utils.parseEther("0.01")
  );

  const fund2 = await folioController.createFund(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.sUSD,
    addresses.users.hardhat1,
    addresses.users.hardhat1,
    "Fund Number TWO",
    "FNTW",
    ethers.utils.parseEther("1")
  );

  const fund3 = await folioController.createFund(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.sUSD,
    addresses.users.hardhat1,
    addresses.users.hardhat1,
    "Fund Number Three",
    "FNTH",
    ethers.utils.parseEther("10")
  );

  // Initialize fund integrations
  [fund, fund2, fund3].forEach(fundIter => {
    integrationsList.forEach(integration => {
      // integration.initialize(fundIter);
    });
  });

  return {
    folioController,
    integrations: {
      aaveIntegration,
      compoundIntegration
    },
    funds: {
      one: fund,
      two: fund2,
      three: fund3
    },
    fundValuer,
    priceOracle,
    owner,
    signer1,
    signer2,
    signer3
  };
}

module.exports = { deployFolioFixture };
