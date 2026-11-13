import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-mocha-ethers";

const config: HardhatUserConfig = {
  solidity: "0.8.28", // 根据你的 main.sol 中的 pragma 版本进行调整
};

export default config;