import { Transactor } from "../helpers";
import useGasPrice from "../hooks/GasPrice";

import { parseEther } from "@ethersproject/units";
import React, { useState } from "react";
import styled from "styled-components";
import { notification } from "antd";
import { Box, Blockie, EthAddress, Field, Form, Heading, Button, Modal, Card } from "rimble-ui";

interface InvesModalProps {
  provider: any
  contract: any
  address: string
}

function InvestModal({ provider, contract, address }: InvesModalProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [depositAmount, setDepositAmount] = useState("");
  const tx = Transactor(provider, useGasPrice("fast"));

  const closeModal = e => {
    e.preventDefault();
    setIsOpen(false);
  };

  const openModal = e => {
    e.preventDefault();
    setIsOpen(true);
  };

  const handleSubmitDeposit = async e => {
    e.preventDefault();
    if (tx && depositAmount) {
      try {
        const result = await tx(contract.deposit(parseEther("1"), 1, { value: parseEther(depositAmount.toString()) }));
        if (result) {
          notification.success({
            message: "Transaction Sent",
            description:
              "Your deposit transaction has been sent.",
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
    setDepositAmount(e.target.value);
  };

  return (
    <Box className="App" p={4}>
      <Box>
        <StyledInvestButton onClick={openModal}>Invest</StyledInvestButton>
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
              <Heading.h3>How much would you like to invest?</Heading.h3>
              <Blockie
                opts={{
                  seed: address,
                  color: "#dfe",
                  bgcolor: "#a71",
                  size: 15,
                  scale: 3,
                  spotcolor: "#000"
                }}
              />
              <EthAddress mb={3} address={address} />
              <Form onSubmit={handleSubmitDeposit}>
                <Field label="Deposit Amount" width={1}>
                  <Form.Input onChange={handleInputChange} type="number" required placeholder="0" value={depositAmount} />
                </Field>
                <Button type="submit">Deposit</Button>
              </Form>
            </Box>
          </Card>
        </Modal>
      </Box>
    </Box>
  );
}

const StyledInvestButton = styled(Button)`
  width: 100%;
`

export default InvestModal;
