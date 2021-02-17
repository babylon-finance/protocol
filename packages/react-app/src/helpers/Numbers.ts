import { BigNumber } from "@ethersproject/bignumber";
import { commify, formatEther } from "@ethersproject/units";

export const formatTokenDisplay = (value: BigNumber) => {
  const MAX_CHARS = 7;
  const splitArray = formatEther(value).split('.');

  if (splitArray[0].length < MAX_CHARS) {
    return commify(splitArray[0] + "." + splitArray[1].substring(0, (MAX_CHARS - splitArray[0].length)));
  } else {
    return commify(splitArray[0]);
  }
};

export const formatBigNumberDate = (value: BigNumber) => {
  return new Date(value.toNumber() * 1000);
};
