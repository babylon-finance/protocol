const { expect } = require('chai');
const { ethers, deployments } = require('hardhat');

const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { fund } = require('lib/whale');
const addresses = require('lib/addresses');
const { deploy } = deployments;

const { increaseTime, increaseBlock, voteType, proposalState } = require('utils/test-helpers');
const { getVoters, getGovernorMock, getProposal, castVotes, claimTokens } = require('utils/gov-helpers');

const { setupTests } = require('fixtures/GardenFixture');
const { impersonateAddress } = require('lib/rpc');
const { finalizeStrategy, finalizeStrategyImmediate } = require('fixtures/StrategyHelper');

describe('governor', function () {
  let deployer;
  let owner;
  let signer1;
  let signer2;
  let signer3;
  let bablToken;
  let babGovernor;
  let timelockController;
  let babController;
  let voters;
  let PROPOSER_ROLE;
  let EXECUTOR_ROLE;
  let dai;

  const votingPeriod = ONE_DAY_IN_SECONDS * 7;

  async function voteProposal(governor, { targets, values, calldatas, description }) {
    const { id, args } = await getProposal(governor, {
      targets,
      values,
      calldatas,
      description,
    });

    // propose
    await governor.connect(voters[0])['propose(address[],uint256[],bytes[],string)'](...args, { gasPrice: 0 });

    // mine blocks to reach the block where the voting starts
    await increaseBlock(await governor.votingDelay());

    const votes = voters.map((vot) => ({ voter: vot, support: voteType.For }));
    await castVotes(id, votes, governor);

    // this is super slow but hardhat doesn't allow mine multiple blocks right
    // now should be fixed once this functionality avaiable
    // mine blocks to skip voting period
    await increaseBlock((await governor.votingPeriod()).add(1));

    const [, , eta, , , forVotes, againstVotes, abstainVotes, , ,] = await governor.proposals(id);
    return { id };
  }

  async function failProposal(governor, { targets, values, calldatas, description }) {
    const { id } = await voteProposal(governor, { targets, values, calldatas, description });

    await expect(governor.connect(deployer)['queue(uint256)'](id)).to.be.rejectedWith(
      /VM Exception while processing transaction: reverted with reason string 'AccessControl/,
    );
  }

  async function runProposal(governor, { targets, values, calldatas, description }) {
    const { id } = await voteProposal(governor, { targets, values, calldatas, description });

    await governor.connect(deployer)['queue(uint256)'](id);

    await increaseTime(ONE_DAY_IN_SECONDS);

    await governor.connect(deployer)['execute(uint256)'](id);

    const state = await governor.state(id);
    expect(state).to.eq(proposalState.Executed);
  }

  beforeEach(async () => {
    ({
      deployer,
      owner,
      signer1,
      signer2,
      signer3,
      bablToken,
      babGovernor,
      timelockController,
      babController,
      dai,
    } = await setupTests()());
    voters = await getVoters();
    await claimTokens(bablToken, voters);

    PROPOSER_ROLE = await timelockController.PROPOSER_ROLE();
    EXECUTOR_ROLE = await timelockController.EXECUTOR_ROLE();
  });

  it('can enableTokensTransfers and miningProgram', async function () {
    await runProposal(babGovernor, {
      targets: [bablToken.address, babController.address],
      values: [from(0), from(0)],
      calldatas: [
        new ethers.utils.Interface(['function enableTokensTransfers()']).encodeFunctionData('enableTokensTransfers'),
        new ethers.utils.Interface(['function enableBABLMiningProgram()']).encodeFunctionData(
          'enableBABLMiningProgram',
        ),
      ],
      description: 'enable tokenTrasfers and miningProgram',
    });
  });
  it.only('can enable miningProgram and include all active strategies on it', async function () {
    const deployer = await impersonateAddress('0x040cC3AF8455F3c34D1df1D2a305e047a062BeBf');
    const owner = await impersonateAddress('0xeA4E1d01Fad05465a84bAd319c93B73Fa12756fB');
    const governor = await ethers.getContractAt('BabylonGovernor', '0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24');
    const token = await ethers.getContractAt('BABLToken', '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74');
    const keeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');

    const controller = await ethers.getContractAt('BabController', '0xd4a5b5fcb561daf3adf86f8477555b92fba43b5f', owner);
    await claimTokens(token, voters);

    const distributor = await ethers.getContractAt(
      'RewardsDistributor',
      '0x40154ad8014df019a53440a60ed351dfba47574e',
      owner,
    );
    await fund([owner.address, deployer.address], {
      tokens: [addresses.tokens.ETH],
    });

    const signers = await ethers.getSigners();
    const signer = signers[0];
    // upgrade controller
    const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', owner);
    const controllerNewImpl = await deploy('BabController', {
      from: signer.address,
    });
    await proxyAdmin.upgrade(controller.address, controllerNewImpl.address);

    // upgrade rewards distributor
    const distributorNewImpl = await deploy('RewardsDistributor', {
      from: signer.address,
    });

    await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address);

    // We transfer ownership of BabController to TimelockController
    await controller.transferOwnership('0xe6Ed0eAcB79a6e457416E4df38ed778fd6C6D193');
    await runProposal(governor, {
      targets: [controller.address],
      values: [from(0)],
      calldatas: [
        new ethers.utils.Interface(['function enableBABLMiningProgram()']).encodeFunctionData(
          'enableBABLMiningProgram',
        ),
      ],
      description: 'enable miningProgram',
    });
    const strategies = await controller.getLiveStrategies(50);

    for (let i = 0; i < strategies.length; i++) {
      console.log('strategies governor', i, strategies[i]);
    }
    // from 19 to 50 are empty (ADDRESS(0))
    await distributor.addLiveStrategies(strategies.slice(0, 18));
    increaseTime(ONE_DAY_IN_SECONDS * 30);
    // We check that we can finalize strategies and all get rewards
    /* for (let i = 0; i < 18; i++) {
      console.log('finalized strategy i', i, strategies[i]);
      const strategyContract = await ethers.getContractAt('IStrategy', strategies[i], owner);

      console.log('---check---1');
      await strategyContract.connect(keeper).finalizeStrategy(0, '');
      // expect(await strategy.strategyRewards()).to.be.gt(0);
    } */
  });

  it('can upgrade Governor to a new one', async function () {
    // create new governor
    const mockFactory = await ethers.getContractFactory('BabylonGovernorMock');
    const newGovernor = await mockFactory.deploy(bablToken.address, timelockController.address, 1, 10);

    // 0 grant new gov access
    // 1 remove old gov access
    await runProposal(babGovernor, {
      targets: [
        timelockController.address,
        timelockController.address,
        timelockController.address,
        timelockController.address,
      ],
      values: [from(0), from(0), from(0), from(0)],
      calldatas: [
        new ethers.utils.Interface([
          'function grantRole(bytes32 role, address account)',
        ]).encodeFunctionData('grantRole', [PROPOSER_ROLE, newGovernor.address]),
        new ethers.utils.Interface([
          'function grantRole(bytes32 role, address account)',
        ]).encodeFunctionData('grantRole', [EXECUTOR_ROLE, newGovernor.address]),
        new ethers.utils.Interface([
          'function revokeRole(bytes32 role, address account)',
        ]).encodeFunctionData('revokeRole', [PROPOSER_ROLE, babGovernor.address]),
        new ethers.utils.Interface([
          'function revokeRole(bytes32 role, address account)',
        ]).encodeFunctionData('revokeRole', [EXECUTOR_ROLE, babGovernor.address]),
      ],
      description: 'upgrade Governor to a new one',
    });

    // new gov can execute a proposal
    await runProposal(newGovernor, {
      targets: [ADDRESS_ZERO],
      values: [from(0)],
      calldatas: ['0x'],
      description: 'empty',
    });

    // old gov can NOT execute a proposal
    await failProposal(babGovernor, {
      targets: [ADDRESS_ZERO],
      values: [from(0)],
      calldatas: ['0x'],
      description: 'empty',
    });
  });

  it('can update timelock in the Governor', async function () {
    // create new governor
    const mockFactory = await ethers.getContractFactory('BabylonGovernorMock');
    const newGovernor = await mockFactory.deploy(bablToken.address, timelockController.address, 1, 10);
    // Speed up grantRole to new governor at current timelockcontroller (avoid being part of a proposal)
    await timelockController.connect(owner).grantRole(PROPOSER_ROLE, newGovernor.address);
    await timelockController.connect(owner).grantRole(EXECUTOR_ROLE, newGovernor.address);

    // create new timelockcontroller
    const timelockFactory = await ethers.getContractFactory('TimelockController');
    const newTimelock = await timelockFactory.deploy(ONE_DAY_IN_SECONDS, [babGovernor.address], [babGovernor.address]);

    expect(await newGovernor.timelock()).to.equal(timelockController.address);
    await runProposal(newGovernor, {
      targets: [newGovernor.address],
      values: [from(0)],
      calldatas: [
        new ethers.utils.Interface([
          'function updateTimelock(address newTimelock)',
        ]).encodeFunctionData('updateTimelock', [newTimelock.address]),
      ],
      description: 'update timelockcontroller to a new one',
    });
    expect(await newGovernor.timelock()).to.equal(newTimelock.address);
  });

  it('can own treasury and transfer funds out', async function () {
    const governor = await ethers.getContractAt('BabylonGovernor', '0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24');

    const deployer = await impersonateAddress('0x040cC3AF8455F3c34D1df1D2a305e047a062BeBf');
    const treasury = await ethers.getContractAt('Treasury', '0xD7AAf4676F0F52993cb33aD36784BF970f0E1259');
    await treasury.connect(deployer).transferOwnership('0xe6Ed0eAcB79a6e457416E4df38ed778fd6C6D193');

    const token = await ethers.getContractAt('BABLToken', '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74');

    for (const voter of voters) {
      if (!(await token.balanceOf(voter.address)).gt(0)) {
        await token.connect(voter).claimMyTokens({ gasPrice: 0 });
      }
      await token.connect(voter).delegate(voter.address, { gasPrice: 0 });
    }

    await runProposal(governor, {
      targets: [treasury.address],
      values: [from(0)],
      calldatas: [
        new ethers.utils.Interface([
          'function sendTreasuryFunds(address _asset, uint256 _amount, address _to)',
        ]).encodeFunctionData('sendTreasuryFunds', [dai.address, eth(100), signer1.address]),
      ],
      description: 'Transfer some DAI',
    });

    expect(await dai.balanceOf(signer1.address)).to.eq(eth(100));
  });
});
