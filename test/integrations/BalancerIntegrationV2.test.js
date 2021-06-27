const { expect } = require('chai');
const { ethers } = require('hardhat');
const { setupTests } = require('../fixtures/GardenFixture');
const {
  DEFAULT_STRATEGY_PARAMS,
  createStrategy,
  executeStrategy,
  finalizeStrategy,
} = require('../fixtures/StrategyHelper');
const addresses = require('../../lib/addresses');
const { ADDRESS_ZERO, ONE_ETH } = require('../../lib/constants');

describe.only('BalancerV2IntegrationTest', function () {
  let balancerV2Integration;
  let babController;
  let signer1;
  let signer2;
  let signer3;
  let garden1;
  let admin: owner, creator: signer1, lp: signer2, relayer: signer3;
  let allTokens: TokenList;
  const authorizerAddress = '0xA331D84eC860Bf466b4CdCcFb4aC09a1B43F3aE6';

  /**

  type JoinPoolData = {
    poolId?: string;
    tokenAddresses?: string[];
    maxAmountsIn?: BigNumberish[];
    fromInternalBalance?: boolean;
    joinAmounts?: BigNumberish[];
    dueProtocolFeeAmounts?: BigNumberish[];
    fromRelayer?: boolean;
    signature?: boolean;
  };

  async function joinPool(data: JoinPoolData = {}): Promise<ContractTransaction> {
    const request = {
      assets: data.tokenAddresses ?? tokens.addresses,
      maxAmountsIn: data.maxAmountsIn ?? array(MAX_UINT256),
      fromInternalBalance: data.fromInternalBalance ?? false,
      userData: encodeJoin(data.joinAmounts ?? joinAmounts, data.dueProtocolFeeAmounts ?? DUE_PROTOCOL_FEE_AMOUNTS),
    };

    const args = [data.poolId ?? poolId, lp.address, ZERO_ADDRESS, request];
    let calldata = balancerV2Integration.interface.encodeFunctionData('joinPool', args);

    if (data.signature) {
      const nonce = await vault.getNextNonce(lp.address);
      const signature = await signJoinAuthorization(balancerV2Integration, lp, relayer, calldata, nonce, MAX_UINT256);
      calldata = encodeCalldataAuthorization(calldata, MAX_UINT256, signature);
    }

    // Hardcoding a gas limit prevents (slow) gas estimation
    return (data.fromRelayer ? relayer : lp).sendTransaction({
      to: balancerV2Integration.address,
      data: calldata,
      gasLimit: MAX_GAS_LIMIT,
    });
  }
 */

  before(async () => {
    [, admin, creator, lp, relayer] = await ethers.getSigners();
  });

  beforeEach(async () => {
    ({ balancerV2Integration, babController, garden1, signer1, signer2, signer3 } = await setupTests()());
  });

  describe('Balancer V2 Pool Integration Deployment', function () {
    it('should successfully deploy the contract V2', async function () {
      const deployed = await babController.deployed();
      const deployedBalancer = await balancerV2Integration.deployed();
      expect(!!deployed).to.equal(true);
      expect(!!deployedBalancer).to.equal(true);
    });
  });
  describe.only('Vault Authorizer', () => {

  });
});
