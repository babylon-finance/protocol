const { expect } = require('chai');
const { ethers, deployments } = require('hardhat');
const { deploy } = deployments;
const addresses = require('lib/addresses');
const { fund } = require('lib/whale');
const { setupTests } = require('fixtures/GardenFixture');
const { getERC20 } = require('utils/test-helpers');

describe('Rari Refund', function () {
  let signer1;
  let babController;
  let owner;
  let WETH;
  let USDC;
  let DAI;
  let rariRefund;

  beforeEach(async () => {
    ({ owner, babController } = await setupTests()());
    await fund([owner.address]);

    WETH = await getERC20(addresses.tokens.WETH);
    USDC = await getERC20(addresses.tokens.USDC);
    DAI = await getERC20(addresses.tokens.DAI);

    const deployment = await deploy('Liquidation', {
      from: signer1.address,
      args: [babController.address, 0, 0, 0],
    });
    rariRefund = await ethers.getContractAt('RariRefund', deployment.address);
  });

  describe('sendTreasuryFunds', async function () {
    it(`can send ${name}`, async function () {

    });
  });
});
