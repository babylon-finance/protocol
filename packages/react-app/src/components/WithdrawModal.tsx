import TransactionSummaryModal from "./TransactionSummaryModal";

import { Transactor } from "../helpers";
import useGasPrice from "../hooks/GasPrice";
import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";

import { formatEther } from "@ethersproject/units";
import React, { useState, useEffect } from "react";
import styled from "styled-components";
import { notification } from "antd";
import { Box, Blockie, Button, Card, EthAddress, Field, Form, Heading, Modal, Pill } from "rimble-ui";

interface InvesModalProps {
  provider: any
  contractAddress: string
  userAddress: string
  active: boolean
  contributor: any
}

interface Contracts {
  ClosedFund: any
  IERC20: any
}

const fundContractName = "ClosedFund";
const tokenContractName = "IERC20";

function WithdrawModal({ provider, contractAddress, userAddress, active, contributor }: InvesModalProps) {
  const [isOpen, setIsOpen] = useState<boolean>(false);
  const [showSummary, setShowSummary] = useState<boolean>(false);
  const [withdrawAmount, setWithdrawAmount] = useState<number>(0);
  const [formValidated, setFormaValidated] = useState<boolean>(false);
  const [contracts, setContracts] = useState<Contracts | undefined>(undefined);
  const [tokenBalance, setTokenBalance] = useState<number | undefined>(undefined);
  const [tokenSymbol, setTokenSymbol] = useState<string | undefined>(undefined);

  const estGasPrice = useGasPrice("fast");
  const tx = Transactor(provider, estGasPrice);

  const handleShowSummary = e => {
    e.preventDefault();
    setShowSummary(true);
    setIsOpen(false);
  };

  const handleSubmit = async e => {
    if (contracts && tx && (withdrawAmount > 0)) {
      try {
        const result = await tx(
          contracts.ClosedFund.withdraw(
            withdrawAmount,
            1,
            userAddress,
          )
        );
        if (result) {
          notification.success({
            message: "Transaction Sent",
            description:
              "Your withdraw transaction has been submitted.",
          });
        }
      } catch (err) {
        notification.error({
          message: "Transaction Failed",
          description:
            err.toString()
        });
      }
    }
    setIsOpen(false);
  }

  const getTokensAfterBurn = () => {
    if (tokenBalance && withdrawAmount) {
      return tokenBalance - withdrawAmount;
    } else {
      return 0;
    }
  }

  const handleInputChange = e => {
    setWithdrawAmount(e.target.value);
  };

  const buttonText = () => {
    return active === true ? "Withdraw" : "Inactive";
  };

  const closeModal = e => {
    e.preventDefault();
    setIsOpen(false);
  };

  const openModal = e => {
    e.preventDefault();
    if (active) {
      setIsOpen(true);
    }
  };

  // The math here is wrong. I think we need to grab the "available amount to withdraw" from somwhere else. For now
  // this is just PoC to experience simple withdrawl flow.
  const validateWithdrawForm = () => {
    if (tokenBalance && withdrawAmount <= tokenBalance && withdrawAmount > 0) {
      setFormaValidated(true);
    } else {
      setFormaValidated(false);
    }
  };

  useEffect(() => {
    async function getContracts() {
      const fund = await loadContractFromNameAndAddress(contractAddress, fundContractName, provider);
      const token = await loadContractFromNameAndAddress(contractAddress, tokenContractName, provider);
      setContracts({ ClosedFund: fund, IERC20: token });
      if (token) {
        setTokenBalance(await token.balanceOf(userAddress));
      }
    }
    if (!contracts) {
      getContracts();
    }
    validateWithdrawForm();
  });

  return (
    <Box className="WithdrawModel" p={1}>
      <Box>
        <StyledWithdrawButton onClick={openModal} disabled={!active}>{buttonText()}</StyledWithdrawButton>
        <Modal isOpen={isOpen}>
          <Card width={"550px"} p={0}>
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
              <Heading.h3>How much would you like to withdraw?</Heading.h3>
              <Blockie
                opts={{
                  seed: userAddress,
                  color: "#dfe",
                  bgcolor: "#a71",
                  size: 15,
                  scale: 3,
                  spotcolor: "#000"
                }}
              />
              <EthAddress mb={3} address={userAddress} />
              {tokenBalance && (
                <Pill color="green">
                  Available: {tokenBalance.toString()}
                </Pill>
              )}
              <Form onSubmit={handleShowSummary} validated={formValidated}>
                <Field label="Withdrawl Amount" width={1}>
                  <Form.Input onChange={handleInputChange} type="number" required placeholder="0" value={withdrawAmount} />
                </Field>
                <Button type="submit" disabled={!formValidated}>Preview Withdrawl</Button>
              </Form>
            </Box>
          </Card>
        </Modal>
        {contracts && estGasPrice && (
          <TransactionSummaryModal
            headerText={"Withdrawl Preview"}
            submitCallback={handleSubmit}
            showModal={showSummary}
            tokensAfterTx={getTokensAfterBurn()}
            toAddress={userAddress}
            fromAddress={contracts.ClosedFund.address}
            ethToReceive={withdrawAmount}
            estGasPrice={formatEther(estGasPrice)}
            tokenSymbol="TOKEN" />
        )}
      </Box>
    </Box>
  );
}

const StyledWithdrawButton = styled(Button)`
  width: 100%;
`

export default WithdrawModal;
