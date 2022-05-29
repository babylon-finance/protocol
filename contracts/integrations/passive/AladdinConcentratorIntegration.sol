// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeDecimalMath} from '../../lib/SafeDecimalMath.sol';

import {IBabController} from '../../interfaces/IBabController.sol';
import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IPickleJarRegistry} from '../../interfaces/IPickleJarRegistry.sol';
import {IGarden} from '../../interfaces/IGarden.sol';
import {PreciseUnitMath} from '../../lib/PreciseUnitMath.sol';
import {BytesLib} from '../../lib/BytesLib.sol';
import {LowGasSafeMath} from '../../lib/LowGasSafeMath.sol';
import {PassiveIntegration} from './PassiveIntegration.sol';
import {IAladdinCRV} from '../../interfaces/external/aladdin/IAladdinCRV.sol';
import {IAladdinConvexVault} from '../../interfaces/external/aladdin/IAladdinConvexVault.sol';
import {ICleverCVXLocker} from '../../interfaces/external/aladdin/ICleverCVXLocker.sol';
import 'hardhat/console.sol';

/**
 * @title AladdinConcentratorIntegration
 * @author Babylon Finance Protocol
 *
 * Aladdin Concentrator Integration
 */
contract AladdinConcentratorIntegration is PassiveIntegration {
    using LowGasSafeMath for uint256;
    using PreciseUnitMath for uint256;
    using SafeDecimalMath for uint256;

    /* ============ Constants ============ */
    address private constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52; // crv
    address private constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // cvx
    ICleverCVXLocker private constant aladdinCVXLocker = ICleverCVXLocker(0x96C68D861aDa016Ed98c30C810879F9df7c64154);

    /* ============ State Variables ============ */
    IAladdinCRV public immutable aladdinCRV;
    IAladdinConvexVault public aladdinConvexVault;

    mapping(address => uint256) private cacheAladdinLpTokenToPid;
    uint256 private elementsCached = 0;

    // Mapping of valid Vaults
    mapping(address => bool) public aladdinPools;
    address[] public aladdinList;

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _controller                   Address of the controller
     * @param _aladdinCRV                   Address of our aladdin crv
     * @param _aladdinConvexVault           Address of our aladdin convex vault contract
     */
    constructor(
        IBabController _controller,
        IAladdinCRV _aladdinCRV,
        IAladdinConvexVault _aladdinConvexVault
    ) PassiveIntegration('aladdin_concentrator', _controller) {
        aladdinCRV = _aladdinCRV;
        aladdinConvexVault = _aladdinConvexVault;
        updateCache();
    }

    /* ============ Public Functions ============ */

    /**
     * Refreshes aladdin vaults
     */
    function updateCache() public {
        uint256 poolLength = aladdinConvexVault.poolLength();
        if (elementsCached >= poolLength) {
            return;
        }
        for (uint256 i = elementsCached; i < poolLength; i++) {
            (, , , , address lpToken, , , , , , ) = aladdinConvexVault.poolInfo(i);
            cacheAladdinLpTokenToPid[lpToken] = i + 1;
            aladdinPools[lpToken] = true;
            aladdinList.push(lpToken);
        }
        elementsCached = poolLength;
    }

    /**
     * Gets the PID in convex of a convex lp token
     * @param _asset                         Address of the convex lp token
     * @return uint256                       Pid of the pool in convex
     */
    function getPid(address _asset) public view returns (bool, uint256) {
        if (cacheAladdinLpTokenToPid[_asset] > 0) {
            return (true, cacheAladdinLpTokenToPid[_asset] - 1);
        }
        uint256 poolLength = aladdinConvexVault.poolLength();
        if (elementsCached >= poolLength) {
            return (false, 0);
        }
        for (uint256 i = elementsCached; i < poolLength; i++) {
            (, , , , address lpToken, , , , , , ) = aladdinConvexVault.poolInfo(i);
            if (lpToken == _asset) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    /* ============ Internal Functions ============ */

    function _getSpender(
        address _lpToken,
        uint8 /* _op */
    ) internal view override returns (address) {
        // clever
        if (_lpToken == CVX) {
            return address(aladdinCVXLocker);
        }
        // curve concentrator
        if (_lpToken == CRV) {
            return address(aladdinCRV);
        }
        // concentrator convex vaults
        return address(aladdinConvexVault);
    }

    function _getInvestmentAsset(address _lpToken) internal pure override returns (address) {
        return _lpToken;
    }

    function _getResultAsset(address _lpToken) internal view override returns (address) {
        if (_lpToken == CRV) {
            return address(aladdinCRV);
        }
        return _lpToken;
    }

    function _getResultBalance(address _strategy, address _resultAssetAddress)
        internal
        view
        override
        returns (uint256)
    {
        // clever
        if (_resultAssetAddress == CVX) {
            (uint256 totalDeposited, , , , ) = aladdinCVXLocker.getUserInfo(_strategy);
            console.log('clever result balance', totalDeposited);
            return totalDeposited;
        }
        // curve concentrator
        if (_resultAssetAddress == address(aladdinCRV)) {
            return ERC20(address(aladdinCRV)).balanceOf(_strategy);
        }
        // convex concentrator
        (, uint256 pid) = getPid(_resultAssetAddress);
        (uint128 shares, , ) = aladdinConvexVault.userInfo(pid, _strategy);
        return uint256(shares);
    }

    function _getRewards(address _strategy, address _investmentAddress)
        internal
        view
        override
        returns (address, uint256)
    {
        // clever
        if (_investmentAddress == CVX) {
            (, , , , uint256 totalReward) = aladdinCVXLocker.getUserInfo(_strategy);
            return (CVX, totalReward);
        }
        // curve concentrator
        if (_investmentAddress == CRV) {
            return (address(0), 0);
        }
        // convex concentrator
        (, uint256 pid) = getPid(_investmentAddress);
        (, uint256 rewards, ) = aladdinConvexVault.userInfo(pid, _strategy);
        // No need to return amount because it is included in the balance
        // This is just for exit in the convex vaults
        return (CRV, rewards);
    }

    /**
     * Return join investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * @param  _asset                          Address of the vault
     * hparam  _investmentTokensOut            Amount of investment tokens to send
     * hparam  _tokenIn                        Addresses of tokens to send to the investment
     * hparam  _maxAmountIn                    Amounts of tokens to send to the investment
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getEnterInvestmentCalldata(
        address _strategy,
        address _asset,
        uint256, /* _investmentTokensOut */
        address, /* _tokenIn */
        uint256 _maxAmountIn
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
        (bool found, uint256 pid) = getPid(_asset);
        require(_asset == CRV || _asset == CVX || found, 'Aladdin pool does not exist');
        // convex concentrator as default
        bytes memory methodData = abi.encodeWithSignature('depositAll(uint256)', pid);
        address target = address(aladdinConvexVault);
        // Clever
        if (_asset == CVX) {
            target = address(aladdinCVXLocker);
            methodData = abi.encodeWithSignature('deposit(uint256)', _maxAmountIn);
        }
        // aCRV is a special case. Curve concentrator
        if (_asset == CRV) {
            target = address(aladdinCRV);
            methodData = abi.encodeWithSignature('depositAllWithCRV(address)', _strategy);
        }
        // Encode method data for Garden to invoke
        return (target, 0, methodData);
    }

    /**
     * Return exit investment calldata which is already generated from the investment API
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _asset                          Address of the investment
     * hparam  _investmentTokensIn             Amount of investment tokens to receive
     * hparam  _tokenOut                       Addresses of tokens to receive
     * hparam  _minAmountOut                   Amounts of investment tokens to receive
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getExitInvestmentCalldata(
        address _strategy,
        address _asset,
        uint256 _investmentTokensIn,
        address, /* _tokenOut */
        uint256 _minAmountOut
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
        (bool found, uint256 pid) = getPid(_asset);
        require(_asset == CRV || _asset == CVX || found, 'Aladdin pool does not exist');
        // convex concentrator as default
        bytes memory methodData =
            abi.encodeWithSignature(
                'withdrawAndClaim(uint256,uint256,uint256,uint8)',
                pid,
                _investmentTokensIn,
                _minAmountOut,
                IAladdinConvexVault.ClaimOption.ClaimAsCRV
            );
        address target = address(aladdinConvexVault);
        // clever
        if (_asset == CVX) {
            target = address(aladdinCVXLocker);
            methodData = abi.encodeWithSignature('withdrawUnlocked()');
        }
        // curve concentrator
        if (_asset == CRV) {
            target = address(aladdinCRV);
            methodData = abi.encodeWithSignature(
                'withdraw(address,uint256,uint256,uint8)',
                _strategy,
                _investmentTokensIn,
                _minAmountOut,
                IAladdinCRV.WithdrawOption.WithdrawAsCRV
            );
        }
        return (target, 0, methodData);
    }

    /**
     * Return unlock investment calldata to prepare for withdrawal
     *
     * hparam  _strategy                       Address of the strategy
     * hparam  _data                           Data
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getUnlockInvestmentCalldata(address _strategy, bytes calldata _data)
        internal
        view
        override
        returns (
            address,
            uint256,
            bytes memory
        )
    {
        address _asset = BytesLib.decodeOpDataAddress(_data);
        if (_asset == CVX) {
            (uint256 totalDeposited, uint256 totalPendingUnlocked, , , ) = aladdinCVXLocker.getUserInfo(_strategy);
            bytes memory methodData =
                abi.encodeWithSignature('unlock(uint256)', totalDeposited.sub(totalPendingUnlocked));
            return (address(aladdinCVXLocker), 0, methodData);
        }
        return (address(0), 0, bytes(''));
    }

    /**
     * Checks if the integration needs to execute a tx to prepare the withdrawal
     *
     * @param _strategy                           Address of the strategy
     * @param _data                               Data param
     * @return bool                               True if it is needed
     */
    function _needsUnlockSignal(address _strategy, bytes calldata _data) internal view override returns (bool) {
        address _asset = BytesLib.decodeOpDataAddress(_data);
        if (_asset != CVX) {
            return false;
        }
        // Only needed for clever
        (uint256 totalDeposited, uint256 totalPendingUnlocked, , , ) = aladdinCVXLocker.getUserInfo(_strategy);
        return totalDeposited > totalPendingUnlocked && _getRemainingDurationStrategy(_strategy) <= (17 weeks + 3 days);
    }
}
