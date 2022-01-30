const { expect } = require('chai');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { pick, getERC20, eth, increaseTime } = require('utils/test-helpers');
const { impersonateAddress } = require('lib/rpc');

describe('Heart Integration Test', function () {
  let heartGarden;
  let heart;
  let treasury;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let garden2;
  let garden3;
  let keeper;
  let owner;
  let babController;
  let priceOracle;
  let BABL;
  let USDC;
  let WBTC;
  let FEI;
  let FRAX;
  let DAI;
  let WETH;
  let cDAI;
  let feeDistributionWeights;

  beforeEach(async () => {
    ({
      heartGarden,
      treasury,
      heart,
      keeper,
      signer1,
      signer2,
      signer3,
      garden1,
      garden2,
      garden3,
      owner,
      keeper,
      priceOracle,
      babController,
    } = await setupTests()());
    FRAX = await getERC20(addresses.tokens.FRAX);
    WETH = await getERC20(addresses.tokens.WETH);
    FEI = await getERC20(addresses.tokens.FEI);
    DAI = await getERC20(addresses.tokens.DAI);
    BABL = await getERC20(addresses.tokens.BABL);
    WBTC = await getERC20(addresses.tokens.WBTC);
    USDC = await getERC20(addresses.tokens.USDC);
    cDAI = await ethers.getContractAt('ICToken', '0xa6c25548df506d84afd237225b5b34f2feb1aa07');
    await heart.connect(owner).setHeartGardenAddress(heartGarden.address);
    feeDistributionWeights = await heart.connect(owner).getFeeDistributionWeights();
    // Impersonate visor and add heart to the whitelist
    const visorOwner = await impersonateAddress('0xc40ccde9c951ace468154d1d39917d8f8d11b38c');
    const visor = await ethers.getContractAt('IHypervisor', '0xF19F91d7889668A533F14d076aDc187be781a458');
    await visor.connect(visorOwner).appendList([heart.address], { gasPrice: 0 });
    // Adds weekly rewards
    await BABL.connect(owner).approve(heart.address, ethers.utils.parseEther('5000'));
    await heart.connect(owner).addReward(ethers.utils.parseEther('5000'), ethers.utils.parseEther('300'));
  });

  async function pumpAmount(amountInFees) {
    const daiPerWeth = await priceOracle.connect(owner).getPrice(WETH.address, DAI.address);
    await heart
      .connect(keeper)
      .resolveGardenVotes(
        [garden1.address, garden2.address, garden3.address],
        [ethers.utils.parseEther('0.33'), ethers.utils.parseEther('0.33'), ethers.utils.parseEther('0.33')],
      );
    const wethTreasuryBalanceBeforePump = await WETH.balanceOf(treasury.address);
    const bablTreasuryBalanceBeforePump = await BABL.balanceOf(treasury.address);
    const heartBABLBalanceBeforePump = await BABL.balanceOf(heartGarden.address);
    const balanceGarden1BeforePump = await WETH.balanceOf(garden1.address);
    const balanceGarden2BeforePump = await WETH.balanceOf(garden2.address);
    const balanceGarden3BeforePump = await WETH.balanceOf(garden3.address);
    const fuseBalanceDAIBeforePump = await cDAI.getCash();
    await heart.connect(signer1).pump();
    const statsAfterPump = await heart.getTotalStats();
    // Check the total fees is 3 WETH
    expect(statsAfterPump[0]).to.be.closeTo(amountInFees, amountInFees.div(100));
    // Check that we sent exactly 0.3 WETH to treasury and stat is right
    expect((await WETH.balanceOf(treasury.address)).sub(wethTreasuryBalanceBeforePump)).to.be.closeTo(
      amountInFees.mul(feeDistributionWeights[0]).div(1e9).div(1e9),
      ethers.utils.parseEther('0.01'),
    );
    expect(statsAfterPump[1]).to.be.closeTo(
      amountInFees.mul(feeDistributionWeights[0]).div(1e9).div(1e9),
      amountInFees.mul(feeDistributionWeights[0]).div(1e9).div(1e9).div(100),
    );
    // Checks buybacks
    const bablBought = statsAfterPump[2];
    expect(await BABL.balanceOf(heartGarden.address)).to.be.gte(heartBABLBalanceBeforePump.add(bablBought.div(2)));
    expect(await BABL.balanceOf(treasury.address)).to.be.gte(bablTreasuryBalanceBeforePump.add(bablBought.div(2)));
    // Checks liquidity
    expect(statsAfterPump[3]).to.be.closeTo(
      amountInFees.mul(feeDistributionWeights[2]).div(1e9).div(1e9),
      amountInFees.mul(feeDistributionWeights[2]).div(1e9).div(1e9).div(100),
    );
    // Checks garden seed investments
    const totalPumpedGardens = amountInFees.mul(feeDistributionWeights[3]).div(1e9).div(1e9);
    expect(statsAfterPump[4]).to.be.closeTo(totalPumpedGardens, totalPumpedGardens.div(100));
    expect(await WETH.balanceOf(garden1.address)).to.be.closeTo(
      balanceGarden1BeforePump.add(totalPumpedGardens.div(3)),
      ethers.utils.parseEther('0.01'),
    );
    expect(await WETH.balanceOf(garden2.address)).to.be.closeTo(
      balanceGarden2BeforePump.add(totalPumpedGardens.div(3)),
      ethers.utils.parseEther('0.01'),
    );
    expect(await WETH.balanceOf(garden3.address)).to.be.closeTo(
      balanceGarden3BeforePump.add(totalPumpedGardens.div(3)),
      ethers.utils.parseEther('0.01'),
    );
    // Checks fuse pool
    const amountLentToFuse = amountInFees.mul(feeDistributionWeights[4]).div(1e9).div(1e9);
    expect(statsAfterPump[5]).to.be.closeTo(amountLentToFuse, amountLentToFuse.div(100));
    expect(await cDAI.getCash()).to.be.closeTo(
      fuseBalanceDAIBeforePump.add(amountLentToFuse.mul(daiPerWeth).div(1e9).div(1e9)),
      fuseBalanceDAIBeforePump.add(amountLentToFuse.mul(daiPerWeth).div(1e9).div(1e9)).div(100),
    );
    // Checks weekly rewards
    expect(await heart.bablRewardLeft()).to.equal(ethers.utils.parseEther('4700'));
    expect(await BABL.balanceOf(heartGarden.address)).to.be.equal(
      heartBABLBalanceBeforePump.add(bablBought.div(2)).add(await heart.weeklyRewardAmount()),
    );
  }

  describe('pump', async function () {
    it('will pump correctly with 3 WETH', async function () {
      const amountInFees = ethers.utils.parseEther('3');
      await WETH.connect(owner).transfer(heart.address, amountInFees);
      await pumpAmount(amountInFees);
    });

    it('will pump correctly with 3 ETH, 1000 DAI', async function () {
      const wethPerDai = await priceOracle.connect(owner).getPrice(DAI.address, WETH.address);
      const amountInFees = ethers.utils
        .parseEther('3')
        .add(ethers.utils.parseEther('1000').mul(wethPerDai).div(1e9).div(1e9));
      await WETH.connect(owner).transfer(heart.address, ethers.utils.parseEther('3'));
      await DAI.connect(owner).transfer(heart.address, ethers.utils.parseEther('1000'));
      await pumpAmount(amountInFees);
    });

    it('will pump correctly with 3 ETH, 1000 DAI, 1000 USDC', async function () {
      const wethPerDai = await priceOracle.connect(owner).getPrice(DAI.address, WETH.address);
      const amountInFees = ethers.utils
        .parseEther('3')
        .add(ethers.utils.parseEther('2000').mul(wethPerDai).div(1e9).div(1e9));
      await WETH.connect(owner).transfer(heart.address, ethers.utils.parseEther('3'));
      await DAI.connect(owner).transfer(heart.address, ethers.utils.parseEther('1000'));
      await USDC.connect(owner).transfer(heart.address, 1000 * 1e6);
      await pumpAmount(amountInFees);
    });
  });
});
