const { extendEnvironment } = require('hardhat/config');
const { getRapid } = require('../../lib/gasnow');

extendEnvironment((hre) => {
  hre.getRapid = getRapid;
});
