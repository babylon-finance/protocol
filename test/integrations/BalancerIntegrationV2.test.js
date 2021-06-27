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
    it('has an initial authorizer', async () => {
      //const vault = await deployVault(authorizer.address);
      const authorizer = await balancerV2Integration.getAuthorizer();
      console.log('Authorizer', authorizer);

      expect(await vault.getAuthorizer()).to.equal(authorizer.address);
    });
  });
  
  describe.only('Liquidity pools', () => {
    it('get pool id', async () => {
      const { balances: previousPoolBalances } = await balancerV2Integration.getPoolTokens(poolId);
      console.log('balances before', balances.toString());
      await joinPool({ dueProtocolFeeAmounts, fromRelayer, fromInternalBalance, signature });
      const { balances: currentPoolBalances } = await balancerV2Integration.getPoolTokens(poolId);
      console.log('balances after', balances.toString());
  });
  /**
    it('assigns tokens to the pool', async () => {
        const { balances: previousPoolBalances } = await balancerV2Integration.getPoolTokens(poolId);
        console.log('balances before', balances.toString());
        await joinPool({ dueProtocolFeeAmounts, fromRelayer, fromInternalBalance, signature });
        const { balances: currentPoolBalances } = await balancerV2Integration.getPoolTokens(poolId);
        console.log('balances after', balances.toString());
    }); */
  });
/**
  describe('Liquidity Pools', function () {
    let daiWethPool;

    beforeEach(async () => {
      daiWethPool = await ethers.getContractAt('IBPool', addresses.balancer.pools.wethdai);
    });

    it('check that a valid pool is valid', async function () {
      expect(await balancerIntegration.isPool(addresses.balancer.pools.wethdai)).to.equal(true);
    });

    it('check that an invalid pool is not valid', async function () {
      expect(await balancerIntegration.isPool(ADDRESS_ZERO)).to.equal(false);
    });

    it('can enter and exit the weth dai pool', async function () {
      const strategyContract = await createStrategy(
        'lp',
        'vote',
        [signer1, signer2, signer3],
        balancerIntegration.address,
        garden1,
        DEFAULT_STRATEGY_PARAMS,
        addresses.balancer.pools.wethdai,
      );
      await executeStrategy(strategyContract);
      expect(await strategyContract.capitalAllocated()).to.equal(ONE_ETH);
      expect(await daiWethPool.balanceOf(strategyContract.address)).to.be.gt(0);

      await finalizeStrategy(strategyContract, 0);
      expect(await daiWethPool.balanceOf(strategyContract.address)).to.equal(0);
    });
  });
   */
});
