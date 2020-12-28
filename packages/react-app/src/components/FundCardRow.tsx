import FundCard from "../components/FundCard"
import useContractLoader from "../hooks/ContractLoader";

import React, { useState, useEffect } from 'react';
import styled from "styled-components";

interface FundCardRowProps {
  provider: any
  address: string
}

const FundCardRow = ({ provider, address }: FundCardRowProps) => {
  const [firstLoad, setFirstLoad] = useState(false)
  const [loading, setLoading] = useState(false);
  const [funds, setFunds] = useState();
  const contracts = useContractLoader(provider, address);
  console.log(contracts);
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
            <FundCard provider={provider} address={address} key={address} />
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
