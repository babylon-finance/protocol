// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.9;
pragma abicoder v1;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import {ICToken} from '../../interfaces/external/compound/ICToken.sol';
import {IComptroller} from '../../interfaces/external/compound/IComptroller.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBabController} from '../../interfaces/IBabController.sol';

import {UniversalERC20} from '../../lib/UniversalERC20.sol';
import {ControllerLib} from '../../lib/ControllerLib.sol';

import {LendIntegration} from './LendIntegration.sol';

/**
 * @title CompoundLendIntegration
 * @author Babylon Finance Protocol
 *
 * Compound lend integration.
 */
contract CompoundLendIntegration is LendIntegration {
    using SafeCast for uint256;
    using UniversalERC20 for IERC20;
    using ControllerLib for IBabController;

    /* ============ Constant ============ */

    IComptroller internal immutable comptroller;

    address private constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    // Mapping of asset addresses to cToken addresses
    mapping(address => address) public assetToCToken;

    /* ============ Struct ============ */

    /* ============ Events ============ */

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     * @param _comptroller            Address of the compound comptroller
     */
    constructor(
        string memory _name,
        IBabController _controller,
        IComptroller _comptroller
    ) LendIntegration(_name, _controller) {
        comptroller = _comptroller;
        _overrideMappings(_comptroller);
    }

    /* ============ External Functions ============ */

    // Governance function
    function overrideMappings() external {
        controller.onlyGovernanceOrEmergency();
        _overrideMappings(comptroller);
    }

    // Governance function
    function updateCTokenMapping(address _assetAddress, address _cTokenAddress) external {
        controller.onlyGovernanceOrEmergency();
        assetToCToken[_assetAddress] = _cTokenAddress;
    }

    function getInvestmentTokenAmount(address _address, address _assetToken) public view override returns (uint256) {
        ICToken ctoken = ICToken(_getInvestmentToken(_assetToken));
        return (ctoken.balanceOf(_address) * (ctoken.exchangeRateStored())) / (10**18);
    }

    /* ============ Internal Functions ============ */

    function _overrideMappings(IComptroller _comptroller) private {
        address[] memory markets = _comptroller.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            address underlying = address(0);
            // Skip cEther
            if (markets[i] != 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5) {
                underlying = ICToken(markets[i]).underlying();
            }
            assetToCToken[underlying] = markets[i];
        }
    }

    function _getRewardToken() internal view virtual override returns (address) {
        return COMP;
    }

    function _getCollateralFactor(address _assetToken) internal view virtual override returns (uint256) {
        ICToken ctoken = ICToken(_getInvestmentToken(_assetToken));
        (, uint256 collateral) = IComptroller(comptroller).markets(address(ctoken));
        return collateral;
    }

    function _getRewardsAccrued(address _strategy) internal view virtual override returns (uint256) {
        return IComptroller(comptroller).compAccrued(_strategy);
    }

    function _isInvestment(address _assetToken) internal view override returns (bool) {
        return assetToCToken[_assetToken] != address(0);
    }

    function _getExpectedShares(address _assetToken, uint256 _numTokensToSupply)
        internal
        view
        override
        returns (uint256)
    {
        uint256 oneCTokenInUderlying = _getExchangeRatePerToken(_assetToken);
        return (oneCTokenInUderlying * (_numTokensToSupply)) / (10**18);
    }

    // TODO: Test this
    function _getExchangeRatePerToken(address _assetToken) internal view override returns (uint256) {
        address cToken = assetToCToken[_assetToken];
        uint256 exchangeRateCurrent = ICToken(cToken).exchangeRateStored();
        uint256 assetDecimals = IERC20(_assetToken).universalDecimals();
        // cTokens always have 8 decimals.
        if (assetDecimals < 8) {
            uint256 mantissa = 8 - assetDecimals;
            return exchangeRateCurrent * (10**mantissa);
        } else {
            uint256 mantissa = assetDecimals - 8;
            return exchangeRateCurrent / (10**mantissa);
        }
    }

    function _getRedeemCalldata(
        address, /* _strategy */
        address _assetToken,
        uint256 _numTokensToReedem
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('redeemUnderlying(uint256)', _numTokensToReedem);

        return (assetToCToken[_assetToken], 0, methodData);
    }

    function _claimRewardsCallData(address _strategy)
        internal
        view
        virtual
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Encode method data for Garden to invoke
        bytes memory methodData = abi.encodeWithSignature('claimComp(address)', _strategy);

        return (address(comptroller), 0, methodData);
    }

    /**
     * Returns calldata for supplying tokens.
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getSupplyCalldata(
        address, /* _strategy */
        address _assetToken,
        uint256 _numTokensToSupply
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        // Encode method data for Garden to invoke
        bytes memory methodData;
        if (_assetToken == address(0)) {
            methodData = abi.encodeWithSignature('mint()');
        } else {
            methodData = abi.encodeWithSignature('mint(uint256)', _numTokensToSupply);
        }
        // If it is ETH, send the value
        return (assetToCToken[_assetToken], _assetToken == address(0) ? _numTokensToSupply : 0, methodData);
    }

    /**
     * Return pre action calldata
     *
     * @param  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * @param  _borrowOp                Type of Borrow op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address _asset,
        uint256, /* _amount */
        uint256 _borrowOp
    )
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        if (_borrowOp == 0) {
            // Encode method data for Garden to invoke
            address[] memory markets = new address[](1);
            markets[0] = assetToCToken[_asset];
            bytes memory methodData = abi.encodeWithSignature('enterMarkets(address[])', markets);
            return (address(comptroller), 0, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    function _getSpender(address _assetToken) internal view override returns (address) {
        return assetToCToken[_assetToken];
    }

    function _getInvestmentToken(address _assetToken) internal view override returns (address) {
        return assetToCToken[_assetToken];
    }
}
