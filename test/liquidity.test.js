const { expect } = require("chai")
const { ethers } = require("hardhat")

const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
const DAI_WHALE = "0x2FAF487A4414Fe77e2327F0bf4AE2a264a776AD2"
const USDC_WHALE = "0x2FAF487A4414Fe77e2327F0bf4AE2a264a776AD2"
const UNISWAP = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
describe("Compounder", () => {
  let compounder
  let accounts
  let dai
  let usdc
  let uniswap
  before(async () => {
    accounts = await ethers.getSigners(1)

    const Compounderfi = await ethers.getContractFactory(
      "Compounder"
    )

    compounder = await Compounderfi.deploy()
    await compounder.deployed()

    dai = await ethers.getContractAt("IERC20", DAI)
    usdc = await ethers.getContractAt("IERC20", USDC)
    uniswap = await ethers.getContractAt("INonfungiblePositionManager", UNISWAP)
    
    // Unlock DAI and USDC whales
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [DAI_WHALE],
    })
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [USDC_WHALE],
    })

    const daiWhale = await ethers.getSigner(DAI_WHALE)
    const usdcWhale = await ethers.getSigner(USDC_WHALE)
    
    // Send DAI and USDC to accounts[0]
    const daiAmount = 100n * 10n ** 18n
    const usdcAmount = 100n * 10n ** 6n

    expect(await dai.balanceOf(daiWhale.address)).to.gte(daiAmount)
    expect(await usdc.balanceOf(usdcWhale.address)).to.gte(usdcAmount)

    await dai.connect(daiWhale).transfer(accounts[0].address, daiAmount)
    await usdc.connect(usdcWhale).transfer(accounts[0].address, usdcAmount)
  })

  it("mintNewPosition", async () => {
    const daiAmount = 100n * 10n ** 18n
    const usdcAmount = 100n * 10n ** 6n
  
    await dai.connect(accounts[0]).approve(UNISWAP, ethers.constants.MaxUint256);
    await usdc.connect(accounts[0]).approve(UNISWAP, ethers.constants.MaxUint256)

    const s = await uniswap
      .connect(accounts[0])
      .mint(
      ["0x6B175474E89094C44Da98b954EedeAC495271d0F",
       "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
       100,
       -100,
       100,
       10,
       10,
       0,
       0,
       accounts[0].address,
       2659131770
      ]
      )
    const receipt = await s.wait();
    for (const event of receipt.events) {
      console.log(`Event ${event.event} with args ${event.args}`);
    }
  
    
    console.log(
      "DAI balance after add liquidity",
      await dai.balanceOf(accounts[0].address)
    )
    console.log(
      "USDC balance after add liquidity",
      await usdc.balanceOf(accounts[0].address)
    )
  })
})