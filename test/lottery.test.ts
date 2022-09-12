import { deployments, ethers, getNamedAccounts } from "hardhat";
import { Lottery, MockERC20 } from "../typechain";
import { assert, expect } from "chai";
import {
  offChainSignGetRSV,
  offChainSignGetRSVWithSignerIndex,
} from "../utils/off-chain-sign";

describe("Flashbot Unit Tests", async function () {
  let lottery: Lottery, deployer: string;

  beforeEach(async () => {
    await deployments.fixture(["all"]);
    lottery = await ethers.getContract("Lottery");
    deployer = (await getNamedAccounts()).deployer;
  });

  describe("Verify Offchain signed", async function () {
    it("should working", async function () {
      const blockNumBefore = await ethers.provider.getBlockNumber();
      const blockBefore = await ethers.provider.getBlock(blockNumBefore);
      const timestampBefore = blockBefore.timestamp;
      const encodeMessage = await lottery.encodeFreeClaimTicketHasedMessage(
        deployer,
        0,
        timestampBefore + 120,
        [1, 2, 3, 4]
      );
      console.log(encodeMessage);
      const [signed, r, s, v] = await offChainSignGetRSV(encodeMessage);
      const tx = await lottery.freeClaimTicketPermit(
        timestampBefore + 120,
        [1, 2, 3, 4],
        v,
        r,
        s
      );
      await tx.wait(1);
    });

    it("should not working", async function () {
      const blockNumBefore = await ethers.provider.getBlockNumber();
      const blockBefore = await ethers.provider.getBlock(blockNumBefore);
      const timestampBefore = blockBefore.timestamp;
      const encodeMessage = await lottery.encodeFreeClaimTicketHasedMessage(
        deployer,
        0,
        timestampBefore + 120,
        [1, 2, 3, 4]
      );
      console.log(encodeMessage);
      const [signed, r, s, v] = await offChainSignGetRSVWithSignerIndex(
        encodeMessage,
        2
      );
      await expect(
        lottery.freeClaimTicketPermit(
          timestampBefore + 120,
          [1, 2, 3, 4],
          v,
          r,
          s
        )
      ).to.be.revertedWith("Not Accepted");
    });
  });
});
