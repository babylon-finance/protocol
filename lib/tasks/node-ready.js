const { TASK_NODE_SERVER_READY } = require('hardhat/builtin-tasks/task-names');

const { subtask } = require('hardhat/config');
const { setup } = require('../scripts/setup');

subtask(TASK_NODE_SERVER_READY).setAction(async (args, hre, runSuper) => {
  await runSuper(args);
  // initialize dApp
  setup(hre);
  // export abi and bytecode
  hre.run('export', { ...args, export: 'contracts.json', network: 'hardhat' });
});
