import FundCard from "../components/FundCard"
import useContractLoader from "../hooks/ContractLoader";

import styled from "styled-components";
import React, { useState, useEffect } from 'react';

interface FundCardRowProps {
  provider: any
  address: string
  callback: any
}

const FundCardRow = ({ provider, address, callback }: FundCardRowProps) => {
  const [funds, setFunds] = useState();
  const contracts = useContractLoader(provider, address);

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
            <FundCard provider={provider} address={address} callback={callback} key={address} />
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
