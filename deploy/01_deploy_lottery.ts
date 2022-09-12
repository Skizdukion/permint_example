import { DeployFunction } from "hardhat-deploy/types";
import { getNamedAccounts, deployments, network, ethers } from "hardhat";
import { Lottery, MockERC20 } from "../typechain";

const deployFunction: DeployFunction = async () => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy("Lottery", {
    contract: "Lottery",
    from: deployer,
    log: true,
  });

  const lottery: Lottery = await ethers.getContract("Lottery");
  const winery: MockERC20 = await ethers.getContract("MockERC20V1");

  await lottery.initialize(
    winery.address,
    2000000000,
    150,
    deployer,
    deployer,
    deployer,
    2000000000
  );

  //   function initialize(
  //     IERC20 _winery,
  //     uint256 _minPrice,
  //     uint8 _maxNumber,
  //     address _owner,
  //     address _adminAddress,
  //     address _treasuryAddress,
  //     uint256 _nextTime
  // ) public initializer {
  //     winery = _winery;
  //     minPrice = _minPrice;
  //     maxNumber = _maxNumber;
  //     adminAddress = _adminAddress;
  //     treasuryAddress = _treasuryAddress;
  //     lastTimestamp = block.timestamp;
  //     rolloverAllocation = 5;
  //     _setAllocation(65, 20, 10);
  //     initOwner(_owner);
  //     lotteryId = 0;
  //     nextTimeDraw = _nextTime;
  // }
};

export default deployFunction;
deployFunction.tags = [`all`, `box`, `main`];
