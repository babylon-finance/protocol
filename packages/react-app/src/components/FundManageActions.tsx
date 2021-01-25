import TradeActionModal from "./TradeActionModal";

import { Box } from 'rimble-ui';
import React from "react";
import styled from "styled-components";
import { useParams } from "react-router-dom";

interface FundManageActionsProps {
  provider: any
}

const FundManageActions = ({ provider }: FundManageActionsProps) => {
  let { address } = useParams();
  return (
    <PageWrapper>
      <ContainerLarge>
        <h1>{address}</h1>
        <div className="manage-action__trade">
          <TradeActionModal provider={provider} fundAddress={address} />
        </div>
      </ContainerLarge>
    </PageWrapper>
  );
}

const PageWrapper = styled.div`
  width: 100%;
`

const ContainerLarge = styled(Box)`
  position: relative;
  margin: 0 auto;
  width: 1400px;
`

export default FundManageActions;
