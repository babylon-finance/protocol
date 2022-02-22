const { task } = require('hardhat/config');

task('vesting').setAction(async (args, { getContract, ethers, getGasPrice }, runSuper) => {
  const signers = await ethers.getSigners();
  const signer = signers[0];
  const timelock = await ethers.getContractAt('TimeLockRegistry', '0x009efacc05539b5d41c1bac30e01832726a3ca3c', signer);
  const bablToken = await ethers.getContractAt('BABLToken', '0xF4Dc48D260C93ad6a96c5Ce563E70CA578987c74', signer);
  const allocations = await timelock.getRegistrations();
  const team = [];
  const investors = [];
  /*  struct VestedToken {
        bool teamOrAdvisor;
        uint256 vestingBegin;
        uint256 vestingEnd;
        uint256 lastClaim;
  } */
  for (let i = 0; i < allocations.length; i++) {
    const value = await timelock.checkRegisteredDistribution(allocations[i]);
    const vestingRegisteredConditions = await timelock.tokenVested(allocations[i]);
    const vestingConditions = await bablToken.vestedToken(allocations[i]);
    // We check if claimed already or still claim pending
    const vestingBegin = value.eq(0) ? vestingConditions.vestingBegin : vestingRegisteredConditions.vestingBegin;
    // console.log('checking vesting of address', allocations[i].toString());

    if (vestingBegin.gt(0)) {
      // Active vesting (not cancelled)
      if (vestingConditions.teamOrAdvisor) {
        // Team tokens
        team[allocations[i]] = vestingBegin;
      } else {
        // Investors tokens
        investors[allocations[i]] = vestingBegin;
      }
    }
  }
  console.log('');
  console.log('Investors registrations');
  console.log('');
  for (const key in investors) {
    const date = new Date(investors[key] * 1000);
    console.log(' Investor address ' + key + ' started at ' + date);
  }
  console.log('');
  console.log('Team registrations');
  console.log('');
  for (const key in team) {
    const date = new Date(team[key] * 1000);
    console.log(' Team address ' + key + ' started at ' + date);
  }
});
