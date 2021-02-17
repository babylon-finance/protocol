import React from 'react';
import { Link } from "react-router-dom";
import { Box, Blockie, Button, MetaMaskButton } from 'rimble-ui';
import styled from "styled-components";

const PRIMARY_FUND = "0x0b306bf915c4d645ff596e518faf3f9669b97016";
interface AppHeaderProps {
  onConnect: any
  resetApp: any
  appState: any
  index?: boolean
}

const AppHeader = ({ onConnect, resetApp, appState, index }: AppHeaderProps) => {
  const mkShortAddress = (address): string => {
    const prefix = address.slice(0, 4);
    const suffix = address.slice(address.length - 4, address.length);

    return (`${prefix}...${suffix}`);
  }
  const renderConnectionWrapper = () => {
    return (
      <ConnectionWrapper>
        {appState.connected && (
          <ConnectedWrapper>
            <Blockie
              opts={{
                seed: appState.address,
                color: "#dfe",
                bgcolor: "#a71",
                size: 6,
                scale: 6,
                spotcolor: "#000"
              }} />
            <AddressButton>
              {mkShortAddress(appState.address)}
            </AddressButton>
            <LinkWrapper>
              <DisconnectLink onClick={resetApp} target="_blank">
                Disconnect
                </DisconnectLink>
            </LinkWrapper>
          </ConnectedWrapper>
        )}
        {!appState.connected && (
          <MetaMaskButton.Outline onClick={onConnect} size="small">
            Connect Wallet
          </MetaMaskButton.Outline>
        )}
      </ConnectionWrapper>
    );
  };

  const renderIndexButton = () => {
    return (
      <IndexLink to={`/fund/${PRIMARY_FUND}`}>
        <IndexButton>View Fund</IndexButton>
      </IndexLink>
    );
  };

  return (
    <HeaderWrapper>
      <ContainerLarge>
        <StyledHeader>
          <LogoWrapper>
            <img width="30" src="/tmp_logo_1.png" alt="" />
            <HomeLink to="/"><span className="main-text">Babylon</span><span className="tld-text">.finance</span></HomeLink>
          </LogoWrapper>
          {index
            ? renderIndexButton()
            : renderConnectionWrapper()
          }
        </StyledHeader>
      </ContainerLarge>
    </HeaderWrapper>
  );
}

const AddressButton = styled(Button.Outline)`
  font-family: cera-light;
  color: var(--purple);
  margin-left: 10px;
`

const DisconnectLink = styled.a`
  font-size: 16px;
  color: rgb(170, 149, 133);
  text-decoration: none;
  margin-left: 10px;
  &:hover {
    color: rgb(128, 94, 73);
  }
`

const LinkWrapper = styled.div`
  display: flex;
  align-items: center;
`

const IndexButton = styled(Button.Outline)`
  font-family: cera-regular;
  color: var(--primary);
  background-color: var(--white);
  margin-left: auto;
`

const IndexLink = styled(Link)`
  margin-left: auto;
  display: flex;
  align-items: center;
`

const ContainerLarge = styled(Box)`
  position: relative;
  margin: 0 auto;
  width: var(--screen-md-max);
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
  margin-bottom: 20px;
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
  padding: 20px 0;
`

export default AppHeader;
