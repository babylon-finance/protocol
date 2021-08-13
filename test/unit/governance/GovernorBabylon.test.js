const { expect } = require('chai');
const { ethers } = require('hardhat');
const { expectRevert, time } = require('@openzeppelin/test-helpers');
const EthCrypto = require('eth-crypto');

const { ONE_ETH, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { increaseTime, voteType, proposalState } = require('utils/test-helpers');

const { setupTests } = require('fixtures/GardenFixture');

describe.only('Governor Babylon contract', function () {
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let governorBabylon;
  let timelockController;
  let babController;

  const name = 'Governor Babylon';
  const version = '1';
  const tokenName = 'Babylon.Finance';
  const tokenSymbol = 'BABL';
  const value = ethers.utils.parseEther('0');
  let voter1;
  let voter2;
  let voter3;
  let voter4;

  const votingPeriod = ONE_DAY_IN_SECONDS * 7;

  async function createProposal(proposer, target, value, encodedData, description) {
    const settings = {
      proposal: [[target], [value], [encodedData], description],
      proposer: proposer, // proposer
      tokenHolder: owner,
      voters: [
        { voter: voter1, weight: ethers.utils.parseEther('1'), support: voteType.For, reason: 'This is nice' },
        { voter: voter2, weight: ethers.utils.parseEther('10'), support: voteType.For },
        { voter: voter3, weight: ethers.utils.parseEther('5'), support: voteType.Against },
        { voter: voter4, weight: ethers.utils.parseEther('2'), support: voteType.Abstain },
      ],
    };
    return settings;
  }

  async function transferTokens(settings) {
    for (const voter of settings.voters) {
      await bablToken.connect(owner).transfer(voter.voter.address, voter.weight);
    }
  }

  beforeEach(async () => {
    ({
      owner,
      signer1,
      signer2,
      signer3,
      bablToken,
      governorBabylon,
      timelockController,
      babController,
    } = await setupTests()());
    voter1 = signer1;
    voter2 = signer2;
    voter3 = signer3;
    voter4 = owner;
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
  describe('Proposals', function () {
    it.only('hash a proposal', async function () {
      const ABI = ['function enableBABLMiningProgram()'];
      const iface = new ethers.utils.Interface(ABI);
      const encodedData = iface.encodeFunctionData('enableBABLMiningProgram');
      const proposalDescription = EthCrypto.hash.keccak256([{ type: 'string', value: '<proposal description>' }]);
      const proposer = signer1;
      const settings = await createProposal(proposer, babController.address, value, encodedData, proposalDescription);
      const id = await governorBabylon.hashProposal(...settings.proposal);
      expect(id.toString()).to.equal('31592073516640214093428763406121273246927507816899979568469470593665780044126');
    });
    it.only('should successfully create a proposal', async function () {
      const ABI = ['function enableBABLMiningProgram()'];
      const iface = new ethers.utils.Interface(ABI);
      const encodedData = iface.encodeFunctionData('enableBABLMiningProgram');
      const proposer = signer1;
      let settings = await createProposal(
        proposer,
        babController.address,
        value,
        encodedData,
        '<proposal description>',
      );

      // console.log(settings);

      // enable token transfers
      await bablToken.connect(owner).enableTokensTransfers();
      // transfer tokens
      await transferTokens(settings);

      console.log('CHECK 0');

      // propose
      await governorBabylon.connect(settings.proposer).propose(...settings.proposal);

      console.log('CHECK 1');

      // get id to check the created proposal
      const proposalDescription = EthCrypto.hash.keccak256([{ type: 'string', value: '<proposal description>' }]);
      settings = await createProposal(proposer, babController.address, value, encodedData, proposalDescription);
      const id = await governorBabylon.hashProposal(...settings.proposal);

      const proposed = await governorBabylon.proposals(id);
      expect(proposed[0]).to.be.equal(id);
      expect(proposed[1]).to.be.equal(proposer);

      // TODO check all params eta, startBlock, etc.
      // expect(proposed[2]).to.be.equal(eta); // eta
      // expect(proposed[3]).to.be.equal(startBlock); // startBlock
      // expect(proposed[4]).to.be.equal(endBlock); // endBlock
      // expect(proposed[5]).to.be.equal(forVotes); // forVotes
      // expect(proposed[6]).to.be.equal(againstVotes); // againstVotes
      // expect(proposed[7]).to.be.equal(abstainVotes); // abstainVotes
      // expect(proposed[8]).to.be.equal(canceled); // canceled
      // expect(proposed[9]).to.be.equal(executed); // executed
    });
    it.skip('should successfully vote a proposal', async function () {
      // TODO
      // Take the id of the proposal to check votes
      // const proposalDescription = EthCrypto.hash.keccak256([{ type: 'string', value: '<proposal description>' }]);
      // const settings = await createProposal(proposer, babController.address, value, encodedData, proposalDescription);
      // const id = await governorBabylon.hashProposal(...settings.proposal);
      // expect(await governorBabylon.hasVoted(id, voter1)).to.be.equal(true);
      // expect(await governorBabylon.hasVoted(id, voter2)).to.be.equal(true);
      // expect(await governorBabylon.hasVoted(id, voter3)).to.be.equal(true);
      // expect(await governorBabylon.hasVoted(id, voter4)).to.be.equal(true); // voter 4 is owner
    });
    it.skip('should successfully vote a proposal by sig', async function () {
      // TODO
    });
    it.skip('should successfully queue a proposal', async function () {
      // TODO
    });
  });
});
