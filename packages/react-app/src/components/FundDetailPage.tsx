import BaseActionForm from "./BaseActionForm";
import DepositModal from "./DepositModal";
import FundDetailChart from "./FundDetailChart";
import PassiveActionForm from "./PassiveActionForm";
import WithdrawModal from "./WithdrawModal";

import * as contractNames from "../constants/contracts";
import { formatTokenDisplay, formatBigNumberDate } from "../helpers/Numbers";
import { Token, TokensMapByAddress } from "../constants/GlobalTokenList";
import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";
import { usePoller } from "eth-hooks";

import { BigNumber } from "@ethersproject/bignumber";
import { commify, formatEther, parseEther } from "@ethersproject/units";
import { Link } from "react-router-dom";
import React, { useState, useEffect } from 'react';
import { Avatar, Box, Button, Flex, Loader, Table } from 'rimble-ui';
import { useParams } from "react-router-dom";
import styled from "styled-components";
import { useCallback } from "react";

interface FundDetailPageState { }

interface FundDetailPageProps {
  provider?: any
  userAddress?: any
}

interface Position {
  token: Token
  amount: BigNumber
}

interface FundDetails {
  name: string
  active: boolean
  positions: Position[]
  reserveAsset: string
  integrations: string[]
  totalContributors: BigNumber
  totalFunds: BigNumber
  fundEndDate: BigNumber
}

interface Contracts {
  ClosedFund: any
  FundIdeas: any
}

interface Contributor {
  totalDeposit: any
  tokensReceived: number
  lastDeposit: number
}

const INITIAL_DETAILS: FundDetails = {
  name: "",
  active: false,
  positions: [],
  reserveAsset: "",
  integrations: [],
  totalContributors: BigNumber.from(0),
  totalFunds: BigNumber.from(0),
  fundEndDate: BigNumber.from(0)
}

