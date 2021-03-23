const fs = require('fs');

function readArgumentsFile(contractName) {
  let args = [];
  try {
    const argsFile = `./args/${contractName}.args`;
    if (fs.existsSync(argsFile)) {
      args = JSON.parse(fs.readFileSync(argsFile));
    }
  } catch (e) {
    console.log(e);
  }

  return args;
}

module.exports = { readArgumentsFile };
