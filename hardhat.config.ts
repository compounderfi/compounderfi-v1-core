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
            runs: 100000000,
          },
        },
      },
    ],
  },
  networks: {
    local: {
			url: 'http://127.0.0.1:8545'
	  },
    hardhat: {
      forking: {
        url: "https://eth-mainnet.g.alchemy.com/v2/wg9DkB-JY9NwnIUmYAC7V0lR_I7DIjLk",
        blockNumber: 15277386  
      },
    },
  },
  mocha: {
     timeout: 100000000,
  }
}