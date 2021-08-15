const { expect } = require('chai');
const { ethers } = require('hardhat');
const EthCrypto = require('eth-crypto');

const { ONE_ETH, ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { increaseTime, voteType, proposalState } = require('utils/test-helpers');

const { setupTests } = require('fixtures/GardenFixture');
const { impersonateAddress } = require('lib/rpc');

describe('Governor Babylon contract', function () {
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
  const votingPeriod = ONE_DAY_IN_SECONDS * 7;

  let voter1;
  let voter2;
  let voter3;
  let voter4;

  async function createProposal(proposer, target, value, encodedData, description) {
    const settings = {
      proposal: [[target], [value], [encodedData], description],
      proposer: proposer,
      tokenHolder: owner,
      voters: [
        { voter: voter1, support: voteType.For, reason: 'This is nice' },
        { voter: voter2, support: voteType.For },
        { voter: voter3, support: voteType.Against },
        { voter: voter4, support: voteType.Abstain },
      ],
    };
    return settings;
  }

  async function claimTokens(settings) {
    for (const voter of settings.voters) {
      console.log(voter.voter.address);
      await bablToken.connect(voter.voter).claimMyTokens();
    }
  }

  async function selfDelegation(settings) {
    for (const voter of settings.voters) {
      await bablToken.connect(voter.voter).delegate(voter.voter.address);
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

    voter1 = await impersonateAddress('0x3E7c4E57A1dc4dD4bBE81bEFBe3E437f69619DaB'); // 20K
    voter2 = await impersonateAddress('0x06601571AA9D3E8f5f7CDd5b993192618964bAB5'); // 15K
    voter3 = await impersonateAddress('0x83f4622A18e38bE297e089fB055Dd5123bb0b279'); // Team 24K
    voter4 = await impersonateAddress('0x232775eAD28F0C0c750A097bA77302E7d84efd3B'); // Team 17K
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
    it('hashProposal', async function () {
      const ABI = ['function enableBABLMiningProgram()'];
      const iface = new ethers.utils.Interface(ABI);
      const encodedData = iface.encodeFunctionData('enableBABLMiningProgram');
      const proposalDescription = EthCrypto.hash.keccak256([{ type: 'string', value: '<proposal description>' }]);
      const proposer = signer1;
      const settings = await createProposal(proposer, babController.address, value, encodedData, proposalDescription);
      const id = await governorBabylon.hashProposal(...settings.proposal);

      expect(id.toString()).to.equal('31592073516640214093428763406121273246927507816899979568469470593665780044126');
    });
    it.only('cannot propose below proposalThreshold', async function () {
      const ABI = ['function enableBABLMiningProgram()'];
      const iface = new ethers.utils.Interface(ABI);
      const encodedData = iface.encodeFunctionData('enableBABLMiningProgram');
      const proposer = signer1; // does not have enough BABL tokens
      let settings = await createProposal(
        proposer,
        babController.address,
        value,
        encodedData,
        '<proposal description>',
      );

      // propose
      await expect(
        governorBabylon
          .connect(settings.proposer)
          ['propose(address[],uint256[],bytes[],string)'](...settings.proposal)
      ).to.be.revertedWith('GovernorCompatibilityBravo: proposer votes below proposal threshold');
    });

    it.only('propose', async function () {
      const ABI = ['function enableBABLMiningProgram()'];
      const iface = new ethers.utils.Interface(ABI);
      const encodedData = iface.encodeFunctionData('enableBABLMiningProgram');
      // const proposer = await impersonateAddress('0x3E7c4E57A1dc4dD4bBE81bEFBe3E437f69619DaB');
      const proposer = owner;
      let settings = await createProposal(
        proposer,
        babController.address,
        value,
        encodedData,
        '<proposal description>',
      );

      await claimTokens(settings);
      console.log('owner babl', (await bablToken.balanceOf(owner.address)).toString());
      console.log('voter1 babl', (await bablToken.balanceOf(voter1.address)).toString());
      console.log('voter2 babl', (await bablToken.balanceOf(voter2.address)).toString());
      console.log('voter3 babl', (await bablToken.balanceOf(voter3.address)).toString());
      console.log('voter4 babl', (await bablToken.balanceOf(voter4.address)).toString());

      await selfDelegation(settings);

      // console.log(settings.proposer);
      console.log((await governorBabylon.proposalThreshold()).toString());
      await increaseTime(ONE_DAY_IN_SECONDS * 20);

      // propose
      await governorBabylon
        .connect(owner)
        ['propose(address[],uint256[],bytes[],string)'](...settings.proposal);

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
