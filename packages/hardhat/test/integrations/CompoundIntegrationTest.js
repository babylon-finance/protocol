const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { impersonateAddress } = require("../../utils/rpc");
const addresses = require("../../utils/addresses");
const { deployFolioFixture } = require("../fixtures/ControllerFixture");

const { loadFixture } = waffle;

describe("CompoundIntegration", function() {
  let system;
  let owner;
  let controller;
  let compoundBorrowing;
  const daiWhaleAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  let fund;
  let compAbi;

  beforeEach(async () => {
    system = await loadFixture(deployFolioFixture);
    owner = system.owner;
    controller = system.folioController;
    compoundBorrowing = system.integrations.compoundIntegration;
    compAbi = compoundBorrowing.interface;
    fund = system.funds.one;
  });

  describe("Deployment", function() {
    it("should successfully deploy the contract", async function() {
      const deployed = await controller.deployed();
      const deployedC = await compoundBorrowing.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedC).to.equal(true);
    });
  });

  describe("CompoundBorrowing", async function() {
    let whaleSigner;
    let cethToken;
    let daiToken;
    let cdaiToken;
    // let usdcToken;
    // let cusdcToken;

    beforeEach(async () => {
      whaleSigner = await impersonateAddress(daiWhaleAddress);
      daiToken = await ethers.getContractAt("IERC20", addresses.tokens.DAI);
      cdaiToken = await ethers.getContractAt("ICToken", addresses.tokens.CDAI);
      // usdcToken = await ethers.getContractAt("IERC20", addresses.tokens.USDC);
      // cusdcToken = await ethers.getContractAt(
      //   "ICToken",
      //   addresses.tokens.CUSDC
      // );
      cethToken = await ethers.getContractAt("ICEther", addresses.tokens.CETH);
    });

    describe("Compound Borrowing/Lending", function() {
      it("can supply ether", async function() {
        expect(await cethToken.balanceOf(fund.address)).to.equal(0);
        await expect(() =>
          owner.sendTransaction({
            to: fund.address,
            gasPrice: 0,
            value: ethers.utils.parseEther("1")
          })
        ).to.changeEtherBalance(owner, ethers.utils.parseEther("-1"));
        console.log(fund.address);
        const data = compAbi.encodeFunctionData(
          compoundBorrowing.interface.functions[
            "depositCollateral(address,uint256)"
          ],
          [addresses.tokens.WETH, ethers.utils.parseEther("1")]
        );
        await fund.callIntegration(
          compoundBorrowing.address,
          ethers.utils.parseEther("1"),
          data,
          {
            gasPrice: 0
          }
        );
        const balance = await cethToken.balanceOf(fund.address);
        expect(balance).to.be.gt(0);
        expect(await cethToken.balanceOf(compoundBorrowing.address)).to.equal(
          0
        );
      });

      it("can supply erc20", async function() {
        expect(
          await daiToken
            .connect(whaleSigner)
            .transfer(fund.address, ethers.utils.parseEther("1000"), {
              gasPrice: 0
            })
        );
        expect(await cdaiToken.balanceOf(fund.address)).to.equal(0);
        expect(await daiToken.balanceOf(fund.address)).to.equal(
          ethers.utils.parseEther("1000")
        );

        // Add allowance to the integration
        fund.addAllowanceIntegration(
          compoundBorrowing.address,
          daiToken.address,
          ethers.utils.parseEther("100")
        );
        await expect(() =>
          owner.sendTransaction({
            to: compoundBorrowing.address,
            gasPrice: 0,
            value: ethers.utils.parseEther("1")
          })
        ).to.changeEtherBalance(owner, ethers.utils.parseEther("-1"));
        const data = compAbi.encodeFunctionData(
          compoundBorrowing.interface.functions[
            "depositCollateral(address,uint256)"
          ],
          [addresses.tokens.DAI, ethers.utils.parseEther("100")]
        );
        await fund.callIntegration(compoundBorrowing.address, 0, data, {
          gasPrice: 0
        });

        const balance = await cdaiToken.balanceOf(fund.address);
        expect(balance).to.be.gt(0);
      });

      // it("can supply ether and borrow dai", async function() {
      //   expect(await cethToken.balanceOf(compoundBorrowing.address)).to.equal(
      //     0
      //   );
      //   await expect(() =>
      //     owner.sendTransaction({
      //       to: compoundBorrowing.address,
      //       gasPrice: 0,
      //       value: 1000000000
      //     })
      //   ).to.changeEtherBalance(owner, -1000000000);
      //   await compoundBorrowing.depositCollateral(
      //     addresses.tokens.WETH,
      //     ethers.utils.parseEther("10"),
      //     { value: ethers.utils.parseEther("10") }
      //   );
      //   let balance = await cethToken.balanceOf(compoundBorrowing.address);
      //   expect(balance).to.be.gt(0);
      //   expect(
      //     await compoundBorrowing.enterMarketsAndApproveCTokens([
      //       cdaiToken.address,
      //       cethToken.address
      //     ])
      //   );
      //   expect(await cdaiToken.balanceOf(compoundBorrowing.address)).to.equal(
      //     0
      //   );
      //   expect(
      //     await compoundBorrowing.borrow(
      //       daiToken.address,
      //       ethers.utils.parseEther("10")
      //     )
      //   );
      //   balance = await cdaiToken.borrowBalanceCurrent(
      //     compoundBorrowing.address
      //   );
      //   expect(balance).to.be.gt(0);
      // });

      // it("can supply dai and borrow usdc", async function() {
      //   expect(
      //     await daiToken
      //       .connect(whaleSigner)
      //       .transfer(
      //         compoundBorrowing.address,
      //         ethers.utils.parseEther("1000"),
      //         { gasPrice: 0 }
      //       )
      //   );
      //   expect(
      //     await daiToken
      //       .connect(whaleSigner)
      //       .transfer(owner.getAddress(), ethers.utils.parseEther("1000"), {
      //         gasPrice: 0
      //       })
      //   );
      //   expect(await cdaiToken.balanceOf(compoundBorrowing.address)).to.equal(
      //     0
      //   );
      //   expect(await daiToken.balanceOf(compoundBorrowing.address)).to.equal(
      //     ethers.utils.parseEther("1000")
      //   );
      //   expect(await daiToken.balanceOf(owner.getAddress())).to.equal(
      //     ethers.utils.parseEther("2000")
      //   );
      //   await expect(() =>
      //     owner.sendTransaction({
      //       to: compoundBorrowing.address,
      //       gasPrice: 0,
      //       value: 1000000000
      //     })
      //   ).to.changeEtherBalance(owner, -1000000000);
      //   expect(
      //     await compoundBorrowing.depositCollateral(
      //       addresses.tokens.DAI,
      //       ethers.utils.parseEther("100"),
      //       { gasPrice: 0 }
      //     )
      //   );
      //   let balance = await cdaiToken.balanceOf(compoundBorrowing.address);
      //   expect(balance).to.be.gt(0);
      //   expect(
      //     await compoundBorrowing.enterMarketsAndApproveCTokens([
      //       cdaiToken.address,
      //       cusdcToken.address
      //     ])
      //   );
      //   expect(await cdaiToken.balanceOf(compoundBorrowing.address)).to.be.gt(
      //     0
      //   );
      //   expect(
      //     await compoundBorrowing.borrow(
      //       usdcToken.address,
      //       ethers.utils.parseEther("1")
      //     )
      //   );
      //   balance = await cusdcToken.borrowBalanceCurrent(
      //     compoundBorrowing.address
      //   );
      //   expect(balance).to.be.gt(0);
      // });

      // it("can supply ether, borrow dai and repay", async function() {
      //   await expect(() =>
      //     owner.sendTransaction({
      //       to: compoundBorrowing.address,
      //       gasPrice: 0,
      //       value: 1000000000
      //     })
      //   ).to.changeEtherBalance(owner, -1000000000);
      //   await compoundBorrowing.depositCollateral(
      //     addresses.tokens.WETH,
      //     ethers.utils.parseEther("10"),
      //     { value: ethers.utils.parseEther("10") }
      //   );
      //   expect(
      //     await compoundBorrowing.enterMarketsAndApproveCTokens([
      //       cdaiToken.address,
      //       cethToken.address
      //     ])
      //   );
      //   expect(
      //     await compoundBorrowing.borrow(
      //       daiToken.address,
      //       ethers.utils.parseEther("10")
      //     )
      //   );
      //   const balance = await cdaiToken.borrowBalanceCurrent(
      //     compoundBorrowing.address
      //   );
      //   expect(balance).to.be.gt(0);
      //   console.log("balance after borrow", ethers.utils.formatEther(balance));
      //   expect(
      //     await compoundBorrowing.repayBorrow(
      //       cdaiToken.address,
      //       ethers.utils.parseEther("10")
      //     )
      //   );
      //   const balance2 = await cdaiToken.borrowBalanceCurrent(
      //     compoundBorrowing.address
      //   );
      //   console.log(
      //     "balance after repayment",
      //     ethers.utils.formatEther(balance2)
      //   );
      //   expect(balance2).to.be.lt(balance);
      // });
    });
  });
});
