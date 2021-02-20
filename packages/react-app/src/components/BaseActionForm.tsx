import PassiveActionForm from "./PassiveActionForm";

import { integrations, getIntegrationsWithAddress, integrationsGroupedByKey } from "../models/Integration";
import InvestmentIdea from "../models/InvestmentIdea";
import { Transactor } from "../helpers";
import useGasPrice from "../hooks/GasPrice";
import * as addresses from "../contracts/addresses";

import { BigNumber } from "@ethersproject/bignumber";
import { Box,  Button, Flex, Field, Form, Input, Heading, Select } from "rimble-ui";
import { notification } from "antd";
import { parseEther } from "@ethersproject/units";

import React, { FC, Reducer, useEffect, useReducer } from "react";
import styled from "styled-components";

interface BaseActionFormProps {
  provider: any
  fundContract: any
  fundIdeasContract: any
}

interface IFormState{
    capitalRequested: number
    integrationName: string
    integrationMap: any
    initialLoad: boolean
    duration: number
    stake: number
    expectedReturn: number
    enterData: string
    exitData: string
    formValidated: boolean
    showPrimaryForm: boolean
    showChildForm: boolean
    showSummaryForm: boolean
}

interface IAction {
  type: string
  value?: any
}

const initialFormState: IFormState = {
  capitalRequested: 0,
  integrationName: "",
  integrationMap: null,
  initialLoad: true,
  duration: 0,
  stake: 0,
  expectedReturn: 0,
  enterData: "",
  exitData: "",
  formValidated: true,
  showPrimaryForm: true,
  showChildForm: false,
  showSummaryForm: false,
};

const reducer = (state: IFormState, action: IAction) => {
  if (action.type === "reset") {
      return initialFormState;
  }

  const result: IFormState = { ...state };
  result[action.type] = action.value;
  return result;
};

const BaseActionForm = ({provider, fundContract, fundIdeasContract}: BaseActionFormProps) => {
  const [state, dispatch] = useReducer<Reducer<IFormState, IAction>, IFormState>(reducer, initialFormState, () => initialFormState);
  const {
    capitalRequested,
    integrationName,
    integrationMap,
    initialLoad,
    duration,
    formValidated,
    stake,
    expectedReturn,
    enterData,
    exitData,
    showPrimaryForm,
    showChildForm,
    showSummaryForm,
  } = state;

  const estGasPrice = useGasPrice("fast");
  const tx = Transactor(provider, estGasPrice);

  useEffect(() => {
    if (initialLoad) {
      dispatch({type: "integrationMap", value: integrationsGroupedByKey("type")});
    }
    dispatch({type: "initialLoad", value: false});
  }, [initialLoad]);

  const onChange = (e) => {
    const { name, value } = e.target;
    dispatch({ type: name, value });
  };

  const handleNextStepClick = e => {
    e.preventDefault();
    dispatch({type: "showPrimaryForm", value: false });
    dispatch({type: "showChildForm", value: true });
  };

  // Pass this callback down to child form
  const handleContractDataChange = (enterData: string, exitData: string) => {
    dispatch({type: "enterData", value: enterData});
    dispatch({type: "exitData", value: exitData});
  };

  const handleShowSummaryFormChange = (state) => {
    dispatch({type: "showSummaryForm", value: state})
  };

  const handleShowChildFormChange = (state) => {
    dispatch({type: "showChildForm", value: state });
  };

  const toUpperFirst = (string: string) => {
    return string[0].toUpperCase() + string.substring(1);
  };

  const buildIntegrationOptions = () => {
    if (integrationMap) {
      const groups = Object.keys(integrationMap);
      return (
        groups.map((group) => (
          <optgroup label={toUpperFirst(group)} key={group}>
            <option>--</option>
            {integrationMap[group.toString()].map((item) => (
              <option value={item.name} key={item.address}>
                {item.name}
              </option>
            ))}
          </optgroup>
        )
      ))
    } else {
      return null;
    }
  };

  const renderIntegrationSelector = () => {
    return (
      <Field label="Investment Type" width={1}>
        <IntegrationSelect required onChange={onChange} name="integrationName" value={integrationName}>
          {buildIntegrationOptions()}
        </IntegrationSelect>
      </Field>
    );
  };

  const resetForm = () => {
    dispatch({ type: "reset" });
  };

  const getIntegrationByName = (name: string) => {
    return getIntegrationsWithAddress().integrations.map(el => {
      if (el.name === name) {
        return el;
      }
    })[0];
  };

  const handleSubmitIdea = async e => {
    e.preventDefault();
    const integration = getIntegrationByName(integrationName);

    if (tx && fundContract && integration) {
      try {
        const idea = new InvestmentIdea(
          parseEther(capitalRequested.toString()),
          parseEther(stake.toString()),
          BigNumber.from(60 * 60 * 24 * duration),
          enterData,
          exitData,
          integration.address,
          parseEther(expectedReturn.toString()),
          [addresses.tokens.DAI], // where should this come from
          [BigNumber.from(1)] // where should this come from
        );

        const result = await tx(
          fundIdeasContract.addInvestmentIdea(...idea.getProps())
        );

        if (result) {
          notification.success({
            message: "Transaction Sent",
            description:
              "Your proposed investment has been submitted."
          });
        }
      } catch (error) {
        notification.error({
          message: "Transaction Failed: Investment idea not submitted",
          description:
            error.toString()
        });
      }
    }

    dispatch({ type: "reset" });
  };

  // Add validation logic
  const validateForm = () => {
    if (true) {
      dispatch({ type: "formValidated", value: "true" });
    }
  };

  const renderChildForm = () => {
    // consider using a switch here that checks a map of the
    // child forms and selects based on state prop
    return (
      <PassiveActionForm
          capitalRequested={capitalRequested}
          resetForm={resetForm}
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
          <Form validated={true}>
            <Heading>Submit an Investment Idea</Heading>
            <Flex mx={-3} flexWrap={"wrap"}>
              <Box width={[1, 1, 1/2]} px={3}>
                <Field label="Capital Requested" width={1}>
                  <Input
                    type="number"
                    required
                    onChange={onChange}
                    name="capitalRequested"
                    value={capitalRequested}
                    width={1}
                  />
                </Field>
                {renderIntegrationSelector()}
                <Field label="Investment Duration (Days)" width={1}>
                  <Input
                    type="number"
                    required
                    onChange={onChange}
                    name="duration"
                    value={duration}
                    width={1}
                  />
                </Field>
                <Field label="Personal Stake" width={1}>
                  <Input
                    type="number"
                    required
                    onChange={onChange}
                    name="stake"
                    value={stake}
                    width={1}
                  />
                </Field>
                <Field label="Expected Return" width={1}>
                  <Input
                    type="number"
                    required
                    onChange={onChange}
                    name="expectedReturn"
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
              <span>Integration: {integrationName}</span>
              <span>Expected Return: {expectedReturn}</span>
            </SummaryDetails>
            <Button disabled={!formValidated} onClick={handleSubmitIdea} type="submit">Submit Idea</Button>
          </Box>
        )}
      </Box>
    </Box>
  );
}

const IntegrationSelect = styled.select`
  height: 45px;
  border-radius: 4px;
  width: 100%;
  box-shadow: 0px 2px 4px rgb(0 0 0 / 10%);

  &:hover {
    box-shadow: 0px 2px 6px rgb(0 0 0 / 30%);
  }
`
const SummaryDetails = styled(Box)`
  display: flex;
  flex-flow: column;
  padding: 4px;
`

export default BaseActionForm;
