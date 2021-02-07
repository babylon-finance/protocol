import { Box, Button } from 'rimble-ui';

import { Link } from "react-router-dom";
import React from "react";
import styled from "styled-components";

const PRIMARY_FUND = "0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82"

const Lander = () => {
  return (
    <ContainerLarge>
      <HeroContainer>
        <HeroValueProp>
          One Fund.
          <br />
          The best investments in DeFi.
        </HeroValueProp>
        <HeroSubHeading>
          Grow your Ether with a single click. ~80% ΞAPY
        </HeroSubHeading>
        <HeroCtaRow>
          <Link to={`/fund/${PRIMARY_FUND}`}>
            <HeroCtaPrimary>Start Investing</HeroCtaPrimary>
          </Link>
          <Link to="/">
            <HeroCtaSecondary>Learn before you <Emoji role="img">🦍</Emoji></HeroCtaSecondary>
          </Link>
        </HeroCtaRow>
        <HeroStatsBox>
          <HeroStatsItem>
            <StatValue>>$25B</StatValue>
            <StatSubLabel>TVL in DeFi</StatSubLabel>
          </HeroStatsItem>
          <HeroStatsItem>
            <StatValue>+703.7%</StatValue>
            <StatSubLabel>ETH growth YoY</StatSubLabel>
          </HeroStatsItem>
          <HeroStatsItem>
            <StatValue>~80%</StatValue>
            <StatSubLabel>*Historic Fund ΞAPY</StatSubLabel>
          </HeroStatsItem>
          <HeroStatsItem>
            <StatValue>25</StatValue>
            <StatSubLabel>Investors</StatSubLabel>
          </HeroStatsItem>
        </HeroStatsBox>
      </HeroContainer>
    </ContainerLarge>
  )
}

const Emoji = styled.span`
  margin-left: 4px;
`

const ContainerLarge = styled(Box)`
  position: relative;
  margin: 0 auto;
  width: var(--screen-md-max);
`

const HeroContainer = styled.div`
  display: flex;
  flex-flow: column nowrap;
  margin-top: 100px;
  min-height: 65vh;
`

const StatValue = styled.p`
  font-family: cera-bold;
  color: var(--black);
  font-size: 2em;
`

const StatSubLabel = styled.p`
  font-family: cera-thin;
  color: var(--black);
  font-size: 1.5em;
`

const HeroCtaRow = styled.div`
  display: flex;
  margin-bottom: 40px;
`

const HeroCtaPrimary = styled(Button)`
  font-family: cera-regular;
`

const HeroCtaSecondary = styled(Button.Outline)`
  font-family: cera-regular;
  color: var(--primary);
  background-color: var(--white);
  margin-left: 8px;
`

const HeroStatsBox = styled.div`
  margin-top: auto;
  width: 100%;
  min-height: 200px;
  background-color: #eef0ff;
  border-radius: 4px;
  display: flex;
  justify-content: space-between;
`

const HeroStatsItem = styled(Box)`
  padding: 50px;
  display: flex;
  flex-flow: column nowrap;
`

const HeroValueProp = styled.h1`
  color: var(--primary);
  margin-bottom: 0px;
`

const HeroSubHeading = styled.h2`
  color: var(--primary);
  margin-bottom: 40px;
`

export default Lander;

