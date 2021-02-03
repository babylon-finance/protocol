import DepositModal from "./DepositModal";
import FundDetailChart from "./FundDetailChart";
import FundManageActions from "./FundManageActions";
import WithdrawModal from "./WithdrawModal";

import * as addresses from "../contracts/addresses";
import * as contractNames from "../constants/contracts";
import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";

import {
  Link,
  Switch,
  Route
} from "react-router-dom";
import { usePoller } from "eth-hooks";
import { commify, formatEther, parseEther } from "@ethersproject/units";
import React, { useState, useEffect } from 'react';
import { Avatar, Box, Button, Flex, Loader, Table } from 'rimble-ui';
import { useParams, useRouteMatch } from "react-router-dom";
import styled from "styled-components";

interface FundDetailPageState { }

interface FundDetailPageProps {
  provider: any
  userAddress: any
}

interface Token {
  chainId: number;
  address: string;
  name: string;
  symbol: string;
  decimals: number;
  logoURI: string;
}

interface Position {
  token: Token
  ammount: number
}

interface FundDetails {
  name: string
  active: boolean
  rollDate: number
  positions: Position[]
}

interface Contracts {
  ClosedFund: any
  DAI: any
  WETH: any
}

interface Contributor {
  totalDeposit: any
  tokensReceived: number
  lastDeposit: number
}

const INITIAL_DETAILS = {
  name: "",
  active: false,
  rollDate: 0,
  positions: []
}

const FundDetailPage = ({ provider, userAddress }: FundDetailPageProps) => {
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);
  const [contributor, setContributor] = useState<Contributor | undefined>(undefined);
  const [daiPosition, setDaiPosition] = useState("");
  const [fundDetails, setFundDetails] = useState<FundDetails>(INITIAL_DETAILS);
  const [isLoading, setIsLoading] = useState(true);
  const [isFundManager, setIsFundManager] = useState(false);
  const [tokenBalance, setTokenBalance] = useState<number>(0);
  const [userHasPosition, setUserHasPosition] = useState(false);
  const [wethPosition, setWethPosition] = useState("");

  const currDate = Date.now();

  let { path, url } = useRouteMatch();
  let { address } = useParams();

  const getFundMetaPoller = async () => {
    let latestBalance;
    if (contracts) {
      latestBalance = await contracts.ClosedFund.balanceOf(userAddress);
    }
    if (latestBalance) {
      setUserHasPosition(latestBalance > 0);
    }
  };

  useEffect(() => {
    async function getContracts() {
      const fund = await loadContractFromNameAndAddress(address, contractNames.ClosedFund, provider);
      // TODO(undfined): Grab these addresses as an array from the fund and then map over to build up the positions
      const daiToken = await loadContractFromNameAndAddress(addresses.tokens.DAI, contractNames.IERC20, provider);
      const wethToken = await loadContractFromNameAndAddress(addresses.tokens.WETH, contractNames.IERC20, provider);

      setContracts({ ClosedFund: fund, DAI: daiToken, WETH: wethToken });

      if (fund) {
        setTokenBalance(await fund.balanceOf(userAddress));
      }

      if (daiToken) {
        setDaiPosition(formatEther(await daiToken.balanceOf(address)));
      }

      if (wethToken) {
        setWethPosition(formatEther(await wethToken.balanceOf(address)));
      }
    }

    if (!contracts && provider) {
      getContracts();
    }

    async function getMeta() {
      if (contracts) {
        setFundDetails({
          name: await contracts.ClosedFund.name(),
          active: await contracts.ClosedFund.active(),
          rollDate: 0,
          positions: []
        })

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

        setIsLoading(false);
      }
    }

    async function getIsFundManager() {
      if (contracts) {
        setIsFundManager(await contracts.ClosedFund.manager() === userAddress);
      }
    }

    getIsFundManager();
    getMeta();
  });

  //usePoller(async () => {
  //  if (contracts) {
  //    getFundMetaPoller();
  //  }
  //}, 5000);

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
                    Ξ{formatEther(contributor.totalDeposit)}
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
                    03/31/2021
                  </InvestorStatsItemMetric>
                </InvestorStatsItem>
              </InvestorStatsRow>
            )}
          </TitleBoxRight>
        </HeroRow>
        <DetailsWrapper>
          <DetailsBlockLeft>
            <DetailsManager>
              <ManagerLabel>
                Managed By:
              </ManagerLabel>
              <ManagerName>
                Babylon.labs
              </ManagerName>
              <ManagerPosition>
                Holds <b>10%</b> of this fund
              </ManagerPosition>
            </DetailsManager>
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
              <InvestorActionButton>
                <DepositModal
                  active={fundDetails.active}
                  provider={provider}
                  contractAddress={address}
                  userAddress={userAddress} />
              </InvestorActionButton>
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
              {isFundManager && (
                <ManageLink to={`${url}/manage`}>
                  <ManageActionButton>Manage</ManageActionButton>
                </ManageLink>
              )}
            </InvestorActionButtonRow>
            <FundStatsRow>
              <FundStatsItem>
                <FundStatsItemLabel>
                  Total Contributors
                  </FundStatsItemLabel>
                <FundStatsItemMetric>
                  100
                  </FundStatsItemMetric>
              </FundStatsItem>
              <FundStatsItem>
                <FundStatsItemLabel>
                  Net Asset Value
                  </FundStatsItemLabel>
                <FundStatsItemMetric>
                  $1,000,000
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
                <tr>
                  <td>
                    <Avatar src="https://airswap-token-images.s3.amazonaws.com/DAI.png" />
                  </td>
                  <th>DAI</th>
                  <td>{daiPosition}</td>
                  <td>100.10</td>
                  <td>+25%</td>
                </tr>
                <tr>
                  <td>
                    <Avatar src="https://airswap-token-images.s3.amazonaws.com/WETH.png" />
                  </td>
                  <th>wETH</th>
                  <td>{wethPosition}</td>
                  <td>100.10</td>
                  <td>+25%</td>
                </tr>
                <tr>
                  <td>
                    <Avatar src="https://airswap-token-images.s3.amazonaws.com/WBTC.png" />
                  </td>
                  <th>wBTC</th>
                  <td>0</td>
                  <td>100.10</td>
                  <td>+25%</td>
                </tr>
              </tbody>
            </PerformanceTable>
          </PerformanceBlockRight>
        </PerformanceWrapper>
      </ContentWrapper>
      <Switch>
        <Route path={`${path}/manage`} children={<FundManageActions provider={provider} />} />
      </Switch>
    </ContainerLarge>
  );
}

const ManageLink = styled(Link)`
  margin-left: auto;
  display: flex;
  align-items: center;
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

const ManageActionButton = styled(Button.Outline)`
  font-family: cera-regular;
  color: var(--primary);
  background-color: var(--white);
  margin-left: 8px;
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
