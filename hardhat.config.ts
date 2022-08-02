import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.6",
        settings: {
          evmVersion: "istanbul",
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      forking: {
        url: "https://eth-mainnet.g.alchemy.com/v2/wg9DkB-JY9NwnIUmYAC7V0lR_I7DIjLk",
        blockNumber: 15259360 
      },
    },
  },
  // mocha: {
  //   timeout: 100000000,
  // },
}