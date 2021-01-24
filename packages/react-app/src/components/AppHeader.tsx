import React from 'react';
import { Link } from "react-router-dom";
import { Box, Blockie, MetaMaskButton } from 'rimble-ui';
import styled from "styled-components";

interface AppHeaderProps {
  onConnect: any
  resetApp: any
  appState: any
}

const AppHeader = ({ onConnect, resetApp, appState }: AppHeaderProps) => {
  return (
    <HeaderWrapper>
      <ContainerLarge>
        <StyledHeader>
          <LogoWrapper>
            <img width="30" src="/logo-red.png" alt="" />
            <HomeLink to="/">Babylon.finance</HomeLink>
          </LogoWrapper>
          <ConnectionWrapper>
            {appState.connected && (
              <ConnectedWrapper>
                <Blockie
                  opts={{
                    seed: appState.address,
                    color: "#dfe",
                    bgcolor: "#a71",
                    size: 15,
                    scale: 3,
                    spotcolor: "#000"
                  }} />
                <LinkWrapper>
                  <DisconnectLink onClick={resetApp} target="_blank">
                    Disconnect
                  </DisconnectLink>
                </LinkWrapper>
              </ConnectedWrapper>
            )}
            {!appState.connected && (
              <MetaMaskButton.Outline onClick={onConnect} size="small">
                Connect with MetaMask
              </MetaMaskButton.Outline>
            )}
          </ConnectionWrapper>
        </StyledHeader>
      </ContainerLarge>
    </HeaderWrapper>
  );
}

const ContainerLarge = styled(Box)`
  position: relative;
  margin: 0 auto;
  width: 1400px;
`

const ConnectionWrapper = styled.div`
  margin-left: auto;
  display: flex;
  align-items: center;
`

const ConnectedWrapper = styled.div`
  margin-left: auto;
  display: flex;
  align-items: center;
`

const HeaderWrapper = styled.div`
  width: 100%;
  background: #160E6B;
  margin-bottom: 40px;
`

const LogoWrapper = styled.div`
  height: 60px;
  padding: 5px;
  border-radius: 62px;
  display: flex;
  align-items: center;
`

const LinkWrapper = styled.div`
  display: flex;
  align-items: center
`

const DisconnectLink = styled.a`
  font-size: 16px;
  padding-left: 16px;
  color: rgb(170, 149, 133);
  text-decoration: none;

  &:hover {
    color: rgb(128, 94, 73);
  }
`

const HomeLink = styled(Link)`
  color: white;
  font-size: 24px;
  font-weight: 600;
  margin-left: 12px;
`

const StyledHeader = styled.div`
  display: flex;
  padding: 20px 0;
`

export default AppHeader;
