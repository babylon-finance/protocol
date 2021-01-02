import { Modal, Card, Box, Blockie, Flex, Icon, Text, Link, Heading, Button } from "rimble-ui";
import React from "react";

function TransactionFailedModal() {
  return (
    <Card p={0} borderRadius={1} mb={4}>
      <Box height="4px" bg="danger" borderRadius={["1rem 1rem 0 0"]} />
      <Flex
        justifyContent="space-between"
        alignItems="center"
        borderBottom={1}
        borderColor="near-white"
        p={[3, 4]}
        pb={3}
      >
        <Icon name="Warning" color="danger" aria-label="Warning" />
        <Heading textAlign="center" as="h1" fontSize={[2, 3]} px={[3, 0]}>
          Deposit Failed
        </Heading>
        <Link>
          <Icon
            name="Close"
            color="moon-gray"
            aria-label="Close and cancel connection"
          />
        </Link>
      </Flex>
      <Text p={[3, 4]}>
        We couldn’t confirm your deposit. Please try again later.
      </Text>
      <Flex
        p={[3, 4]}
        borderTop={1}
        borderColor="near-white"
        justifyContent="flex-end"
        flexDirection={["column", "row"]}
        alignItems="center"
      >
        <Button.Outline mr={[0, 3]} mb={[2, 0]} width={["100%", "auto"]}>
          View on Etherscan
        </Button.Outline>
        <Button width={["100%", "auto"]}>Try again</Button>
      </Flex>
    </Card>
  );
}

export default TransactionFailedModal;
