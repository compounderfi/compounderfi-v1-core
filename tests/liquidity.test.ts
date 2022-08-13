import chai, { expect } from "chai";
import { Console } from "console";
import { Contract, Signer } from "ethers";
import { ethers, network } from "hardhat";
import { BigNumber} from "@ethersproject/bignumber";
import { Address } from "cluster";

const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
const USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
const WHALE = "0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503"

const NFPM = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
const swapRouter = "0xE592427A0AEce92De3Edee1F18E0157C05861564"
const deadline = 2659131770;
async function mint(account: Signer) {
  const contract: Contract = await ethers.getContractAt("INonfungiblePositionManager", NFPM);
  const txn = await contract
      .connect(account)
      .mint(
      [USDC,
       USDT,
       100, //0.01% fee tier
       -5, //min tick
       2, //max tick
       5000000n * 10n ** 6n, //add 5 million in liqudity
       5000000n * 10n ** 6n,
       0,
       0,
       await account.getAddress(),
       deadline
      ]
      )
    
    const receipt = await txn.wait();
    for (const rec of receipt.events) {
      if (rec.event == "IncreaseLiquidity") {
        const tokenID: BigNumber = rec.args[0];
        const amount0added: BigNumber = rec.args[2];
        const amount1added: BigNumber = rec.args[3];
        return [tokenID.toNumber(), amount0added.toNumber(), amount1added.toNumber()];
      }
    }

    return [0, 0, 0];
}

async function swap(account: Signer, tokenA: String, tokenB: String) {
  const contract: Contract = await ethers.getContractAt("ISwapRouter", swapRouter);
  const txn = await contract
  .connect(account)
  .exactInputSingle(
    [
      tokenA,
      tokenB,
      100,
      await account.getAddress(),
      deadline,
      75000000n * 10n ** 6n, //swap 75 million
      0,
      0
    ]
  )
}

describe("Compounder", () => {
  let compounder: Contract
  let usdt: Contract
  let usdc: Contract
  let uniswap: Contract

  let accounts: Signer[]
  let mainSignerAddress: String;

  beforeEach(async () => {
    const Compounderfi = await ethers.getContractFactory("Compounder")
    compounder = await Compounderfi.deploy()
    await compounder.deployed()
  });

  before(async () => {

    accounts = await ethers.getSigners()
    mainSignerAddress = await accounts[0].getAddress();

    usdt = await ethers.getContractAt("IERC20", USDT)
    usdc = await ethers.getContractAt("IERC20", USDC)
    uniswap = await ethers.getContractAt("INonfungiblePositionManager", NFPM)
    
    const whaleSigner = await ethers.getImpersonatedSigner(WHALE)

    // Send DAI and USDC to accounts[0]
    const tx = await accounts[0].sendTransaction({
      to: WHALE,
      value: ethers.utils.parseEther("1.0")
    });
    const usdtAmount = 1000000000n * 10n ** 6n //1B of each
    const usdcAmount = 1000000000n * 10n ** 6n

    await usdt.connect(whaleSigner).transfer(mainSignerAddress, usdtAmount)
    await usdc.connect(whaleSigner).transfer(mainSignerAddress, usdcAmount)

    await usdt.connect(accounts[0]).approve(NFPM, ethers.constants.MaxUint256);
    await usdc.connect(accounts[0]).approve(NFPM, ethers.constants.MaxUint256);

    await usdt.connect(accounts[0]).approve(swapRouter, ethers.constants.MaxUint256);
    await usdc.connect(accounts[0]).approve(swapRouter, ethers.constants.MaxUint256);
  })

  it("sendSingle", async () => {

    const [tokenIDminted, amount0added, amount1added] = await mint(accounts[0]);

    await uniswap.connect(accounts[0])["safeTransferFrom(address,address,uint256)"](mainSignerAddress, compounder.address, tokenIDminted);

    const ArrayOfOwnerStaked: BigNumber[] = await compounder.addressOwns(mainSignerAddress);
    expect(ArrayOfOwnerStaked[0].toNumber()).to.be.equal(tokenIDminted)

    const addressThatSent = await compounder.ownerOfTokenID(tokenIDminted);
    expect(addressThatSent).to.be.equal(mainSignerAddress);

    const resp = await compounder.positionOfTokenID(tokenIDminted);
    //console.log(resp)
    expect(resp[0]).to.be.equal(USDC);
    expect(resp[1]).to.be.equal(USDT);
    
  })

  it("generateFeesAndCompound", async () => {
    const [tokenIDminted, ,] = await mint(accounts[0]);

    await uniswap.connect(accounts[0])["safeTransferFrom(address,address,uint256)"](mainSignerAddress, compounder.address, tokenIDminted);
    for (let i = 0; i < 20; i++) {
      await swap(accounts[0], USDC, USDT);
      await swap(accounts[0], USDT, USDC);
    }

    const x = await compounder.connect(accounts[0]).doSingleUpkeep(tokenIDminted);

  })
})