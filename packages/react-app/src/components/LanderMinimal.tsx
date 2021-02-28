/* eslint-disable jsx-a11y/accessible-emoji */
import { Box, Button, Field, Form } from 'rimble-ui';

import React, { useState, useEffect, useCallback } from "react";
import styled from "styled-components";
import { Empty } from 'antd';

const LanderMinimal = () => {
  const [initialLoad, setInitialLoad] = useState(true);
  const [smallScreen, setSmallScreen] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [email, setEmail] = useState("");
  const [validated, setValidated] = useState(false);

  const windowResizeHandler = useCallback(e => {
    setSmallScreen(e.matches)
  }, []);

  useEffect(() => {
    if (initialLoad) {
      setSmallScreen(window.innerWidth < 1240);
      setInitialLoad(false);
    }
    window.matchMedia("(max-width: 1240px)").addListener(windowResizeHandler);
  }, [initialLoad, windowResizeHandler])

  const encode = (data) => {
    return Object.keys(data)
      .map(key => encodeURIComponent(key) + "=" + encodeURIComponent(data[key]))
      .join("&");
  }

  const handleSubmit = e => {
    fetch("/", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: encode({ "form-name": "lander-subscribe", ...{ email: email } })
    }).then(() => setSubmitted(true)).catch(error => alert(error));

    e.preventDefault();
  }

  const handleFormChange = e => {
    setEmail(e.target.value)
    setValidated(validateEmail(e.target.value));
  }

  const validateEmail = (email: string) => {
    var re = /\S+@\S+\.\S+/;
    return re.test(email);
  }

  const renderForm = () => {
    return (
      <SubscribeBox>
        {!smallScreen && (
          <SubscribeText><Emphasize>Sign up</Emphasize> to join our beta waitlist.</SubscribeText>
        )}
        <EmailForm onSubmit={handleSubmit}>
          <EmailInputContainer>
            <Field label="" width={1}>
              <EmailInput
                type="email"
                name="lander-subscribe"
                method="POST"
                data-netlify="true"
                value={email}
                placeholder="your email"
                onChange={handleFormChange}
                required
                width={1}
              >
              </EmailInput>
            </Field>
            <SubscribeButton disabled={!validated} type="submit"><Arrow /></SubscribeButton>
          </EmailInputContainer>
        </EmailForm>
      </SubscribeBox>
    );
  }

  const renderTempCapture = () => {
    return (
      <FormBox>
        <HeroSubHeading>
          <SubscribeText><Emphasize>Sign up</Emphasize> to join our beta waitlist.</SubscribeText>
        </HeroSubHeading>
        <Form onSubmit={handleSubmit}>
          <Box width={[1, 1, 1 / 2]}>
            <Field label="" width={1}>
              <TempEmailInput
                type="email"
                name="lander-subscribe"
                method="POST"
                data-netlify="true"
                value={email}
                placeholder="defi@rules.xyz"
                onChange={handleFormChange}
                required
                width={1}
              >
              </TempEmailInput>
            </Field>
            <FormButton disabled={!validated} type="submit">Be the first to know</FormButton>
          </Box>
        </Form>
      </FormBox>
    );
  }

  const renderDetailsDesktop = () => {
    return (
      <DetailsColumns>
        <DetailsColumnLeft>
          <DetailBoxSpacer />
          <DetailBox bgColor={"var(--yellow)"}>
            <DetailBoxContent fontColor={"var(--primary)"}>Invest with the community that fits your <Emphasize>risk, time, and liquidity preferences.</Emphasize></DetailBoxContent>
            <DetailBoxIcon />
          </DetailBox>
          <DetailBoxSpacer>
            <SpacerBlockDiagTop />
            <SpacerBlockFull />
          </DetailBoxSpacer>
          <DetailBox bgColor={"var(--primary-gray)"}>
            <DetailBoxContent fontColor={"var(--primary)"}>Retain ownership of your funds with <Emphasize>non-custodial asset management.</Emphasize></DetailBoxContent>
            <DetailBoxIcon />
          </DetailBox>
          <DetailBoxSpacer>
            <SpacerBlockDouble />
          </DetailBoxSpacer>
        </DetailsColumnLeft>
        <DetailsColumnRight>
          <DetailBox bgColor={"var(--purple-aux)"}>
            <DetailBoxContent fontColor={"var(--white)"}>Community owned and community managed. <Emphasize>Trustless and transparent.</Emphasize></DetailBoxContent>
            <DetailBoxIcon />
          </DetailBox>
          <DetailBoxSpacer>
            <SpacerBlockFull />
            <SpacerBlockDiagBottom />
          </DetailBoxSpacer>
          <DetailBox bgColor={"var(--primary)"}>
            <DetailBoxContent fontColor={"var(--white)"}>Participate directly with ETH. No complicated token swapping. <Emphasize>ETH in, ETH out.</Emphasize></DetailBoxContent>
            <DetailBoxIcon />
          </DetailBox>
          <DetailBox bgColor={"var(--pink)"}>
            <DetailBoxContent fontColor={"var(--white)"}><Emphasize>Earn rewards by participating</Emphasize> in the investment community that fits you.</DetailBoxContent>
            <DetailBoxIcon />
          </DetailBox>
        </DetailsColumnRight>
      </DetailsColumns>
    );
  }

  const renderDetailsMobile = () => {
    return (
      <DetailsColumnSmallScreen>
        <DetailBox bgColor={"var(--yellow)"}>
          <DetailBoxContent fontColor={"var(--primary)"}>Invest with the community that fits your <Emphasize>risk, time, and liquidity preferences.</Emphasize></DetailBoxContent>
          <DetailBoxIcon />
        </DetailBox>
        <DetailBox bgColor={"var(--primary-gray)"}>
          <DetailBoxContent fontColor={"var(--primary)"}>Retain ownership of your funds with <Emphasize>non-custodial asset management.</Emphasize></DetailBoxContent>
          <DetailBoxIcon />
        </DetailBox>
        <DetailBox bgColor={"var(--purple-aux)"}>
          <DetailBoxContent fontColor={"var(--white)"}>Community owned and community managed. <Emphasize>Trustless and transparent.</Emphasize></DetailBoxContent>
          <DetailBoxIcon />
        </DetailBox>
        <DetailBox bgColor={"var(--primary)"}>
          <DetailBoxContent fontColor={"var(--white)"}>Participate directly with ETH. No complicated token swapping. <Emphasize>ETH in, ETH out.</Emphasize></DetailBoxContent>
          <DetailBoxIcon />
        </DetailBox>
        <DetailBox bgColor={"var(--pink)"}>
          <DetailBoxContent fontColor={"var(--white)"}><Emphasize>Earn rewards by participating</Emphasize> in the investment community that fits you.</DetailBoxContent>
          <DetailBoxIcon />
        </DetailBox>
      </DetailsColumnSmallScreen>
    );
  }

  return (
    <FullWidthContainer>
      <ContainerLarge>
        <HeroContainer>
          <HeroValuePropA className="uvp-a">
            Community-led{smallScreen && (<br />)} asset management.
          </HeroValuePropA>
          <HeroValuePropB className="uvp-b">
            Powered by DeFi.
          </HeroValuePropB>
          {smallScreen && (
            <LanderLogoSmallWrapper>
              <LanderLogoSmall src="./block-logo-lander.svg"/>
            </LanderLogoSmallWrapper>
          )}
          {smallScreen && !submitted && (
            <SubscribeText><Emphasize>Sign up</Emphasize> to join our beta waitlist.</SubscribeText>
          )}
          {submitted
            ? <FormSuccess>Thank you for connecting! We will be in touch.</FormSuccess>
            : (smallScreen ? renderForm() : renderTempCapture())
          }
          {/*
          <InvestorsContainer>
            <InvestorsLabelWrapper>Backed by <Emphasize>world-class investors</Emphasize></InvestorsLabelWrapper>
            <InvestorShowcaseRow>
              <InvestorIconBlock><InvestorIcon src="./tmp-investor-icon.svg"/></InvestorIconBlock>
              <InvestorIconBlock><InvestorIcon src="./tmp-investor-icon.svg"/></InvestorIconBlock>
              <InvestorIconBlock><InvestorIcon src="./tmp-investor-icon.svg"/></InvestorIconBlock>
              <InvestorIconBlock><InvestorIcon src="./tmp-investor-icon.svg"/></InvestorIconBlock>
            </InvestorShowcaseRow>
            <InvestorShowcaseRow>
              <InvestorIconBlock><InvestorIcon src="./tmp-investor-icon.svg"/></InvestorIconBlock>
              <InvestorIconBlock><InvestorIcon src="./tmp-investor-icon.svg"/></InvestorIconBlock>
              <InvestorIconBlock><InvestorIcon src="./tmp-investor-icon.svg"/></InvestorIconBlock>
              <InvestorIconBlock><InvestorIcon src="./tmp-investor-icon.svg"/></InvestorIconBlock>
            </InvestorShowcaseRow>
          </InvestorsContainer>
          */}
        </HeroContainer>
      </ContainerLarge>
      {smallScreen
        ? renderDetailsMobile()
        : renderDetailsDesktop()
      }
      <InvestCtaBox />
      {submitted
        ? <FormSuccess>Thanks for connecting! We will be in touch.</FormSuccess>
        : renderForm()
      }
    </FullWidthContainer>
  )
}

