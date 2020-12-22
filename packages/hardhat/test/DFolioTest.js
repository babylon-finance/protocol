const { expect } = require("chai");

const ADD_FUND_PROPS = ["new fund", "NewFundToken", "NFT"];
const ADD_FUND_PROPS_2 = ["new fund 2", "NewFundToken2", "NFT2"];

describe("DFolio Deploy", function() {
  it("Should deploy DFolio", async function() {
    const [owner] = await ethers.getSigners();
    const DFolio = await ethers.getContractFactory("DFolio", owner);
    await DFolio.deploy();
  });
});

describe("DFolio", async function() {
  const [owner, addr1, addr2] = await ethers.getSigners();
  const DFolio = await ethers.getContractFactory("DFolio", owner);

  let dfolio;

  beforeEach(async () => {
    dfolio = await DFolio.deploy();
  });

  describe("Interacting with Funds", function() {
    it("should start empty", async function() {
      expect(await dfolio.totalFunds()).to.equal(0);
      expect(await dfolio.currentFundIndex()).to.equal(1);
    });

    it("should set the protocol manager address", async function() {
      expect(await dfolio.protocolManager()).to.equal(await owner.getAddress());
    });

    it("can add a hedge fund and retrieve it", async function() {
      expect(await dfolio.addFund(...ADD_FUND_PROPS));
      expect(await dfolio.totalFunds()).to.equal(1);
      expect(await dfolio.currentFundIndex()).to.equal(2);
      const { name, active, index } = await dfolio.getFund(
        ADD_FUND_PROPS[0]
      );
      expect(name).to.equal(ADD_FUND_PROPS[0]);
      expect(active).to.equal(false);
      expect(index).to.equal(1);
    });

    it("can add a hedge funds and retrieve all", async function() {
      expect(await dfolio.addFund(...ADD_FUND_PROPS));
      expect(await dfolio.addFund(...ADD_FUND_PROPS_2));
      expect(await dfolio.totalFunds()).to.equal(2);
      expect(await dfolio.currentFundIndex()).to.equal(3);
      const funds = await dfolio.getAllFunds();
      expect(funds.length).to.equal(2);
    });

    it("only protocol manager can add hedge funds", async function() {
      await expect(dfolio.connect(addr2).addFund(...ADD_FUND_PROPS)).to.be
        .reverted;
    });

    it("can not add the same hedge fund twice", async function() {
      expect(await dfolio.addFund(...ADD_FUND_PROPS));
      await expect(dfolio.addFund(...ADD_FUND_PROPS)).to.be.reverted;
    });

    it("can disable a hedge fund and retrieve it", async function() {
      expect(await dfolio.addFund(...ADD_FUND_PROPS));
      expect(await dfolio.totalFunds()).to.equal(1);
      expect(await dfolio.currentFundIndex()).to.equal(2);
      expect(await dfolio.disableFund(ADD_FUND_PROPS[0]));
      const { name, active, index } = await dfolio.getFund(
        ADD_FUND_PROPS[0]
      );
      expect(name).to.equal(ADD_FUND_PROPS[0]);
      expect(active).to.equal(false);
      expect(index).to.equal(1);
      expect(await dfolio.totalFunds()).to.equal(0);
    });

    it("can not disable a hedge fund that does not exist", async function() {
      await expect(dfolio.disableFund("my imaginary fund")).to.be.reverted;
    });

    it("can reenable a hedge fund after disabling it", async function() {
      expect(await dfolio.addFund(...ADD_FUND_PROPS));
      expect(await dfolio.totalFunds()).to.equal(1);
      expect(await dfolio.currentFundIndex()).to.equal(2);
      expect(await dfolio.disableFund(ADD_FUND_PROPS[0]));
      expect(await dfolio.totalFunds()).to.equal(0);
      expect(await dfolio.reenableFund(ADD_FUND_PROPS[0]));
      const { name, active, index } = await dfolio.getFund(
        ADD_FUND_PROPS[0]
      );
      expect(name).to.equal(ADD_FUND_PROPS[0]);
      expect(active).to.equal(true);
      expect(index).to.equal(1);
      expect(await dfolio.totalFunds()).to.equal(1);
    });
  });
});
