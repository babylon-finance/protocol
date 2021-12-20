const { extendEnvironment } = require('hardhat/config');

const AdminUpgradeabilityProxy = require('@openzeppelin/upgrades-core/artifacts/contracts/proxy/AdminUpgradeabilityProxy.sol/AdminUpgradeabilityProxy.json');
const ProxyAdmin = require('@openzeppelin/upgrades-core/artifacts/contracts/proxy/ProxyAdmin.sol/ProxyAdmin.json');
const { assertUpgradeSafe, getVersion, getUnlinkedBytecode } = require('@openzeppelin/upgrades-core');
const { readValidations } = require('@openzeppelin/hardhat-upgrades/dist/validations');

const DEPLOY_ONLY = process.env.DEPLOY_ONLY;
const UPGRADE_ONLY = process.env.UPGRADE_ONLY;
const NONCE = +process.env.NONCE;

let hreLocal;

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
  let newImpl;
  if (!UPGRADE_ONLY) {
    newImpl = await deploy(newImplName, { ...opts, nonce: NONCE });
    console.log(`Deploying new implementation ${newImplName}`);
  } else {
    newImpl = await deployments.get(newImplName);
  }
  if (!DEPLOY_ONLY) {
    if (newImpl.newlyDeployed || UPGRADE_ONLY) {
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
        await proxyAdminContract.upgradeAndCall(proxy.address, newImpl.address, upgradeData, {
          gasPrice: opts.gasPrice,
        });
      } else {
        const tx = await proxyAdminContract.upgrade(proxy.address, newImpl.address, { gasPrice: opts.gasPrice });
        console.log(`Tx hash ${tx.hash}`);
        await tx.wait();
      }
    } else {
      throw new Error(`Implementation ${newImplName} is already deployed`);
    }
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

  const signer = await getSigner(opts.from);
  const beaconContract = await ethers.getContractAt(beacon.abi, beacon.address, signer);
  const previousImpl = await deployments.get(previousImplName);
  const actualImpl = await beaconContract.implementation();

  let newImpl;
  if (!UPGRADE_ONLY) {
    newImpl = await deploy(newImplName, { ...opts, nonce: NONCE });
    console.log(`Deploying new implementation ${newImplName}`);
  } else {
    newImpl = await deployments.get(newImplName);
  }
  if (!DEPLOY_ONLY) {
    if (newImpl.newlyDeployed || UPGRADE_ONLY) {
      if (actualImpl !== previousImpl.address) {
        throw new Error(`Beacon is actually pointing on: ${actualImpl}`);
      }
      console.log(`Upgrading from ${previousImplName} to ${newImplName}`);
      const tx = await beaconContract.upgradeTo(newImpl.address, { gasPrice: opts.gasPrice });
      console.log(`Tx hash ${tx.hash}`);
      await tx.wait();
    } else {
      throw new Error(`Implementation ${newImplName} is already deployed`);
    }
  }
  return beacon;
};

extendEnvironment((hre) => {
  hreLocal = hre;
  const { deployments } = hre;

  hre.upgradesDeployer = {
    deployAdminProxy,
    upgradeAdmin,
    upgradeBeacon,
  };
});
