const { expect } = require("chai");

const ADD_FUND_PROPS = ["new fund", "NewFundToken", "NFT"];

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

  describe("Hedge Funds", function() {
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
      expect(name == "my first fund");
      expect(active == true);
      expect(index == 1);
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
      expect(name == "my first fund");
      expect(active == false);
      expect(index == 1);
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
      expect(name == "my first fund");
      expect(active == true);
      expect(index == 1);
      expect(await holder.totalHedgeFunds()).to.equal(1);
    });
  });
});
