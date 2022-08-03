import chai, { expect } from "chai";
import { Console } from "console";
import { Contract, Signer } from "ethers";
import { ethers, network } from "hardhat";
import { BigNumber} from "@ethersproject/bignumber";

const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
const USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
const WHALE = "0x2FAF487A4414Fe77e2327F0bf4AE2a264a776AD2"

const UNISWAP = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"

async function mint(uniswap: Contract, account: Signer, mainSignerAddress : String) {
  const s = await uniswap
      .connect(account)
      .mint(
      [USDC,
       USDT,
       100, //0.01% fee tier
       -5, //min tick
       -2, //max tick
       10000000n * 10n ** 6n, //add 10 million in liqudity
       10000000n * 10n ** 6n,
       0,
       0,
       mainSignerAddress,
       2659131770
      ]
      )
    const receipt = await s.wait();
    const increaseLiqLog = receipt.events[4];
    const tokenID: BigNumber = increaseLiqLog.args[0];
    return tokenID.toNumber();
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
    await uniswap.connect(accounts[0]).setApprovalForAll(compounder.address, true);
  });

  before(async () => {

    accounts = await ethers.getSigners()
    mainSignerAddress = await accounts[0].getAddress();

    usdt = await ethers.getContractAt("IERC20", USDT)
    usdc = await ethers.getContractAt("IERC20", USDC)
    uniswap = await ethers.getContractAt("INonfungiblePositionManager", UNISWAP)
    
    const whaleSigner = await ethers.getImpersonatedSigner(WHALE)

    // Send DAI and USDC to accounts[0]
    const usdtAmount = 100000000n * 10n ** 6n //100 million of each
    const usdcAmount = 100000000n * 10n ** 6n

    await usdt.connect(whaleSigner).transfer(mainSignerAddress, usdtAmount)
    await usdc.connect(whaleSigner).transfer(mainSignerAddress, usdcAmount)

    await usdt.connect(accounts[0]).approve(UNISWAP, ethers.constants.MaxUint256);
    await usdc.connect(accounts[0]).approve(UNISWAP, ethers.constants.MaxUint256);
  })

  it("sendSingle", async () => {
    const tokenIDminted = await mint(uniswap, accounts[0], mainSignerAddress);
    await compounder.connect(accounts[0]).send(tokenIDminted);
    
    const ArrayOfOwnerStaked: BigNumber[] = await compounder.addressOwns(mainSignerAddress);
    expect(ArrayOfOwnerStaked[0].toNumber()).to.be.equal(tokenIDminted)

    const addressThatSent = await compounder.ownerOfTokenID(tokenIDminted);
    expect(addressThatSent).to.be.equal(mainSignerAddress);

    const resp = await compounder.positionOfTokenID(tokenIDminted);
    expect(resp[0]).to.be.equal(USDC);
    expect(resp[1]).to.be.equal(USDT);
    
  })
})