import FundCard from "../components/FundCard"
import useContractLoader from "../hooks/ContractLoader";

import styled from "styled-components";
import React, { useState, useEffect } from 'react';

interface FundCardRowProps {
  provider: any
  userAddress: string
}

const FundCardRow = ({ provider, userAddress }: FundCardRowProps) => {
  const [funds, setFunds] = useState();
  const contracts = useContractLoader(provider, userAddress);

  useEffect(() => {
    async function getFunds() {
      setFunds(await contracts.FolioController.getFunds());
    }
    if (contracts) {
      getFunds();
    }
  }, [contracts])

  return (
    <RowWrapper>
      { funds && (
        funds.map((address: string) => {
          return (
            <FundCard provider={provider} contractAddress={address} userAddress={userAddress} key={address} />
          )
        })
      )}
    </RowWrapper>
  );
}

const RowWrapper = styled.div`
  display: flex;
`
export default FundCardRow;
