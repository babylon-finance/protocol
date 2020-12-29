// const { waffle } = require("hardhat");
const { ethers } = require("hardhat");
// const addresses = require("../../utils/addresses");
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

  return {
    folioController,
    fundValuer,
    priceOracle,
    owner,
    signer1,
    signer2,
    signer3
  };
}

module.exports = { deployFolioFixture };
