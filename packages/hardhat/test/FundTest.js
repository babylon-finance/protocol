const { expect } = require("chai");

describe("Fund", async function() {
  const [owner, addr1, addr2, addr3] = await ethers.getSigners();
  const contractProps = {
    name: "FakeFund",
    tokenName: "FakeFundToken",
    tokenSymbol: "FFT",
    manager: owner.getAddress(),
  };
  const Fund = await ethers.getContractFactory("Fund", owner);

  let hedgeFund;
  let fundToken;

  beforeEach(async () => {
    hedgeFund = await Fund.deploy(
      contractProps.name,
      contractProps.tokenName,
      contractProps.tokenSymbol,
      contractProps.manager
    );
    const fundTokenAddress = await hedgeFund.token();
    fundToken = await ethers.getContractAt("IERC20", fundTokenAddress);
  });

  describe("Fund construction", async function() {
    it("should have expected properties upon deployment", async function() {
      expect(await hedgeFund.totalContributors()).to.equal(0);
      expect(await hedgeFund.manager()).to.equal(await owner.getAddress());
    });

    it("only the Fund can call transferEth", async function() {
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

  describe("Fund state", async function() {
    it("only the current manager should be able to update active state", async function() {
      expect(await hedgeFund.setActive(false));
      await expect(hedgeFund.connect(addr2).setActive(false)).to.be.reverted;
    });

    it("only the current manager should be able to update the manager", async function() {
      expect(await hedgeFund.setManager(addr2.getAddress()));
      const manager = await hedgeFund.manager()
      await expect(hedgeFund.connect(owner).setManager(addr2.getAddress())).to.be.reverted;
    });
  });

  describe("Fund contributors", async function() {
    it("a contributor can make an initial deposit", async function() {
      await hedgeFund.connect(addr2).depositFunds({ value: 100000000000000 });
      expect(await hedgeFund.totalContributors()).to.equal(1);
      expect(await fundToken.balanceOf(addr2.getAddress())).to.equal(100);
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

    it("a contributor can withdraw funds if they have enough in deposits", async function() {
      await hedgeFund.connect(addr2).depositFunds({ value: 100000000000000 });
      expect(await hedgeFund.totalFunds()).to.equal(100000000000000);
      expect(await hedgeFund.totalContributors()).to.equal(1);
      await hedgeFund.connect(addr2).withdrawFunds(100000000000000);
      expect(await hedgeFund.totalFunds()).to.equal(0);
      expect(await hedgeFund.totalContributors()).to.equal(0);
    });

    it("a contributor cannot withdraw more funds than they have deposited", async function() {
      await hedgeFund.connect(addr2).depositFunds({ value: 100000000000000 });
      expect(await hedgeFund.totalFunds()).to.equal(100000000000000);
      expect(await hedgeFund.totalContributors()).to.equal(1);
      await expect(hedgeFund.connect(addr2).withdrawFunds(200000000000000)).to
        .be.reverted;
      expect(await hedgeFund.totalFunds()).to.equal(100000000000000);
      expect(await hedgeFund.totalContributors()).to.equal(1);
    });
  });
});