const LanderLogoSmallWrapper = styled.div`
  margin: 40px 0;
  width: 100%;
  height: 100%;
  display: flex;
  justify-content: center;
`

const LanderLogoSmall = styled.img`
  width: 275px;
  height: 275px;
`

const InvestorIcon = styled.img`
  flex-grow: 1;

  @media only screen and (max-width: 1240px) {
    margin-top: 12px;
  }
`

const InvestorShowcaseRow = styled.div`
  display: flex;
  flex-flow: row nowrap;
  justify-content: space-between;
  padding: 20px 140px;

  @media only screen and (max-width: 1240px) {
    padding: 0 10px;
    flex-flow: row wrap;
  }
`

const InvestorsContainer = styled.div`
  display: flex;
  flex-flow: column;
  margin-top: 200px;

  @media only screen and (max-width: 1240px) {
    margin-top: 0;
  }
`

const InvestorsLabelWrapper = styled.div`
  padding: 120px 20px;
  width: 100%;
  color: var(--primary);
  font-family: cera-regular;
  font-size: 24px;
  text-align: center;

  @media only screen and (max-width: 1240px) {
    padding: 120px 0 20px 0;
  }
`

const InvestorIconBlock = styled.div`
  width: 200px;
  height: 200px;

  @media only screen and (max-width: 1240px) {
    width: 100px;
    height: 100px;
    margin-top: 20px;
  }
`

