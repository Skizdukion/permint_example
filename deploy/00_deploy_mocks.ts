import { DeployFunction } from "hardhat-deploy/types";
import { getNamedAccounts, deployments, network, ethers } from "hardhat";

const deployFunction: DeployFunction = async () => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId: number | undefined = network.config.chainId;

  // If we are on a local development network, we need to deploy mocks!
  if (chainId === 31337) {
    log(`Local network detected! Deploying mocks...`);

    await deploy("MockERC20V1", {
      contract: "MockERC20",
      from: deployer,
      log: true,
      args: ["Mock1ERC20", "M1", ethers.constants.MaxUint256],
    });

    await deploy("MockERC20V2", {
      contract: "MockERC20",
      from: deployer,
      log: true,
      args: ["Mock2ERC20", "M2", ethers.constants.MaxUint256],
    });

    await deploy("MockERC20V3", {
      contract: "MockERC20",
      from: deployer,
      log: true,
      args: ["Mock3ERC20", "M3", ethers.constants.MaxUint256],
    });

    await deploy("MockERC20V4", {
      contract: "MockERC20",
      from: deployer,
      log: true,
      args: ["Mock3ERC20", "M3", ethers.constants.MaxUint256],
    });

    await deploy("MockERC20V5", {
      contract: "MockERC20",
      from: deployer,
      log: true,
      args: ["Mock3ERC20", "M3", ethers.constants.MaxUint256],
    });

    log(`Mocks Deployed!`);
  }
};

export default deployFunction;
deployFunction.tags = [`all`, `mocks`, `main`];
