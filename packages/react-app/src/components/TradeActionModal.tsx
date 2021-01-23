import * as addresses from "../contracts/addresses";
import * as contractNames from "../constants/contracts";
import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";
import { Transactor } from "../helpers";
import useGasPrice from "../hooks/GasPrice";
import { Token, UniswapTokenList } from "../constants/UniswapTokenList";

import { notification } from "antd";
import { commify, formatEther, parseEther } from "@ethersproject/units";
import { BigNumber } from "@ethersproject/bignumber";
import { Box, Button, Card, Heading, Input, Loader, Field, Flex, Form, Modal } from 'rimble-ui';

import { usePoller } from "eth-hooks";
import React, { useCallback, useEffect, useState } from "react";
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
  expectedRate: BigNumber
  expectedRateDisplay: string
  worstRate: BigNumber
  worstRateDisplay: string
}

const EMPTY_QUOTE_PAIR = {
  expectedRate: BigNumber.from(0),
  expectedRateDisplay: "0",
  worstRate: BigNumber.from(0),
  worstRateDisplay: "0"
};

const TradeActionModal = ({ fundAddress, provider }: TradeActionModalProps) => {
  const [showModal, setShowModal] = useState(false);
  const [showSummary, setShowSummary] = useState(false);
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);
  const [providing, setProviding] = useState<string | undefined>(undefined);
  const [providingDetails, setProvidingDetails] = useState<Token | undefined>(undefined);
  const [providingAmount, setProvidingAmount] = useState<number>(1);
  const [txConfirm, setTxConfirm] = useState<boolean>(false);
  const [receiving, setReceiving] = useState<string | undefined>(undefined);
  const [receivingDetails, setReceivingDetails] = useState<Token | undefined>(undefined);
  const [quotePair, setQuotePair] = useState<QuotePair>(EMPTY_QUOTE_PAIR);
  const [quoteLoading, setQuoteLoading] = useState<boolean>(false);

  const estGasPrice = useGasPrice("fast");
  const tx = Transactor(provider, estGasPrice);
  const TokensMapByAddress = new Map(UniswapTokenList.tokens.map(token => [token.address, token]));

  const updateQuotePair = useCallback(async () => {
    if (contracts && providingDetails && receivingDetails) {
      setQuoteLoading(true);

      const quote = await contracts.IKyberNetworkProxy.getExpectedRate(providingDetails.address, receivingDetails.address, parseEther(providingAmount.toString() || "0"));
      const expectedReturn = quote[0].mul(BigNumber.from(providingAmount));
      const worstReturn = quote[1].mul(BigNumber.from(providingAmount));

      setQuotePair({
        expectedRate: quote[0],
        expectedRateDisplay: formatTokenDisplay(expectedReturn),
        worstRate: quote[1],
        worstRateDisplay: formatTokenDisplay(worstReturn)
      });

      setQuoteLoading(false);
    }
  }, [contracts, providingDetails, receivingDetails, providingAmount]);

  useEffect(() => {
    async function getContracts() {
      const kyber = await loadContractFromNameAndAddress(addresses.kyber.proxy, contractNames.IKyberNetworkProxy, provider);
      const fund = await loadContractFromNameAndAddress(fundAddress, contractNames.ClosedFund, provider);

      setContracts({ IKyberNetworkProxy: kyber, ClosedFund: fund });

      if (kyber && providing && receiving) {
        setQuoteLoading(true);

        const providingDetails = TokensMapByAddress.get(providing);
        const receivingDetails = TokensMapByAddress.get(receiving);

        if (!providingDetails || !receivingDetails) {
          throw Error();
        }

        const initialQuote = await kyber.getExpectedRate(providingDetails.address, receivingDetails.address, parseEther(providingAmount.toString()));
        const initialExpected = initialQuote[0];
        const initialWorst = initialQuote[1];

        setQuotePair({
          expectedRate: initialQuote[0],
          expectedRateDisplay: formatTokenDisplay(initialExpected),
          worstRate: initialQuote[1],
          worstRateDisplay: formatTokenDisplay(initialWorst),
        });

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

  const handleEditTradeOnClick = e => {
    e.preventDefault()
    setShowSummary(false);
    setShowModal(true);
  }

  const startTradeAction = async e => {
    e.preventDefault();
    updateQuotePair();
    setShowModal(false);
    setShowSummary(true);
  };

  const handleConfirmTrade = async e => {
    e.preventDefault();
    if (contracts && tx && quotePair && providingDetails && receivingDetails) {
      try {
        setTxConfirm(true);

        const result = await tx(
          contracts.ClosedFund.trade(
            "kyber",
            providingDetails.address,
            parseEther(providingAmount.toString()),
            receivingDetails.address,
            quotePair.expectedRate,
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

    setTxConfirm(false);
    setShowSummary(false);
  };

  const formatTokenDisplay = (value: BigNumber) => {
    const MAX_CHARS = 7;
    const splitArray = formatEther(value).split('.');

    if (splitArray[0].length < MAX_CHARS) {
      return commify(splitArray[0] + "." + splitArray[1].substring(0, (MAX_CHARS - splitArray[0].length)));
    } else {
      return commify(splitArray[0]);
    }
  }

  const handleProvidingOnChange = async e => {
    setQuoteLoading(true);
    setProviding(e.target.value);

    const providingDetails = TokensMapByAddress.get(e.target.value);

    if (providingDetails) {
      setProvidingDetails(providingDetails);
    }
  };

  const handleProvidingAmountOnChange = async e => {
    setProvidingAmount(e.target.value ? parseInt(e.target.value) : 0);
  };

  const handleReceivingOnChange = async e => {
    setQuoteLoading(true);
    setReceiving(e.target.value);

    const receivingDetails = TokensMapByAddress.get(e.target.value);

    if (receivingDetails) {
      setReceivingDetails(receivingDetails);
    }
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
            <Form onSubmit={startTradeAction}>
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
                    {UniswapTokenList.tokens.map((tokenObj) => (
                      <option value={tokenObj.address} key={tokenObj.address}>
                        {tokenObj.name}
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
                    {UniswapTokenList.tokens.map((tokenObj) => (
                      <option value={tokenObj.address} key={tokenObj.address}>
                        {tokenObj.name}
                      </option>
                    ))}
                  </AssetSelect>
                </Field>
                {quoteLoading && (
                  <Loader />
                )}
                <Field label="Amount" required>
                  <Input type="text" disabled required={true} value={quoteLoading ? "--" : quotePair.expectedRateDisplay} />
                </Field>
              </Flex>
              <FormSubmitButton type="submit">Perform Trade</FormSubmitButton>
            </Form>
          </Box>
        </TradeCard>
      </Modal>
      <Modal isOpen={showSummary}>
        <TradeCard width={"550px"} p={4}>
          <p>Providing: {providingAmount} {providingDetails && providingDetails.symbol} </p>
          <p>Receiving: {quotePair.expectedRateDisplay} {receivingDetails && receivingDetails.symbol} </p>
          <p>Estimated Gas Fees: {estGasPrice}</p>
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
          <FormSubmitButton onClick={handleConfirmTrade}>
            {txConfirm
              ? <Loader color="white" />
              : "Confirm Trade"
            }
          </FormSubmitButton>
          <Button.Outline
            disabled={txConfirm}
            color={"moon-gray"}
            ml={3}
            onClick={handleEditTradeOnClick}
          >
            Edit Trade
          </Button.Outline>
        </TradeCard>
        }
      </Modal>
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

const TradeCard = styled(Card)`
  height: 700px;
`

const FormSubmitButton = styled(Button)`
  min-width: 200px;
  margin-top: 12px;
`

export default TradeActionModal;
