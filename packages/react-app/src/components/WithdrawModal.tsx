import { Transactor } from "../helpers";
import useGasPrice from "../hooks/GasPrice";
import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";

import { parseEther, formatEther } from "@ethersproject/units";
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

const contractName = "ClosedFund";

function WithdrawModal({ provider, contractAddress, userAddress, active, contributor }: InvesModalProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [withdrawAmount, setWithdrawAmount] = useState(0);
  const [formValidated, setFormaValidated] = useState(false);
  const [contract, setContract] = useState();
  const tx = Transactor(provider, useGasPrice("fast"));

  const handleSubmit = async e => {
    e.preventDefault();
    if (tx && (withdrawAmount > 0)) {
      try {
        const result = await tx(
          contract.withdraw(
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
    setIsOpen(true);
  };

  // The math here is wrong. I think we need to grab the "available amount to withdraw" from somwhere else. For now
  // this is just PoC to experience simple withdrawl flow.
  const validateWithdrawForm = () => {
    if (withdrawAmount <= contributor.totalDeposit && (withdrawAmount > 0)) {
      setFormaValidated(true);
    } else {
      setFormaValidated(false);
    }
  };

  useEffect(() => {
    async function getContract() {
      setContract(await loadContractFromNameAndAddress(contractAddress, contractName, provider));
    }
    if (!contract) {
      getContract();
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
              <Pill color="green">
                Supplied: {contributor.totalDeposit}
              </Pill>
              <Form onSubmit={handleSubmit} validated={formValidated}>
                <Field label="Withdrawl Amount" width={1}>
                  <Form.Input onChange={handleInputChange} type="number" required placeholder="0" value={withdrawAmount} />
                </Field>
                <Button type="submit" disabled={!formValidated}>Preview Withdrawl</Button>
              </Form>
            </Box>
          </Card>
        </Modal>
      </Box>
    </Box>
  );
}

const StyledWithdrawButton = styled(Button)`
  width: 100%;
`

export default WithdrawModal;
