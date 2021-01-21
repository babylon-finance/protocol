import * as addresses from "../contracts/addresses";
import * as contractNames from "../constants/contracts";
import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";
import { Transactor } from "../helpers";
import useGasPrice from "../hooks/GasPrice";

import { notification } from "antd";
import { formatEther, parseEther } from "@ethersproject/units";
import { Card, Box, Button, Heading, Field, Flex, Form, Modal } from 'rimble-ui';

import { usePoller } from "eth-hooks";
import React, { useEffect, useState } from "react";
import styled from "styled-components";

interface TradeActionModalProps {
  fundAddress: string
  provider: any
}

interface Contracts {
  IKyberNetworkProxy: any
  ClosedFund: any
}

interface QuotePair {
  expectedRate: string
  worstRate: string
}

const TradeActionModal = ({ fundAddress, provider }: TradeActionModalProps) => {
  const [showModal, setShowModal] = useState(false);
  const [showSummary, setShowSummary] = useState(false);
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);
  const [providing, setProviding] = useState<string>("weth");
  const [receiving, setReceiving] = useState<string>("dai");
  const [quotePair, setQuotePair] = useState<QuotePair | undefined>(undefined);

  const estGasPrice = useGasPrice("fast");
  const tx = Transactor(provider, estGasPrice);

  useEffect(() => {
    async function getContracts() {
      const kyber = await loadContractFromNameAndAddress(addresses.kyber.proxy, contractNames.IKyberNetworkProxy, provider);
      const fund = await loadContractFromNameAndAddress(fundAddress, contractNames.ClosedFund, provider);
      setContracts({ IKyberNetworkProxy: kyber, ClosedFund: fund });
    }

    if (!contracts && provider) {
      getContracts();
    }
  });

  usePoller(async () => {
    if (contracts && providing && receiving) {
      setQuotePair(await contracts.IKyberNetworkProxy.getExpectedRate(addresses.tokens.WETH, addresses.tokens.DAI, parseEther("1")));
    }
  }, 500);

  const openModal = e => {
    e.preventDefault();
    setShowModal(true);
  };

  const closeModal = e => {
    e.preventDefault();
    setShowModal(false);
  };

  const closeSummary = e => {
    e.preventDefault();
    setShowSummary(false);
  }

  const submitTradeAction = e => {
    e.preventDefault();
    if (quotePair) {
      console.log(formatEther(quotePair[0]));
    }
    setShowModal(false);
    setShowSummary(true);
  };

  const handleConfirmTrade = async e => {
    e.preventDefault();
    if (contracts && tx && quotePair) {
      try {
        const result = await tx(
          contracts.ClosedFund.trade(
            "kyber",
            addresses.tokens.WETH,
            parseEther("1"),
            addresses.tokens.DAI,
            quotePair[0],
            "0x",
            { gasPrice: estGasPrice }
          )
        );
        if (result) {
          notification.success({
            message: "Transaction Sent",
            description:
              "Your trade has been submitted."
          });
        }
      } catch (err) {
        notification.error({
          message: "Transaction Failed: Trade not submitted",
          description:
            err.toString()
        });
      }
    }
    setShowSummary(false);
  }

  const handleProvidingOnChange = e => {
    setProviding(e.target.value)
  };

  const handleReceivingOnChange = e => {
    setReceiving(e.target.value)
  };

  return (
    <div>
      <Button onClick={openModal}>Start Trade</Button>
      <Modal isOpen={showModal}>
        <TradeCard width={"550px"} p={0}>
          <Button.Text
            icononly
            icon={"Close"}
            color={"moon-gray"}
            position={"absolute"}
            top={0}
            right={0}
            mt={3}
            mr={3}
            onClick={closeModal}
          />
          <Box p={4} mb={3}>
            <Heading.h3>Perform Trade Action</Heading.h3>
            <Form onSubmit={submitTradeAction}>
              <Flex
                justifyContent={"space-between"}
                bg="light-gray"
                p={[2, 3]}
                borderBottom={"1px solid gray"}
                borderColor={"moon-gray"}
                flexDirection={["column", "row"]}
              >
                <Field label="Providing">
                  <select required onChange={handleProvidingOnChange} value={providing}>
                    <option value="weth">wETH</option>
                    <option value="dai">DAI</option>
                  </select>
                </Field>
              </Flex>
              <Flex
                justifyContent={"space-between"}
                bg="white"
                p={[2, 3]}
                flexDirection={["column", "row"]}
              >
                <Field label="Receiving">
                  <select required onChange={handleReceivingOnChange} value={receiving}>
                    <option value="dai">DAI</option>
                    <option value="eth">ETH</option>
                  </select>
                </Field>
              </Flex>
              <FormSubmitButton type="submit">Perform Trade</FormSubmitButton>
            </Form>
          </Box>
        </TradeCard>
      </Modal>
      <Modal isOpen={showSummary}>
        <TradeCard width={"550px"} p={0}>
          <p>Providing: 1 {providing} </p>
          <p>Receiving: 1000 {receiving} </p>
          <Button.Text
            icononly
            icon={"Close"}
            color={"moon-gray"}
            position={"absolute"}
            top={0}
            right={0}
            mt={3}
            mr={3}
            onClick={closeSummary}
          />
          <FormSubmitButton onClick={handleConfirmTrade}>Confirm Trade</FormSubmitButton>
        </TradeCard>
      </Modal>
    </div>
  );
};

const TradeCard = styled(Card)`
  height: 700px;
`

const FormSubmitButton = styled(Button)`
  margin-top: 12px;
`

export default TradeActionModal;
