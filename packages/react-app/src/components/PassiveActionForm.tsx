import * as addresses from "../contracts/addresses";
import * as contractNames from "../constants/contracts";
import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";
import YearnVaultIntegrationAddress from "../contracts/YearnVaultIntegration.address";

import { Box, Button, Form, Heading } from "rimble-ui";
import { parseEther } from "@ethersproject/units";

import React, { useState, useEffect, useCallback } from 'react';
import styled from "styled-components";

interface PassiveActionFormProps {
  provider: any
  capitalRequested: number
  fundContract: any
  resetForm: any
  setContractData: any
  showChildForm: any
  showSummaryForm: any
}

interface Contracts {
  YearnVaultIntegration: any
  FundIdeas: any
  IVault: any
}

const PassiveActionForm = ({capitalRequested, provider, fundContract, resetForm, setContractData, showSummaryForm, showChildForm}: PassiveActionFormProps) => {
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);

  const intitialize = useCallback(async () => {
    if (fundContract) {
      const ideasAddress = await fundContract.fundIdeas();
      const fundIdeas = await loadContractFromNameAndAddress(ideasAddress, contractNames.FundIdeas, provider);
      const yearnI = await loadContractFromNameAndAddress(YearnVaultIntegrationAddress, contractNames.YearnVaultIntegration, provider);
      const yearnV = await loadContractFromNameAndAddress(addresses.yearn.vaults.ydai, "IVault", provider);

      setContracts({ YearnVaultIntegration: yearnI, IVault: yearnV, FundIdeas: fundIdeas });
    }
  }, [provider, fundContract]);

  useEffect(() => {
    if (!contracts) {
      intitialize();
    }
  });

  const handleCompleteChildForm = async e => {
    e.preventDefault();
    if (contracts && fundContract) {
      const amountToDeposit = parseEther(capitalRequested.toString());
      const sharePrice = await contracts.IVault.getPricePerFullShare();
      const expectedYShares = amountToDeposit.div(sharePrice);
      const yearnInterface = contracts.YearnVaultIntegration.interface;

      const enterData = yearnInterface.encodeFunctionData(
        yearnInterface.functions["enterInvestment(address,uint256,address,uint256)"],
        [
          addresses.yearn.vaults.ydai,
          expectedYShares,
          addresses.tokens.DAI,
          parseEther("1")
        ]
      );

      const investmentTokensIn = await contracts.IVault.balanceOf(fundContract.address);

      const exitData = yearnInterface.encodeFunctionData(
        yearnInterface.functions["exitInvestment(address,uint256,address,uint256)"],
        [
          addresses.yearn.vaults.ydai,
          investmentTokensIn,
          addresses.tokens.DAI,
          parseEther("0.9")
        ]
      );

      const integrationName = await contracts.YearnVaultIntegration.name();

      setContractData(enterData, exitData, {name: integrationName, address: YearnVaultIntegrationAddress });
      showChildForm(false);
      showSummaryForm(true);
    }
  };

  const formValidated = true;

  // Add Passive type selector and any meta data for sub integration needed. For now this only
  // submits YearnVault passive integration.
  return (
    <Box p={4}>
      <Heading>Set passive investment details</Heading>
      <Box>
        <Form onSubmit={handleCompleteChildForm} validated={formValidated}>
          <FormSubmitButton type="submit">Show Summary</FormSubmitButton>
        </Form>
      </Box>
    </Box>
  )
};

const FormSubmitButton = styled(Button)`
  min-width: 200px;
  margin-top: 12px;
`
export default PassiveActionForm;
