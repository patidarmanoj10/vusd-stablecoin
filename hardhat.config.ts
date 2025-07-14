import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import "@typechain/hardhat";
import {HardhatUserConfig} from "hardhat/types";
import "solidity-coverage";
import "hardhat-log-remover";
import "hardhat-gas-reporter";
import "hardhat-contract-sizer";
import dotenv from "dotenv";
dotenv.config();

const junk = "test test test test test test test test test test test junk";

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    localhost: {
      saveDeployments: true,
    },
    hardhat: {
      saveDeployments: true,
      forking: {
        url: process.env.FORK_NODE_URL || "https://localhost:8545",
        blockNumber: process.env.FORK_BLOCK_NUMBER ? parseInt(process.env.FORK_BLOCK_NUMBER) : undefined,
      },
    },
    mainnet: {
      url: process.env.NODE_URL || "",
      chainId: 1,
      gas: 6700000,
      accounts: {mnemonic: process.env.MNEMONIC || junk},
    },
  },
  paths: {
    deployments: "deployments",
  },
  namedAccounts: {
    deployer: process.env.DEPLOYER || 0,
  },
  solidity: {
    version: "0.8.3",
  },
};

export default config;
