import { ethers } from "hardhat";

const freeTicketClaimType = ["address", "uint", "uint[]", "uint", "uint"];

export async function offChainSignGetRSV(
  message: string
): Promise<[string, string, string, number]> {
  const accounts = await ethers.getSigners();
  const signer = accounts[0];
  console.log(signer.address);
  const signedMessage = await signer.signMessage(
    ethers.utils.arrayify(message)
  );
  const r = signedMessage.slice(0, 66);
  const s = "0x" + signedMessage.slice(66, 130);
  const v = Number("0x" + signedMessage.slice(130, 132));
  return [signedMessage, r, s, v];
}

export async function offChainSignGetRSVWithSignerIndex(
  message: string,
  index: number
): Promise<[string, string, string, number]> {
  const accounts = await ethers.getSigners();
  const signer = accounts[index];
  console.log(signer.address);
  const signedMessage = await signer.signMessage(
    ethers.utils.arrayify(message)
  );
  const r = signedMessage.slice(0, 66);
  const s = "0x" + signedMessage.slice(66, 130);
  const v = Number("0x" + signedMessage.slice(130, 132));
  return [signedMessage, r, s, v];
}
