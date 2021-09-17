module.exports = async ({
  network,
  getTenderlyContract,
  tenderly,
  getNamedAccounts,
  deployments,
  ethers,
  getRapid,
  getController,
}) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await getSigner(deployer);
  const gasPrice = await getRapid();
  const contract = 'IshtarGate';

  const controller = await getController();

  const deployment = await deploy(contract, {
    from: deployer,
    args: [controller.address, 'https://babylon.mypinata.cloud/ipfs/QmTTcF8a1asL9YKsCB5DzND1Biy4Kyw4nX7EPSgv1pLEDA'],
    log: true,
    gasPrice,
  });

  if (deployment.newlyDeployed) {
    console.log(`Setting ishtar gate on controller ${deployment.address}`);
    await (await controller.editIshtarGate(deployment.address, { gasPrice })).wait();

    const ishtarGate = await ethers.getContractAt('IshtarGate', deployment.address, signer);
    for (const address of [
      '0x83f4622A18e38bE297e089fB055Dd5123bb0b279',
      '0x21584Cc5a52102AbB381286a5119E3be08431CfD',
      '0x232775eAD28F0C0c750A097bA77302E7d84efd3B',
      '0x908295e2be3a36021aadaaed0bbb124fd602cbf2',
      '0xFBbA8ceA4e9835B9f304d6E69905cD9403F2b606',
      '0x1C4aD6087B14e69a4f8ae378ccEF1DF2A46c671f',
      '0x1e78164019779F11030e602c02714945a33bA3D5',
      '0x766e4D47A35d7Ffcc7F4E12ac338697f3e94392B',
      '0x48d21Dc6BBF18288520E9384aA505015c26ea43C',
    ]) {
      console.log(`Setting creator permission for ${address}`);
      await (await ishtarGate.setCreatorPermissions(address, true, { gasPrice })).wait();
    }
  }

  if (network.live && deployment.newlyDeployed) {
    await tenderly.push(await getTenderlyContract(contract));
  }
};

module.exports.tags = ['Gate'];
