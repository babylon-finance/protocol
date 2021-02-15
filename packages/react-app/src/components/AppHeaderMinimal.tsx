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
            <LogoImg src="/tmp_logo_1.png" alt="" />
            <HomeLink to="/"><span className="main-text">Babylon</span><span className="tld-text">.finance</span></HomeLink>
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

  @media only screen and (max-width: 840px) {
    padding: 20px 30px 0 30px;
  }
`

const LogoImg = styled.img`
  width: 30px;
  @media only screen and (max-width: 840px) {
    width: 22px;
  }
`

const HeaderWrapper = styled.div`
  width: 100%;
`

const LogoWrapper = styled.div`
  height: 60px;
  padding: 5px;
  display: flex;
  align-items: center;

  .main-text {
    color: var(--primary);
  }

  .tld-text {
    color: var(--purple-aux);
  }

  @media only screen and (max-width: 840px) {
    .main-text {
      font-size: 18px;
    }

    .tld-text {
      font-size: 18px;
    }
  }
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
