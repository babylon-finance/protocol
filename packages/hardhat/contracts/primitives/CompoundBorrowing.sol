pragma solidity >=0.7.0 <0.9.0;

import "hardhat/console.sol";
import '../interfaces/compound/ICToken.sol';
import '../interfaces/compound/ICEther.sol';
import '../interfaces/compound/ICompoundPriceOracle.sol';
import '../interfaces/compound/IComptroller.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Cmpoiund Borrowing primitive
 */

contract CompoundBorrowing {

  event MyLog(string, uint256);

  using SafeMath for uint256;

  address constant CompoundComptrollerAddress = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
  address constant CEtherAddress = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

  function _transferFromUnderlying(
      address sender,
      address recipient,
      address cToken,
      uint256 amount
  ) internal {
      address underlying = ICToken(cToken).underlying();
      require(
          IERC20(underlying).transferFrom(sender, recipient, amount),
          "cmpnd-mgr-transferFrom-underlying-failed"
      );
  }

  function _transferUnderlying(
      address cToken,
      address recipient,
      uint256 amount
  ) internal {
      if (cToken == CEtherAddress) {
          recipient.call{value: amount}("");
      } else {
          require(
              IERC20(ICToken(cToken).underlying()).transfer(
                  recipient,
                  amount
              ),
              "cmpnd-mgr-transfer-underlying-failed"
          );
      }
  }

  function _transfer(address token, address recipient, uint256 amount)
      internal
  {
      require(
          IERC20(token).transfer(recipient, amount),
          "cmpnd-mgr-transfer-failed"
      );
  }

  function getBorrowBalanceUnderlying(
      address cToken,
      address owner
  )
      public
      view
      returns (uint256)
  {
      (
          uint256 err,
          uint256 cTokenBalance,
          uint256 borrowBalance,
          uint256 exchangeRateMantissa
      ) = ICToken(cToken).getAccountSnapshot(owner);

      // Source: balanceOfUnderlying from any ctoken
      return cTokenBalance.mul(exchangeRateMantissa).div(1e18);
  }

  function enterMarkets(
      address[] memory cTokens // Address of the Compound derivation token (e.g. cDAI)
  ) public {
      // Enter the compound markets for all the specified tokens
      uint256[] memory errors = IComptroller(CompoundComptrollerAddress)
          .enterMarkets(cTokens);

      for (uint256 i = 0; i < errors.length; i++) {
          require(errors[i] == 0, "cmpnd-mgr-enter-markets-failed");
      }
  }

  function approveCToken(address cToken, uint256 amount) public {
      // Approves CToken contract to call `transferFrom`
      address underlying = ICToken(cToken).underlying();
      require(
          IERC20(underlying).approve(cToken, amount) == true,
          "cmpnd-mgr-ctoken-approved-failed"
      );
  }

  function approveCTokens(
      address[] memory cTokens // Tokens to approve
  ) public {
      for (uint256 i = 0; i < cTokens.length; i++) {
          // Don't need to approve ICEther
          if (cTokens[i] != CEtherAddress) {
              approveCToken(cTokens[i], uint256(-1));
          }
      }
  }

  function enterMarketsAndApproveCTokens(address[] memory cTokens) public {
      enterMarkets(cTokens);
      approveCTokens(cTokens);
  }

  function supply(address cToken, uint256 amount) public payable {
      if (cToken == CEtherAddress) {
          ICEther(CEtherAddress).mint{value: amount }();
      } else {
          // Approves CToken contract to call `transferFrom`
          approveCToken(cToken, amount);

          require(
              ICToken(cToken).mint(amount) == 0,
              "cmpnd-mgr-ctoken-supply-failed"
          );
      }
  }

  function borrow(address cToken, uint256 borrowAmount) public {
      require(
          ICToken(cToken).borrow(borrowAmount) == 0,
          "cmpnd-mgr-ctoken-borrow-failed"
      );
  }

  function supplyAndBorrow(
      address supplyCToken,
      uint256 supplyAmount,
      address borrowCToken,
      uint256 borrowAmount
  ) public payable {
      supply(supplyCToken, supplyAmount);
      borrow(borrowCToken, borrowAmount);
  }

  function repayBorrow(address cToken, uint256 amount) public payable {
      if (cToken == CEtherAddress) {
          ICEther(cToken).repayBorrow{ value: amount }();
      } else {
          approveCToken(cToken, amount);
          require(
              ICToken(cToken).repayBorrow(amount) == 0,
              "cmpnd-mgr-ctoken-repay-failed"
          );
      }
  }

  function repayBorrowBehalf(
      address recipient,
      address cToken,
      uint256 amount
  ) public payable {
      if (cToken == CEtherAddress) {
          ICEther(cToken).repayBorrowBehalf{ value: amount}(recipient);
      } else {
          approveCToken(cToken, amount);
          require(
              ICToken(cToken).repayBorrowBehalf(recipient, amount) == 0,
              "cmpnd-mgr-ctoken-repaybehalf-failed"
          );
      }
  }

  function redeem(address cToken, uint256 redeemTokens) public payable {
      require(
          ICToken(cToken).redeem(redeemTokens) == 0,
          "cmpnd-mgr-ctoken-redeem-failed"
      );
  }

  function redeemUnderlying(address cToken, uint256 redeemTokens)
      public
      payable
  {
      require(
          ICToken(cToken).redeemUnderlying(redeemTokens) == 0,
          "cmpnd-mgr-ctoken-redeem-underlying-failed"
      );
  }


  // Seed the contract with a supported underyling asset before running this
  // `node seed-account-with-erc20/dai.js` then transfer to the contract
  function borrowErc20Example(
      address payable _cEtherAddress,
      address _comptrollerAddress,
      address _compoundPriceOracleAddress,
      address _cTokenAddress,
      uint _underlyingDecimals
  ) public payable returns (uint256) {
      ICEther cEth = ICEther(_cEtherAddress);
      IComptroller comptroller = IComptroller(_comptrollerAddress);
      ICompoundPriceOracle compoundPriceOracle = ICompoundPriceOracle(_compoundPriceOracleAddress);
      ICToken cToken = ICToken(_cTokenAddress);

      // Supply ETH as collateral, get cETH in return
      cEth.mint{ value: msg.value}();

      // Enter the ETH market so you can borrow another type of asset
      address[] memory cTokens = new address[](1);
      cTokens[0] = _cEtherAddress;
      uint256[] memory errors = comptroller.enterMarkets(cTokens);
      if (errors[0] != 0) {
          revert("Comptroller.enterMarkets failed.");
      }

      // Get my account's total liquidity value in Compound
      (uint256 error, uint256 liquidity, uint256 shortfall) = comptroller
          .getAccountLiquidity(address(this));
      if (error != 0) {
          revert("Comptroller.getAccountLiquidity failed.");
      }
      require(shortfall == 0, "account underwater");
      require(liquidity > 0, "account has excess collateral");

      // Get the collateral factor for our collateral
      // (
      //   bool isListed,
      //   uint collateralFactorMantissa
      // ) = comptroller.markets(_cEthAddress);
      // emit MyLog('ETH Collateral Factor', collateralFactorMantissa);

      // Get the amount of underlying added to your borrow each block
      // uint borrowRateMantissa = cToken.borrowRatePerBlock();
      // emit MyLog('Current Borrow Rate', borrowRateMantissa);

      // Get the underlying price in USD from the Price Feed,
      // so we can find out the maximum amount of underlying we can borrow.
      uint256 underlyingPrice = compoundPriceOracle.getUnderlyingPrice(_cTokenAddress);
      uint256 maxBorrowUnderlying = liquidity / underlyingPrice;

      // Borrowing near the max amount will result
      // in your account being liquidated instantly
      // emit MyLog("Maximum underlying Borrow (borrow far less!)", maxBorrowUnderlying);

      // Borrow underlying
      uint256 numUnderlyingToBorrow = 10;

      // Borrow, check the underlying balance for this contract's address
      cToken.borrow(numUnderlyingToBorrow * 10**_underlyingDecimals);

      // Get the borrow balance
      uint256 borrows = cToken.borrowBalanceCurrent(address(this));
      emit MyLog("Current underlying borrow amount", borrows);

      return borrows;
  }

  function myErc20RepayBorrow(
      address _erc20Address,
      address _ICTokenAddress,
      uint256 amount
  ) public returns (bool) {
      IERC20 underlying = IERC20(_erc20Address);
      ICToken cToken = ICToken(_ICTokenAddress);

      underlying.approve(_ICTokenAddress, amount);
      uint256 error = cToken.repayBorrow(amount);

      require(error == 0, "ICToken.repayBorrow Error");
      return true;
  }

  function borrowEthExample(
      address payable _cEtherAddress,
      address _comptrollerAddress,
      address _cTokenAddress,
      address _underlyingAddress,
      uint256 _underlyingToSupplyAsCollateral
  ) public returns (uint) {
      ICEther cEth = ICEther(_cEtherAddress);
      IComptroller comptroller = IComptroller(_comptrollerAddress);
      ICToken cToken = ICToken(_cTokenAddress);
      IERC20 underlying = IERC20(_underlyingAddress);

      // Approve transfer of underlying
      underlying.approve(_cTokenAddress, _underlyingToSupplyAsCollateral);

      // Supply underlying as collateral, get cToken in return
      uint256 error = cToken.mint(_underlyingToSupplyAsCollateral);
      require(error == 0, "ICToken.mint Error");

      // Enter the market so you can borrow another type of asset
      address[] memory cTokens = new address[](1);
      cTokens[0] = _cTokenAddress;
      uint256[] memory errors = comptroller.enterMarkets(cTokens);
      if (errors[0] != 0) {
          revert("Comptroller.enterMarkets failed.");
      }

      // Get my account's total liquidity value in Compound
      (uint256 error2, uint256 liquidity, uint256 shortfall) = comptroller
          .getAccountLiquidity(address(this));
      if (error2 != 0) {
          revert("Comptroller.getAccountLiquidity failed.");
      }
      require(shortfall == 0, "account underwater");
      require(liquidity > 0, "account has excess collateral");

      // Borrowing near the max amount will result
      // in your account being liquidated instantly
      emit MyLog("Maximum ETH Borrow (borrow far less!)", liquidity);

      // // Get the collateral factor for our collateral
      // (
      //   bool isListed,
      //   uint collateralFactorMantissa
      // ) = comptroller.markets(_cTokenAddress);
      // emit MyLog('Collateral Factor', collateralFactorMantissa);

      // // Get the amount of ETH added to your borrow each block
      // uint borrowRateMantissa = cEth.borrowRatePerBlock();
      // emit MyLog('Current ETH Borrow Rate', borrowRateMantissa);

      // Borrow a fixed amount of ETH below our maximum borrow amount
      uint256 numWeiToBorrow = 20000000000000000; // 0.02 ETH

      // Borrow, then check the underlying balance for this contract's address
      cEth.borrow(numWeiToBorrow);

      uint256 borrows = cEth.borrowBalanceCurrent(address(this));
      emit MyLog("Current ETH borrow amount", borrows);

      return borrows;
  }

  function myEthRepayBorrow(address _cEtherAddress, uint256 amount)
      public
      returns (bool)
  {
      ICEther cEth = ICEther(_cEtherAddress);
      cEth.repayBorrow{ value: amount}();
      return true;
  }

  function supplyEthToCompound(address payable _cEtherContract)
      public
      payable
      returns (bool)
  {
      // Create a reference to the corresponding cToken contract
      ICEther cToken = ICEther(_cEtherContract);

      // Amount of current exchange rate from cToken to underlying
      uint256 exchangeRateMantissa = cToken.exchangeRateCurrent();
      emit MyLog("Exchange Rate (scaled up by 1e18): ", exchangeRateMantissa);

      // Amount added to you supply balance this block
      uint256 supplyRateMantissa = cToken.supplyRatePerBlock();
      emit MyLog("Supply Rate: (scaled up by 1e18)", supplyRateMantissa);

      cToken.mint{ value: msg.value, gas: 250000}();
      return true;
  }

  function supplyErc20ToCompound(
      address _erc20Contract,
      address _ICTokenContract,
      uint256 _numTokensToSupply
  ) public returns (uint) {
      // Create a reference to the underlying asset contract, like DAI.
      IERC20 underlying = IERC20(_erc20Contract);

      // Create a reference to the corresponding cToken contract, like cDAI
      ICToken cToken = ICToken(_ICTokenContract);

      // Amount of current exchange rate from cToken to underlying
      uint256 exchangeRateMantissa = cToken.exchangeRateCurrent();
      emit MyLog("Exchange Rate (scaled up): ", exchangeRateMantissa);

      // Amount added to you supply balance this block
      uint256 supplyRateMantissa = cToken.supplyRatePerBlock();
      emit MyLog("Supply Rate: (scaled up)", supplyRateMantissa);

      // Approve transfer on the ERC20 contract
      underlying.approve(_ICTokenContract, _numTokensToSupply);

      // Mint cTokens
      uint mintResult = cToken.mint(_numTokensToSupply);
      return mintResult;
  }

  function redeemICTokenTokens(
      uint256 amount,
      bool redeemType,
      address _ICTokenContract
  ) public returns (bool) {
      // Create a reference to the corresponding cToken contract, like cDAI
      ICToken cToken = ICToken(_ICTokenContract);

      // `amount` is scaled up, see decimal table here:
      // https://compound.finance/docs#protocol-math

      uint256 redeemResult;

      if (redeemType == true) {
          // Retrieve your asset based on a cToken amount
          redeemResult = cToken.redeem(amount);
      } else {
          // Retrieve your asset based on an amount of the asset
          redeemResult = cToken.redeemUnderlying(amount);
      }

      // Error codes are listed here:
      // https://compound.finance/developers/ctokens#ctoken-error-codes
      emit MyLog("If this is not 0, there was an error", redeemResult);

      return true;
  }

  function redeemCEth(
      uint256 amount,
      bool redeemType,
      address _cEtherContract
  ) public returns (bool) {
      // Create a reference to the corresponding cToken contract
      ICEther cToken = ICEther(_cEtherContract);

      // `amount` is scaled up by 1e18 to avoid decimals

      uint256 redeemResult;

      if (redeemType == true) {
          // Retrieve your asset based on a cToken amount
          redeemResult = cToken.redeem(amount);
      } else {
          // Retrieve your asset based on an amount of the asset
          redeemResult = cToken.redeemUnderlying(amount);
      }

      // Error codes are listed here:
      // https://compound.finance/docs/ctokens#ctoken-error-codes
      emit MyLog("If this is not 0, there was an error", redeemResult);

      return true;
  }

  // Need this to receive ETH when `borrowEthExample` and calling `redeemCEth` executes
  fallback() external payable {}
}
