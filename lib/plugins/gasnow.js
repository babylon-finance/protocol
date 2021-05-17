const { extendEnvironment } = require('hardhat/config');
const { getRapid } = require('../../lib/gasnow');

extendEnvironment((hre) => {
  hre.getRapid = async () => {
    const chainId = await hre.getChainId();
    if (chainId === '1') {
      return await getRapid();
    } else return 0;
  };
});