const FundDetailPage = ({ provider, userAddress }: FundDetailPageProps) => {
  const [isLoading, setIsLoading] = useState(true);
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);
  const [contributor, setContributor] = useState<Contributor | undefined>(undefined);
  const [contributors, setContributors] = useState<string[]>([]);
  const [fundDetails, setFundDetails] = useState<FundDetails>(INITIAL_DETAILS);
  const [positions, setPositions] = useState<Position[]>([]);
  const [tokenBalance, setTokenBalance] = useState<number>(0);
  const [userHasPosition, setUserHasPosition] = useState(false);

  let { address } = useParams();

  const getFundMetaPoller = async () => {
    if (contracts && provider) {
      fetchContributorDetails();
      fetchFundDetails();
      fetchPositionDetails();
      fetchContributors();
    }
  };

  const fetchFundDetails = useCallback(async () => {
    if (contracts?.ClosedFund) {
      setFundDetails({
        name: await contracts.ClosedFund.name(),
        active: await contracts.ClosedFund.active(),
        positions: await contracts.ClosedFund.getPositions(),
        reserveAsset: await contracts.ClosedFund.getReserveAsset(),
        integrations: await contracts.ClosedFund.getIntegrations(),
        totalContributors: await contracts.ClosedFund.totalContributors(),
        totalFunds: await contracts.ClosedFund.totalFundsDeposited(),
        fundEndDate: await contracts.ClosedFund.fundEndsBy()
      });
    }
  }, [contracts]);

  const fetchPositionDetails = useCallback(async () => {
    if (contracts?.ClosedFund) {
      const addresses = await contracts.ClosedFund.getPositions();
      const positions: Promise<Position>[] = await addresses.map(async address => {
        const token = TokensMapByAddress.get(address);
        const erc20 = await loadContractFromNameAndAddress(address, contractNames.IERC20, provider);
        const amount = await erc20?.balanceOf(address);

        return { token: token, amount: amount };
      });

      const mergedPositions = await Promise.all(positions);

      setPositions(mergedPositions);
    }
  }, [contracts, provider]);

  const fetchContributorDetails = useCallback(async () => {
    if (contracts?.ClosedFund && userAddress) {
      const maybeContributor = await contracts.ClosedFund.getContributor(userAddress);

      if (maybeContributor) {
        const totalDeposit = maybeContributor[0];

        setContributor({
          totalDeposit: totalDeposit,
          tokensReceived: maybeContributor[1].toNumber(),
          lastDeposit: maybeContributor[2].toNumber()
        });

        if (tokenBalance > 0) {
          setUserHasPosition(true);
        }
      }
    }
  }, [contracts, tokenBalance, userAddress]);

  // This could be a very large array at some point. Consider how to paginate or similar
  const fetchContributors = useCallback(async () => {
    if (contracts?.ClosedFund) {
      //setContributors(await contracts.ClosedFund.contributors());
    }
  }, [contracts]);

  const initialize = useCallback(async () => {
    const fund = await loadContractFromNameAndAddress(address, contractNames.ClosedFund, provider);
    let fundIdeas;
    if (fund) {
      const ideasAddress = await fund.fundIdeas();
      fundIdeas = await loadContractFromNameAndAddress(ideasAddress, contractNames.FundIdeas, provider);
    }

    setContracts({ ClosedFund: fund, FundIdeas: fundIdeas });

    if (fund) {
      setTokenBalance(await fund.balanceOf(userAddress));
    }
  }, [address, provider, userAddress]);

  useEffect(() => {
    setIsLoading(true);
    if (!contracts && provider) {
      initialize();
    }
    fetchFundDetails();
    fetchPositionDetails();
    fetchContributorDetails();
    fetchContributors();
    setIsLoading(false);
  }, [contracts, fundDetails, fetchContributors, fetchFundDetails, fetchContributorDetails, fetchPositionDetails, initialize, provider]);

  usePoller(async () => {
    if (contracts) {
      getFundMetaPoller();
    }
  }, 5000);

  return (
    <ContainerLarge>
      <ContentWrapper>
        <HeroRow>
          <TitleBoxLeft>
            <TitleHero>
              {fundDetails.name}
            </TitleHero>
          </TitleBoxLeft>
          <TitleBoxRight>
            {userHasPosition && contributor && (
              <InvestorStatsRow>
                <InvestorStatsItem>
                  <InvestorStatsItemLabel>
                    Your Position
                    </InvestorStatsItemLabel>
                  <InvestorStatsItemMetric>
                    {formatEther(contributor.totalDeposit)}Ξ
                  </InvestorStatsItemMetric>
                </InvestorStatsItem>
                <InvestorStatsItem>
                  <InvestorStatsItemLabel>
                    Your Return
                  </InvestorStatsItemLabel>
                  <InvestorStatsItemMetric>
                    20.50%
                    </InvestorStatsItemMetric>
                </InvestorStatsItem>
                <InvestorStatsItem>
                  <InvestorStatsItemLabel>
                    End Date
                  </InvestorStatsItemLabel>
                  <InvestorStatsItemMetric>
                    {formatBigNumberDate(fundDetails.fundEndDate).toLocaleDateString("en-US")}
                  </InvestorStatsItemMetric>
                </InvestorStatsItem>
              </InvestorStatsRow>
            )}
          </TitleBoxRight>
        </HeroRow>
        <DetailsWrapper>
          <DetailsBlockLeft>
            <DetailsDescription>
              This strategy aims to generate ETH for investors by exploiting changes in market structure and offering positive convexity in both up and down markets. We believe ETH will outperform BTC and USD in the medium term. The goal is to accumulate more ETH while capturing upside. No impermanent loss will occur because we will not be exchanging the underlying ETH assets. We will use crypto lending protocols to obtain a safe position of stablecoin borrowings that can be used to engage in liquidity pool, staking, and yield farming opportunities.
            </DetailsDescription>
            <DetailsPerformance>
              <DetailsGroup>
                <DetailsGroupLabel>
                  Risk Profile
                </DetailsGroupLabel>
                <DetailsGroupMetricRow>
                  <DetailsGroupMetricItem>
                    Sortino: 0.1
                  </DetailsGroupMetricItem>
                  <DetailsGroupMetricItem>
                    Value at Risk: 0.01
                </DetailsGroupMetricItem>
                </DetailsGroupMetricRow>
              </DetailsGroup>
              <DetailsGroup>
                <DetailsGroupLabel>
                  Fee Structure
                </DetailsGroupLabel>
                <DetailsGroupMetricRow>
                  <DetailsGroupMetricItem>
                    Exit: 0.5%
                    </DetailsGroupMetricItem>
                  <DetailsGroupMetricItem>
                    Performance: 10%
                  </DetailsGroupMetricItem>
                </DetailsGroupMetricRow>
              </DetailsGroup>
            </DetailsPerformance>
            <DetailsFees>
            </DetailsFees>
          </DetailsBlockLeft>
          <DetailsBlockRight>
            <InvestorActionButtonRow>
              {provider && (
                <InvestorActionButton>
                  <DepositModal
                    active={fundDetails.active}
                    provider={provider}
                    contractAddress={address}
                    userAddress={userAddress} />
                </InvestorActionButton>
              )}
              {userHasPosition && (
                <InvestorActionButton>
                  <WithdrawModal
                    active={fundDetails.active}
                    provider={provider}
                    contractAddress={address}
                    userAddress={userAddress}
                    contributor={contributor} />
                </InvestorActionButton>
              )}
            </InvestorActionButtonRow>
            <FundStatsRow>
              <FundStatsItem>
                <FundStatsItemLabel>
                  Total Contributors
                  </FundStatsItemLabel>
                <FundStatsItemMetric>
                  {fundDetails.totalContributors.toNumber()}
                </FundStatsItemMetric>
              </FundStatsItem>
              <FundStatsItem>
                <FundStatsItemLabel>
                  Total Deposits
                  </FundStatsItemLabel>
                <FundStatsItemMetric>
                  {formatEther(fundDetails.totalFunds)}Ξ
                </FundStatsItemMetric>
              </FundStatsItem>
              <FundStatsItem>
                <FundStatsItemLabel>
                  APY
                  </FundStatsItemLabel>
                <FundStatsItemMetric>
                  80%
                </FundStatsItemMetric>
              </FundStatsItem>
            </FundStatsRow>
          </DetailsBlockRight>
        </DetailsWrapper>
        <PerformanceWrapper>
          <PerformanceBlockLeft>
            <PerformanceBlockTitle>
              Performance
            </PerformanceBlockTitle>
            <FundDetailChart height={275} />
          </PerformanceBlockLeft>
          <PerformanceBlockRight>
            <PerformanceBlockTitle>
              Positions
            </PerformanceBlockTitle>
            <PerformanceTable>
              <thead>
                <tr>
                  <th>Asset</th>
                  <th></th>
                  <th>Quantity</th>
                  <th>Value</th>
                  <th>Change</th>
                </tr>
              </thead>
              <tbody>
                {positions.map(position => {
                  return (
                    <tr key={position.token.address}>
                      <td>
                        <Avatar src={position.token.logoURI} />
                      </td>
                      <th>{position.token.symbol}</th>
                      <td>{formatTokenDisplay(position.amount)}</td>
                      <td>100.10</td>
                      <td>+25%</td>
                    </tr>
                  )
                })}
              </tbody>
            </PerformanceTable>
          </PerformanceBlockRight>
        </PerformanceWrapper>
        <TabbedActionsWrapper>
          {contracts && (
            <BaseActionForm provider={provider} fundContract={contracts.ClosedFund} fundIdeasContract={contracts.FundIdeas} />
          )}
        </TabbedActionsWrapper>
      </ContentWrapper>
    </ContainerLarge>
  );
}

