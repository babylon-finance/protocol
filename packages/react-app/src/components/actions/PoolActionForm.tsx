import * as addresses from "../../contracts/addresses";
import * as contractNames from "../../constants/contracts";
import { loadContractFromNameAndAddress } from "../../hooks/ContractLoader";
import UniswapPoolIntegrationAddress from "../../contracts/UniswapPoolIntegration.address";

import { Box, Button, Form, Heading } from "rimble-ui";
import { parseEther } from "@ethersproject/units";

import React, { useState, useEffect, useCallback } from 'react';
import styled from "styled-components";

interface PoolActionFormProps {
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
  UniswapPoolIntegration: any
  FundIdeas: any
}

const PoolActionForm = ({
  capitalRequested,
  provider,
  fundContract,
  integrationName,
  resetForm,
  setContractData,
  showSummaryForm,
  showChildForm
}: PoolActionFormProps) => {
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);

  const intitialize = useCallback(async () => {
    if (fundContract) {
      const ideasAddress = await fundContract.fundIdeas();
      const fundIdeas = await loadContractFromNameAndAddress(ideasAddress, contractNames.FundIdeas, provider);
      const uniswapI = await loadContractFromNameAndAddress(UniswapPoolIntegrationAddress, contractNames.UniswapPoolIntegration, provider);

      setContracts({ UniswapPoolIntegration: uniswapI, FundIdeas: fundIdeas });
    }
  }, [provider, fundContract]);

  useEffect(() => {
    if (!contracts) {
      intitialize();
    }
  });

  const handleConfirmForm = async e => {
    e.preventDefault();
    if (contracts && fundContract) {
      const uniswapInterface = contracts.UniswapPoolIntegration.interface;
      const enterData = uniswapInterface.encodeFunctionData(
        uniswapInterface.functions["joinPool(address,uint256,address[],uint256[])"],
        [
          addresses.uniswap.pairs.wethdai,
          parseEther(capitalRequested.toString()),
          [addresses.tokens.DAI, addresses.tokens.WETH],
          [parseEther("1000"), parseEther("0.9")]
        ]
      );

      const exitData = uniswapInterface.encodeFunctionData(
        uniswapInterface.functions["exitPool(address,uint256,address[],uint256[])"],
        [
          addresses.uniswap.pairs.wethdai,
          parseEther("1"), // Not sure how get thise yet, need to look at Uniswap contract
          [addresses.tokens.DAI, addresses.tokens.WETH],
          [parseEther("900"), parseEther("0.7")]
        ]
      );

      const integrationName = await contracts.UniswapPoolIntegration.name();

      setContractData(enterData, exitData, {name: integrationName, address: UniswapPoolIntegrationAddress });
      showChildForm(false);
      showSummaryForm(true);
    }
  };

  const formValidated = true;

  // Add Pool type selector and any meta data for sub integration needed. For now this only
  // submits UniswapWethDai.
  return (
    <Box p={4}>
      <Heading>Set liquidity pool investment details</Heading>
      <Box>
        <Form onSubmit={handleConfirmForm} validated={formValidated}>
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
export default PoolActionForm;
