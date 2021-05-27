/*
    Copyright 2021 Babylon Finance

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.7.6;
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { SafeMath } from '@openzeppelin/contracts/math/SafeMath.sol';

import { IBabController } from '../../interfaces/IBabController.sol';
import { PreciseUnitMath } from '../../lib/PreciseUnitMath.sol';
import { PassiveIntegration } from './PassiveIntegration.sol';

import { IHarvestVault } from '../../interfaces/external/harvest/IVault.sol';

/**
 * @title HarvestIntegration
 * @author Babylon Finance Protocol
 *
 * Harvest v2 Vault Integration
 */
contract HarvestVaultIntegration is PassiveIntegration {
  using SafeMath for uint256;
  using PreciseUnitMath for uint256;

  /* ============ Modifiers ============ */

  /**
   * Throws if the sender is not the protocol
   */
  modifier onlyGovernance() {
    require(msg.sender == controller.owner(), 'Only governance can call this');
    _;
  }

  /* ============ State Variables ============ */

  mapping(address => address) public assetToVault;

  /* ============ Constructor ============ */

  /**
   * Creates the integration
   *
   * @param _controller                   Address of the controller
   * @param _weth                         Address of the WETH ERC20
   */
  constructor(IBabController _controller, address _weth) PassiveIntegration('harvestvaults', _weth, _controller) {
    // WETH
    assetToVault[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 0xFE09e53A81Fe2808bc493ea64319109B5bAa573e; // fWETH/WETH

    // Stablecoins
    assetToVault[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 0xab7FA2B2985BCcfC13c6D86b1D5A17486ab1e04C; // fDAI/DAI
    assetToVault[0x0000000000085d4780B73119b644AE5ecd22b376] = 0x7674622c63Bee7F46E86a4A5A18976693D54441b; // fTUSD/TUSD
    assetToVault[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 0x053c80eA73Dc6941F518a68E2FC52Ac45BDE7c9C; // fUSDT/USDT
    assetToVault[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE; // fUSDC/USDC
    assetToVault[0x4f3E8F405CF5aFC05D68142F3783bDfE13811522] = 0x683E683fBE6Cf9b635539712c999f3B3EdCB8664; // fusdn3CRV/usdn3CRV
    assetToVault[0x3B3Ac5386837Dc563660FB6a0937DFAa5924333B] = 0x4b1cBD6F6D8676AcE5E412C78B7a59b4A1bbb68a; // fyDAI+yUSDC+yUSDT+yBUSD/yDAI+yUSDC+yUSDT+yBUSD
    assetToVault[0x845838DF265Dcd2c412A1Dc9e959c7d08537f8a2] = 0x998cEb152A42a3EaC1f555B1E911642BeBf00faD; // fcDAI+cUSDC/cDAI+cUSDC
    assetToVault[0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490] = 0x71B9eC42bB3CB40F017D8AD8011BE8e384a95fa5; // f3Crv/3Crv
    assetToVault[0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8] = 0x0FE4283e0216F94f5f9750a7a11AC54D3c9C38F3; // fyDAI+yUSDC+yUSDT+yTUSD/yDAI+yUSDC+yUSDT+yTUSD
    assetToVault[0x5B5CFE992AdAC0C9D48E05854B2d91C73a003858] = 0x29780C39164Ebbd62e9DDDE50c151810070140f2; // fhusd3CRV/husd3CRV

    // BTC
    assetToVault[0xb19059ebb43466C323583928285a49f558E572Fd] = 0xCC775989e76ab386E9253df5B0c0b473E22102E2; // fhCRV/hCRV
    assetToVault[0x64eda51d3Ad40D56b9dFc5554E06F94e1Dd786Fd] = 0x640704D106E79e105FDA424f05467F005418F1B5; // ftbtc/sbtcCrv/tbtc/sbtcCrv
    assetToVault[0x49849C98ae39Fff122806C06791Fa73784FB3675] = 0x9aA8F427A17d6B0d91B6262989EdC7D45d6aEdf8; // crvRenWBTC/crvRenWBTC
    assetToVault[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599] = 0x5d9d25c7C457dD82fc8668FFC6B9746b674d4EcB; // fWBTC/WBTC
    assetToVault[0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D] = 0xC391d1b08c1403313B0c28D47202DFDA015633C4; // frenBTC/renBTC

    // Sushiswap
    assetToVault[0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f] = 0x203E97aa6eB65A1A02d9E80083414058303f241E; // fSLP-DAI:WETH
    assetToVault[0x397FF1542f962076d0BFE58eA045FfA2d347ACa0] = 0x01bd09A1124960d9bE04b638b142Df9DF942b04a; // fSLP-USDC:WETH
    assetToVault[0x06da0fd433C1A5d7a4faa01111c044910A184553] = 0x64035b583c8c694627A199243E863Bb33be60745; // fSLP-WETH:USDT
    assetToVault[0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58] = 0x5C0A3F55AAC52AA320Ff5F280E77517cbAF85524; // fSLP-WBTC:WETH
    assetToVault[0x2Dbc7dD86C6cd87b525BD54Ea73EBeeBbc307F68] = 0xF553E1f826f42716cDFe02bde5ee76b2a52fc7EB; // fSLP-WBTC:TBTC

    // Uniswap
    assetToVault[0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11] = 0x307E2752e8b8a9C29005001Be66B1c012CA9CDB7; // fUNI-DAI:WETH
    assetToVault[0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc] = 0xA79a083FDD87F73c2f983c5551EC974685D6bb36; // fUNI-USDC:WETH
    assetToVault[0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852] = 0x7DDc3ffF0612E75Ea5ddC0d6Bd4e268f70362Cff; // fUNI-WETH:USDT
    assetToVault[0xBb2b8038a1640196FbE3e38816F3e67Cba72D940] = 0x01112a60f427205dcA6E229425306923c3Cc2073; // fUNI-WBTC:WETH
    assetToVault[0x4d5ef58aAc27d99935E5b6B4A6778ff292059991] = 0x2a32dcBB121D48C106F6d94cf2B4714c0b4Dfe48; // fUNI-DPI:WETH
  }

  /* ============ External Functions ============ */

  // Governance function
  function updateVaultMapping(address _asset, address _vault) external onlyGovernance {
    assetToVault[_asset] = _vault;
  }

  /* ============ Internal Functions ============ */

  function _isInvestment(address _vault) internal view override returns (bool) {
    return IHarvestVault(_vault).underlying() != address(0);
  }

  function _getSpender(address _vault) internal view override returns (address) {
    return _vault;
  }

  function _getExpectedShares(address _vault, uint256 _amount) internal view override returns (uint256) {
    return _amount.preciseDiv(IHarvestVault(_vault).getPricePerFullShare());
  }

  function _getPricePerShare(address _vault) internal view override returns (uint256) {
    return IHarvestVault(_vault).getPricePerFullShare();
  }

  function _getInvestmentAsset(address _vault) internal view override returns (address) {
    return IHarvestVault(_vault).underlying();
  }

  /**
   * Return join investment calldata which is already generated from the investment API
   *
   * hparam  _strategy                       Address of the strategy
   * @param  _investmentAddress              Address of the vault
   * hparam  _investmentTokensOut            Amount of investment tokens to send
   * hparam  _tokenIn                        Addresses of tokens to send to the investment
   * @param  _maxAmountIn                    Amounts of tokens to send to the investment
   *
   * @return address                         Target contract address
   * @return uint256                         Call value
   * @return bytes                           Trade calldata
   */
  function _getEnterInvestmentCalldata(
    address, /* _strategy */
    address _investmentAddress,
    uint256, /* _investmentTokensOut */
    address, /* _tokenIn */
    uint256 _maxAmountIn
  )
    internal
    pure
    override
    returns (
      address,
      uint256,
      bytes memory
    )
  {
    // Encode method data for Garden to invoke
    bytes memory methodData = abi.encodeWithSignature('deposit(uint256)', _maxAmountIn);

    return (_investmentAddress, 0, methodData);
  }

  /**
   * Return exit investment calldata which is already generated from the investment API
   *
   * hparam  _strategy                       Address of the strategy
   * @param  _investmentAddress              Address of the investment
   * @param  _investmentTokensIn             Amount of investment tokens to receive
   * hparam  _tokenOut                       Addresses of tokens to receive
   * hparam  _minAmountOut                   Amounts of investment tokens to receive
   *
   * @return address                         Target contract address
   * @return uint256                         Call value
   * @return bytes                           Trade calldata
   */
  function _getExitInvestmentCalldata(
    address, /* _strategy */
    address _investmentAddress,
    uint256 _investmentTokensIn,
    address, /* _tokenOut */
    uint256 /* _minAmountOut */
  )
    internal
    pure
    override
    returns (
      address,
      uint256,
      bytes memory
    )
  {
    // Encode method data for Garden to invoke
    bytes memory methodData = abi.encodeWithSignature('withdraw(uint256)', _investmentTokensIn);

    return (_investmentAddress, 0, methodData);
  }
}