const TabbedActionsWrapper = styled(Box)`
  margin-top: 40px;
  width: 100%;
  background: white;
  border: 1px #ccc solid;
  height: 700px;
`

const PerformanceTable = styled(Table)`
  height: 275px;
  background: white;
  font-family: cera-regular;
`

const PerformanceBlockTitle = styled.h2``

const PerformanceWrapper = styled(Flex)`
  flex-flow: row nowrap;
  padding-top: 40px;
`

const PerformanceBlockRight = styled.div`
  flex: 1;
  padding-left: 25px;
`

const PerformanceBlockLeft = styled.div`
  flex: 1;
  padding-right: 25px;
`

const ContainerLarge = styled(Box)`
  position: relative;
  margin: 0 auto;
  width: var(--screen-md-max);
`

const ContentWrapper = styled.div`
  padding: 20px 6px 0 6px;
`

const DetailsDescription = styled.p`
`

const DetailsWrapper = styled(Flex)`
  flex-flow: row nowrap;
`

const DetailsManager = styled(Flex)`
  flex-flow: row;
  padding-bottom: 10px;
`

const DetailsBlockLeft = styled(Box)`
  flex: 1;
  flex-flow: column;
  padding-right: 25px;
`

const DetailsBlockRight = styled(Box)`
  flex: 1;
  flex-flow: column;
  padding-left: 25px;
`

