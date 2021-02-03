import TradeActionModal from "./TradeActionModal";

import { Box, Button, Flex } from 'rimble-ui';
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
        <ActionButtonRow>
          <div className="manage-action__trade">
            <TradeActionModal provider={provider} fundAddress={address} />
          </div>
          <Button>Liquidity</Button>
          <Button>Leverage</Button>
        </ActionButtonRow>
      </ContainerLarge>
    </PageWrapper>
  );
}

const ActionButtonRow = styled(Flex)`
  width: 100%;
  flex-flow: row;
  justify-content: space-between;
`

const PageWrapper = styled.div`
  width: 100%;
`

const ContainerLarge = styled(Box)`
  position: relative;
  margin: 0 auto;
  max-width: var(--screen-md-max);
`

export default FundManageActions;
