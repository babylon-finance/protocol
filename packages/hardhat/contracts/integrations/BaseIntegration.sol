/*
    Copyright 2020 DFolio.

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

pragma solidity 0.7.4;

import "hardhat/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFolioController } from "../interfaces/IFolioController.sol";
import { IIntegration } from "../interfaces/IIntegration.sol";
import { IWETH } from "../interfaces/external/weth/IWETH.sol";
import { IFund } from "../interfaces/IFund.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { PreciseUnitMath } from "../lib/PreciseUnitMath.sol";

/**
 * @title BaseIntegration
 * @author DFolio
 *
 * Abstract class that houses common Integration-related state and functions.
 */
abstract contract BaseIntegration {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;

    /* ============ Modifiers ============ */

    /**
     * Throws if the sender is not the protocol
     */
    modifier onlyProtocol() {
      require(msg.sender == controller, "Only controller can call this");
      _;
    }

    modifier onlyFund() {
      require(isFundValidAndInitialized(msg.sender), "Only a fund can call this");
      require(initializedByFund[msg.sender], "integration has already been initialized");
      _;
    }


    /* ============ State Variables ============ */

    address constant USDCAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDTAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WBTCAddress = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // Address of the controller
    address public controller;
    // Wrapped ETH address
    address public immutable weth;
    // Name of the integration
    string public name;
    mapping(address => bool) public initializedByFund;
    bool initialized;
    // Mapping of asset addresses to cToken addresses
    mapping(address => address) public assetToCtoken;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     */

    constructor(string memory _name, address _weth, address _controller) {
      require(_controller != address(0), "Controller must be non-zero address.");
      name = _name;
      controller = _controller;
      weth = _weth;
      initialized = false;
      assetToCtoken[0x6B175474E89094C44Da98b954EedeAC495271d0F] = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643; // DAI
      assetToCtoken[0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5; // WETH
      assetToCtoken[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 0x39AA39c021dfbaE8faC545936693aC917d5E7563; // USDC
      assetToCtoken[0xdAC17F958D2ee523a2206206994597C13D831ec7] = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9; // USDT
      assetToCtoken[0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599] = 0xC11b1268C1A384e55C48c2391d8d480264A3A7F4; // WBTC
      assetToCtoken[0xc00e94Cb662C3520282E6f5717214004A7f26888] = 0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4; // COMP
    }

    /* ============ External Functions ============ */

    /**
     * Initializes the integration.
     * @param _fund addres of the fund
     */
    function initialize(address _fund) onlyProtocol external {
      require(!initializedByFund[_fund], "integration has already been initialized");
      IFund(_fund).initializeIntegration();
      initializedByFund[_fund] = true;
    }

    /**
     * Returns the name of the integration
     */
    function getName() external view returns (string memory) {
      return name;
    }

    // TODO: Move this to protocol
    // Governance function
    function updateCTokenMapping(address _assetAddress, address _cTokenAddress) external onlyProtocol {
      assetToCtoken[_assetAddress] = _cTokenAddress;
    }

    /* ============ Internal Functions ============ */


    /**
     * Updates the position in the fund with the new units
     *
     * @param _fund                     Address of the fund
     * @param _component                Address of the ERC20
     * @param _newTotal                 New unit of the fund position
     */
    function updateFundPosition(address _fund, address _component, uint256 _newTotal) internal {
      IFund(_fund).calculateAndEditPosition(_component, _newTotal);
    }

    /**
     * Transfers tokens from an address (that has set allowance on the module).
     *
     * @param  _token          The address of the ERC20 token
     * @param  _from           The address to transfer from
     * @param  _to             The address to transfer to
     * @param  _quantity       The number of tokens to transfer
     */
    function transferFrom(IERC20 _token, address _from, address _to, uint256 _quantity) internal {
        IERC20(_token).transferFrom(_from, _to, _quantity);
    }

    /**
     * Gets the total fee for this integration of the passed in index (fee % * quantity)
     */
    function getIntegrationFee(uint256 _feeIndex, uint256 _quantity) internal view returns(uint256) {
        uint256 feePercentage = IFolioController(controller).getIntegrationFee(address(this));
        return _quantity.preciseMul(feePercentage);
    }

    /**
     * Pays the _feeQuantity from the _setToken denominated in _token to the protocol fee recipient
     */
    function payProtocolFeeFromFund(address _fund, address _token, uint256 _feeQuantity) internal {
        if (_feeQuantity > 0) {
          IERC20(_token).transferFrom(_fund, IFolioController(controller).getFeeRecipient(), _feeQuantity);
        }
    }

    /**
     * Returns true if the integration is in process of initialization on the fund
     */
    function isFundPendingInitialization(address _fund) internal view returns(bool) {
        return IFund(_fund).isPendingIntegration(address(this));
    }

    /**
     * Returns true if the address is the Fund's manager
     */
    function isFundManager(address _fund, address _toCheck) internal view returns(bool) {
        return IFund(_fund).manager() == _toCheck;
    }

    /**
     * Returns true if Fund must be enabled on the controller
     * and module is registered on the Fund
     */
    function isFundValidAndInitialized(address _fund) internal view returns(bool) {
        return IFolioController(controller).isFund(address(_fund)) &&
            IFund(_fund).isInitializedIntegration(address(this));
    }

    /**
      Normalize all the amounts of all tokens so all can be called with 10^18.
      e.g Call functions like borrow, supply with parseEther
    */
    function normalizeDecimals(address asset, uint256 amount) internal view returns (uint256)  {
      // USDC and USDT have only 6 decimals
      // TODO: create a mpping for decimals managed by the protocol
      uint256 newAmount = amount;
      if (asset == USDCAddress || asset == USDTAddress) {
        newAmount = amount.div(10**12);
      }
      // WBTC has 8 decimals
      if (asset == WBTCAddress) {
        newAmount = amount.div(10**10);
      }
      return newAmount;
    }

}
