import * as contractNames from "../../constants/contracts";
import * as solidity from "../../constants/solidity";
import { getBestPairQuote, PairQuote, EMPTY_PAIR_QUOTE } from "../../helpers/PairQuote";
import { loadContractFromNameAndAddress } from "../../hooks/ContractLoader";
import { Token, GlobalTokenList, TokensMapByAddress } from "../../constants/GlobalTokenList";
import KyberTradeIntegrationAddress from "../../contracts/KyberTradeIntegration.address";

import { parseEther } from "@ethersproject/units";
import { Box, Button, Heading, Input, Loader, Field, Flex, Form } from 'rimble-ui';

import { usePoller } from "eth-hooks";
import React, { useCallback, useEffect, useState } from "react";
import styled from "styled-components";

interface TradeActionFormProps {
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
  ClosedFund: any
  KyberTradeIntegration: any
}

const TradeActionForm = ({
  capitalRequested,
  provider,
  fundContract,
  integrationName,
  resetForm,
  setContractData,
  showSummaryForm,
  showChildForm
}: TradeActionFormProps) => {
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);
  const [providing, setProviding] = useState<string | undefined>(undefined);
  const [providingDetails, setProvidingDetails] = useState<Token | undefined>(undefined);
  const [providingAmount, setProvidingAmount] = useState<number>(1);
  const [receiving, setReceiving] = useState<string | undefined>(undefined);
  const [receivingDetails, setReceivingDetails] = useState<Token | undefined>(undefined);
  const [pairQuote, setPairQuote] = useState<PairQuote>(EMPTY_PAIR_QUOTE);
  const [quoteLoading, setQuoteLoading] = useState<boolean>(false);

  const updateQuotePair = useCallback(async () => {
    if (providingDetails && receivingDetails) {
      setQuoteLoading(true);
      setPairQuote(
        await getBestPairQuote({
          provider: provider,
          providingAmount: providingAmount,
          providingAddress: providingDetails.address,
          receivingAddress: receivingDetails.address
        })
      );
      setQuoteLoading(false);
    }
  }, [provider, providingDetails, receivingDetails, providingAmount]);

  useEffect(() => {
    async function getContracts() {
      const kyberIntegration = await loadContractFromNameAndAddress(
        KyberTradeIntegrationAddress,
        contractNames.KyberTradeIntegration,
        provider
      );

      setContracts({
        KyberTradeIntegration: kyberIntegration,
        ClosedFund: fundContract
      });

      if (providing && receiving) {
        setQuoteLoading(true);

        const providingDetails = TokensMapByAddress.get(providing);
        const receivingDetails = TokensMapByAddress.get(receiving);

        if (!providingDetails || !receivingDetails) {
          throw Error("Failed to find details for provided token");
        }

        setPairQuote(
          await getBestPairQuote({
            provider: provider,
            providingAmount: providingAmount,
            providingAddress: providingDetails.address,
            receivingAddress: receivingDetails.address
          })
        );
        setQuoteLoading(false);
      }
    }

    if (!contracts && provider) {
      getContracts();
    }
  });

  usePoller(async () => {
    if (contracts && providing && receiving) {
      updateQuotePair();
    }
  }, 5000);

  const handleConfirmTradeForm = async e => {
    e.preventDefault();

    if (contracts && fundContract && providingDetails && receivingDetails) {
      const kyberInterface = contracts.KyberTradeIntegration.interface;
      const enterData = kyberInterface.encodeFunctionData(
        kyberInterface.functions["trade(address,uint256,address,uint256,bytes)"],
        [
          providingDetails.address,
          parseEther("1"),
          receivingDetails.address,
          //figure out to handle decimal conversion here
          parseEther("900"), // / 10 ** 12,
          solidity.EMPTY_BYTES
        ]
      );

      const exitData = kyberInterface.encodeFunctionData(
        kyberInterface.functions["trade(address,uint256,address,uint256,bytes)"],
        [
          receivingDetails.address,
          parseEther("1"),
          providingDetails.address,
          //figure out to handle decimal conversion here
          parseEther("900"), // / 10 ** 12,
          solidity.EMPTY_BYTES
        ]
      );

      setContractData(enterData, exitData, { name: integrationName, address: KyberTradeIntegrationAddress });
      showChildForm(false);
      showSummaryForm(true);
    }
  };

  const handleProvidingOnChange = async e => {
    setProviding(e.target.value);

    const providingDetails = TokensMapByAddress.get(e.target.value);

    if (providingDetails) {
      setProvidingDetails(providingDetails);
    }
    updateQuotePair();
  };

  const handleProvidingAmountOnChange = async e => {
    setProvidingAmount(e.target.value ? parseInt(e.target.value) : 0);
    updateQuotePair();
  };

  const handleReceivingOnChange = async e => {
    setReceiving(e.target.value);

    const receivingDetails = TokensMapByAddress.get(e.target.value);

    if (receivingDetails) {
      setReceivingDetails(receivingDetails);
    }
    updateQuotePair();
  };

  return (
    <div>
      <Box p={4} mb={3}>
        <Heading.h3>Set trade investment details</Heading.h3>
        <Form onSubmit={handleConfirmTradeForm}>
          <Flex
            justifyContent={"space-between"}
            bg="light-gray"
            p={[2, 3]}
            borderBottom={"1px solid gray"}
            borderColor={"moon-gray"}
            flexDirection={["column", "row"]}
          >
            <Field label="Providing">
              <AssetSelect required onChange={handleProvidingOnChange} value={providing}>
                <option value="">--</option>
                {GlobalTokenList.tokens.map((tokenObj) => (
                  <option value={tokenObj.address} key={tokenObj.address}>
                    {tokenObj.symbol}
                  </option>
                ))}
              </AssetSelect>
            </Field>
            <Field label="Amount">
              <Input type="number" required={true} placeholder="Amount" onChange={handleProvidingAmountOnChange} value={providingAmount} />
            </Field>
          </Flex>
          <Flex
            justifyContent={"space-between"}
            bg="white"
            p={[2, 3]}
            flexDirection={["column", "row"]}
          >
            <Field label="Receiving">
              <AssetSelect required onChange={handleReceivingOnChange} value={receiving}>
                <option value="">--</option>
                {GlobalTokenList.tokens.map((tokenObj) => (
                  <option value={tokenObj.address} key={tokenObj.address}>
                    {tokenObj.symbol}
                  </option>
                ))}
              </AssetSelect>
            </Field>
            {quoteLoading && (
              <Loader />
            )}
            <Field label="Amount" required>
              <Input type="text" disabled required={true} value={quoteLoading ? "--" : pairQuote.expectedRateDisplay} />
            </Field>
          </Flex>
          <FormSubmitButton type="submit">Confirm Trade</FormSubmitButton>
        </Form>
      </Box>
    </div >
  );
};

const AssetSelect = styled.select`
  min-width: 200px;
  height: 3rem;
  padding: 12px;
  font-size: 1rem;
  border: 1px solid #ccc;
  border-radius: 4px;
  box-shadow: 0px 2px 4px rgba(0,0,0,0.1);
`

const FormSubmitButton = styled(Button)`
  min-width: 200px;
  margin-top: 12px;
`

export default TradeActionForm;
