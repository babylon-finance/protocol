import * as addresses from "../../contracts/addresses";
import * as contractNames from "../../constants/contracts";
import { loadContractFromNameAndAddress } from "../../hooks/ContractLoader";
import YearnVaultIntegrationAddress from "../../contracts/YearnVaultIntegration.address";
import { getVaults, getVaultByName, Vault } from "../../models/Vaults";

import { Box, Button, Field, Flex, Form, Heading } from "rimble-ui";
import { parseEther } from "@ethersproject/units";

import React, { useState, useEffect, useCallback } from 'react';
import styled from "styled-components";

interface PassiveActionFormProps {
  provider: any
  capitalRequested: number
  fundContract: any
  integrationName: string
  resetForm: any
  setContractData: any
  showChildForm: any
  showSummaryForm: any
}

interface Contracts {
  YearnVaultIntegration: any
  FundIdeas: any
}

const PassiveActionForm = ({
  capitalRequested,
  provider,
  fundContract,
  integrationName,
  resetForm,
  setContractData,
  showSummaryForm,
  showChildForm
}: PassiveActionFormProps) => {
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);
  const [vaultName, setVaultName] = useState<string | undefined>(undefined);
  const [vault, setVault] = useState<Vault | undefined>(undefined);
  const [vaults, setVaults] = useState<Vault[] | undefined>(undefined);

  const intitialize = useCallback(async () => {
    if (fundContract) {
      const ideasAddress = await fundContract.fundIdeas();
      const fundIdeas = await loadContractFromNameAndAddress(ideasAddress, contractNames.FundIdeas, provider);
      const yearnI = await loadContractFromNameAndAddress(YearnVaultIntegrationAddress, contractNames.YearnVaultIntegration, provider);
      const yRegistry = await loadContractFromNameAndAddress(addresses.yearn.vaultRegistry, contractNames.YRegistry, provider);

      setVaults(await getVaults(yRegistry, provider));
      setContracts({ YearnVaultIntegration: yearnI, FundIdeas: fundIdeas });
    }
  }, [provider, fundContract]);

  useEffect(() => {
    if (!contracts && provider) {
      intitialize();
    }
  }, [contracts, provider]);

  const handleConfirmPassiveForm = async e => {
    e.preventDefault();
    if (contracts && fundContract && vault) {
      const amountToDeposit = parseEther(capitalRequested.toString());
      const sharePrice = await vault.contract.getPricePerFullShare();
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

      const investmentTokensIn = await vault.contract.balanceOf(fundContract.address);

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

      setContractData(enterData, exitData, { name: integrationName, address: YearnVaultIntegrationAddress });
      showChildForm(false);
      showSummaryForm(true);
    }
  };

  const formValidated = true;

  const handleVaultNameOnChange = e => {
    console.log(vaults);
    setVaultName(e.target.value);
    if (vaults) {
      setVault(getVaultByName(vaults, e.target.value));
    }
  }

  const buildVaultOptions = () => {
    return (
      vaults?.map(vault => (
        <option value={vault.name} key={vault.address}>
          {vault.name}
        </option>
      ))
    )
  };

  return (
    <Box p={4}>
      <Heading>Set passive investment details</Heading>
        <Form onSubmit={handleConfirmPassiveForm} validated={formValidated}>
          <Flex mx={-3} flexWrap={"wrap"}>
            <Box width={[1, 1, 1/2]} px={3}>
              <Field label="Select Vault Type" width={1/2}>
                <VaultSelect required onChange={handleVaultNameOnChange} value={vaultName}>
                  {buildVaultOptions()}
                </VaultSelect>
              </Field>
            </Box>
          </Flex>
          <FormSubmitButton type="submit">Show Summary</FormSubmitButton>
        </Form>
    </Box>
  )
};

const VaultSelect = styled.select`
  height: 45px;
  border-radius: 4px;
  width: 100%;
  box-shadow: 0px 2px 4px rgb(0 0 0 / 10%);

  &:hover {
    box-shadow: 0px 2px 6px rgb(0 0 0 / 30%);
  }
`

const FormSubmitButton = styled(Button)`
  min-width: 200px;
  margin-top: 12px;
`
export default PassiveActionForm;
