const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;
const { EMPTY_BYTES, ONE_DAY_IN_SECONDS } = require("../utils/constants");
const addresses = require("../utils/addresses");
const constants = require("../utils/constants");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("Position testing", function() {
  let controller;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let community1;
  let community2;
  let integrationList;
  let weth;
  let usdcToken;

  beforeEach(async () => {
    const {
      babController,
      signer1,
      signer2,
      signer3,
      comunities,
      integrations,
      owner
    } = await loadFixture(deployFolioFixture);

    integrationList = integrations;
    controller = babController;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    community1 = comunities.one;
    community2 = comunities.two;
    usdcToken = await ethers.getContractAt("IERC20", addresses.tokens.USDC);
    weth = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
  });

  describe("Initial Positions", async function() {
    it("when creating a community the positions are at 0", async function() {
      expect(await community2.totalContributors()).to.equal(0);
      expect(await community2.getPositionCount()).to.equal(0);
      expect(await community2.totalCommunities()).to.equal(ethers.utils.parseEther("0"));
      const wethPosition = await community1.getPositionBalance(weth.address);
      expect(wethPosition).to.be.gt(ethers.utils.parseEther("0"));
      expect(await community2.totalSupply()).to.equal(ethers.utils.parseEther("0"));
    });

    it("updates weth position accordingly when initializing the community", async function() {
      expect(await community1.totalContributors()).to.equal(1);
      expect(await community1.getPositionCount()).to.equal(1);
      expect(await community1.totalCommunities()).to.equal(ethers.utils.parseEther("0.1"));
      const wethPosition = await community1.getPositionBalance(weth.address);
      expect(await weth.balanceOf(community1.address)).to.equal(
        ethers.utils.parseEther("0.1")
      );
      expect(wethPosition).to.equal(ethers.utils.parseEther("0.1"));
      expect(await community1.creator()).to.equal(await ownerSigner.getAddress());
      expect(await community1.balanceOf(ownerSigner.getAddress())).to.equal(
        await community1.totalSupply()
      );
      expect(await community1.totalSupply()).to.equal(
        ethers.utils.parseEther("0.1").div(await community1.initialBuyRate())
      );
    });
  });

  describe("On deposit/ withdrawal", async function() {
    it("supply and positions update accordingly after deposits", async function() {
      const communityBalance = await weth.balanceOf(community1.address);
      const supplyBefore = await community1.totalSupply();
      const wethPositionBefore = await community1.getPositionBalance(weth.address);
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      expect(await community1.totalContributors()).to.equal(2);
      expect(await community1.getPositionCount()).to.equal(1);
      const wethPosition = await community1.getPositionBalance(weth.address);
      const communityBalanceAfter = await weth.balanceOf(community1.address);
      const supplyAfter = await community1.totalSupply();
      expect(supplyAfter.div(11)).to.equal(supplyBefore);
      expect(communityBalanceAfter.sub(communityBalance)).to.equal(
        ethers.utils.parseEther("1")
      );
      expect(wethPosition.sub(wethPositionBefore)).to.equal(
        ethers.utils.parseEther("1")
      );
      expect(await community1.totalCommunities()).to.equal(ethers.utils.parseEther("1.1"));
      expect(await community1.totalCommunitiesDeposited()).to.equal(
        ethers.utils.parseEther("1.1")
      );
    });

    it("supply and positions update accordingly after deposits", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      const communityBalance = await weth.balanceOf(community1.address);
      const tokenBalance = await community1.balanceOf(userSigner3.getAddress());
      const supplyBefore = await community1.totalSupply();
      const wethPositionBefore = await community1.getPositionBalance(weth.address);
      ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 90]);
      const protocolTreasury = await weth.balanceOf(ownerSigner.address);
      await community1
        .connect(userSigner3)
        .withdraw(tokenBalance.div(2), 1, userSigner3.getAddress());
      const wethPosition = await community1.getPositionBalance(weth.address);
      const communityBalanceAfter = await weth.balanceOf(community1.address);
      const supplyAfter = await community1.totalSupply();
      expect(supplyAfter.add(tokenBalance / 2)).to.equal(supplyBefore);
      expect(communityBalance.sub(communityBalanceAfter)).to.equal(
        ethers.utils.parseEther("0.5")
      );
      expect(wethPositionBefore.sub(wethPosition)).to.equal(
        ethers.utils.parseEther("0.5")
      );
      expect(await community1.totalCommunities()).to.equal(ethers.utils.parseEther("0.6"));
      // Check that the protocol got 0.5% exit fee
      const protocolTreasuryAfter = await weth.balanceOf(
        ownerSigner.address
      );
      expect(protocolTreasuryAfter.sub(protocolTreasury)).to.equal(
        ethers.utils
          .parseEther("0.5")
          .mul(5)
          .div(1000)
      );
      expect(await community1.totalCommunitiesDeposited()).to.equal(
        ethers.utils.parseEther("1.1")
      );
    });
  });

  describe("Interacting with Trade integrations", async function() {
    it("updates positions accordingly after trading", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      const communityBalance = await weth.balanceOf(community1.address);
      const supplyBefore = await community1.totalSupply();
      const wethPositionBefore = await community1.getPositionBalance(weth.address);
      const usdcPositionBefore = await community1.getPositionBalance(
        usdcToken.address
      );
      expect(usdcPositionBefore).to.equal(0);

      // await community1.trade(
      //   "kyber",
      //   addresses.tokens.WETH,
      //   ethers.utils.parseEther("1"),
      //   usdcToken.address,
      //   ethers.utils.parseEther("900") / 10 ** 12,
      //   EMPTY_BYTES,
      //   { gasPrice: 0 }
      // );
      //
      // const wethPosition = await community1.getPositionBalance(weth.address);
      // const usdcPosition = await community1.getPositionBalance(usdcToken.address);
      // const communityBalanceAfter = await weth.balanceOf(community1.address);
      // const supplyAfter = await community1.totalSupply();
      //
      // // Communities don't change
      // expect(await community1.totalCommunitiesDeposited()).to.equal(
      //   ethers.utils.parseEther("1.1")
      // );
      // expect(await community1.totalCommunities()).to.equal(ethers.utils.parseEther("1.1"));
      // expect(supplyAfter).to.equal(supplyBefore);
      // expect(communityBalance.sub(ethers.utils.parseEther("1"))).to.equal(
      //   communityBalanceAfter
      // );
      // // Positions do
      // expect(wethPositionBefore.sub(wethPosition)).to.equal(
      //   ethers.utils.parseEther("1")
      // );
      // expect(usdcPosition.sub(usdcPositionBefore)).to.be.gt(900 * 10 ** 6);
      // expect(await community1.getPositionCount()).to.equal(2);
    });
  });

  describe("Interacting with Borrowing integrations", async function() {
  });



  describe("Interacting with Pool integrations", async function() {
  });

  describe("Interacting with Passive Investment integrations", async function() {
  });

});
