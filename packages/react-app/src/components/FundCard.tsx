import FundCardChart from "./FundCardChart";
import InvestModal from "./InvestModal";

import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";
import { usePoller } from "eth-hooks";
import React, { useState, useEffect } from "react";
import styled from "styled-components";
import { Card } from 'rimble-ui';

interface FundCardProps {
  provider: any
  address: string
  callback: any
}

const contractName = "BaseFund";

const FundCard = ({ provider, address, callback }: FundCardProps) => {
  const [isLoaded, setIsLoaded] = useState("false");
  const [contract, setContract] = useState();
  const [fundName, setFundName] = useState("");

  useEffect(() => {
    async function getContract() {
      setContract(await loadContractFromNameAndAddress(address, contractName, provider));
    }
    if (!contract) {
      getContract();
    }
  })

  usePoller(async () => {
    if (contract) {
      setIsLoaded("true");
      setFundName(await contract.name());
    }
  }, 1000);

  return (
    <FundCardWrapper loading={isLoaded}>
      <FundCardHeader>
        <FundTokenSymbol>ABCD</FundTokenSymbol>
        {fundName}
      </FundCardHeader>
      <FundCardDesc>
        This is a subheading and brief description of the fund.
      </FundCardDesc>
      <FundCompositionBlock>
        <FundCompositionLabel>Composition</FundCompositionLabel>
        <FundCompositionItem>ETH Long  50%</FundCompositionItem>
        <FundCompositionItem>USD Short 50%</FundCompositionItem>
      </FundCompositionBlock>
      <FundPerfomanceHistogram>
        <FundCardChart />
      </FundPerfomanceHistogram>
      <FundPerformanceBlock>
        <FundPerformanceReturns>Performance: +300%</FundPerformanceReturns>
        <FundPerformanceAmount>Invested: 300 ETH</FundPerformanceAmount>
        <FundPerformanceAmount>Participants: 300</FundPerformanceAmount>
      </FundPerformanceBlock>
      <FundCardInvestButtonWrapper>
        <InvestModal provider={provider} contract={contract} address={address} />
      </FundCardInvestButtonWrapper>
    </FundCardWrapper>
  );
}

const FundCardWrapper = styled(Card)`
  width: 450px;
  height: 625px;
`

const FundTokenSymbol = styled.div`
  margin: 0 8px 0 0;
  font-weight: 600;
`

const FundCardHeader = styled.div`
  color: #160E6B;
  padding: 12px 12px 0 12px;
  font-size: 1.5em;
  display: flex;
`

const FundCardDesc = styled.div`
  padding: 8px 12px 0 12px;
  text-align: left;
  font-size: 1em;
  margin-bottom: 10px;
`

const FundCompositionBlock = styled.div`
  color: #160E6B;
  border-top: 1px solid #D3D3D3;
  padding: 8px 12px 0 12px;
  height: 100px;
  margin-bottom: 10px;
`

const FundCompositionLabel = styled.div`
  text-align: left;
  margin-bottom: 8px;
  font-size: 1.1em
`

const FundCompositionItem = styled.div`
  text-align: left;
  font-size: 0.85em;
`

const FundPerformanceBlock = styled.div`
  color: #160E6B;
  padding: 8px 12px 0 12px;
  border-top: 1px solid #D3D3D3;
  display: flex;
  text-align: left
`

const FundPerformanceReturns = styled.div`
  padding: 8px 12px 0 12px;
`

const FundPerformanceAmount = styled.div`
  padding: 8px 12px 0 12px;
`

const FundPerfomanceHistogram = styled.div`
  background: white;
`

const FundCardInvestButtonWrapper = styled.div`
`

export default FundCard;
