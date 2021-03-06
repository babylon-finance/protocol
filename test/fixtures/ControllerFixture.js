const { ethers } = require("hardhat");
const { ONE_DAY_IN_SECONDS } = require("../../utils/constants.js");
const {
  TWAP_ORACLE_WINDOW,
  TWAP_ORACLE_GRANULARITY
} = require("../../utils/system.js");
const addresses = require("../../utils/addresses");
const argsUtil = require("../../utils/arguments.js");

async function deployFolioFixture() {
  const [owner, signer1, signer2, signer3] = await ethers.getSigners();

  const RollingCommunity = await ethers.getContractFactory(
    "RollingCommunity",
    owner
  );
  const CommunityIdeas = await ethers.getContractFactory(
    "CommunityIdeas",
    owner
  );

  const BabController = await ethers.getContractFactory("BabController", owner);
  const babController = await BabController.deploy(
    ...argsUtil.readArgumentsFile("BabController")
  );

  await babController.addReserveAsset(addresses.tokens.WETH);
  await babController.addKeepers(Object.values(addresses.users));

  const CommunityValuer = await ethers.getContractFactory(
    "CommunityValuer",
    owner
  );
  const PriceOracle = await ethers.getContractFactory("PriceOracle", owner);
  const ReservePool = await ethers.getContractFactory("ReservePool", owner);
  const UniswapTWAP = await ethers.getContractFactory("UniswapTWAP", owner);
  const communityValuer = await CommunityValuer.deploy(babController.address);
  const reservePool = await ReservePool.deploy(babController.address);

  const uniswapTWAPAdapter = await UniswapTWAP.deploy(
    babController.address,
    addresses.uniswap.factory,
    TWAP_ORACLE_WINDOW,
    TWAP_ORACLE_GRANULARITY
  );
  const priceOracle = await PriceOracle.deploy(
    babController.address,
    addresses.compound.OpenOracle,
    [uniswapTWAPAdapter.address]
  );
  // Sets the price oracle and communityvaluer address
  babController.editPriceOracle(priceOracle.address);
  babController.editCommunityValuer(communityValuer.address);
  babController.editReservePool(reservePool.address);

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

  // Creates a new Community instance
  const community = await RollingCommunity.deploy(
    integrationsAddressList,
    addresses.tokens.WETH,
    babController.address,
    addresses.users.hardhat1,
    "Absolute ETH Return [beta]",
    "EYFA",
    ethers.utils.parseEther("0.01")
  );

  const community2 = await RollingCommunity.deploy(
    integrationsAddressList,
    addresses.tokens.WETH,
    babController.address,
    addresses.users.hardhat1,
    "ETH Yield Farm [a]",
    "EYFB",
    ethers.utils.parseEther("1")
  );

  const community3 = await RollingCommunity.deploy(
    integrationsAddressList,
    addresses.tokens.WETH,
    babController.address,
    addresses.users.hardhat1,
    "ETH Yield Farm [b]",
    "EYFG",
    ethers.utils.parseEther("10")
  );

  await babController.createCommunity(
    integrationsAddressList,
    community.address
  );
  await babController.createCommunity(
    integrationsAddressList,
    community2.address
  );
  await babController.createCommunity(
    integrationsAddressList,
    community3.address
  );

  const communityAddressesList = await babController.getCommunities();
  // Initialize community integrations
  communityAddressesList.forEach(communityIter => {
    integrationsAddressList.forEach(async integration => {
      const communityI = await ethers.getContractAt(
        "RollingCommunity",
        communityIter
      );
      await communityI.initializeIntegration(integration);
    });
  });

  // Investment ideas first community
  const communityIdeas1 = await CommunityIdeas.deploy(
    community.address,
    babController.address,
    ONE_DAY_IN_SECONDS,
    ethers.utils.parseEther("0.15"), // 15%
    ethers.utils.parseEther("0.05"), // 5%
    ethers.utils.parseEther("0.10"), // 10%
    ONE_DAY_IN_SECONDS * 3,
    ONE_DAY_IN_SECONDS * 365
  );

  // Initial deposit
  await community.initialize(
    ethers.utils.parseEther("10"),
    1,
    communityIdeas1.address,
    ethers.utils.parseEther("1000"),
    2,
    { value: ethers.utils.parseEther("0.1") }
  );

  return {
    babController,
    reservePool,
    integrations: {
      aaveIntegration,
      compoundIntegration,
      kyberTradeIntegration,
      oneInchTradeIntegration,
      balancerIntegration,
      uniswapPoolIntegration,
      yearnVaultIntegration
    },
    comunities: {
      one: community,
      two: community2,
      three: community3
    },
    communityValuer,
    priceOracle,
    owner,
    signer1,
    signer2,
    signer3,
    contractsToPublish: [
      { name: "BabController", contract: babController },
      { name: "KyberTradeIntegration", contract: kyberTradeIntegration },
      { name: "BalancerIntegration", contract: balancerIntegration },
      { name: "YearnVaultIntegration", contract: yearnVaultIntegration },
      { name: "UniswapPoolIntegration", contract: uniswapPoolIntegration }
    ]
  };
}

module.exports = { deployFolioFixture };
