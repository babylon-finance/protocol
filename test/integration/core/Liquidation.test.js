const { expect } = require('chai');
const { ethers, deployments } = require('hardhat');
const { deploy } = deployments;
const { fund } = require('lib/whale');
const addresses = require('lib/addresses');
const { setupTests } = require('fixtures/GardenFixture');
const { pick, getERC20, from, eth } = require('utils/test-helpers');

describe('Liquidation', function () {
  let signer1;
  let treasury;
  let DAI;
  let BABL;
  let owner;
  let babController;
  let liquidation;

  beforeEach(async () => {
    ({ babController, owner } = await setupTests()());
    BABL = await getERC20(addresses.tokens.BABL);
    DAI = await getERC20(addresses.tokens.DAI);
    await fund([owner.address]);
    const deployment = await deploy('Liquidation', {
      from: signer1.address,
      args: [babController.address, 0,0, 0],
    });
    liquidation = await ethers.getContractAt('Liquidation', deployment.address);
  });

  describe('sendTreasuryFunds', async function () {
    it(`can send ${name}`, async function () {

    });
  });
});
