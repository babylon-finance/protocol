import { ReactComponent as MediumLogo } from "../icons/medium_logo.svg"
import { ReactComponent as DiscordLogo } from "../icons/discord_logo.svg"
import { ReactComponent as TwitterLogo } from "../icons/twitter_logo.svg"
import { ReactComponent as TelegramLogo } from "../icons/telegram_logo.svg"

import React from "react";
import { Box, Link as StyledLink } from "rimble-ui";
import styled from "styled-components";

const ExternalTarget = {
  discord: "discord",
  docs: "docs",
  litepaper: "litepaper",
  medium: "medium",
  telegram: "telegram",
  twitter: "twitter",
};

const AppFooter = () => {
  const getTargetLink = (target) => {
    switch (target) {
      case ExternalTarget.twitter:
        return 'https://twitter.com/BabylonFinance';
      case ExternalTarget.medium:
        return 'https://medium.com/babylon-finance';
      case ExternalTarget.discord:
        return 'https://discord.gg/eGatHr2a5u';
      case ExternalTarget.telegram:
        return 'https://t.me/joinchat/HQ5TId7ZUCb9ktgT';
      // Update these when we have the new links!!!!!!!
      case ExternalTarget.docs:
        return 'https://t.me/joinchat/HQ5TId7ZUCb9ktgT';
      case ExternalTarget.litepaper:
        return 'https://t.me/joinchat/HQ5TId7ZUCb9ktgT';
    }
  }

  return (
    <FooterWrapper>
      <ContainerLarge>
        <FooterContentWrapper>
           <FooterTextLinkBlock>
            <FooterTextLink href={getTargetLink(ExternalTarget.docs)} target="_blank" rel="noopener noreferrer">
              Documentation
            </FooterTextLink>
            <FooterTextLink href={getTargetLink(ExternalTarget.litepaper)} target="_blank" rel="noopener noreferrer">
              Litepaper
            </FooterTextLink>
          </FooterTextLinkBlock>
          <FooterSocialLinkBlock>
            <FooterSocialLinkLabel>Join us!</FooterSocialLinkLabel>
            <FooterSocialLinkIcons>
              <a href={getTargetLink(ExternalTarget.telegram)} target="_blank" rel="noopener noreferrer">
                <FooterSocialIcon>
                  <TelegramLogo/>
                </FooterSocialIcon>
              </a>
              <a href={getTargetLink(ExternalTarget.discord)} target="_blank" rel="noopener noreferrer">
                <FooterSocialIcon>
                  <DiscordLogo />
                </FooterSocialIcon>
              </a>
              <a href={getTargetLink(ExternalTarget.medium)} target="_blank" rel="noopener noreferrer">
                <FooterSocialIcon>
                  <MediumLogo />
                </FooterSocialIcon>
              </a>
              <a href={getTargetLink(ExternalTarget.twitter)} target="_blank" rel="noopener noreferrer">
                <FooterSocialIcon>
                  <TwitterLogo />
                </FooterSocialIcon>
              </a>
            </FooterSocialLinkIcons>
          </FooterSocialLinkBlock>
          <FooterLogoWrapper>
            <img height="80" src="/Babylon_logo_horizontal-blue.svg" alt="babylon-logo-mono" />
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

  @media only screen and (max-width: 1240px) {
    padding: 30px 30px 0 30px;
  }
`

const FooterTextLinkBlock = styled.div`
  display: flex;
  flex-flow: column;
  min-width: 175px;

  @media only screen and (max-width: 1240px) {
    min-width: 140px;
  }
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
  min-width: 180px;
  justify-content: space-between;
`

const FooterSocialIcon = styled.svg`
  display: flex;
  width: 40px;
  height: 40px;
  fill: var(--primary);
  opacity: 0.3;
  padding: 4px;

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
    text-decoration: none;
  }
`

const FooterContentWrapper = styled.div`
  display: flex;
  flex-flow: row;
  min-height: 200px;
  width: 100%;

  @media only screen and (max-width: 1240px) {
    min-height: 100px;
  }
`

const FooterWrapper = styled.div`
  width: 100%;
`

const FooterLogoWrapper = styled.div`
  align-items: top;
  display: flex;
  font-family: cera-bold;
  margin-left: auto;
  padding: 5px;

  @media only screen and (max-width: 1240px) {
    display: none;
  }
`

export default AppFooter;