const EmailForm = styled(Form)`
  width: 100%;
`

const EmailInput = styled(Form.Input)`
  width: 100%;
  background: none;
  box-shadow: none;
  border: none;
  border-radius: 0;
  padding-left: 0;
  font-size: 24px;
  color: var(--purple);
  font-family: cera-bold;
  border-bottom: 2px var(--purple) solid;

  &:hover {
    box-shadow: none;
  }

  @media only screen and (max-width: 1240px) {
    font-size: 16px;
  }
`

const EmailInputContainer = styled.div`
  width: 100%;
  display: flex;
  flex-flow: row nowrap;
  padding-left: 100px;

  @media only screen and (max-width: 1240px) {
    padding-left: 12px;
  }
`

const SubscribeBox = styled(Box)`
  height: 250px;
  display: flex;
  flex-flow: row nowrap;
  width: 100%;
  background-color: var(--light-gray);
  padding: 80px 300px;

  @media only screen and (max-width: 1240px) {
    height: 100px;
    padding: 20px 20px;
  }
`

const SubscribeText = styled.div`
  font-size: 24px;
  color: var(--primary);
  line-height: 1.5;

  @media only screen and (max-width: 1240px) {
    font-size: 18px;
    margin: 20px 0;
  }
`

const SubscribeButton = styled(Button.Outline)`
  border: 1px var(--purple) solid;
  border-radius: 2px;
  margin-left: 24px;
  padding: 12px 24px;
`

const Arrow = styled.span`
  &:before {
    content: "↑";
  }
  font-size: 24px;
  transform: rotate(90deg);
`

const FullWidthContainer = styled.div`
  width: 100%;
`

const DetailsColumnSmallScreen = styled.div`
  display: flex;
  flex-flow: column nowrap;
`

