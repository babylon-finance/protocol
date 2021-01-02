
import {
  Flex,
  Box,
  Heading,
  Button,
  Link,
  Modal,
  Card,
  Text,
  Image,
  Icon,
  Loader,
  Tooltip
} from 'rimble-ui';
import React, { useState } from 'react';

function TransactionSummaryModal() {
  const [isOpen, setIsOpen] = useState(false);

  const closeModal = e => {
    e.preventDefault();
    setIsOpen(false);
  };

  const openModal = e => {
    e.preventDefault();
    setIsOpen(true);
  };

  return (
    <Box>
      <Flex alignItems={"center"}>
        <Button onClick={openModal}>Invest</Button>
      </Flex>

      <Modal isOpen={isOpen}>
        <Card borderRadius={1} p={0} overflow={"scroll"}>
          <Flex
            justifyContent="space-between"
            alignItems="center"
            borderBottom={1}
            borderColor="near-white"
            p={[3, 4]}
            pb={3}
          >
            <Image
              src="/images/MetaMaskIcon.svg"
              aria-label="MetaMask extension icon"
              size="24px"
            />
            <Heading textAlign="center" as="h1" fontSize={[2, 3]} px={[3, 0]}>
              Confirm your transfer in [wallet]
              </Heading>
            <Link onClick={closeModal}>
              <Icon name="Close" color="moon-gray" aria-label="Close" />
            </Link>
          </Flex>
          <Box p={[3, 4]}>
            <Flex justifyContent={"space-between"} flexDirection={"column"}>
              <Text textAlign="center">
                Double check the details here – your transfer can't be reversed.
                </Text>
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
                <Box bg={"primary"} px={3} py={2}>
                  <Text color={"white"}>ETH transfer</Text>
                </Box>

                <Flex
                  p={3}
                  borderBottom={"1px solid gray"}
                  borderColor={"moon-gray"}
                  alignItems={"center"}
                  flexDirection={["column", "row"]}
                >
                  <Box
                    position={"relative"}
                    height={"2em"}
                    width={"2em"}
                    mr={[0, 3]}
                    mb={[3, 0]}
                  >
                    <Box position={"absolute"} top={"0"} left={"0"}>
                      <Loader size={"2em"} />
                    </Box>
                  </Box>
                  <Box>
                    <Text
                      textAlign={["center", "left"]}
                      fontWeight={"600"}
                      fontSize={1}
                      lineHeight={"1.25em"}
                    >
                      Waiting for confirmation...
                      </Text>
                    <Link
                      fontWeight={100}
                      lineHeight={"1.25em"}
                      color={"primary"}
                    >
                      Don't see the MetaMask popup?
                      </Link>
                  </Box>
                </Flex>

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
                    From (you)
                    </Text>
                  <Link
                    href={"https://rinkeby.etherscan.io/address/"}
                    target={"_blank"}
                  >
                    <Tooltip message="0xAc03BB73b6a9e108530AFf4Df5077c2B3D481e5A">
                      <Flex
                        justifyContent={["center", "auto"]}
                        alignItems={"center"}
                        flexDirection="row-reverse"
                      >
                        <Text fontWeight="bold">0xAc03...1e5A</Text>
                        <Flex
                          mr={2}
                          p={1}
                          borderRadius={"50%"}
                          bg={"primary-extra-light"}
                          height={"2em"}
                          width={"2em"}
                          alignItems="center"
                          justifyContent="center"
                        >
                          <Icon
                            color={"primary"}
                            name="RemoveRedEye"
                            size={"1em"}
                          />
                        </Flex>
                      </Flex>
                    </Tooltip>
                  </Link>
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
                    To
                    </Text>
                  <Link
                    href={"https://rinkeby.etherscan.io/address/"}
                    target={"_blank"}
                  >
                    <Tooltip message="0xD145f9c4f276be0e1a7Df3F4c52a0abDeea757F5">
                      <Flex
                        justifyContent={["center", "auto"]}
                        alignItems={"center"}
                        flexDirection="row-reverse"
                      >
                        <Text fontWeight="bold">0xD145...57F5</Text>
                        <Flex
                          mr={2}
                          p={1}
                          borderRadius={"50%"}
                          bg={"primary-extra-light"}
                          height={"2em"}
                          width={"2em"}
                          alignItems="center"
                          justifyContent="center"
                        >
                          <Icon
                            color={"primary"}
                            name="RemoveRedEye"
                            size={"1em"}
                          />
                        </Flex>
                      </Flex>
                    </Tooltip>
                  </Link>
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
                    Amount
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
                      5.4 ETH
                      </Text>
                    <Text color="mid-gray" fontSize={1}>
                      $1450 USD
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
                      $0.42
                      </Text>
                    <Text color="mid-gray" fontSize={1}>
                      0.00112 ETH
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
                  <Text color="near-black" fontWeight="bold">
                    Estimated time
                    </Text>
                  <Text color={"mid-gray"}>Less than 2 minutes</Text>
                </Flex>
              </Flex>
              <Button.Outline onClick={closeModal}>
                Cancel purchase
                </Button.Outline>
            </Flex>
          </Box>
        </Card>
      </Modal>
    </Box>
  );
}

export default TransactionSummaryModal;
