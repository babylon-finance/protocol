import { Transactor } from "../../helpers";
import useGasPrice from "../../hooks/GasPrice";
import { loadContractFromNameAndAddress } from "../../hooks/ContractLoader";

import { parseEther } from "@ethersproject/units";
import React, { useState, useEffect } from "react";
import styled from "styled-components";
import { notification } from "antd";
import { Box, Blockie, EthAddress, Field, Form, Heading, Button, Modal, Card } from "rimble-ui";

interface DepositModalProps {
  provider: any
  contractAddress: string
  userAddress: string
  active: boolean
}

const contractName = "ClosedFund";

function DepositModal({ provider, contractAddress, userAddress, active }: DepositModalProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [depositAmount, setDepositAmount] = useState(0);
  const [contract, setContract] = useState();
  const tx = Transactor(provider, useGasPrice("fast"));

  useEffect(() => {
    async function getContract() {
      setContract(await loadContractFromNameAndAddress(contractAddress, contractName, provider));
    }
    if (!contract) {
      getContract();
    }
  }, [contract, provider, contractAddress])

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

  const handleSubmitDeposit = async e => {
    e.preventDefault();
    if (tx && (depositAmount > 0)) {
      try {
        const result = await tx(
          contract.deposit(
            parseEther("1"),
            1,
            userAddress,
            {
              value: parseEther(depositAmount.toString())
            },
          )
        );
        if (result) {
          notification.success({
            message: "Transaction Sent",
            description:
              "Your deposit transaction has been submitted.",
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

  const investButtonText = () => {
    return active === true ? "Deposit" : "Inactive";
  };

  return (
    <Box className="InvestModel" p={1}>
      <Box>
        <StyledInvestButton onClick={openModal} disabled={!active}>{investButtonText()}</StyledInvestButton>
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
                  seed: userAddress,
                  color: "#dfe",
                  bgcolor: "#a71",
                  size: 15,
                  scale: 3,
                  spotcolor: "#000"
                }}
              />
              <EthAddress mb={3} address={userAddress} />
              <Form onSubmit={handleSubmitDeposit}>
                <Field label="Deposit Amount" width={1}>
                  <Form.Input onChange={handleInputChange} type="number" required placeholder="0" value={depositAmount} />
                </Field>
                <Button type="submit">Preview Deposit</Button>
              </Form>
            </Box>
          </Card>
        </Modal>
      </Box>
    </Box>
  );
}

const StyledInvestButton = styled(Button)`
  font-family: cera-regular;
  width: 100%;
`

export default DepositModal;
