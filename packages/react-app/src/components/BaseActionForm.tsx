import PassiveActionForm from "./PassiveActionForm";

import InvestmentIdea from "../models/InvestmentIdea";
import { Transactor } from "../helpers";
import useGasPrice from "../hooks/GasPrice";
import * as addresses from "../contracts/addresses";

import { BigNumber } from "@ethersproject/bignumber";
import { Box,  Button, Flex, Field, Form, Input, Heading } from "rimble-ui";
import { notification } from "antd";
import { parseEther } from "@ethersproject/units";
import React, { useState } from 'react';
import styled from "styled-components";

interface BaseActionFormProps {
  provider: any
  fundContract: any
  fundIdeasContract: any
}

interface Integration {
  name: string
  address: string
}

const BaseActionForm = ({provider, fundContract, fundIdeasContract}: BaseActionFormProps) => {
  const [capitalRequested, setCapitalRequested] = useState<number>(0);
  const [duration, setDuration] = useState<number>(0);
  const [integration, setIntegration] = useState<Integration>({name: "", address: ""});
  const [investmentType, setInvestmentType] = useState("Passive");
  const [stake, setStake] = useState(0);
  const [expectedReturn, setExpectedReturn] = useState(0);
  const [enterData, setEnterData] = useState("");
  const [exitData, setExitData] = useState("");
  const [formValidated, setFormValidated] = useState(true);
  const [showPrimaryForm, setShowPrimaryForm] = useState(true);
  const [showChildForm, setShowChildForm] = useState(false);
  const [showSummaryForm, setShowSummaryForm] = useState(false);
  const [txConfirm, setTxConfirm] = useState<boolean>(false);

  const estGasPrice = useGasPrice("fast");
  const tx = Transactor(provider, estGasPrice);

  const handleSubmit = async e => {
    e.preventDefault();
    console.log("submit");
  };

  const handleRequestedChange = e => {
    e.preventDefault();
    setCapitalRequested(e.target.value);
  };

  const handleIntegrationChange = e => {
    e.preventDefault();
    setIntegration(e.target.value);
  };

  const handleDurationChange = e => {
    e.preventDefault();
    setDuration(e.target.value);
  };

  const handleStakeChange = e => {
    e.preventDefault();
    setStake(e.target.value);
  }

  const handleExpectedChange = e => {
    e.preventDefault();
    setExpectedReturn(e.target.value);
  }

  const buildInvestmentIdeaFromState = () => {
    return null; // Grab all state props here
  };

  const handleNextStepClick = e => {
    e.preventDefault();
    setShowPrimaryForm(false);
    setShowChildForm(true);
  }

  // Pass this callback down to child form
  const handleContractDataChange = (enterData: string, exitData: string, integration: Integration) => {
    setEnterData(enterData);
    setExitData(exitData);
    setIntegration(integration)
  };

  const handleInvestmentTypeChange = e => {
    setInvestmentType(e.target.value);
  };

  const handleShowSummaryFormChange = (state) => {
    setShowSummaryForm(state);
  };

  const handleShowChildFormChange = (state) => {
    setShowChildForm(state);
  };

  const resetForms = () => {
    console.log("reset");
  };

  const handleSubmitIdea= async e => {
    e.preventDefault();
    if (tx && fundContract && integration) {
      try {
        setTxConfirm(true);

        const idea = new InvestmentIdea(
          parseEther(capitalRequested.toString()),
          parseEther("1"),
          BigNumber.from(60 * 60 * 24 * duration), // clean this up
          enterData,
          exitData,
          integration.address,
          parseEther("0"),
          [addresses.tokens.DAI], // where should this come from
          [BigNumber.from(1)] // where should this come from
        );

        // TODO(undfined): These params need to be cleaned up
        const result = await tx(
          fundIdeasContract.addInvestmentIdea(...idea.getProps())
        );

        if (result) {
          notification.success({
            message: "Transaction Sent",
            description:
              "Your Idea has been submitted."
          });
          resetForms();
        }
      } catch (error) {
        notification.error({
          message: "Transaction Failed: Idea not submitted",
          description:
            error.toString()
        });
      }
    }

    setTxConfirm(false);
  };

  // Add validation logic
  const validateForm = () => {
    setFormValidated(true);
  };

  const renderChildForm = () => {
    // consider using a switch here that checks a map of the
    // child forms and selects based on state prop
    return (
      <PassiveActionForm
          capitalRequested={capitalRequested}
          showSummaryForm={handleShowSummaryFormChange}
          showChildForm={handleShowChildFormChange}
          provider={provider}
          fundContract={fundContract}
          setContractData={handleContractDataChange} />
    )
  };

  // clean up the rendering logic for when to show each form
  return(
    <Box p={4}>
      <Box>
        {showPrimaryForm && !showChildForm && !showSummaryForm && (
          <Form onSubmit={handleSubmit} validated={true}>
            <Heading>Submit an Investment Idea</Heading>
            <Flex mx={-3} flexWrap={"wrap"}>
              <Box width={[1, 1, 1/2]} px={3}>
                <Field label="Capital Requested" width={1}>
                  <Input
                    type="number"
                    required
                    onChange={handleRequestedChange}
                    value={capitalRequested}
                    width={1}
                  />
                </Field>
                <Field label="Investment Type" width={1}>
                  <Input
                    type="text"
                    required
                    onChange={handleInvestmentTypeChange}
                    value={investmentType}
                    width={1}
                  />
                </Field>
                <Field label="Investment Duration (Days)" width={1}>
                  <Input
                    type="number"
                    required
                    onChange={handleDurationChange}
                    value={duration}
                    width={1}
                  />
                </Field>
                <Field label="Personal Stake" width={1}>
                  <Input
                    type="number"
                    required
                    onChange={handleStakeChange}
                    value={stake}
                    width={1}
                  />
                </Field>
                <Field label="Expected Return" width={1}>
                  <Input
                    type="number"
                    required
                    onChange={handleExpectedChange}
                    value={expectedReturn}
                    width={1}
                  />
                </Field>
              </Box>
            </Flex>
            <Button disabled={!formValidated} onClick={handleNextStepClick} type="submit">To Investment Details</Button>
          </Form>
        )}
        {showChildForm && !showPrimaryForm && !showSummaryForm && (
          renderChildForm()
        )}
        {showSummaryForm && !showPrimaryForm && !showChildForm && (
          <Box>
            <Heading>Review Idea</Heading>
            <SummaryDetails>
              <span>Capital Requested: {capitalRequested}</span>
              <span>Staked Amount: {stake}</span>
              <span>Investment Duration: {duration}</span>
              <span>Integration: {integration.name}</span>
              <span>Expected Return: {expectedReturn}</span>
            </SummaryDetails>
            <Button disabled={!formValidated} onClick={handleSubmitIdea} type="submit">Submit Idea</Button>
          </Box>
        )}
      </Box>
    </Box>
  );
}

const SummaryDetails = styled(Box)`
  display: flex;
  flex-flow: column;
  padding: 4px;
`

export default BaseActionForm;
