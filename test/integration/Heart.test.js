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
  let BABL;
  let USDC;
  let WBTC;
  let FEI;
  let FRAX;
  let DAI;
  let WETH;
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
      babController,
    } = await setupTests()());
    FRAX = await getERC20(addresses.tokens.FRAX);
    WETH = await getERC20(addresses.tokens.WETH);
    FEI = await getERC20(addresses.tokens.FEI);
    DAI = await getERC20(addresses.tokens.DAI);
    BABL = await getERC20(addresses.tokens.BABL);
    WBTC = await getERC20(addresses.tokens.WBTC);
    USDC = await getERC20(addresses.tokens.USDC);
    await heart.connect(owner).setHeartGardenAddress(heartGarden.address);
    feeDistributionWeights = await heart.connect(owner).getFeeDistributionWeights();
    // Impersonate visor and add heart to the whitelist
    const visorOwner = await impersonateAddress('0xc40ccde9c951ace468154d1d39917d8f8d11b38c');
    const visor = await ethers.getContractAt('IHypervisor', '0x5e6c481dE496554b66657Dd1CA1F70C61cf11660');
    await visor.connect(visorOwner).appendList([heart.address], { gasPrice: 0 });
  });

  describe('pump', async function () {
    it('will pump correctly with 3 WETH', async function () {
      const amountInFees = ethers.utils.parseEther('3');
      await WETH.connect(owner).transfer(heart.address, amountInFees);
      await heart
        .connect(keeper)
        .resolveGardenVotes(
          [garden1.address, garden2.address, garden3.address],
          [ethers.utils.parseEther('0.33'), ethers.utils.parseEther('0.33'), ethers.utils.parseEther('0.33')],
        );
      const wethTreasuryBalanceBeforePump = await WETH.balanceOf(treasury.address);
      const heartBABLBalanceBeforePump = await BABL.balanceOf(heartGarden.address);
      await heart.connect(signer1).pump();
      const statsAfterPump = await heart.getTotalStats();
      // Check the total fees is 3 WETH
      expect(statsAfterPump[0]).to.equal(amountInFees);
      // Check that we sent exactly 0.3 WETH to treasury and stat is right
      expect((await WETH.balanceOf(treasury.address)).sub(wethTreasuryBalanceBeforePump)).to.be.closeTo(
        amountInFees.mul(feeDistributionWeights[0]).div(1e9).div(1e9),
        ethers.utils.parseEther('0.01'),
      );
      expect(statsAfterPump[1]).to.equal(amountInFees.mul(feeDistributionWeights[0]).div(1e9).div(1e9));
      // Checks buybacks
      const bablBought = statsAfterPump[2];
      expect(await BABL.balanceOf(heartGarden.address)).to.be.equal(heartBABLBalanceBeforePump.add(bablBought));
      // Checks liquidity
      expect(statsAfterPump[3]).to.equal(amountInFees.mul(feeDistributionWeights[2]).div(1e9).div(1e9));
      // Checks garden seed investments
      expect(statsAfterPump[4]).to.equal(amountInFees.mul(feeDistributionWeights[3]).div(1e9).div(1e9));
      // TODO: check 3 gardens got more reserve asset
      // Checks fuse pool
      expect(statsAfterPump[5]).to.equal(amountInFees.mul(feeDistributionWeights[4]).div(1e9).div(1e9));
      // TODO: check underlying in fuse pool
      // TODO: Check weekly rewards
    });

    it('will pump correctly with 3 ETH, 1000 DAI', async function () {});
    it('will pump correctly with 3 ETH, 1000 DAI, 1000 USDC', async function () {});
  });
});
