import { BigNumber } from "@ethersproject/bignumber";

export default class InvestmentIdea {
  capitalRequested: BigNumber
  stake: BigNumber
  investmentDuration: BigNumber
  enterData: string
  exitData: string
  integration: string
  expectedReturn: BigNumber
  enterTokensNeeded: string[]
  enterTokensAmounts: BigNumber[]

  constructor (
    capitalRequested: BigNumber,
    stake: BigNumber,
    investmentDuration: BigNumber,
    enterData: string,
    exitData: string,
    integration: string,
    expectedReturn: BigNumber,
    enterTokensNeeded: string[],
    enterTokensAmounts: BigNumber[]
   ) {
      this.capitalRequested = capitalRequested;
      this.stake = stake;
      this.investmentDuration = investmentDuration;
      this.enterData = enterData;
      this.exitData = exitData;
      this.integration = integration;
      this.expectedReturn = expectedReturn;
      this.enterTokensNeeded = enterTokensNeeded;
      this.enterTokensAmounts = enterTokensAmounts;
  }

  getProps() {
    return [
      this.capitalRequested,
      this.stake,
      this.investmentDuration,
      this.enterData,
      this.exitData,
      this.integration,
      this.expectedReturn,
      this.enterTokensNeeded,
      this.enterTokensAmounts,
    ]
  }
}
