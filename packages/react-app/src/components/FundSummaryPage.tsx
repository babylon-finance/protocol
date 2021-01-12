import FundCardRow from "./FundCardRow";

import { Box } from 'rimble-ui';
import React, { useState, useEffect } from "react";
import styled from "styled-components";

interface FundSummaryPageProps {
  appState: any
}

const FundSummaryPage = ({ appState }: FundSummaryPageProps) => {
  return (
    <ContentWrapper>
      <ContainerLarge>
        <div style={{
          display: 'flex',
          flexFlow: 'row wrap',
          margin: '10px 0'
        }}>
        </div>
        <div>
          <FundCardRowWrapper>
            <FundCardRow
              provider={appState.provider}
              userAddress={appState.address}
            />
          </FundCardRowWrapper>
        </div>
      </ContainerLarge>
    </ContentWrapper>
  );
}

const ContainerLarge = styled(Box)`
  position: relative;
`
const ContentWrapper = styled.div`
  display: flex;
  flex-flow: column nowrap;
  justify-content: left;
  align-items: center;
  text-align: center;
  width: 100%;
  height: auto;
`

const FundCardRowWrapper = styled.div`
  div:not(:first-child) {
    margin-left: 12px;
  }
  margin-top: 50px;
`

export default FundSummaryPage;
