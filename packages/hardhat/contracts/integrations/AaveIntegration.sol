pragma solidity >=0.7.0 <0.9.0;

import "hardhat/console.sol";
import { ILendingPool } from '../interfaces/external/aave/ILendingPool.sol';
import { IProtocolDataProvider} from '../interfaces/external/aave/IProtocolDataProvider.sol';
import { IStableDebtToken } from '../interfaces/external/aave/IStableDebtToken.sol';
import { IBorrow } from '../interfaces/IBorrow.sol';
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

/**
 * Aave Integration
 * This example supports stable interest rate borrows.
 */

contract AaveIntegration is BorrowIntegration {
    using SafeERC20 for IERC20;

    ILendingPool constant lendingPool = ILendingPool(address(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9)); // Mainnet
    IProtocolDataProvider constant dataProvider = IProtocolDataProvider(address(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d)); // Mainnet

    /* ============ Constructor ============ */

    /**
     * Creates the integration
     *
     * @param _weth                   Address of the WETH ERC20
     * @param _controller             Address of the controller
     * @param _maxCollateralFactor    Max collateral factor allowed
     */
    constructor(IWETH _weth, IFolioController _controller, uint256 _maxCollateralFactor) public BorrowIntegration(_weth, _controller, _maxCollateralFactor) {

    }



    /**
     * Deposits collateral into the Aave.
     * This would be called by a fund within a strategy
     * @param asset The asset to be deposited as collateral
     * @param amount The amount to be deposited as collateral
     *
     */
    function depositCollateral(address asset, uint256 amount) external {
      IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
      IERC20(asset).safeApprove(address(lendingPool), amount);
      uint allowance = IERC20(asset).allowance(address(this), address(lendingPool));
      lendingPool.deposit(asset, amount, address(this), 0);
    }

    /**
     * Borrows an asset
     * @param asset The asset to be borrowed
     * @param amount The amount to borrow
     * @param interestRateMode 1 for stable, 2 for variable
     */
    function borrow(address asset, uint256 amount, uint256 interestRateMode, address onBehalf) external {
      lendingPool.borrow(asset, amount, interestRateMode, 0, address(this));
      // Sends the borrowed assets back to the caller
      IERC20(asset).transfer(msg.sender, amount);
    }

    /**
     * Repays a borrowed asset debt
     * @param asset The asset to be repaid
     * @param amount The amount to repay
     * @param interestRateMode 1 for stable, 2 for variable
     */
    function repay(address asset, uint256 amount, uint256 interestRateMode) external {
      IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
      IERC20(asset).safeApprove(address(lendingPool), amount);
      lendingPool.repay(asset, amount, interestRateMode, address(this));
    }

    /**
     * Withdraw all of a collateral as the underlying asset
     * @param asset The underlying asset to withdraw
     *
     */
    function withdrawCollateral(address asset) external {
      (address aTokenAddress,,) = dataProvider.getReserveTokensAddresses(asset);
      uint256 assetBalance = IERC20(aTokenAddress).balanceOf(address(this));
      lendingPool.withdraw(asset, assetBalance, msg.sender);
    }

    function repayAll(address asset) external {
      // TODO
    }

    function withdrawAllCollateral(address asset) external {
      // TODO
    }
    function getBorrowBalance(address asset) external view returns (uint256) {
      // TODO
      return 0;
    }
}
