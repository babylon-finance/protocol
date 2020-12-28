const { waffle } = require("hardhat");
const { deployContract } = waffle;
const argsUtil = require("../../utils/arguments.js");
const { ethers } = require("hardhat");

const provider = waffle.provider;

async function fixture() {
  const [owner, addr1, addr2, addr3] = await ethers.getSigners();
  const FolioController = await ethers.getContractFactory(
    "FolioController",
    owner
  );
  folioController = await FolioController.deploy(
    ...argsUtil.readArgumentsFile("FolioController")
  );

  const FundValuer = await ethers.getContractFactory("FundValuer", owner);
  const PriceOracle = await ethers.getContractFactory("PriceOracle", owner);

  fundValuer = await FundValuer.deploy(folioController.address);
  priceOracle = await PriceOracle.deploy(
    folioController.address,
    ...argsUtil.readArgumentsFile("PriceOracle")
  );

  return {
    folioController,
    fundValuer,
    priceOracle,
  };
}

module.exports = { fixture };
