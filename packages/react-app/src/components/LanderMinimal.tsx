/* eslint-disable jsx-a11y/accessible-emoji */
import { Box, Button, Field, Form } from 'rimble-ui';

import React, { useState } from "react";
import styled from "styled-components";
const LanderMinimal = () => {
  const [submitted, setSubmitted] = useState(false);
  const [email, setEmail] = useState("");
  const [validated, setValidated] = useState(false);

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
      <FormBox>
        <HeroSubHeading>
          Sign up to learn more about what's coming.
        </HeroSubHeading>
        <Form onSubmit={handleSubmit}>
          <Box width={[1, 1, 1 / 2]}>
            <Field label="" width={1}>
              <EmailInput
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
              </EmailInput>
            </Field>
            <FormButton disabled={!validated} type="submit">Be the first to know</FormButton>
          </Box>
        </Form>
      </FormBox>
    );
  }

  return (
    <ContainerLarge>
      <HeroContainer>
        <HeroValuePropA className="uvp-a">
          Community-led asset management.
        </HeroValuePropA>
        <HeroValuePropB className="uvp-b">
          The best investments in DeFi.
        </HeroValuePropB>
        {submitted
          ? <FormSuccess>Thanks for connecting! We will be in touch.</FormSuccess>
          : renderForm()
        }
      </HeroContainer>
    </ContainerLarge>
  )
}

const EmailInput = styled(Form.Input)`
  width: 100%;
`

const FormSuccess = styled.div`
  padding: 30px 0;
  font-size: 36px;
`

const FormBox = styled(Box)`
  font-family: cera-regular;
  width: 100%;
  margin-top: 50px;
`

const FormButton = styled(Button)`
  font-family: cera-regular;
`

const ContainerLarge = styled(Box)`
  max-width: 100%;
  padding: 100px 120px 0 120px;
  position: relative;
  line-height: 1.15;

  @media only screen and (max-width: 840px) {
    padding: 30px 30px 0 30px;
    .uvp-a, .uvp-b {
      font-size: 30px;
    }
  }
`

const HeroContainer = styled.div`
  display: flex;
  flex-flow: column nowrap;
  min-height: 65vh;
`

const HeroValuePropA = styled.div`
  color: var(--primary);
  font-family: cera-bold;
  font-size: 56px;

  @media only screen and (max-width: 840px) {
    margin-bottom: 4px;
  }
`

const HeroValuePropB = styled.div`
  color: var(--purple-aux);
  font-family: cera-bold;
  font-size: 56px;
`

const HeroSubHeading = styled.h2`
  font-family: cera-regular;
  color: var(--primary);
  margin-bottom: 8px;

  @media only screen and (max-width: 840px) {
    font-size: 18px;
  }
`

export default LanderMinimal;
