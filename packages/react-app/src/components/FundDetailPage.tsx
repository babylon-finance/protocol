import FundDetailChart from "./FundDetailChart";
import FundManageActions from "./FundManageActions";

import * as addresses from "../contracts/addresses";
import * as contractNames from "../constants/contracts";
import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";

import {
  Link,
  Switch,
  Route
} from "react-router-dom";
import { formatEther } from "@ethersproject/units";
import React, { useState, useEffect } from 'react';
import { Avatar, Box, Flex, Table } from 'rimble-ui';
import { useParams, useRouteMatch } from "react-router-dom";
import styled from "styled-components";

interface FundDetailPageState { }

interface FundDetailPageProps {
  provider: any
  userAddress: any
}

interface Contracts {
  ClosedFund: any
  DAI: any
}

const FundDetailPage = ({ provider, userAddress }: FundDetailPageProps) => {
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);
  const [daiPosition, setDaiPosition] = useState("");
  const [wethPosition, setWethPosition] = useState("");
  const [isFundManager, setIsFundManager] = useState(false);
  const [tokenBalance, setTokenBalance] = useState<number>(0);

  let { path, url } = useRouteMatch();
  let { address } = useParams();

  useEffect(() => {
    async function getContracts() {
      const fund = await loadContractFromNameAndAddress(address, contractNames.ClosedFund, provider);
      const daiToken = await loadContractFromNameAndAddress(addresses.tokens.DAI, contractNames.IERC20, provider);
      const wethToken = await loadContractFromNameAndAddress(addresses.tokens.WETH, contractNames.IERC20, provider);

      setContracts({ ClosedFund: fund, DAI: daiToken });

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

    async function getIsFundManager() {
      if (contracts) {
        setIsFundManager(await contracts.ClosedFund.manager() === userAddress);
      }
    }

    getIsFundManager();
  });

  return (
    <ContainerLarge>
      <ContentWrapper>
        <TitleWrapper>
          <TitleHero>
            Cool Fund Name: {address.slice(0, 6)}
          </TitleHero>
          {isFundManager && (
            <ManageLink to={`${url}/manage`}>Manage</ManageLink>
          )}
          <StatsHero>
            <StatsHeroItem>
              <StatsHeroItemLabel>
                Total Contributors
              </StatsHeroItemLabel>
              <StatsHeroItemMetric>
                1,000
              </StatsHeroItemMetric>
            </StatsHeroItem>
            <StatsHeroItem>
              <StatsHeroItemLabel>
                Assets Under Management
              </StatsHeroItemLabel>
              <StatsHeroItemMetric>
                $100,000,000
              </StatsHeroItemMetric>
            </StatsHeroItem>
            <StatsHeroItem>
              <StatsHeroItemLabel>
                Daily Change
              </StatsHeroItemLabel>
              <StatsHeroItemMetric>
                +25%
              </StatsHeroItemMetric>
            </StatsHeroItem>
          </StatsHero>
        </TitleWrapper>
        <DetailsWrapper>
          <DetailsBlockLeft>
            <DetailsManager>
              <ManagerName>
                Manager: Ramon Recuero
              </ManagerName>
              <ManagerPosition>
                Holds <b>10%</b> of this fund
              </ManagerPosition>
            </DetailsManager>
            <DetailsDescription>
              I'm baby heirloom poke selfies, flannel normcore snackwave hella four dollar toast cloud
              bread twee palo santo distillery meggings fashion axe bushwick. Pabst literally keytar kitsch
              single-origin coffee hashtag kogi. Organic synth everyday carry freegan gluten-free vegan authentic.
              Crucifix fashion axe everyday carry microdosing street art aesthetic photo booth.
            </DetailsDescription>
          </DetailsBlockLeft>
          <DetailsBlockRight>
            <DetailsPerformance>
              <DetailsGroupLabel>
                Risk Profile
              </DetailsGroupLabel>
              <DetailsGroupMetricRow>
                <DetailsGroupMetricItem>
                  Sortino: 0.1
                </DetailsGroupMetricItem>
                <DetailsGroupMetricItem>
                  Alpha: 0.1
                </DetailsGroupMetricItem>
                <DetailsGroupMetricItem>
                  Value at Risk: 0.1
                </DetailsGroupMetricItem>
                <DetailsGroupMetricItem>
                  Standard Deviation: 0.1
                </DetailsGroupMetricItem>
              </DetailsGroupMetricRow>
            </DetailsPerformance>
            <DetailsFees>
              <DetailsGroupLabel>
                Fee Structure
              </DetailsGroupLabel>
              <DetailsGroupMetricRow>
                <DetailsGroupMetricItem>
                  Exit: 0.5%
                </DetailsGroupMetricItem>
                <DetailsGroupMetricItem>
                  Performance: 0.5%
                </DetailsGroupMetricItem>
              </DetailsGroupMetricRow>
            </DetailsFees>
          </DetailsBlockRight>
        </DetailsWrapper>
        <PerformanceWrapper>
          <PerformanceBlockLeft>
            <PerformanceBlockTitle>
              Performance
            </PerformanceBlockTitle>
            <FundDetailChart height={300} />
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
                  <td>100</td>
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
  height: 300px;
  background: white;
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
  width: 1400px;
`

const ContentWrapper = styled.div`
  padding: 20px 6px 0 6px;
`

const TitleWrapper = styled(Flex)`
  padding: 10px 0 18px 0;
  flex-flow: row nowrap;
`

const DetailsWrapper = styled(Flex)`
  flex-flow: row nowrap;
`

const DetailsManager = styled(Flex)`
  flex-flow: row nowrap;
`

const DetailsBlockLeft = styled(Flex)`
  flex: 1;
  flex-flow: column nowrap;
  padding-right: 25px;
`

const DetailsBlockRight = styled(Flex)`
  flex: 1;
  flex-flow: column nowrap;
  padding-left: 25px;
`

const DetailsPerformance = styled(Flex)`
  flex-flow: column nowrap;
  padding-bottom: 25px;
`

const DetailsFees = styled(Flex)`
  flex-flow: column nowrap;
`

const DetailsGroupMetricRow = styled(Flex)`
  flow-flow: row nowrap;
`

const DetailsGroupMetricItem = styled.div`
  padding-right: 12px;
`

const DetailsGroupLabel = styled.h3`
`

const ManagerName = styled.h3`
`

const ManagerPosition = styled.div`
  margin-left: 25px;
  text-align: right;
  padding-top: 2px;
`

const DetailsDescription = styled.p`
`

const TitleHero = styled.h1``

const StatsHero = styled(Flex)`
  margin-left: auto;
  flex-flow: row nowrap;
`

const StatsHeroItem = styled(Flex)`
  margin-left: 45px;
  flex-flow: column nowrap;
`

const StatsHeroItemLabel = styled.h2`
  text-align: right;
`

const StatsHeroItemMetric = styled.p`
  text-align: right;
`


export default FundDetailPage;
