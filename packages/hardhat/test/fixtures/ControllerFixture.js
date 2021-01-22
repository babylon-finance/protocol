const { ethers } = require("hardhat");
const addresses = require("../../utils/addresses");
const argsUtil = require("../../utils/arguments.js");

async function deployFolioFixture() {
  const [owner, signer1, signer2, signer3] = await ethers.getSigners();

  const ClosedFund = await ethers.getContractFactory("ClosedFund", owner);

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

  const OneInchIntegration = await ethers.getContractFactory(
    "OneInchTradeIntegration",
    owner
  );
  const oneInchTradeIntegration = await OneInchIntegration.deploy(
    folioController.address,
    addresses.tokens.WETH,
    addresses.oneinch.exchange
  );

  const BalancerIntegration = await ethers.getContractFactory(
    "BalancerIntegration",
    owner
  );
  const balancerIntegration = await BalancerIntegration.deploy(
    folioController.address,
    addresses.tokens.WETH,
    addresses.balancer.factory
  );

  const UniswapPoolIntegration = await ethers.getContractFactory(
    "UniswapPoolIntegration",
    owner
  );
  const uniswapPoolIntegration = await UniswapPoolIntegration.deploy(
    folioController.address,
    addresses.tokens.WETH,
    addresses.uniswap.router
  );

  const YearnVaultIntegration = await ethers.getContractFactory(
    "YearnVaultIntegration",
    owner
  );
  const yearnVaultIntegration = await YearnVaultIntegration.deploy(
    folioController.address,
    addresses.tokens.WETH,
    addresses.yearn.vaultRegistry
  );

  const integrationsList = [
    aaveIntegration,
    compoundIntegration,
    kyberTradeIntegration,
    oneInchTradeIntegration,
    balancerIntegration,
    uniswapPoolIntegration,
    yearnVaultIntegration
  ];

  // Adding integrations
  integrationsList.forEach(async integration => {
    folioController.addIntegration(
      await integration.getName(),
      integration.address
    );
  });

  const integrationsAddressList = integrationsList.map(iter => iter.address);

  // Creates a new Fund instance
  const fund = await ClosedFund.deploy(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.WETH,
    folioController.address,
    addresses.users.hardhat1,
    addresses.users.hardhat1,
    "Fund Number One",
    "FNON",
    ethers.utils.parseEther("0.01")
  );

  const fund2 = await ClosedFund.deploy(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.WETH,
    folioController.address,
    addresses.users.hardhat1,
    addresses.users.hardhat1,
    "Fund Number Two",
    "FNTW",
    ethers.utils.parseEther("1")
  );

  const fund3 = await ClosedFund.deploy(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.WETH,
    folioController.address,
    addresses.users.hardhat1,
    addresses.users.hardhat1,
    "Fund Number Three",
    "FNTH",
    ethers.utils.parseEther("10")
  );

  await folioController.createFund(integrationsAddressList, fund.address);
  await folioController.createFund(integrationsAddressList, fund2.address);
  await folioController.createFund(integrationsAddressList, fund3.address);

  const fundAddressesList = await folioController.getFunds();
  // Initialize fund integrations
  fundAddressesList.forEach(fundIter => {
    integrationsAddressList.forEach(async integration => {
      await folioController.initializeIntegration(integration, fundIter);
    });
  });

  // Initial deposit
  await fund.initialize(
    ethers.utils.parseEther("0.1"),
    0,
    0,
    0,
    0,
    0,
    1,
    ethers.utils.getAddress(addresses.zero),
    ethers.utils.getAddress(addresses.zero),
    { value: ethers.utils.parseEther("0.2") }
  );

  return {
    folioController,
    integrations: {
      aaveIntegration,
      compoundIntegration,
      kyberTradeIntegration,
      oneInchTradeIntegration,
      balancerIntegration,
      uniswapPoolIntegration,
      yearnVaultIntegration
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
    signer3,
    contractsToPublish: [{ name: "FolioController", contract: folioController }]
  };
}

module.exports = { deployFolioFixture };
