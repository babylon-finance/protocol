const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

describe("Fund", function() {
  let controller;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  let fund1;
  let fund2;
  let fund3;
  let weth;

  beforeEach(async () => {
    const {
      folioController,
      signer1,
      signer2,
      signer3,
      funds,
      owner,
    } = await loadFixture(deployFolioFixture);

    controller = folioController;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;
    fund1 = funds.one;
    fund2 = funds.two;
    fund3 = funds.three;
    weth = await ethers.getContractAt("IERC20", addresses.tokens.WETH);

  });

  describe("Fund construction", async function() {
    it("should have expected properties upon deployment", async function() {
      expect(await fund1.totalContributors()).to.equal(1);
      expect(await fund1.manager()).to.equal(await ownerSigner.getAddress());
    });
  });

  describe("Fund state", async function() {
    it("only the current manager or protocol should be able to update active state", async function() {
      await expect(fund1.connect(userSigner1).setActive(true)).to.be.reverted;
    });

    it("only the current manager or the protocol should be able to update the manager", async function() {
      await expect(
        fund1.connect(userSigner3).setManager(userSigner3.getAddress())
      ).to.be.reverted;
    });
  });

  describe("Fund contributors", async function() {
    it("a contributor can make an initial deposit", async function() {
      expect(await fund1.totalContributors()).to.equal(1);

      await fund1.connect(userSigner3).deposit(ethers.utils.parseEther("1"), 1, addresses.users.hardhat3, {
        value: ethers.utils.parseEther("1")
      });
      //expect(await fund1Token.balanceOf(addresses.users.hardhat3.getAddress())).to.equal(100);
    });

    //it("a contributor can make multiple deposits", async function() {
    //  await fund1.connect(addresses.users.hardhat3).deposit({ value: 100000000000000 });
    //  await fund1.connect(addresses.users.hardhat3).deposit({ value: 100000000000000 });
    //  expect(await fund1.totalContributors()).to.equal(1);
    //  expect(await fund1.totalFunds()).to.equal(200000000000000);
    //});

    //it("multiple contributors can make deposits", async function() {
    //  await fund1.connect(addresses.users.hardhat3).deposit({ value: 100000000000000 });
    //  await fund1.connect(addr3).deposit({ value: 100000000000000 });
    //  expect(await fund1.totalContributors()).to.equal(2);
    //  expect(await fund1.totalFunds()).to.equal(200000000000000);
    //});

    //it("a contributor can withdraw fund1s if they have enough in deposits", async function() {
    //  await fund1.connect(addresses.users.hardhat3).deposit({ value: 100000000000000 });
    //  expect(await fund1.totalFunds()).to.equal(100000000000000);
    //  expect(await fund1.totalContributors()).to.equal(1);
    //  await fund1.connect(addresses.users.hardhat3).withdrawFunds(100000000000000);
    //  expect(await fund1.totalFunds()).to.equal(0);
    //  expect(await fund1.totalContributors()).to.equal(0);
    //});

    //it("a contributor cannot withdraw more fund1s than they have deposited", async function() {
    //  await fund1.connect(addresses.users.hardhat3).deposit({ value: 100000000000000 });
    //  expect(await fund1.totalFunds()).to.equal(100000000000000);
    //  expect(await fund1.totalContributors()).to.equal(1);
    //  await expect(fund1.connect(addresses.users.hardhat3).withdrawFunds(200000000000000)).to.be
    //    .reverted;
    //  expect(await fund1.totalFunds()).to.equal(100000000000000);
    //  expect(await fund1.totalContributors()).to.equal(1);
    //});
  });
});
