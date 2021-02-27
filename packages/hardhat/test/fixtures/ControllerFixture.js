const { ethers } = require("hardhat");
const { ONE_DAY_IN_SECONDS } = require("../../utils/constants.js");
const addresses = require("../../utils/addresses");
const argsUtil = require("../../utils/arguments.js");

async function deployFolioFixture() {
  const [owner, signer1, signer2, signer3] = await ethers.getSigners();

  const ClosedFund = await ethers.getContractFactory("ClosedFund", owner);
  const FundIdeas = await ethers.getContractFactory("FundIdeas", owner);

  const BabController = await ethers.getContractFactory("BabController", owner);

  const babController = await BabController.deploy(
    ...argsUtil.readArgumentsFile("BabController")
  );

  await babController.addReserveAsset(addresses.tokens.WETH);
  await babController.addAssetsWhitelist(Object.values(addresses.tokens));
  await babController.addKeepers(Object.values(addresses.users));

  const FundValuer = await ethers.getContractFactory("FundValuer", owner);
  const PriceOracle = await ethers.getContractFactory("PriceOracle", owner);

  const fundValuer = await FundValuer.deploy(babController.address);
  const priceOracle = await PriceOracle.deploy(
    babController.address,
    addresses.compound.OpenOracle,
    []
  );
  // Sets the price oracle and fundvaluer address
  babController.editPriceOracle(priceOracle.address);
  babController.editFundValuer(fundValuer.address);

  const AaveIntegration = await ethers.getContractFactory(
    "AaveIntegration",
    owner
  );
  const aaveIntegration = await AaveIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    50
  );

  const CompoundIntegration = await ethers.getContractFactory(
    "CompoundIntegration",
    owner
  );
  const compoundIntegration = await CompoundIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    50
  );

  const KyberTradeIntegration = await ethers.getContractFactory(
    "KyberTradeIntegration",
    owner
  );
  const kyberTradeIntegration = await KyberTradeIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.kyber.proxy
  );

  const OneInchIntegration = await ethers.getContractFactory(
    "OneInchTradeIntegration",
    owner
  );
  const oneInchTradeIntegration = await OneInchIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.oneinch.exchange
  );

  const BalancerIntegration = await ethers.getContractFactory(
    "BalancerIntegration",
    owner
  );
  const balancerIntegration = await BalancerIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.balancer.factory
  );

  const UniswapPoolIntegration = await ethers.getContractFactory(
    "UniswapPoolIntegration",
    owner
  );
  const uniswapPoolIntegration = await UniswapPoolIntegration.deploy(
    babController.address,
    addresses.tokens.WETH,
    addresses.uniswap.router
  );

  const YearnVaultIntegration = await ethers.getContractFactory(
    "YearnVaultIntegration",
    owner
  );
  const yearnVaultIntegration = await YearnVaultIntegration.deploy(
    babController.address,
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
    babController.addIntegration(
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
    babController.address,
    addresses.users.hardhat1,
    "Absolute ETH Return [beta]",
    "EYFA",
    ethers.utils.parseEther("0.01")
  );

  const fund2 = await ClosedFund.deploy(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.WETH,
    babController.address,
    addresses.users.hardhat1,
    "ETH Yield Farm [a]",
    "EYFB",
    ethers.utils.parseEther("1")
  );

  const fund3 = await ClosedFund.deploy(
    integrationsAddressList,
    addresses.tokens.WETH,
    addresses.tokens.WETH,
    babController.address,
    addresses.users.hardhat1,
    "ETH Yield Farm [b]",
    "EYFG",
    ethers.utils.parseEther("10")
  );

  await babController.createFund(integrationsAddressList, fund.address);
  await babController.createFund(integrationsAddressList, fund2.address);
  await babController.createFund(integrationsAddressList, fund3.address);

  const fundAddressesList = await babController.getFunds();
  // Initialize fund integrations
  fundAddressesList.forEach(fundIter => {
    integrationsAddressList.forEach(async integration => {
      await babController.initializeIntegration(integration, fundIter);
    });
  });

  // Investment ideas first fund
  const fundIdeas1 = await FundIdeas.deploy(
    fund.address,
    babController.address,
    ONE_DAY_IN_SECONDS,
    ethers.utils.parseEther("0.15"), // 15%
    ethers.utils.parseEther("0.05"), // 5%
    ethers.utils.parseEther("0.10") // 10%
  );

  // Initial deposit
  await fund.initialize(
    ethers.utils.parseEther("10"),
    0,
    1,
    ONE_DAY_IN_SECONDS * 90,
    ONE_DAY_IN_SECONDS * 3,
    fundIdeas1.address,
    { value: ethers.utils.parseEther("0.1") }
  );

  return {
    babController,
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
    contractsToPublish: [
      { name: "BabController", contract: babController },
      { name: "KyberTradeIntegration", contract: kyberTradeIntegration },
      { name: "YearnVaultIntegration", contract: yearnVaultIntegration },
      { name: "UniswapPoolIntegration", contract: uniswapPoolIntegration }
    ]
  };
}

module.exports = { deployFolioFixture };
