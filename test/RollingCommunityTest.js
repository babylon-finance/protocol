const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { ONE_DAY_IN_SECONDS, NOW } = require("../utils/constants.js");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("Community", function() {
  let controller;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let community1;
  let community2;
  let community3;
  let weth;

  beforeEach(async () => {
    const {
      babController,
      signer1,
      signer2,
      signer3,
      communitys,
      owner
    } = await loadFixture(deployFolioFixture);

    controller = babController;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    community1 = communitys.one;
    community2 = communitys.two;
    community3 = communitys.three;
    weth = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
  });

  describe("Community construction", async function() {
    it("should have expected properties upon deployment", async function() {
      expect(await community1.totalContributors()).to.equal(1);
      expect(await community1.creator()).to.equal(await ownerSigner.getAddress());
    });
  });

  describe("Community state", async function() {
    it("only the protocol should be able to update active state", async function() {
      await expect(community1.connect(userSigner1).setActive(true)).to.be.reverted;
    });

    it("the initial deposit must be correct", async function() {
      const balance = await community1.signer.getBalance();
      await expect(balance).to.be.gt(ethers.utils.parseEther("0.099"));
    });
  });

  describe("Community deposit limit", async function() {
    it("reverts if the deposit is bigger than the limit", async function() {
      await controller.changeCommunityDepositLimit(
        community1.address,
        ethers.utils.parseEther("11")
      );
      await expect(
        community1
          .connect(userSigner3)
          .deposit(ethers.utils.parseEther("11"), 1, userSigner3.getAddress(), {
            value: ethers.utils.parseEther("11")
          })
      ).to.be.reverted;
    });
  });

  describe("Community deposit disabled", async function() {
    it("reverts if the community is disabled", async function() {
      await controller.disableCommunity(community1.address);
      await expect(
        community1
          .connect(userSigner3)
          .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
            value: ethers.utils.parseEther("1")
          })
      ).to.be.reverted;
    });
  });

  describe("Community contributors", async function() {
    it("a contributor can make an initial deposit", async function() {
      expect(await community1.totalContributors()).to.equal(1);
      const communityBalance = await weth.balanceOf(community1.address);
      const supplyBefore = await community1.totalSupply();
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      const communityBalanceAfter = await weth.balanceOf(community1.address);
      const supplyAfter = await community1.totalSupply();
      // Communities
      // Manager deposit in fixture is only 0.1
      expect(supplyAfter.div(11)).to.equal(supplyBefore);
      expect(communityBalanceAfter.sub(communityBalance)).to.equal(
        ethers.utils.parseEther("1")
      );
      expect(await community1.totalContributors()).to.equal(2);
      expect(await community1.totalCommunities()).to.equal(ethers.utils.parseEther("1.1"));
      expect(await community1.totalCommunitiesDeposited()).to.equal(
        ethers.utils.parseEther("1.1")
      );
      // Positions
      expect(await community1.getPositionCount()).to.equal(1);
      const wethPosition = await community1.getPositionBalance(weth.address);
      expect(wethPosition).to.be.gt(ethers.utils.parseEther("1.099"));
      // Contributor Struct
      const contributor = await community1.contributors(userSigner3.getAddress());
      expect(contributor.totalDeposit).to.equal(ethers.utils.parseEther("1"));
      expect(contributor.tokensReceived).to.equal(
        supplyAfter.sub(supplyBefore)
      );
    });

    it("a contributor can make multiple deposits", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      // Note: Community is initialized with manager as first contributor, hence the count and totalCommunities delta
      expect(await community1.totalContributors()).to.equal(2);
      expect(await community1.totalCommunities()).to.equal(
        ethers.utils.parseEther("2.1")
      );
    });

    it("multiple contributors can make deposits", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });

      await community1
        .connect(userSigner2)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner2.getAddress(), {
          value: ethers.utils.parseEther("1")
        });

      // Note: Community is initialized with manager as first contributor
      expect(await community1.totalContributors()).to.equal(3);
      expect(await community1.totalCommunities()).to.equal(ethers.utils.parseEther("2.1"));
    });

    it("a contributor can withdraw communitys if they have enough in deposits", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 90]);
      expect(await community1.totalCommunities()).to.equal(ethers.utils.parseEther("1.1"));
      expect(await community1.totalContributors()).to.equal(2);
      await community1
        .connect(userSigner3)
        .withdraw(1000000, 1, userSigner3.getAddress());
    });

    it("a contributor cannot withdraw communitys until the time ends", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      expect(await community1.totalCommunities()).to.equal(ethers.utils.parseEther("1.1"));
      expect(await community1.totalContributors()).to.equal(2);
      await expect(
        community1
          .connect(userSigner3)
          .withdraw(1000000, 1, userSigner3.getAddress())
      ).to.be.reverted;
    });

    it("a contributor cannot make a deposit when the community ends", async function() {
      ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 90]);
      await expect(
        community1
          .connect(userSigner3)
          .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
            value: ethers.utils.parseEther("1")
          })
      ).to.be.reverted;
    });

    it("a contributor cannot withdraw more communitys than they have deposited", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 90]);
      expect(await community1.totalCommunities()).to.equal(ethers.utils.parseEther("1.1"));
      expect(await community1.totalContributors()).to.equal(2);
      await expect(
        community1
          .connect(userSigner3)
          .withdraw(10000000, 2, userSigner3.getAddress())
      ).to.be.reverted;
      await expect(
        community1
          .connect(userSigner3)
          .withdraw(1000001, 2, userSigner3.getAddress())
      ).to.be.reverted;
    });
  });
});
