const { ethers } = require("hardhat");
const addresses = require("../../utils/addresses");
const argsUtil = require("../../utils/arguments.js");

async function deployFolioFixture() {
  const [owner, signer1, signer2, signer3] = await ethers.getSigners();

  const FolioController = await ethers.getContractFactory(
    "FolioController",
    owner
  );
  const folioController = await FolioController.deploy(
    ...argsUtil.readArgumentsFile("FolioController")
  );

  await folioController.addReserveAsset(addresses.tokens.WETH);

  const FundValuer = await ethers.getContractFactory("FundValuer", owner);
  const PriceOracle = await ethers.getContractFactory("PriceOracle", owner);

  const fundValuer = await FundValuer.deploy(folioController.address);
  const priceOracle = await PriceOracle.deploy(
    folioController.address,
    addresses.compound.OpenOracle,
    []
  );
  // Sets the price oracle and fundvaluer address
  folioController.editPriceOracle(priceOracle.address);
  folioController.editFundValuer(fundValuer.address);
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

  const KyberTradeIntegration = await ethers.getContractFactory(
    "KyberTradeIntegration",
    owner
  );
  const kyberTradeIntegration = await KyberTradeIntegration.deploy(
    folioController.address,
    addresses.tokens.WETH,
    addresses.kyber.proxy
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
  folioController.addIntegration(
    await kyberTradeIntegration.getName(),
    kyberTradeIntegration.address
  );

  const integrationsList = [
    aaveIntegration,
    compoundIntegration,
    kyberTradeIntegration
  ];

  const integrationsAddressList = integrationsList.map(iter => iter.address);

  await folioController.createFund(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.WETH,
    addresses.users.hardhat1,
    addresses.users.hardhat1,
    "Fund Number One",
    "FNON",
    ethers.utils.parseEther("0.01")
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
  const fund = await ethers.getContractAt("ClosedFund", fundAddressesList[0]);
  await fund.initialManagerDeposit({ value: ethers.utils.parseEther("0.01") });
  await fund.initialize(
    0,
    0,
    0,
    0,
    1,
    ethers.utils.getAddress(addresses.zero),
    ethers.utils.getAddress(addresses.zero)
  );
  const fund2 = await ethers.getContractAt("ClosedFund", fundAddressesList[1]);
  const fund3 = await ethers.getContractAt("ClosedFund", fundAddressesList[2]);

  return {
    folioController,
    integrations: {
      aaveIntegration,
      compoundIntegration,
      kyberTradeIntegration
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
