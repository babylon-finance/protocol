import * as addresses from "../contracts/addresses";
import * as contractNames from "../constants/contracts";
import { formatTokenDisplay } from "./Numbers";
import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";

import { BigNumber } from "@ethersproject/bignumber";
import { parseEther } from "@ethersproject/units";

export interface PairQuoteProps {
  provider: any
  providingAmount: number
  providingAddress: string
  receivingAddress: string
}

export interface PairQuote {
  expectedRate: BigNumber
  expectedRateDisplay: string
  worstRate: BigNumber
  worstRateDisplay: string
}

export const EMPTY_PAIR_QUOTE = {
  expectedRate: BigNumber.from(0),
  expectedRateDisplay: "0",
  worstRate: BigNumber.from(0),
  worstRateDisplay: "0"
};

// Update this to check both Kyber and 1Inch then return the best quote
// and which aggregator to use.
export async function getBestPairQuote(props: PairQuoteProps) {
  const kyber = await loadContractFromNameAndAddress(
    addresses.kyber.proxy,
    contractNames.IKyberNetworkProxy,
    props.provider
  );
  const quote = await kyber?.getExpectedRate(
    props.providingAddress,
    props.receivingAddress,
    parseEther(props.providingAmount.toString() || "0")
  );
  const expectedReturn = quote[0].mul(BigNumber.from(props.providingAmount));
  const worstReturn = quote[1].mul(BigNumber.from(props.providingAmount));

  return ({
    expectedRate: quote[0],
    expectedRateDisplay: formatTokenDisplay(expectedReturn),
    worstRate: quote[1],
    worstRateDisplay: formatTokenDisplay(worstReturn)
  });
}
