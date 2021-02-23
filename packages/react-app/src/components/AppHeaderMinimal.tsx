import React from 'react';
import { Link } from "react-router-dom";
import { Box } from 'rimble-ui';
import styled from "styled-components";

const AppHeaderMinimal = () => {
  return (
    <HeaderWrapper>
      <ContainerLarge>
        <StyledHeader>
          <LogoWrapper>
            <LogoImg src="/Babylon_logo-horizontal-full.svg" alt="babylon-logo-full" />
          </LogoWrapper>
        </StyledHeader>
      </ContainerLarge>
    </HeaderWrapper>
  );
}

const ContainerLarge = styled(Box)`
  margin: 0 auto;
  position: relative;
  padding: 40px 120px 0 120px;
  width: 100%;

  @media only screen and (max-width: 1240px) {
    padding: 20px 30px 0 30px;
  }
`

const LogoImg = styled.img`
  height: 80px;
  @media only screen and (max-width: 1240px) {
    height: 70px;
  }
`

const HeaderWrapper = styled.div`
  width: 100%;
`

const LogoWrapper = styled.div`
  display: flex;
  align-items: flex-start;
`

const HomeLink = styled(Link)`
  color: white;
  font-size: 24px;
  font-family: cera-bold;
  margin-left: 12px;

  &:hover {
    color: white;
    text-decoration: none;
  }
`

const StyledHeader = styled.div`
  display: flex;
`

export default AppHeaderMinimal;
