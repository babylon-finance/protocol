const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_ETH, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { increaseTime } = require('utils/test-helpers');

const { setupTests } = require('fixtures/GardenFixture');

describe('Governor Babylon contract', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let governorBabylon;
  let timelockController;

  const name = 'Governor Babylon';
  const version = '1';
  const tokenName = 'Babylon.Finance';
  const tokenSymbol = 'BABL';

  const votingPeriod = ONE_DAY_IN_SECONDS * 7;

  beforeEach(async () => {
    ({ owner, signer1, signer2, signer3, bablToken, governorBabylon, timelockController } = await setupTests()());
    const voter1 = signer1;
    const voter2 = signer2;
    const voter3 = signer3;
    const voter4 = owner;
    await bablToken.connect(voter1).delegate(voter1.address);
    await bablToken.connect(voter2).delegate(voter2.address);
    await bablToken.connect(voter3).delegate(voter3.address);
    await bablToken.connect(voter4).delegate(voter4.address);
  });

  describe('Deployment check', function () {
    it('should successfully deploy Governor Babylon contract', async function () {
      const deployedc = await governorBabylon.deployed();
      const tokenSupply = await bablToken.totalSupply();
      expect(!!deployedc).to.equal(true);
      expect(await governorBabylon.name()).to.be.equal(name);
      expect(await governorBabylon.version()).to.be.equal(version);
      expect(await governorBabylon.token()).to.be.equal(bablToken.address);
      expect(await governorBabylon.votingDelay()).to.be.equal('4');
      expect(await governorBabylon.votingPeriod()).to.be.equal(votingPeriod);
      expect(await governorBabylon.quorum(0)).to.be.equal(tokenSupply.div(25)); // 4% of totalSupply BABL
      expect(await governorBabylon.proposalThreshold()).to.be.equal(tokenSupply.div(100)); // 1% of totalSupply BABL
      expect(await governorBabylon.COUNTING_MODE()).to.be.equal('support=bravo&quorum=bravo');
      expect(await governorBabylon.timelock()).to.be.equal(timelockController.address);

      // Check the linked BABL Token
      expect(await bablToken.name()).to.be.equal(tokenName);
      expect(await bablToken.symbol()).to.be.equal(tokenSymbol);
    });
  });
});
