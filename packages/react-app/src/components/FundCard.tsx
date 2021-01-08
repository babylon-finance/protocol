import FundCardChart from "./FundCardChart";
import DepositModal from "./DepositModal";
import WithdrawModal from "./WithdrawModal";

import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";

import { formatEther } from "@ethersproject/units";
import BigNumber from "@ethersproject/bignumber";
import { usePoller } from "eth-hooks";
import React, { useState, useEffect } from "react";
import styled from "styled-components";
import { Card } from 'rimble-ui';
import contracts from "../contracts/contracts";

interface FundCardProps {
  provider: any
  contractAddress: string
  userAddress: string
}

interface Contributor {
  totalDeposit: any
  tokensReceived: number
  lastDeposit: number
}

interface Contracts {
  ClosedFund: any
  IERC20: any
}

// TODO(tylerm): Move these under a const file that we cna reuse
const fundContractName = "ClosedFund";
const tokenContractName = "IERC20";

const FundCard = ({ provider, contractAddress, userAddress }: FundCardProps) => {
  const [loading, setLoading] = useState("true");
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);
  const [fundName, setFundName] = useState("");
  const [contributor, setContributor] = useState<Contributor | undefined>(undefined);
  const [isFundManager, setIsFundManager] = useState(false);
  const [hasPosition, setHasPosition] = useState(false);
  const [fundActive, setFundActive] = useState(false);
  const [fundIntegrations, setFundIntegrations] = useState<string[]>([]);
  const [tokenBalance, setTokenBalance] = useState<number>(0);

  const getFundMetaPoller = async () => {
    let latestBalance;
    if (contracts) {
      //
      latestBalance = await contracts.IERC20.balanceOf(userAddress);
    }
    if (latestBalance) {
      setHasPosition(latestBalance > 0);
    }
  };

  useEffect(() => {
    async function getContracts() {
      const fund = await loadContractFromNameAndAddress(contractAddress, fundContractName, provider);
      const token = await loadContractFromNameAndAddress(contractAddress, tokenContractName, provider);
      setContracts({ ClosedFund: fund, IERC20: token });
      if (token) {
        setTokenBalance(await token.balanceOf(userAddress));
      }
    }

    if (!contracts) {
      getContracts();
    }

    async function getIsFundManager() {
      if (contracts) {
        setIsFundManager(await contracts.ClosedFund.manager() === userAddress);
      }
    }

    async function getMeta() {
      if (contracts) {
        setFundName(await contracts.ClosedFund.name());
        setFundActive(await contracts.ClosedFund.active());
        setFundIntegrations(await contracts.ClosedFund.getIntegrations());

        const maybeContributor = await contracts.ClosedFund.getContributor(userAddress);

        if (maybeContributor) {
          const totalDeposit = maybeContributor[0];

          setContributor({
            totalDeposit: totalDeposit,
            tokensReceived: maybeContributor[1].toNumber(),
            lastDeposit: maybeContributor[2].toNumber()
          });

          if (tokenBalance > 0) {
            setHasPosition(true);
          }
        }
      }
    }

    if (!contracts) {
      getContracts();
    }

    getMeta();
    getIsFundManager();
    setLoading("false");
  }, [contracts, contractAddress, provider, userAddress, tokenBalance]);

  usePoller(async () => {
    if (contracts) {
      getFundMetaPoller();
    }
  }, 500);

  return (
    <FundCardWrapper loading={loading}>
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
      <FundCardButtonRow>
        <FundCardActionButton>
          <DepositModal
            active={fundActive}
            provider={provider}
            contractAddress={contractAddress}
            userAddress={userAddress} />
        </FundCardActionButton>
        {hasPosition && (
          <FundCardActionButton>
            <WithdrawModal
              active={fundActive}
              provider={provider}
              contractAddress={contractAddress}
              userAddress={userAddress}
              contributor={contributor} />
          </FundCardActionButton>
        )}
      </FundCardButtonRow>
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

const FundCardActionButton = styled.div`
  flex: 1;
  flex-shrink: 0
`

const FundCardButtonRow = styled.div`
  margin-top: 25px;
  display: flex;
`

export default FundCard;
