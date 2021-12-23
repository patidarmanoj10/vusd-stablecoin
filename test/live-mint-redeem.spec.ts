import hre from "hardhat";
const ethers = hre.ethers;
import {expect} from "chai";
import {VUSD, Minter, Redeemer, ERC20} from "../typechain";
import address from "./utils/address";
import releases from "../releases/1.2.1/contracts.json";

const USDC_WHALE = "0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0";

describe("Live mint and redeem test", async function () {
  let minter: Minter, redeemer: Redeemer, vusd: VUSD, usdc: ERC20;
  beforeEach(async function () {
    minter = (await ethers.getContractAt("Minter", releases.networks.mainnet.Minter)) as Minter;
    redeemer = (await ethers.getContractAt("Redeemer", releases.networks.mainnet.Redeemer)) as Redeemer;
    vusd = (await ethers.getContractAt("VUSD", releases.networks.mainnet.VUSD)) as VUSD;
    usdc = (await ethers.getContractAt("ERC20", address.USDC)) as ERC20;
  });

  it("Should verify mint and redeem", async function () {
    expect(await minter.VERSION()).to.eq("1.2.1", "Wrong contract version");

    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [USDC_WHALE],
    });
    const signer = await ethers.getSigner(USDC_WHALE);

    expect(await vusd.balanceOf(signer.address)).to.eq(0, "VUSD amount should be zero");
    // Approve to mint VUSD
    const usdcAmount = ethers.utils.parseUnits("1000", 6); // 1000 USDC
    await usdc.connect(signer).approve(minter.address, usdcAmount);
    await minter.connect(signer)["mint(address,uint256)"](address.USDC, usdcAmount);

    const vUSDBalance = await vusd.balanceOf(signer.address);
    expect(vUSDBalance).to.eq(ethers.utils.parseUnits(usdcAmount.toString(), 12), "Incorrect VUSD amount");

    // Approve VUSD to redeem USDC
    await vusd.connect(signer).approve(redeemer.address, vUSDBalance);
    await redeemer.connect(signer)["redeem(address,uint256)"](address.USDC, vUSDBalance);
    expect(await vusd.balanceOf(signer.address)).to.eq(0, "VUSD amount should be zero");
  });
});
