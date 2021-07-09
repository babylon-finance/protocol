const { extendEnvironment } = require('hardhat/config');

const AdminUpgradeabilityProxy = require('@openzeppelin/upgrades-core/artifacts/contracts/proxy/AdminUpgradeabilityProxy.sol/AdminUpgradeabilityProxy.json');
const ProxyAdmin = require('@openzeppelin/upgrades-core/artifacts/contracts/proxy/ProxyAdmin.sol/ProxyAdmin.json');
const { assertUpgradeSafe, getVersion, getUnlinkedBytecode } = require('@openzeppelin/upgrades-core');
const { readValidations } = require('@openzeppelin/hardhat-upgrades/dist/validations');

let hreLocal;

const getSigner = async (address) => {
  const signers = await ethers.getSigners();
  return signers.find((signer) => signer.address === address);
};

const getInitializerData = (ImplFactory, args = [], initializer) => {
  if (initializer === false) {
    return '0x';
  }
  const allowNoInitialization = initializer === undefined && args.length === 0;
  initializer = initializer || 'initialize';

  try {
    const fragment = ImplFactory.interface.getFunction(initializer);
    return ImplFactory.interface.encodeFunctionData(fragment, args);
  } catch (e) {
    if (e instanceof Error) {
      if (allowNoInitialization && e.message.includes('no matching function')) {
        return '0x';
      }
    }
    throw e;
  }
};

const deployProxyAdmin = async (opts) => {
  const { deployments } = hreLocal;
  const { deploy } = deployments;
  return await deploy('ProxyAdmin', {
    ...opts,
    ...{
      contract: ProxyAdmin,
    },
  });
};

const deployAdminProxy = async (firstImplName, proxyName, opts, { initializer, postUpgrade, upgrades }) => {
  const { deployments } = hreLocal;
  const { deploy } = deployments;
  let proxyAdmin;
  try {
    proxyAdmin = await deployments.get('ProxyAdmin');
  } catch (error) {
    proxyAdmin = await deployProxyAdmin(opts);
  }
  const firstImpl = await deploy(firstImplName, opts);
  const initData = getInitializerData(
    await ethers.getContractFactory(firstImplName),
    initializer && initializer.args ? initializer.args : [],
    initializer ? initializer.method : false,
  );
  let proxy = await deployments.getOrNull(proxyName);
  if (!proxy) {
    proxy = await deploy(proxyName, {
      ...opts,
      ...{
        contract: AdminUpgradeabilityProxy,
        log: true,
        args: [firstImpl.address, proxyAdmin.address, initData],
      },
    });
  }
  return proxy;
};

const upgradeAdmin = async (proxyName, previousImplName, newImplName, postUpgrade, opts) => {
  const { deployments } = hreLocal;
  const { deploy } = deployments;
  const proxyAdmin = await deployments.get('ProxyAdmin');

  const proxy = await deployments.get(proxyName);

  if (previousImplName === newImplName) throw new Error("Same implementation, can't upgrade.");

  // validations
  console.log('TODO: Implement upgrade validations');

  const newImplFactory = await ethers.getContractFactory(newImplName);
  const validations = await readValidations(hreLocal);
  const unlinkedBytecode = getUnlinkedBytecode(validations, newImplFactory.bytecode);
  const version = getVersion(unlinkedBytecode, newImplFactory.bytecode);
  assertUpgradeSafe(validations, version, {
    unsafeAllowCustomTypes: false,
    unsafeAllowLinkedLibraries: false,
  });

  const signer = await getSigner(opts.from);
  const proxyAdminContract = await ethers.getContractAt(proxyAdmin.abi, proxyAdmin.address, signer);
  const previousImpl = await deployments.get(previousImplName);
  const actualImpl = await proxyAdminContract.getProxyImplementation(proxy.address);
  console.log(`Deploying new implementation ${newImplName}`);
  const newImpl = await deploy(newImplName, opts);
  if (newImpl.newlyDeployed) {
    if (actualImpl !== previousImpl.address) {
      throw new Error(`Proxy is actually pointing on: ${actualImpl}`);
    }
    console.log(`Upgrading from ${previousImplName} to ${newImplName}`);
    if (postUpgrade && postUpgrade.method && postUpgrade.args) {
      const upgradeData = getInitializerData(
        await ethers.getContractFactory(newImplName),
        postUpgrade.args,
        postUpgrade.method,
      );
      await proxyAdminContract.upgradeAndCall(proxy.address, newImpl.address, upgradeData);
    } else await proxyAdminContract.upgrade(proxy.address, newImpl.address);
  } else {
    throw new Error(`Implementation ${newImplName} is already deployed`);
  }
  return proxy;
};

const upgradeBeacon = async (beaconName, previousImplName, newImplName, postUpgrade, opts) => {
  const { deployments } = hreLocal;
  const { deploy } = deployments;

  const beacon = await deployments.get(beaconName);

  if (previousImplName === newImplName) throw new Error("Same implementation, can't upgrade.");

  // validations
  console.log('TODO: Implement upgrade validations');

  const newImplFactory = await ethers.getContractFactory(newImplName);
  const signer = await getSigner(opts.from);
  const beaconContract = await ethers.getContractAt(beacon.abi, beacon.address, signer);
  const previousImpl = await deployments.get(previousImplName);
  const actualImpl = await beaconContract.implementation();

  console.log(`Deploying new implementation ${newImplName}`);
  const newImpl = await deploy(newImplName, opts);
  if (newImpl.newlyDeployed) {
    if (actualImpl !== previousImpl.address) {
      throw new Error(`Beacon is actually pointing on: ${actualImpl}`);
    }
    console.log(`Upgrading from ${previousImplName} to ${newImplName}`);
    await beaconContract.upgradeTo(newImpl.address);
  } else {
    throw new Error(`Implementation ${newImplName} is already deployed`);
  }
  return beacon;
};

extendEnvironment((hre) => {
  hreLocal = hre;
  const { deployments } = hre;

  async function getContract(contractName, deploymentName, signer) {
    return await ethers.getContractAt(
      contractName,
      (
        await deployments.get(deploymentName || contractName)
      ).address,
      signer,
    );
  }

  hre.upgradesDeployer = {
    deployAdminProxy,
    upgradeAdmin,
    upgradeBeacon,
  };
  hre.getSigner = getSigner;
  hre.getContract = getContract;
});
