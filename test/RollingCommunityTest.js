const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { ONE_DAY_IN_SECONDS, EMPTY_BYTES } = require("../utils/constants.js");
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
  let balancerIntegration;

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

    balancerIntegration = integrations.balancerIntegration;
    controller = babController;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    community1 = comunities.one;
    community2 = comunities.two;
    community3 = comunities.three;
    weth = await ethers.getContractAt("IERC20", addresses.tokens.WETH);
  });

  describe("Community construction", async function() {
    it("should have expected properties upon deployment", async function() {
      expect(await community1.totalContributors()).to.equal(1);
      expect(await community1.creator()).to.equal(
        await userSigner1.getAddress()
      );
      expect(await community1.controller()).to.equal(controller.address);
      expect(await community1.ideaCooldownPeriod()).to.equal(
        ONE_DAY_IN_SECONDS
      );
      expect(await community1.ideaCreatorProfitPercentage()).to.equal(
        ethers.utils.parseEther("0.13")
      );
      expect(await community1.ideaVotersProfitPercentage()).to.equal(
        ethers.utils.parseEther("0.05")
      );
      expect(await community1.communityCreatorProfitPercentage()).to.equal(
        ethers.utils.parseEther("0.02")
      );
      expect(await community1.minVotersQuorum()).to.equal(
        ethers.utils.parseEther("0.10")
      );
      expect(await community1.minIdeaDuration()).to.equal(
        ONE_DAY_IN_SECONDS * 3
      );
      expect(await community1.maxIdeaDuration()).to.equal(
        ONE_DAY_IN_SECONDS * 365
      );
    });
  });

  describe("Community state", async function() {
    it("only the protocol should be able to update active state", async function() {
      await expect(community1.connect(userSigner1).setActive(true)).to.be
        .reverted;
    });

    it("the initial deposit must be correct", async function() {
      const balance = await community1.signer.getBalance();
      await expect(balance).to.be.gt(ethers.utils.parseEther("0.099"));
    });
  });

  describe("Community deposit limit", async function() {
    it("reverts if the deposit is bigger than the limit", async function() {
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
      // expect(supplyAfter.div(11)).to.equal(supplyBefore);
      expect(communityBalanceAfter.sub(communityBalance)).to.equal(
        ethers.utils.parseEther("1")
      );
      expect(await community1.totalContributors()).to.equal(2);
      expect(await community1.totalFunds()).to.equal(
        ethers.utils.parseEther("1.1")
      );
      expect(await community1.totalFundsDeposited()).to.equal(
        ethers.utils.parseEther("1.1")
      );
      const wethPosition = await community1.getReserveBalance();
      expect(wethPosition).to.be.gt(ethers.utils.parseEther("1.099"));
      // Contributor Struct
      const contributor = await community1.contributors(
        userSigner3.getAddress()
      );
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
      // Note: Community is initialized with manager as first contributor, hence the count and totalFunds delta
      expect(await community1.totalContributors()).to.equal(2);
      expect(await community1.totalFunds()).to.equal(
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
      expect(await community1.totalFunds()).to.equal(
        ethers.utils.parseEther("2.1")
      );
    });

    it("a contributor can withdraw funds if they have enough in deposits", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 90]);
      expect(await community1.totalFunds()).to.equal(
        ethers.utils.parseEther("1.1")
      );
      expect(await community1.totalContributors()).to.equal(2);
      console.log(
        "balance",
        ethers.utils.formatEther(
          await community1.balanceOf(userSigner3.getAddress())
        )
      );
      await community1
        .connect(userSigner3)
        .withdraw(90909, 1, userSigner3.getAddress());
    });

    it("a contributor cannot withdraw comunities until the time ends", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      expect(await community1.totalFunds()).to.equal(
        ethers.utils.parseEther("1.1")
      );
      expect(await community1.totalContributors()).to.equal(2);
      await expect(
        community1
          .connect(userSigner3)
          .withdraw(1000000, 1, userSigner3.getAddress())
      ).to.be.reverted;
    });

    it("a contributor cannot make a deposit when the community is disabled", async function() {
      await expect(controller.disableCommunity(community1.address)).to.not.be
        .reverted;
      await expect(
        community1
          .connect(userSigner3)
          .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
            value: ethers.utils.parseEther("1")
          })
      ).to.be.reverted;
    });

    it("a contributor cannot withdraw more comunity tokens than they have deposited", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 90]);
      expect(await community1.totalFunds()).to.equal(
        ethers.utils.parseEther("1.1")
      );
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

  describe("Add Investment Idea", async function() {
    it("should not be able to add an investment idea unless there is a contributor", async function() {
      await expect(
        community1
          .connect(userSigner2)
          .addInvestmentIdea(
            ethers.utils.parseEther("10"),
            ethers.utils.parseEther("1"),
            ONE_DAY_IN_SECONDS * 15,
            EMPTY_BYTES,
            EMPTY_BYTES,
            balancerIntegration.address,
            ethers.utils.parseEther("0.05"),
            ethers.utils.parseEther("2"),
            [addresses.tokens.DAI],
            [ethers.utils.parseEther("100")],
            {
              gasLimit: 9500000,
              gasPrice: 0
            }
          )
      ).to.be.reverted;
    });

    it("a contributor should be able to add an investment idea", async function() {
      await community1
        .connect(userSigner3)
        .deposit(ethers.utils.parseEther("1"), 1, userSigner3.getAddress(), {
          value: ethers.utils.parseEther("1")
        });
      await expect(
        community1.connect(userSigner3).addInvestmentIdea(
          ethers.utils.parseEther("10"),
          ethers.utils.parseEther("0.001"),
          ONE_DAY_IN_SECONDS * 30,
          ethers.utils.parseEther("0.05"), // 5%
          ethers.utils.parseEther("1")
        )
      ).to.not.be.reverted;
    });
  });
});
