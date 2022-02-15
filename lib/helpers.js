const { ethers } = require('ethers');

function eth(value = 1) {
  return ethers.utils.parseEther(value.toString());
}

function formatNumber(num) {
  // String with formatted number
  var totalStr = '';
  // Convert number to string
  var numStr = num + '';
  // Separate number on before point and after
  var parts = numStr.split('.');
  // Save length of rounded number
  var numLen = parts[0].length;
  // Start iterating numStr chars
  for (var i = 0; i < numLen; i++) {
    // Position of digit from end of string
    var y = numLen - i;

    // If y is divided without remainder on 3...
    if (i > 0 && y % 3 == 0) {
      // add aposrtoph when greater than 6 digit
      // or add point when smaller than 6 digit
      totalStr += y >= 6 ? "'" : ',';
    }

    // Append current position digit to total string
    totalStr += parts[0].charAt(i);
  }
  return `${totalStr}.${parts[1].slice(0, 2)}`;
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function formatUnit(num) {
  return formatNumber(ethers.utils.formatUnits(num, 'ether'));
}

module.exports = {
  from: ethers.BigNumber.from,
  parse: ethers.utils.parseEther,
  eth,
  formatNumber,
  formatUnit,
  sleep,
};
