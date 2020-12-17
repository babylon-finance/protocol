pragma solidity >=0.7.0 <0.9.0;

import './interfaces/aave/ILendingPool.sol';
import './interfaces/aave/IProtocolDataProvider.sol';
import './interfaces/aave/IStableDebtToken.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

/**
 * This is a proof of concept starter contract, showing how uncollaterised loans are possible
 * using Aave v2 credit delegation.
 * This example supports stable interest rate borrows.
 * It is not production ready (!). User permissions and user accounting of loans should be implemented.
 * See @dev comments
 */

contract AaveBorrowing {
    using SafeERC20 for IERC20;

    ILendingPool constant lendingPool = ILendingPool(address(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9)); // Mainnet
    IProtocolDataProvider constant dataProvider = IProtocolDataProvider(address(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d)); // Mainnet

    address public owner;

    constructor(address _owner) public {
      owner = _owner;
    }

    modifier onlyOwner() {
      require(owner == msg.sender, "Ownable: caller is not the owner");
      _;
    }

    /**
     * Deposits collateral into the Aave.
     * This would be called by a fund within a strategy
     * @param asset The asset to be deposited as collateral
     * @param amount The amount to be deposited as collateral
     *
     */
    function depositCollateral(address asset, uint256 amount) public onlyOwner {
      IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
      IERC20(asset).safeApprove(address(lendingPool), amount);
      lendingPool.deposit(asset, amount, address(this), 0);
    }

    /**
     * Borrows an asset
     * @param asset The asset to be borrowed
     * @param amount The amount to borrow
     * @param interestRateMode 1 for stable, 2 for variable
     */
    function borrowAsset(address asset, uint256 amount, uint256 interestRateMode) public onlyOwner  {
      // Borrow asset
      lendingPool.borrow(asset, amount, interestRateMode, 0, msg.sender);
      // Sends the borrowed assets back to the caller
      IERC20(asset).safeTransferFrom(address(this), msg.sender, amount);
    }

    /**
     * Repays a borrowed asset debt
     * @param asset The asset to be repaid
     * @param amount The amount to repay
     * @param interestRateMode 1 for stable, 2 for variable
     */
    function repayAsset(address asset, uint256 amount, uint256 interestRateMode) public onlyOwner {
      IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
      IERC20(asset).safeApprove(address(lendingPool), amount);
      lendingPool.repay(asset, amount, interestRateMode, msg.sender);
    }

    /**
     * Withdraw all of a collateral as the underlying asset
     * @param asset The underlying asset to withdraw
     *
     */
    function withdrawCollateral(address asset) public onlyOwner {
      (address aTokenAddress,,) = dataProvider.getReserveTokensAddresses(asset);
      uint256 assetBalance = IERC20(aTokenAddress).balanceOf(address(this));
      lendingPool.withdraw(asset, assetBalance, owner);
    }
}
