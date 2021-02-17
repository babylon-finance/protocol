import * as addresses from "../contracts/addresses";
import * as contractNames from "../constants/contracts";
import InvestmentIdea from "../models/InvestmentIdea";
import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";
import { Transactor } from "../helpers";
import useGasPrice from "../hooks/GasPrice";
import YearnVaultIntegrationAddress from "../contracts/YearnVaultIntegration.address";

import { BigNumber } from "@ethersproject/bignumber";
import { Box, Blockie, Button, Card, Flex, Field, Form, Input, Heading } from "rimble-ui";
import { notification } from "antd";
import { parseEther } from "@ethersproject/units";

import React, { useState, useEffect, useCallback } from 'react';
import styled from "styled-components";

interface PassiveActionFormProps {
  provider: any
  fundContract: any
}

interface Contracts {
  YearnVaultIntegration: any
  FundIdeas: any
  IVault: any
}

const PassiveActionForm = ({provider, fundContract}: PassiveActionFormProps) => {
  const [loading, setLoading] = useState<boolean>(true);
  const [amountReserve, setAmountReserve] = useState<string>("");
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);
  const [integration, setIntegration] = useState<string>("");
  const [txConfirm, setTxConfirm] = useState<boolean>(false);

  const estGasPrice = useGasPrice("fast");
  const tx = Transactor(provider, estGasPrice);

  const intitialize = useCallback(async () => {
    if (fundContract) {
      setLoading(true);

      const ideasAddress = await fundContract.fundIdeas();
      const fundIdeas = await loadContractFromNameAndAddress(ideasAddress, contractNames.FundIdeas, provider);
      const yearnI = await loadContractFromNameAndAddress(YearnVaultIntegrationAddress, contractNames.YearnVaultIntegration, provider);
      const yearnV = await loadContractFromNameAndAddress(addresses.yearn.vaults.ydai, "IVault", provider);

      setContracts({ YearnVaultIntegration: yearnI, IVault: yearnV, FundIdeas: fundIdeas });
      setLoading(false);
    }
  }, [provider, fundContract]);

  useEffect(() => {
    if (!contracts) {
      intitialize();
    }
  }, [contracts]);

  const handleSubmit = async e => {
    e.preventDefault();
    if (contracts && tx && fundContract) {
      try {
        setTxConfirm(true);

        const amountToDeposit = parseEther("1");
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

        const idea = new InvestmentIdea(
          amountToDeposit,
          parseEther("1"),
          BigNumber.from(60*60*24*7),
          enterData,
          exitData,
          contracts.YearnVaultIntegration.address,
          parseEther("0"),
          [addresses.tokens.DAI],
          [BigNumber.from(1)]
        );

        // TODO(undfined): These params need to be cleaned up
        const result = await tx(
          contracts.FundIdeas.addInvestmentIdea(...idea.getProps())
        );

        if (result) {
          notification.success({
            message: "Transaction Sent",
            description:
              "Your Idea has been submitted."
          });
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

  const handleAmountInput = e => {
    e.preventDefault();
    setAmountReserve(e.target.value);
  };

  const formValidated = true;

  return (
    <Box p={4}>
      <Box>
        <Form onSubmit={handleSubmit} validated={formValidated}>
          <Flex mx={-3} flexWrap={"wrap"}>
            <Box width={[1, 1, 1/2]} px={3}>
              <Field label="Amount" width={1}>
                <Input
                  type="text"
                  required
                  onChange={handleAmountInput}
                  value={amountReserve}
                  width={1}
                />
              </Field>
            </Box>
          </Flex>
          <FormSubmitButton disabled={loading} type="submit">Submit Idea</FormSubmitButton>
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
