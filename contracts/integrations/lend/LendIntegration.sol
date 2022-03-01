

pragma solidity 0.8.9;

import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import {IGarden} from '../../interfaces/IGarden.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';
import {IBabController} from '../../interfaces/IBabController.sol';
import {ILendIntegration} from '../../interfaces/ILendIntegration.sol';

import {BaseIntegration} from '../BaseIntegration.sol';

/**
 * @title LendIntegration
 * @author Babylon Finance Protocol
 *
 * Base class for integration with lending protocols
 */
abstract contract LendIntegration is BaseIntegration, ReentrancyGuard, ILendIntegration {
    using SafeCast for uint256;

    /* ============ Struct ============ */
    struct InvestmentInfo {
        IStrategy strategy; // Strategy address
        IGarden garden; // Garden address
        address assetToken;
        address investment; // Investment address
        uint256 investmentTokensInTransaction; // Investment tokens affected by this transaction
        uint256 investmentTokensInGarden; // Investment tokens garden balance
        uint256 underlyingTokensInGarden; // Underlying tokens garden balance
        uint256 limitDepositTokenQuantity; // Limit deposit/withdrawal token amount
    }

    /* ============ Events ============ */

    event TokensSupplied(
        address indexed garden,
        address indexed strategy,
        address indexed assetToken,
        uint256 numTokensToSupply
    );

    event TokensRedeemed(
        address indexed garden,
        address indexed strategy,
        address indexed assetToken,
        uint256 numTokensToRedeem,
        uint256 protocolFee
    );

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _name                   Name of the integration
     * @param _controller             Address of the controller
     */
    constructor(string memory _name, IBabController _controller) BaseIntegration(_name, _controller) {}

    /* ============ External Functions ============ */
    function getInvestmentToken(address _assetToken) external view override returns (address) {
        return _getInvestmentToken(_assetToken);
    }

    function getCollateralFactor(address _assetToken) external view override returns (uint256) {
        return _getCollateralFactor(_assetToken);
    }

    /**
     * Returns the reward token
     *
     * @return address       Address of the reward token
     */
    function getRewardToken() external view override returns (address) {
        return _getRewardToken();
    }

    /**
     * Returns the number of reward tokens accrued
     *
     * @param _strategy      Address of the strategy
     * @return address       Address of the reward token
     */
    function getRewardsAccrued(address _strategy) external view override returns (uint256) {
        return _getRewardsAccrued(_strategy);
    }

    /**
     * Checks whether an investment address is valid
     *
     * @param _investmentAddress                 Investment address to check
     * @return bool                              True if the address is a investment
     */
    function isInvestment(address _investmentAddress) external view returns (bool) {
        return _isInvestment(_investmentAddress);
    }

    function getInvestmentTokenAmount(address _address, address _assetToken)
        public
        view
        virtual
        override
        returns (uint256);

    function supplyTokens(
        address _strategy,
        address _assetToken,
        uint256 _numTokensToSupply,
        uint256 _minAmountExpected
    ) external override nonReentrant onlySystemContract {
        InvestmentInfo memory investmentInfo =
            _createInvestmentInfo(
                _strategy,
                _assetToken,
                _getInvestmentToken(_assetToken),
                _numTokensToSupply,
                _minAmountExpected
            );

        _validatePreJoinInvestmentData(investmentInfo);

        // Pre actions (enter markets for compound)
        (address targetAddressP, uint256 callValueP, bytes memory methodDataP) =
            _getPreActionCallData(_assetToken, _numTokensToSupply, 0);

        if (targetAddressP != address(0)) {
            // Invoke protocol specific call
            investmentInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }

        // not needed for ETH
        if (_assetToken != address(0)) {
            investmentInfo.strategy.invokeApprove(_getSpender(_assetToken), _assetToken, _numTokensToSupply);
        }

        (address targetInvestment, uint256 callValue, bytes memory methodData) =
            _getSupplyCalldata(_strategy, _assetToken, _numTokensToSupply);

        investmentInfo.strategy.invokeFromIntegration(targetInvestment, callValue, methodData);
        _validatePostEnterInvestmentData(investmentInfo);

        emit TokensSupplied(
            address(investmentInfo.garden),
            address(investmentInfo.strategy),
            _assetToken,
            _numTokensToSupply
        );
    }

    function redeemTokens(
        address _strategy,
        address _assetToken,
        uint256 _numTokensToRedeem,
        uint256 _minAmountExpected
    ) external override nonReentrant onlySystemContract {
        InvestmentInfo memory investmentInfo =
            _createInvestmentInfo(
                _strategy,
                _assetToken,
                _getInvestmentToken(_assetToken),
                _numTokensToRedeem,
                _minAmountExpected
            );

        _validatePreExitInvestmentData(investmentInfo);

        // Pre actions (enter markets for compound)
        (address targetAddressP, uint256 callValueP, bytes memory methodDataP) =
            _getPreActionCallData(_assetToken, _numTokensToRedeem, 1);

        if (targetAddressP != address(0)) {
            // Invoke protocol specific call
            investmentInfo.strategy.invokeFromIntegration(targetAddressP, callValueP, methodDataP);
        }

        (address targetInvestment, uint256 callValue, bytes memory methodData) =
            _getRedeemCalldata(_strategy, _assetToken, _numTokensToRedeem);

        investmentInfo.strategy.invokeFromIntegration(targetInvestment, callValue, methodData);

        // Claim rewards
        (address targetAddressR, uint256 callValueR, bytes memory methodDataR) = _claimRewardsCallData(_strategy);
        if (targetAddressR != address(0)) {
            // Invoke protocol specific call
            investmentInfo.strategy.invokeFromIntegration(targetAddressR, callValueR, methodDataR);
        }

        _validatePostExitInvestmentData(investmentInfo);

        emit TokensSupplied(
            address(investmentInfo.garden),
            address(investmentInfo.strategy),
            _assetToken,
            _numTokensToRedeem
        );
    }

    function getExchangeRatePerToken(address _assetToken) external view override returns (uint256) {
        return _getExchangeRatePerToken(_assetToken);
    }

    /**
     * Gets the amount of cTokens expected to get after depositing ERC20 asset.
     *
     * @param _numTokensToSupply                 Amount of ERC20 tokens to supply
     * @return uint256                           Amount of supply tokens to receive
     */
    function getExpectedShares(address _assetToken, uint256 _numTokensToSupply)
        external
        view
        override
        returns (uint256)
    {
        return _getExpectedShares(_assetToken, _numTokensToSupply);
    }

    /* ============ Internal Functions ============ */

    /**
     * Validate pre investment join data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePreJoinInvestmentData(InvestmentInfo memory _investmentInfo) internal view {
        require(_isInvestment(_investmentInfo.assetToken), 'The investment address is not valid');
        require(
            _investmentInfo.investmentTokensInTransaction > 0,
            'Min investment tokens to receive must be greater than 0'
        );
    }

    /**
     * Validate post enter investment data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePostEnterInvestmentData(InvestmentInfo memory _investmentInfo) internal view {
        require(
            getInvestmentTokenAmount(address(_investmentInfo.strategy), _investmentInfo.assetToken) >
                _investmentInfo.investmentTokensInGarden,
            'The garden did not receive the investment tokens'
        );
    }

    /**
     * Validate post exit investment data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePostExitInvestmentData(InvestmentInfo memory _investmentInfo) internal view {
        uint256 balance =
            _investmentInfo.assetToken == address(0)
                ? address(_investmentInfo.strategy).balance
                : IERC20(_investmentInfo.assetToken).balanceOf(address(_investmentInfo.strategy));
        require(balance > _investmentInfo.underlyingTokensInGarden, 'The garden did not return the investment tokens');
    }

    /**
     * Validate pre investment data. Check investment is valid, token quantity is valid.
     *
     * @param _investmentInfo               Struct containing investment information used in internal functions
     */
    function _validatePreExitInvestmentData(InvestmentInfo memory _investmentInfo) internal view {
        require(_isInvestment(_investmentInfo.assetToken), 'The investment address is not valid');
        require(
            _investmentInfo.investmentTokensInTransaction > 0,
            'Investment tokens to exchange must be greater than 0'
        );
        require(
            _investmentInfo.investmentTokensInGarden >= _investmentInfo.investmentTokensInTransaction,
            'The garden does not have enough investment tokens'
        );
    }

    function _isInvestment(
        address //_investmentAddress
    ) internal view virtual returns (bool);

    /**
     * Create and return InvestmentInfo struct
     *
     * return InvestmentInfo                            Struct containing data for the investment
     */
    function _createInvestmentInfo(
        address _strategy,
        address _assetToken,
        address _investmentToken,
        uint256 _investmentTokensInTransaction,
        uint256 _limitDepositToken
    ) internal view returns (InvestmentInfo memory) {
        InvestmentInfo memory investmentInfo;
        investmentInfo.strategy = IStrategy(_strategy);
        investmentInfo.garden = IGarden(investmentInfo.strategy.garden());
        investmentInfo.assetToken = _assetToken;
        investmentInfo.investment = _investmentToken;
        investmentInfo.investmentTokensInGarden = getInvestmentTokenAmount(_strategy, _assetToken);
        investmentInfo.underlyingTokensInGarden = _assetToken == address(0)
            ? address(_strategy).balance
            : IERC20(_assetToken).balanceOf(address(_strategy));
        investmentInfo.investmentTokensInTransaction = _investmentTokensInTransaction;
        investmentInfo.limitDepositTokenQuantity = _limitDepositToken;

        return investmentInfo;
    }

    function _getExpectedShares(address, uint256) internal view virtual returns (uint256);

    function _getExchangeRatePerToken(address) internal view virtual returns (uint256);

    function _getRedeemCalldata(
        address, /* _strategy */
        address, /* _assetToken */
        uint256 /* _numTokensToSupply */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        );

    /**
     * Returns calldata for supplying tokens.
     *
     * hparam  _strategy                Address of the strat
     * hparam  _assetToken              Address of the token
     * hparam  _numTokensToSupply       Number of tokens
     *
     * @return address                         Target contract address
     * @return uint256                         Call value
     * @return bytes                           Trade calldata
     */
    function _getSupplyCalldata(
        address, /* _strategy */
        address, /* _assetToken */
        uint256 /* _numTokensToSupply */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        );

    /**
     * Return pre action calldata
     *
     * hparam  _asset                    Address of the asset to deposit
     * hparam  _amount                   Amount of the token to deposit
     * hparam  _borrowOp                Type of Borrow op
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _getPreActionCallData(
        address, /* _asset */
        uint256, /* _amount */
        uint256 /* _borrowOp */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        );

    /**
     * Return claim rewards action call data
     *
     * @return address                   Target contract address
     * @return uint256                   Call value
     * @return bytes                     Trade calldata
     */
    function _claimRewardsCallData(
        address /*_strategy */
    )
        internal
        view
        virtual
        returns (
            address,
            uint256,
            bytes memory
        );

    function _getSpender(
        address //_investmentAddress
    ) internal view virtual returns (address);

    function _getRewardToken() internal view virtual returns (address);

    function _getCollateralFactor(address _asset) internal view virtual returns (uint256);

    function _getRewardsAccrued(address _strategy) internal view virtual returns (uint256);

    function _getInvestmentToken(
        address //_investmentAddress
    ) internal view virtual returns (address);
}
