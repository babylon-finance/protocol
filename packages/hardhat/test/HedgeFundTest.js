const { expect } = require("chai");

describe("HedgeFund Deploy", function() {
  it("Should deploy HedgeFund", async function() {
    const [owner, addr1, addr2] = await ethers.getSigners();
    const contractProps = {
      name: "FakeFund",
      tokenName: "FakeFundToken",
      tokenSymbol: "FFT",
      active: true,
      manager: addr1.getAddress(),
    };
    const HedgeFund = await ethers.getContractFactory("HedgeFund", owner);
    await HedgeFund.deploy(
      contractProps.name,
      contractProps.tokenName,
      contractProps.tokenSymbol,
      contractProps.active,
      contractProps.manager
    );
  });
});

describe("HedgeFund", async function() {
  const [owner, addr1, addr2, addr3] = await ethers.getSigners();
  const contractProps = {
    name: "FakeFund",
    tokenName: "FakeFundToken",
    tokenSymbol: "FFT",
    active: true,
    manager: addr1.getAddress(),
  };
  const HedgeFund = await ethers.getContractFactory("HedgeFund", owner);

  let hedgeFund;

  beforeEach(async () => {
    hedgeFund = await HedgeFund.deploy(
      contractProps.name,
      contractProps.tokenName,
      contractProps.tokenSymbol,
      contractProps.active,
      contractProps.manager
    );
  });

  describe("HedgeFund construction", async function() {
    it("should have expected properties upon deployment", async function() {
      expect(await hedgeFund.totalContributors()).to.equal(0);
    });

    it("only the HedgeFund can call transferEth", async function() {
      // No manager
      try {
        await hedgeFund
          .connect(contractProps.manager)
          .transferEth({ _to: 0, amount: 1 });
      } catch (e) {
        expect(e).to.not.be.null;
      }

      // No rando
      try {
        await hedgeFund.connect(addr2).transferEth({ _to: 0, amount: 1 });
      } catch (e) {
        expect(e).to.not.be.null;
      }

      await hedgeFund.connect(addr2).depositFunds({ value: 100000000000000 });
      // No contributor
      try {
        await hedgeFund.connect(addr2).transferEth({ _to: 0, amount: 1 });
      } catch (e) {
        expect(e).to.not.be.null;
      }
    });
  });

  describe("HedgeFund state", async function() {
    it("only the current manager should be able to update active state", async function() {
      expect(await hedgeFund.setActive(false, contractProps.manager));
      await expect(hedgeFund.setActive(false, addr2.getAddress())).to.be
        .reverted;
    });

    it("only the current manager should be able to update the manager", async function() {
      expect(
        await hedgeFund.setManager(addr2.getAddress(), contractProps.manager)
      );
      await expect(
        hedgeFund.setManager(addr2.getAddress(), contractProps.manager)
      ).to.be.reverted;
    });
  });

  describe("HedgeFund contributors", async function() {
    it("a contributor can make an initial deposit", async function() {
      await hedgeFund.connect(addr2).depositFunds({ value: 100000000000000 });
      expect(await hedgeFund.totalContributors()).to.equal(1);
    });

    it("a contributor can make multiple deposits", async function() {
      await hedgeFund.connect(addr2).depositFunds({ value: 100000000000000 });
      await hedgeFund.connect(addr2).depositFunds({ value: 100000000000000 });
      expect(await hedgeFund.totalContributors()).to.equal(1);
      expect(await hedgeFund.totalFunds()).to.equal(200000000000000);
    });

    it("multiple contributors can make deposits", async function() {
      await hedgeFund.connect(addr2).depositFunds({ value: 100000000000000 });
      await hedgeFund.connect(addr3).depositFunds({ value: 100000000000000 });
      expect(await hedgeFund.totalContributors()).to.equal(2);
      expect(await hedgeFund.totalFunds()).to.equal(200000000000000);
    });

    it("a contributor can withdraw funds if they have enough", async function() {
      await hedgeFund.connect(addr2).depositFunds({ value: 100000000000000 });
      expect(await hedgeFund.totalFunds()).to.equal(100000000000000);
      expect(await hedgeFund.totalContributors()).to.equal(1);
      await hedgeFund.connect(addr2).withdrawFunds(100000000000000);
      expect(await hedgeFund.totalFunds()).to.equal(0);
      expect(await hedgeFund.totalContributors()).to.equal(0);
    });
  });
});