const DetailsGroup = styled(Box)`
  display: flex;
  flex-flow: column;
`

const DetailsPerformance = styled(Flex)`
  flex-flow: row;
  justify-content: space-between;
  padding: 25px 0;
`

const DetailsFees = styled(Flex)`
  flex-flow: column nowrap;
`

const DetailsGroupMetricRow = styled(Flex)`
  flow-flow: row nowrap;
`

const DetailsGroupMetricItem = styled.div`
  font-family: cera-light;
  font-size: 18px;
  padding-right: 12px;
`

const DetailsGroupLabel = styled.h3`
`

const FundStatsRow = styled(Box)`
  display: flex;
  flex-flow: row;
  margin-top: 146px;
`

const FundStatsItem = styled(Flex)`
  flex-grow: 1;
  flex-flow: column nowrap;
`

const FundStatsItemLabel = styled.h3`
  font-family: cera-bold;
  text-align: left;
`

const FundStatsItemMetric = styled.p`
  font-family: cera-light;
  font-size: 18px;
  text-align: left;
`

const HeroRow = styled(Box)`
  display: flex;
  flex-flow: row;
`

const InvestorActionButton = styled.div`
  flex: 1;
  flex-shrink: 0
`

const InvestorActionButtonRow = styled.div`
  margin-top: 25px;
  display: flex;
  padding: 0;
`

const InvestorStatsRow = styled(Flex)`
  padding-top: 16px;
  flex-flow: row;
`

const InvestorStatsItem = styled(Flex)`
  flex-grow: 1;
  flex-flow: column nowrap;
`

const InvestorStatsItemLabel = styled.span`
  font-family: cera-bold;
  font-size: 20px;
  text-align: left;
`

const InvestorStatsItemMetric = styled.span`
  font-family: cera-light;
  font-size: 24px;
  text-align: left;
`

const ManagerLabel = styled.span`
  font-family: cera-bold;
`

const ManagerName = styled.span`
  font-family: cera-regular;
  margin-left: 4px;
`

const ManagerPosition = styled.div`
  margin-left: 25px;
  text-align: right;
  padding-top: 2px;
`

const TitleHero = styled.span`
  height: 50px;
  font-family: cera-bold;
  font-size: 36px;
`

const TitleBoxLeft = styled(Box)`
  flex: 1;
  padding: 10px 25px 18px 0;
`

const TitleBoxRight = styled(Box)`
  flex: 1;
  padding: 10px 0 18px 25px;
`

export default FundDetailPage;
