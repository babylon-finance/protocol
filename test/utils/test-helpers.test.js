const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_DAY_IN_SECONDS } = require('../../utils/constants');
const { increaseTime, getTimestamp, mineInBlock } = require('./test-helpers');

describe('Test Helpers', function () {
  beforeEach(async () => {});

  it('can mine multiple transactions within the same block', async function () {
    const [signer] = await ethers.getSigners();
    let onePromise, twoPromise;

    await mineInBlock(async () => {
      onePromise = signer.sendTransaction({
        to: signer.address,
        value: 1,
      });
      twoPromise = signer.sendTransaction({
        to: signer.address,
        value: 1,
      });
    });

    const [receiptOne, receiptTwo] = await Promise.all([(await onePromise).wait(), (await twoPromise).wait()]);

    expect(receiptOne.blockNumber).to.be.gt(0);
    expect(receiptTwo.blockNumber).to.be.gt(0);
    expect(receiptOne.blockNumber).to.be.eq(receiptTwo.blockNumber);
  });

  it('can increase time', async function () {
    const timestampBefore = await getTimestamp();
    const beforeBlock = await ethers.provider.getBlock();

    await increaseTime(ONE_DAY_IN_SECONDS);

    const timestampAfter = await getTimestamp();
    const afterBlock = await ethers.provider.getBlock();

    expect(beforeBlock.number + 1).to.be.eq(afterBlock.number);
    expect(timestampBefore).to.be.closeTo(timestampAfter - ONE_DAY_IN_SECONDS.toNumber(), 1);
  });
});
