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

const deployProxyAdmin = async (owner) => {
  const { deployments } = hreLocal;
  const { deploy } = deployments;
  return await deploy('ProxyAdmin', {
    contract: ProxyAdmin,
    from: owner,
    log: true,
  });
};

const deployOrUpgrade = async (firstImplName, opts, { initializer, postUpgrade, upgrades }) => {
  const { deployments } = hreLocal;
  const { deploy } = deployments;
  let proxyAdmin;
  try {
    proxyAdmin = await deployments.get('ProxyAdmin');
  } catch (error) {
    proxyAdmin = await deployProxyAdmin(opts.from);
  }
  const proxyName = `${firstImplName}Proxy`;
  const firstImpl = await deploy(firstImplName, opts);
  const initData = getInitializerData(
    await ethers.getContractFactory(firstImplName),
    initializer && initializer.args ? initializer.args : [],
    initializer ? initializer.method : false,
  );
  const proxy = await deploy(proxyName, {
    contract: AdminUpgradeabilityProxy,
    from: opts.from,
    log: true,
    args: [firstImpl.address, proxyAdmin.address, initData],
  });

  if (upgrades && upgrades.length > 0) {
    let previousImplName, newImplName;
    if (upgrades.length === 1) {
      previousImplName = firstImplName;
      newImplName = upgrades[0];
    } else {
      newImplName = upgrades.pop();
      previousImplName = upgrades.pop();
      for (const oldUpgrade in upgrades) {
        // unsure previous upgrades exists
        await deployments.get(upgrades[oldUpgrade]);
      }
    }
    if (previousImplName === newImplName) throw new Error("Same implementation, can't upgrade.");
    const newImplFactory = await ethers.getContractFactory(newImplName);
    const validations = await readValidations(hreLocal);
    const unlinkedBytecode = getUnlinkedBytecode(validations, newImplFactory.bytecode);
    const version = getVersion(unlinkedBytecode, newImplFactory.bytecode);
    console.log('assertUpgradeSafe');
    assertUpgradeSafe(validations, version, {
      unsafeAllowCustomTypes: false,
      unsafeAllowLinkedLibraries: false,
    });

    console.log('before signer');
    const signer = await getSigner(opts.from);
    console.log('from', opts.from, signer.address);
    const proxyAdminContract = await ethers.getContractAt(proxyAdmin.abi, proxyAdmin.address, signer);
    const previousImpl = await deployments.get(previousImplName);
    const actualImpl = await proxyAdminContract.getProxyImplementation(proxy.address);
    const newImpl = await deploy(newImplName, {
      from: opts.from,
      log: true,
    });
    if (newImpl.newlyDeployed)
      if (actualImpl === previousImpl.address) {
        console.log(`Upgrading from ${previousImplName} to ${newImplName}`);
        if (postUpgrade && postUpgrade.method && postUpgrade.args) {
          const upgradeData = getInitializerData(
            await ethers.getContractFactory(newImplName),
            postUpgrade.args,
            postUpgrade.method,
          );
          await proxyAdminContract.upgradeAndCall(proxy.address, newImpl.address, upgradeData);
        } else await proxyAdminContract.upgrade(proxy.address, newImpl.address);
      } else throw new Error(`Proxy is actually pointing on: ${actualImpl}`);
  }
  return proxy;
};

extendEnvironment((hre) => {
  hreLocal = hre;
  hre.upgrades = {
    deployOrUpgrade,
  };
  hre.getSigner = getSigner;
});
