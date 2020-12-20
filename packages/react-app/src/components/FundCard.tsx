import FundCardChart from "./FundCardChart";

import React from "react";
import Highcharts from "highcharts/highstock"
import HighchartsReact from "highcharts-react-official";
import styled from "styled-components";
import Web3 from "web3";
import Web3Modal from "web3modal";
import { getDefaultProvider, JsonRpcProvider, Web3Provider } from "@ethersproject/providers";
import { Alert, Button, Space, Spin } from "antd";

interface Props { }

export default class FundCard extends React.PureComponent<Props> {
  render() {
    return (
      <FundCardRow>
        <FundCardWrapper>
          <FundCardHeader>
            <FundTokenSymbol>ABCD</FundTokenSymbol>
            Fund Name
          </FundCardHeader>
          <FundCardDesc>
            This is a subheading and brief description of the fund.
          </FundCardDesc>
          <FundCompositionBlock>
            <FundCompositionLabel>Composition</FundCompositionLabel>
            <FundCompositionItem>ETH Long  50%</FundCompositionItem>
            <FundCompositionItem>USD Short 50%</FundCompositionItem>
          </FundCompositionBlock>
          <FundPerfomanceHistogram>[ GRAPH ]</FundPerfomanceHistogram>
          <FundPerformanceBlock>
            <FundPerformanceReturns>Performance: +300%</FundPerformanceReturns>
            <FundPerformanceAmount>Total Invested: 300 ETH</FundPerformanceAmount>
          </FundPerformanceBlock>
          <FundCardInvestButtonWrapper>
            <FundCardInvestButton>Invest</FundCardInvestButton>
          </FundCardInvestButtonWrapper>
        </FundCardWrapper>
        <FundCardWrapper>
          <FundCardHeader>
            <FundTokenSymbol>ABCD</FundTokenSymbol>
            Fund Name
          </FundCardHeader>
          <FundCardDesc>
            This is a subheading and brief description of the fund.
          </FundCardDesc>
          <FundCompositionBlock>
            <FundCompositionLabel>Composition</FundCompositionLabel>
            <FundCompositionItem>ETH Long  50%</FundCompositionItem>
            <FundCompositionItem>USD Short 50%</FundCompositionItem>
          </FundCompositionBlock>
          <FundPerfomanceHistogram>[ GRAPH ]</FundPerfomanceHistogram>
          <FundPerformanceBlock>
            <FundPerformanceReturns>Performance: +300%</FundPerformanceReturns>
            <FundPerformanceAmount>Total Invested: 300 ETH</FundPerformanceAmount>
          </FundPerformanceBlock>
          <FundCardInvestButtonWrapper>
            <FundCardInvestButton>Invest</FundCardInvestButton>
          </FundCardInvestButtonWrapper>
        </FundCardWrapper>
        <FundCardWrapper>
          <FundCardHeader>
            <FundTokenSymbol>ABCD</FundTokenSymbol>
            Fund Name
          </FundCardHeader>
          <FundCardDesc>
            This is a subheading and brief description of the fund.
          </FundCardDesc>
          <FundCompositionBlock>
            <FundCompositionLabel>Composition</FundCompositionLabel>
            <FundCompositionItem>ETH Long  50%</FundCompositionItem>
            <FundCompositionItem>USD Short 50%</FundCompositionItem>
          </FundCompositionBlock>
          <FundPerfomanceHistogram>[ GRAPH ]</FundPerfomanceHistogram>
          <FundPerformanceBlock>
            <FundPerfomanceHistogram></FundPerfomanceHistogram>
            <FundPerformanceReturns>Performance: +300%</FundPerformanceReturns>
            <FundPerformanceAmount>Total Invested: 300 ETH</FundPerformanceAmount>
          </FundPerformanceBlock>
          <FundCardInvestButtonWrapper>
            <FundCardInvestButton>Invest</FundCardInvestButton>
          </FundCardInvestButtonWrapper>
        </FundCardWrapper>
      </FundCardRow>
    );
  }
}

const FundCardRow = styled.div`
  margin-top: 50px;
  display: flex;
`

const FundCardWrapper = styled.div`
  display: flex;
  flex-direction: column;
  background: white;
  width: 350px;
  height: 550px;
  margin-right: 18px;
  border: 1px solid lightgray;
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
  margin-bottom: 10px;
  height: 80%;
  background: white;
`

const FundCardInvestButtonWrapper = styled.div`
  padding: 20px;
`

const FundCardInvestButton = styled.button`
  font-size: 18px;
  font-weight: 700;
  color: #160E6B;
  width: 90%;
  border-radius: 0;
  background: white;
  border: 1px solid #160E6B;

  &:hover {
    cursor: pointer;
    color: white;
    background: #160E6B;
  }
`
