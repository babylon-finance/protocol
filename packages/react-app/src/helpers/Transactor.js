import { hexlify } from "@ethersproject/bytes";
import { parseUnits } from "@ethersproject/units";
import { notification } from "antd";

// this should probably just be renamed to "notifier"
// it is basically just a wrapper around BlockNative's wonderful Notify.js
// https://docs.blocknative.com/notify

export default function Transactor(provider, gasPrice, etherscan) {
  if (typeof provider !== "undefined") {
    // eslint-disable-next-line consistent-return
    return async tx => {
      const signer = provider.getSigner();
      const network = await provider.getNetwork();
      console.log("network", network);
      try {
        let result;
        if (tx instanceof Promise) {
          console.log("AWAITING TX", tx);
          result = await tx;
        } else {
          if (!tx.gasPrice) {
            tx.gasPrice = gasPrice || parseUnits("4.1", "gwei");
          }
          if (!tx.gasLimit) {
            tx.gasLimit = hexlify(120000);
          }
          console.log("RUNNING TX", tx);
          result = await signer.sendTransaction(tx);
        }
        console.log("RESULT:", result);
        // console.log("Notify", notify);

        return result;
      } catch (e) {
        console.log(e);
        console.log("Transaction Error:", e.message);
        notification.error({
          message: "Transaction Error",
          description: e.message,
        });
      }
    };
  }
}