const DetailsColumns = styled.div`
  display: flex;
  flex-flow: row nowraper;
`

const DetailsColumnLeft = styled.div`
  display: flex;
  flex-flow: column;
  width: 100%;
`

const SpacerBlockFull = styled.div`
  height: 100%;
  width: 100%;
  background-color: var(--light-gray);
`

const SpacerBlockDouble = styled.div`
  width: 100%;
  height: 100%;
  background-color: var(--light-gray);
  clip-path: polygon(100% 0, 0 100%, 100% 100%);
`

const SpacerBlockDiagBottom = styled.div`
  width: 100%;
  height: 100%;
  background-color: var(--light-gray);
  clip-path: polygon(0 0, 0 100%, 100% 100%);
`

const SpacerBlockDiagTop = styled.div`
  width: 100%;
  height: 100%;
  background-color: var(--light-gray);
  clip-path: polygon(0 0, 100% 0, 100% 100%);
`

const DetailsColumnRight= styled.div`
  display: flex;
  flex-flow: column;
  width: 100%;
`

const DetailBox = styled(Box)<{bgColor: string}>`
  display: flex;
  flex-flow: column;
  padding: 80px;
  height: 600px;
  background-color: ${p => p.bgColor};

  @media only screen and (max-width: 1240px) {
    padding: 20px;
    height: 300px;
  }
`

const DetailBoxSpacer = styled.div`
  display: flex;
  flex-flow: row nowrap;
  height: 300px;
  width: 100%;

  @media only screen and (max-width: 1240px) {
    height: 150px;
  }
`

const DetailBoxContent = styled.div<{fontColor: string}>`
  font-family: cera-light;
  font-size: 32px;
  color: ${p => p.fontColor};

  @media only screen and (max-width: 1240px) {
    font-size: 20px;
    line-height: 1.4;
    font-family: cera-regular;
  }
`

const DetailBoxIcon = styled.div`
  border-radius: 50%;
  width: 200px;
  height: 200px;
  background-color: var(--light-gray);
  margin: 75px 0 0 0;

  @media only screen and (max-width: 1240px) {
    width: 100px;
    height: 100px;
    margin: 25px 0 0 0;
  }
`

const InvestCtaBox = styled(Box)`
  width: 100%;
  height: 200px;
  background-color: var(--purple);

  @media only screen and (max-width: 1240px) {
    height: 100px;
  }
`

const Emphasize = styled.span`
  font-family: cera-bold;
`

const FormSuccess = styled.div`
  padding: 30px 25%;
  font-size: 36px;
  color: var(--primary);

  @media only screen and (max-width: 1240px) {
    padding: 30px;
    font-size: 18px;
  }
`

const ContainerLarge = styled(Box)`
  max-width: 100%;
  padding: 100px 120px 0 120px;
  position: relative;
  line-height: 1.15;

  background-image: url(./lander-blocks.svg);
  background-repeat: no-repeat;
  background-position: right top;

  @media only screen and (max-width: 1240px) {
    background: none;
    padding: 30px 30px 0 30px;
    .uvp-a, .uvp-b {
      font-size: 30px;
    }
  }
`

const FormBox = styled(Box)`
  font-family: cera-regular;
  width: 100%;
  margin-top: 50px;
`

const FormButton = styled(Button)`
  font-family: cera-regular;
`

const TempEmailInput = styled(Form.Input)`
  width: 100%;
`

const HeroSubHeading = styled.h2`
  font-family: cera-regular;
  color: var(--primary);
  margin-bottom: 8px;
`

const HeroContainer = styled.div`
  display: flex;
  flex-flow: column nowrap;
  min-height: 45vh;
  padding-bottom: 200px;

  @media only screen and (max-width: 1240px) {
    padding-bottom: 80px;
  }
`

const HeroValuePropA = styled.div`
  color: var(--primary);
  font-family: cera-bold;
  font-size: 56px;

  @media only screen and (max-width: 1240px) {
    margin-bottom: 4px;
  }
`

const HeroValuePropB = styled.div`
  color: var(--purple-aux);
  font-family: cera-bold;
  font-size: 56px;
  margin-bottom: 80px;

  @media only screen and (max-width: 1240px) {
    margin-bottom: 20px;
  }
`

export default LanderMinimal;
