
import {
  Flex,
  Box,
  Button,
  EthAddress,
  Heading,
  Link,
  Modal,
  Card,
  Text,
  Image,
  Icon,
  Tooltip
} from 'rimble-ui';
import React, { useState } from 'react';
import styled from "styled-components";
import { useEffect } from 'react';

interface TxSummaryProps {
  submitCallback: any
  closeCallback: any
  isOpen: boolean
  toAddress: string
  fromAddress: string
  ethToReceive: number
  estGasPrice: string
  tokenSymbol: string
  headerText: string
  tokenBalance: number
  tokensToBurn: number
}

function TransactionSummaryModal({
  isOpen,
  toAddress,
  fromAddress,
  tokenBalance,
  tokensToBurn,
  ethToReceive,
  estGasPrice,
  tokenSymbol,
  submitCallback,
  closeCallback,
  headerText
}: TxSummaryProps) {
  const [showModal, setShowModal] = useState(isOpen);

  useEffect(() => {
    setShowModal(isOpen);
  }, [isOpen]);

  const closeModal = e => {
    e.preventDefault();
    closeCallback(e);
  };

  const handleSubmit = e => {
    submitCallback(e);
  }

  return (
    <Box className="TransactionSummaryModal">
      <Modal isOpen={showModal}>
        <Card borderRadius={1} p={0}>
          <Flex
            justifyContent="space-between"
            alignItems="center"
            borderBottom={1}
            borderColor="near-white"
            p={[3, 4]}
            pb={3}
          >
            <Image
              src="/logo2.png"
              aria-label="MetaMask extension icon"
              size="24px"
            />
            <Heading textAlign="center" as="h1" fontSize={[2, 3]} px={[3, 0]}>
              {headerText}
            </Heading>
            <Link onClick={closeModal}>
              <Icon name="Close" color="moon-gray" aria-label="Close" />
            </Link>
          </Flex>

          <SummaryContainer p={[3, 4]}>
            <Flex justifyContent={"space-between"} flexDirection={"column"}>
              <Flex
                alignItems={"stretch"}
                flexDirection={"column"}
                borderRadius={2}
                borderColor={"moon-gray"}
                borderWidth={1}
                borderStyle={"solid"}
                overflow={"hidden"}
                my={[3, 4]}
              >
                <Box bg={"primary"} px={1} py={1} />
                <Flex
                  justifyContent={"space-between"}
                  bg="near-white"
                  p={[2, 3]}
                  borderBottom={"1px solid gray"}
                  borderColor={"moon-gray"}
                  flexDirection={["column", "row"]}
                >
                  <Text
                    textAlign={["center", "left"]}
                    color="near-black"
                    fontWeight="bold"
                  >
                    From
                  </Text>
                  <SmallAddress address={fromAddress} />
                </Flex>

                <Flex
                  justifyContent={"space-between"}
                  bg="light-gray"
                  p={[2, 3]}
                  borderBottom={"1px solid gray"}
                  borderColor={"moon-gray"}
                  flexDirection={["column", "row"]}
                >
                  <Text
                    textAlign={["center", "left"]}
                    color="near-black"
                    fontWeight="bold"
                  >
                    To (You)
                  </Text>
                  <SmallAddress address={toAddress} />
                </Flex>

                <Flex
                  justifyContent={"space-between"}
                  bg="near-white"
                  py={[2, 3]}
                  px={3}
                  alignItems={"center"}
                  borderBottom={"1px solid gray"}
                  borderColor={"moon-gray"}
                  flexDirection={["column", "row"]}
                >
                  <Text
                    textAlign={["center", "left"]}
                    color="near-black"
                    fontWeight="bold"
                  >
                    Receiving
                    </Text>
                  <Flex
                    alignItems={["center", "flex-end"]}
                    flexDirection={["row", "column"]}
                  >
                    <Text
                      mr={[2, 0]}
                      color="near-black"
                      fontWeight="bold"
                      lineHeight={"1em"}
                    >
                      {ethToReceive} ETH
                    </Text>
                  </Flex>
                </Flex>


                <Flex
                  justifyContent={"space-between"}
                  bg="near-white"
                  py={[2, 3]}
                  px={3}
                  alignItems={"center"}
                  borderBottom={"1px solid gray"}
                  borderColor={"moon-gray"}
                  flexDirection={["column", "row"]}
                >
                  <Text
                    textAlign={["center", "left"]}
                    color="near-black"
                    fontWeight="bold"
                  >
                    Updated Balance
                    </Text>
                  <Flex
                    alignItems={["center", "flex-end"]}
                    flexDirection={["row", "column"]}
                  >
                    <Text
                      mr={[2, 0]}
                      color="near-black"
                      fontWeight="bold"
                      lineHeight={"1em"}
                    >
                      {(tokenBalance - tokensToBurn)} {tokenSymbol}
                    </Text>
                    <Text color="mid-gray" fontSize={1}>
                      -{tokensToBurn}
                    </Text>
                  </Flex>
                </Flex>

                <Flex
                  justifyContent={"space-between"}
                  bg="light-gray"
                  py={[2, 3]}
                  px={3}
                  alignItems={"center"}
                  borderBottom={"1px solid gray"}
                  borderColor={"moon-gray"}
                  flexDirection={["column", "row"]}
                >
                  <Flex alignItems={"center"}>
                    <Text
                      textAlign={["center", "left"]}
                      color="near-black"
                      fontWeight="bold"
                    >
                      Transaction fee
                      </Text>
                    <Tooltip
                      message="Pays the Ethereum network to process your transaction. Spent even if the transaction fails."
                      position="top"
                    >
                      <Icon
                        ml={1}
                        name={"InfoOutline"}
                        size={"14px"}
                        color={"primary"}
                      />
                    </Tooltip>
                  </Flex>

                  <Flex
                    alignItems={["center", "flex-end"]}
                    flexDirection={["row", "column"]}
                  >
                    <Text
                      mr={[2, 0]}
                      color="near-black"
                      fontWeight="bold"
                      lineHeight={"1em"}
                    >
                      {estGasPrice} ETH
                      </Text>
                  </Flex>
                </Flex>

                <Flex
                  justifyContent={"space-between"}
                  bg={"near-white"}
                  p={[2, 3]}
                  alignItems={"center"}
                  flexDirection={["column", "row"]}
                >
                  <Text color="near-black" fontWeight="bold">Estimated time</Text>
                  <Text color={"mid-gray"}>About 2 minutes</Text>
                </Flex>
              </Flex>
              <Button.Outline onClick={handleSubmit}>Submit transaction</Button.Outline>
            </Flex>
          </SummaryContainer>
        </Card>
      </Modal>
    </Box>
  );
}

const SmallAddress = styled(EthAddress)`
  width: 200px;
`
const SummaryContainer = styled(Box)`
  min-width: 450px;
`
export default TransactionSummaryModal;
