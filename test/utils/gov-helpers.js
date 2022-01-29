const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ADDRESS_ZERO, ONE_DAY_IN_SECONDS } = require('lib/constants');
const { from, eth, parse } = require('lib/helpers');
const { increaseTime, increaseBlock, voteType, proposalState } = require('utils/test-helpers');

const { impersonateAddress } = require('lib/rpc');

export async function getVoters() {
  return [
    await impersonateAddress('0x3E7c4E57A1dc4dD4bBE81bEFBe3E437f69619DaB'), // 20K
    await impersonateAddress('0x06601571AA9D3E8f5f7CDd5b993192618964bAB5'), // 15K
    await impersonateAddress('0x83f4622A18e38bE297e089fB055Dd5123bb0b279'), // Team 24K
    await impersonateAddress('0x232775eAD28F0C0c750A097bA77302E7d84efd3B'), // Team 17K
  ];
}

// period and delay is in blocks
export async function getGovernorMock(bablToken, signer, period = 1, delay = 1) {
  // We deploy a mock contract with a custom period and delay
  const timelockFactory = await ethers.getContractFactory('TimelockController');
  const timelock = await timelockFactory.deploy(ONE_DAY_IN_SECONDS, [], []);

  const mockFactory = await ethers.getContractFactory('BabylonGovernorMock');
  const governor = await mockFactory.deploy(bablToken.address, timelock.address, delay, period);

  await timelock.connect(signer).grantRole(await timelock.PROPOSER_ROLE(), governor.address);
  await timelock.connect(signer).grantRole(await timelock.EXECUTOR_ROLE(), governor.address);

  return governor;
}

export async function selfDelegation(bablToken, voters) {
  for (const voter of voters) {
    await bablToken.connect(voter).delegate(voter.address, { gasPrice: 0 });
  }
}

export async function castVotes(id, votes, governor) {
  for (const vote of votes) {
    await governor.connect(vote.voter).castVote(id, from(vote.support), { gasPrice: 0 });
  }
}

export async function claimTokens(bablToken, voters) {
  for (const voter of voters) {
    if ((await bablToken.balanceOf(voter.address)).toString() === '0') {
      // We avoid 'not registered user error' for users that already claimed their tokens
      await bablToken.connect(voter).claimMyTokens({ gasPrice: 0 });
    }
    await bablToken.connect(voter).delegate(voter.address, { gasPrice: 0 });
  }
}

export async function getProposal(
  governor,
  { targets, values, calldatas, description } = {
    targets: [ADDRESS_ZERO],
    values: [from(0)],
    calldatas: ['0x'],
    description: '<proposal description>',
  },
) {
  const descriptionHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(description));

  const id = await governor.hashProposal(targets, values, calldatas, descriptionHash, { gasPrice: 0 });

  return {
    id,
    args: [targets, values, calldatas, description],
  };
}
