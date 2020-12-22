const { expect } = require("chai");

const ADD_FUND_PROPS = ["new fund", "NewFundToken", "NFT"];
const ADD_FUND_PROPS_2 = ["new fund 2", "NewFundToken2", "NFT2"];

describe("Holder Deploy", function() {
  it("Should deploy Holder", async function() {
    const [owner] = await ethers.getSigners();
    const Holder = await ethers.getContractFactory("Holder", owner);
    await Holder.deploy();
  });
});

describe("Holder", async function() {
  const [owner, addr1, addr2] = await ethers.getSigners();
  const Holder = await ethers.getContractFactory("Holder", owner);

  let holder;

  beforeEach(async () => {
    holder = await Holder.deploy();
  });

  describe("Interacting with HedgeFunds", function() {
    it("should start empty", async function() {
      expect(await holder.totalHedgeFunds()).to.equal(0);
      expect(await holder.currentHedgeFundIndex()).to.equal(1);
    });

    it("should set the protocol manager address", async function() {
      expect(await holder.protocolManager()).to.equal(await owner.getAddress());
    });

    it("can add a hedge fund and retrieve it", async function() {
      expect(await holder.addHedgeFund(...ADD_FUND_PROPS));
      expect(await holder.totalHedgeFunds()).to.equal(1);
      expect(await holder.currentHedgeFundIndex()).to.equal(2);
      const { name, active, index } = await holder.getHedgeFund(
        ADD_FUND_PROPS[0]
      );
      expect(name).to.equal(ADD_FUND_PROPS[0]);
      expect(active).to.equal(false);
      expect(index).to.equal(1);
    });

    it("can add a hedge funds and retrieve all", async function() {
      expect(await holder.addHedgeFund(...ADD_FUND_PROPS));
      expect(await holder.addHedgeFund(...ADD_FUND_PROPS_2));
      expect(await holder.totalHedgeFunds()).to.equal(2);
      expect(await holder.currentHedgeFundIndex()).to.equal(3);
      const funds = await holder.getAllHedgeFunds();
      expect(funds.length).to.equal(2);
    });

    it("only protocol manager can add hedge funds", async function() {
      await expect(holder.connect(addr2).addHedgeFund(...ADD_FUND_PROPS)).to.be
        .reverted;
    });

    it("can not add the same hedge fund twice", async function() {
      expect(await holder.addHedgeFund(...ADD_FUND_PROPS));
      await expect(holder.addHedgeFund(...ADD_FUND_PROPS)).to.be.reverted;
    });

    it("can disable a hedge fund and retrieve it", async function() {
      expect(await holder.addHedgeFund(...ADD_FUND_PROPS));
      expect(await holder.totalHedgeFunds()).to.equal(1);
      expect(await holder.currentHedgeFundIndex()).to.equal(2);
      expect(await holder.disableHedgeFund(ADD_FUND_PROPS[0]));
      const { name, active, index } = await holder.getHedgeFund(
        ADD_FUND_PROPS[0]
      );
      expect(name).to.equal(ADD_FUND_PROPS[0]);
      expect(active).to.equal(false);
      expect(index).to.equal(1);
      expect(await holder.totalHedgeFunds()).to.equal(0);
    });

    it("can not disable a hedge fund that does not exist", async function() {
      await expect(holder.disableHedgeFund("my imaginary fund")).to.be.reverted;
    });

    it("can reenable a hedge fund after disabling it", async function() {
      expect(await holder.addHedgeFund(...ADD_FUND_PROPS));
      expect(await holder.totalHedgeFunds()).to.equal(1);
      expect(await holder.currentHedgeFundIndex()).to.equal(2);
      expect(await holder.disableHedgeFund(ADD_FUND_PROPS[0]));
      expect(await holder.totalHedgeFunds()).to.equal(0);
      expect(await holder.reenableHedgeFund(ADD_FUND_PROPS[0]));
      const { name, active, index } = await holder.getHedgeFund(
        ADD_FUND_PROPS[0]
      );
      expect(name).to.equal(ADD_FUND_PROPS[0]);
      expect(active).to.equal(true);
      expect(index).to.equal(1);
      expect(await holder.totalHedgeFunds()).to.equal(1);
    });
  });
});
