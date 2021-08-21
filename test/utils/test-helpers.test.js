const { expect } = require('chai');
const { ethers } = require('hardhat');

const { ONE_DAY_IN_SECONDS } = require('../../lib/constants');
const { increaseTime, increaseBlock, getTimestamp, mineInBlock } = require('utils/test-helpers');

describe('Test Helpers', function () {
  beforeEach(async () => {});

  it('can mine multiple transactions within the same block', async function () {
    const [signer] = await ethers.getSigners();
    let onePromise, twoPromise;

    await mineInBlock(async () => {
      onePromise = await signer.sendTransaction({
        to: signer.address,
        value: 1,
        gasLimit: 21000,
      });
      twoPromise = await signer.sendTransaction({
        to: signer.address,
        value: 1,
        gasLimit: 21000,
      });
    });

    const [receiptOne, receiptTwo] = await Promise.all([onePromise.wait(), twoPromise.wait()]);

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
  it('can increase block', async function () {
    const timestampBefore = await getTimestamp();
    const beforeBlock = await ethers.provider.getBlock();
    const value = 10;
    await increaseBlock(value);

    const timestampAfter = await getTimestamp();
    const afterBlock = await ethers.provider.getBlock();

    expect(beforeBlock.number + value).to.be.eq(afterBlock.number);
    expect(timestampBefore).to.be.closeTo(timestampAfter - ethers.BigNumber.from(value * 20), 1);
  });
});
