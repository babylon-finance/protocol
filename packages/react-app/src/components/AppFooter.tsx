import { ReactComponent as MediumLogo } from "../icons/medium_logo.svg"
import { ReactComponent as DiscordLogo } from "../icons/discord_logo.svg"
import { ReactComponent as TwitterLogo } from "../icons/twitter_logo.svg"

import React from "react";
import { Box, Link as StyledLink } from "rimble-ui";
import styled from "styled-components";

const ExternalTarget = {
  discord: "discord",
  docs: "docs",
  litepaper: "litepaper",
  team: "team",
  medium: "medium",
  twitter: "twitter",
};

const AppFooter = () => {
  const onClickSocialIcon = (target) => {
    switch (target) {
      case ExternalTarget.twitter:
        window.open('https://twitter.com/BabylonFinance');
        break
      case ExternalTarget.medium:
        window.open('https://medium.com/@rrecuero/8199fa89f918');
        break
      case ExternalTarget.discord:
        window.open('https://discord.gg/fQNpNJ9ahb');
        break
    }
  }

  return (
    <FooterWrapper>
      <ContainerLarge>
        <FooterContentWrapper>
          {/*  <FooterTextLinkBlock>
                <FooterTextLink>Documentation</FooterTextLink>
                <FooterTextLink>Litepaper</FooterTextLink>
                <FooterTextLink>Core Team</FooterTextLink>
              </FooterTextLinkBlock>
          */}
          <FooterSocialLinkBlock>
            <FooterSocialLinkLabel>Join us!</FooterSocialLinkLabel>
            <FooterSocialLinkIcons>
              <FooterSocialIcon>
                <MediumLogo onClick={() => onClickSocialIcon(ExternalTarget.medium)} />
              </FooterSocialIcon>
              <FooterSocialIcon>
                <TwitterLogo onClick={() => onClickSocialIcon(ExternalTarget.twitter)} />
              </FooterSocialIcon>
              <FooterSocialIcon>
                <DiscordLogo onClick={() => onClickSocialIcon(ExternalTarget.discord)} />
              </FooterSocialIcon>
            </FooterSocialLinkIcons>
          </FooterSocialLinkBlock>
          <FooterLogoWrapper>
            <img width="30" src="/tmp_logo_1.png" alt="" />
            <span className="main-text">Babylon</span><span className="tld-text">.finance</span>
          </FooterLogoWrapper>
        </FooterContentWrapper>
      </ContainerLarge>
    </FooterWrapper>
  );
}

const ContainerLarge = styled(Box)`
  margin: 0 auto;
  padding: 100px 120px 0 120px;
  position: relative;
  width: 100%;

  @media only screen and (max-width: 840px) {
    padding: 30px 30px 0 30px;
  }
`

const MailingListWrapper = styled.div`
  font-family: cera-light;
  color: var(--primary);
  min-height: 280px;
  background: var(--primary);
  filter: alpha(opacity=10);
  -moz-opacity: 0.1;
  opacity: 0.1;
  width: 100%;
`

const FooterTextLinkBlock = styled.div`
  display: flex;
  flex-flow: column;
  min-width: 145px;
`

const FooterSocialLinkBlock = styled.div`
  display: flex;
  flex-flow: column;
`

const FooterSocialLinkLabel = styled.div`
  color: var(--primary);
  font-family: cera-bold;
  font-size: 16px;
  margin-bottom: 8px;
`

const FooterSocialLinkIcons = styled.div`
  display: flex;
  flex-flow: row;
  min-width: 145px;
  justify-content: space-between;
`

const FooterSocialIcon = styled.svg`
  width: 40px;
  height: 40px;
  fill: var(--primary);
  opacity: 0.3;

  &:hover {
    color: var(--primary);
    opacity: 0.9;
    cursor: pointer;
  }
`

const FooterTextLink = styled(StyledLink)`
  color: var(--primary);
  font-family: cera-light;
  font-size: 16px;
  padding-bottom: 6px;

  &:hover {
    color: var(--primary);
    opacity: 0.3;
  }
`

const FooterContentWrapper = styled.div`
  display: flex;
  flex-flow: row;
  min-height: 200px;
  width: 100%;

  @media only screen and (max-width: 840px) {
    min-height: 100px;
  }
`

const FooterWrapper = styled.div`
  width: 100%;
`

const FooterLogoWrapper = styled.div`
  align-items: center;
  display: flex;
  font-family: cera-bold;
  font-size: 24px;
  height: 60px;
  margin-left: auto;
  padding: 5px;

  .main-text {
    margin-left: 14px;
    color: var(--primary);
  }

  .tld-text {
    color: var(--primary);
  }

  @media only screen and (max-width: 840px) {
    display: none;
  }
`

export default AppFooter;
