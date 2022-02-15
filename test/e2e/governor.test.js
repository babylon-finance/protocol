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
const { executeStrategy } = require('../fixtures/StrategyHelper');

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
      ],
      description: 'enable tokenTrasfers and miningProgram',
    });
  });
  it('can enable miningProgram and include all active strategies on it and they all get proportional rewards after finishing them', async function () {
    const deployer = await impersonateAddress('0x040cC3AF8455F3c34D1df1D2a305e047a062BeBf');
    const owner = await impersonateAddress('0xeA4E1d01Fad05465a84bAd319c93B73Fa12756fB');
    const governor = await ethers.getContractAt('BabylonGovernor', '0xBEC3de5b14902C660Bd2C7EfD2F259998424cc24');
    const token = await ethers.getContractAt('BABLToken', '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74');
    const keeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');

    const controller = await ethers.getContractAt('BabController', '0xd4a5b5fcb561daf3adf86f8477555b92fba43b5f', owner);
    await claimTokens(token, voters);

    const ishtarGate = await ethers.getContractAt('MardukGate', '0x77d200eca7fd0a3db27e96d7b24cf7613b0a2a12', owner);
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
    //
    // upgrade controller
    const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', owner);

    const controllerNewImpl = await deploy('BabController', {
      from: signer.address,
    });

    await proxyAdmin.upgrade(controller.address, controllerNewImpl.address);

    const mardukGate = await deploy('MardukGate', {
      from: signer.address,
      args: [controller.address, ishtarGate.address],
      log: true,
    });

    // edit marduk gate
    await controller.editMardukGate(mardukGate.address);

    // upgrade rewards distributor
    const distributorNewImpl = await deploy('RewardsDistributor', {
      from: signer.address,
    });

    await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address);

    // deploy new contracts
    for (const { contract, type, operation, args } of [
      {
        contract: 'ConvexStakeIntegration',
        type: 'integration',
        args: [controller.address],
      },
      {
        contract: 'CurvePoolIntegration',
        type: 'integration',
        args: [controller.address],
      },
      {
        contract: 'CurveTradeIntegration',
        type: 'integration',
        args: [controller.address],
      },
      {
        contract: 'SynthetixTradeIntegration',
        type: 'integration',
        args: [controller.address],
      },
      {
        contract: 'UniswapV2TradeIntegration',
        type: 'integration',
        args: [controller.address],
      },
      {
        contract: 'UniswapV3TradeIntegration',
        type: 'integration',
        args: [controller.address],
      },

      { contract: 'AddLiquidityOperation', type: 'operation', operation: 1, args: ['lp', controller.address] },
      { contract: 'DepositVaultOperation', type: 'operation', operation: 2, args: ['vault', controller.address] },
      { contract: 'LendOperation', type: 'operation', operation: 3, args: ['lend', controller.address] },
      { contract: 'BuyOperation', type: 'operation', operation: 0, args: ['buy', controller.address] },
    ]) {
      const deployment = await deploy(contract, {
        from: signer.address,
        args,
      });
      if (type === 'integration') {
      }
      if (type === 'operation') {
        await controller.setOperation(operation, deployment.address);
      }
    }

    // deploy MasterSwapper
    const masterSwapper = await deploy('MasterSwapper', {
      from: signer.address,
      args: [
        controller.address,
        (await deployments.get('CurveTradeIntegration')).address,
        (await deployments.get('UniswapV3TradeIntegration')).address,
        (await deployments.get('SynthetixTradeIntegration')).address,
        (await deployments.get('UniswapV2TradeIntegration')).address,
      ],
    });

    // deploy PriceOracle
    const priceOracle = await deploy('PriceOracle', {
      from: signer.address,
      args: [],
    });

    await controller.setMasterSwapper(masterSwapper.address);
    await controller.editPriceOracle(priceOracle.address);

    // upgrade strategy
    const strategyBeacon = await ethers.getContractAt(
      'UpgradeableBeacon',
      '0x31946680978CEFB010e5f5Fa8b8134c058cba7dC',
      deployer,
    );

    const strategyNewImpl = await deploy('Strategy', {
      from: signer.address,
      args: [],
      log: true,
    });

    await strategyBeacon.connect(deployer).upgradeTo(strategyNewImpl.address);

    // upgrade garden
    const gardenBeacon = await ethers.getContractAt(
      'UpgradeableBeacon',
      '0xc8f44C560efe396a6e57e48fF07205bD28AF5E75',
      deployer,
    );

    const gardenNewImpl = await deploy('Garden', {
      from: signer.address,
      args: [],
      log: true,
    });

    await gardenBeacon.connect(deployer).upgradeTo(gardenNewImpl.address);

    // We transfer ownership of BabController to TimelockController
    await controller.transferOwnership('0xe6Ed0eAcB79a6e457416E4df38ed778fd6C6D193');
    await runProposal(governor, {
      targets: [controller.address],
      values: [from(0)],
      calldatas: [],
      description: 'empty proposal',
    });

    const strategies = await controller.getLiveStrategies(50);

    // we only have 18 active strategies from 19 to 50 are empty (ADDRESS(0))
    await distributor.addLiveStrategies(strategies.slice(0, 18));
    await increaseTime(ONE_DAY_IN_SECONDS * 360);

    // We check that we can finalize strategies and all get rewards
    for (let i = 0; i < 18; i++) {
      const strategyContract = await ethers.getContractAt('IStrategy', strategies[i], owner);

      if (i !== 8) {
        // AVT Strategy i=8 has a problem finalizing possibly due to the rug pull
        await strategyContract.connect(keeper).finalizeStrategy(0, '', 0);
        expect(await strategyContract.strategyRewards()).to.be.gt(0);
      }
    }
  });
  it('check rebalanced strategies to fix', async function () {
    const owner = await impersonateAddress('0x0B892EbC6a4bF484CDDb7253c6BD5261490163b9');
    const timelockController = await impersonateAddress('0xe6ed0eacb79a6e457416e4df38ed778fd6c6d193');
    const keeper = await impersonateAddress('0x74D206186B84d4c2dAFeBD9Fd230878EC161d5B8');

    const controller = await ethers.getContractAt(
      'BabController',
      '0xd4a5b5fcb561daf3adf86f8477555b92fba43b5f',
      timelockController,
    );

    // upgrade controller
    const proxyAdmin = await ethers.getContractAt('ProxyAdmin', '0x0C085fd8bbFD78db0107bF17047E8fa906D871DC', owner);
    // Rebalanced strategies to fix
    const strategies = ['0xB60Aa37f42Fd45c6c3ed8DB0a89df1e07f70f1F5', '0xfdea6f30f3dadd60382baa07252923ff6007c35d'];
    const distributor = await ethers.getContractAt(
      'RewardsDistributor',
      '0x40154ad8014df019a53440a60ed351dfba47574e',
      owner,
    );
    const signers = await ethers.getSigners();
    const signer = signers[0];

    // upgrade rewards distributor
    const distributorNewImpl = await deploy('RewardsDistributor', {
      from: signer.address,
    });

    await proxyAdmin.upgrade(distributor.address, distributorNewImpl.address);

    // We check that we can finalize strategies and all get rewards
    for (let i = 0; i < strategies.length; i++) {
      const strategyContract = await ethers.getContractAt('IStrategy', strategies[i], owner);
      const [, miningBool] = await distributor.checkMining(1, strategies[i]);
      expect(miningBool[0]).to.equal(true);
      expect(miningBool[1]).to.equal(true);
      await strategyContract.connect(keeper).executeStrategy(eth(0.1), 0, {
        gasPrice: 0,
      });
      const [miningUint2] = await distributor.checkMining(1, strategies[i]);
      expect(miningUint2[3]).to.be.gt(0);
      expect(miningUint2[4]).to.be.gt(0);
      await increaseTime(ONE_DAY_IN_SECONDS * 60);
      await strategyContract.connect(keeper).finalizeStrategy(0, '', 0);
      expect(await strategyContract.strategyRewards()).to.be.gt(0);
    }
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
