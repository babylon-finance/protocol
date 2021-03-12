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
  const Treasury = await ethers.getContractFactory("Treasury", owner);
  const UniswapTWAP = await ethers.getContractFactory("UniswapTWAP", owner);
  const CommunityFactory = await ethers.getContractFactory(
    "CommunityFactory",
    owner
  );
  const IdeaFactory = await ethers.getContractFactory("IdeaFactory", owner);
  const communityValuer = await CommunityValuer.deploy(babController.address);
  const reservePool = await ReservePool.deploy(babController.address);
  const treasury = await Treasury.deploy(babController.address);
  const communityFactory = await CommunityFactory.deploy();
  const ideaFactory = await IdeaFactory.deploy();

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
  babController.editTreasury(treasury.address);
  babController.editCommunityValuer(communityValuer.address);
  babController.editReservePool(reservePool.address);
  babController.editCommunityFactory(communityFactory.address);
  babController.editIdeaFactory(ideaFactory.address);

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

  await babController
    .connect(signer1)
    .createRollingCommunity(
      integrationsAddressList,
      addresses.tokens.WETH,
      "Absolute ETH Return [beta]",
      "EYFA"
    );

  await babController
    .connect(signer1)
    .createRollingCommunity(
      integrationsAddressList,
      addresses.tokens.WETH,
      "ETH Yield Farm [a]",
      "EYFB"
    );

  await babController
    .connect(signer1)
    .createRollingCommunity(
      integrationsAddressList,
      addresses.tokens.WETH,
      "ETH Yield Farm [b]",
      "EYFG"
    );

  const communities = await babController.getCommunities();

  const community = await ethers.getContractAt(
    "RollingCommunity",
    communities[0]
  );

  const community2 = await ethers.getContractAt(
    "RollingCommunity",
    communities[1]
  );

  const community3 = await ethers.getContractAt(
    "RollingCommunity",
    communities[2]
  );

  const communityAddressesList = await babController.getCommunities();
  // Initialize community integrations
  communityAddressesList.forEach(communityIter => {
    integrationsAddressList.forEach(async integration => {
      const communityI = await ethers.getContractAt(
        "RollingCommunity",
        communityIter
      );
      await communityI.connect(signer1).initializeIntegration(integration);
    });
  });

  // Initial deposit
  await community.connect(signer1).start(
    ethers.utils.parseEther("10"),
    1,
    ethers.utils.parseEther("1000"),
    2,
    ethers.utils.parseEther("0.01"),
    ONE_DAY_IN_SECONDS,
    ethers.utils.parseEther("0.13"), // 13% Ideator
    ethers.utils.parseEther("0.05"), // 5% Voters
    ethers.utils.parseEther("0.02"), // 2% community creator
    ethers.utils.parseEther("0.10"), // 10% quorum
    ONE_DAY_IN_SECONDS * 3,
    ONE_DAY_IN_SECONDS * 365,
    { value: ethers.utils.parseEther("0.1") }
  );

  return {
    babController,
    reservePool,
    treasury,
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
