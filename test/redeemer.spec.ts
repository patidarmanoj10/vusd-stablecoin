import {ethers} from "hardhat";
import chai from "chai";
import {smock} from "@defi-wonderland/smock";
import {
  VUSD,
  VUSD__factory,
  Minter,
  Minter__factory,
  Redeemer,
  Redeemer__factory,
  Treasury,
  Treasury__factory,
} from "../typechain";
import {BigNumber} from "@ethersproject/bignumber";
import tokenSwapper from "./utils/tokenSwapper";
import Address from "./utils/address";

import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";

const {expect} = chai;

describe("VUSD redeemer", async function () {
  let vusd: VUSD, minter: Minter, redeemer: Redeemer, treasury: Treasury;
  let signers;
  let user1, user2, user3, user4;

  async function mintVUSD(toToken: string, caller: SignerWithAddress): Promise<BigNumber> {
    const amount = await tokenSwapper.swapEthForToken("1", toToken, caller);
    const Token = await ethers.getContractAt("ERC20", toToken);
    await Token.connect(caller).approve(minter.address, amount);
    await minter.connect(caller)["mint(address,uint256)"](toToken, amount);
    return amount;
  }

  async function mockOracle(oracleAddress, price) {
    const fakeOracle = await smock.fake("IAggregatorV3", {address: oracleAddress});
    await fakeOracle.decimals.returns(8);
    await fakeOracle.latestRoundData.returns([1, price, 1, 1, 1]);
  }

  beforeEach(async function () {
    signers = await ethers.getSigners();
    [, user1, user2, user3, user4] = signers;
    const vusdFactory = (await ethers.getContractFactory("VUSD", signers[0])) as VUSD__factory;
    vusd = await vusdFactory.deploy(signers[8].address);
    expect(vusd.address).to.be.properAddress;

    const minterFactory = (await ethers.getContractFactory("Minter", signers[0])) as Minter__factory;
    minter = await minterFactory.deploy(vusd.address);
    expect(minter.address).to.be.properAddress;
    await vusd.updateMinter(minter.address);

    const redeemerFactory = (await ethers.getContractFactory("Redeemer", signers[0])) as Redeemer__factory;
    redeemer = await redeemerFactory.deploy(vusd.address);
    expect(redeemer.address).to.be.properAddress;

    const treasuryFactory = (await ethers.getContractFactory("Treasury", signers[0])) as Treasury__factory;
    treasury = await treasuryFactory.deploy(vusd.address);
    expect(treasury.address).to.be.properAddress;
    await vusd.updateTreasury(treasury.address);
    await treasury.updateRedeemer(redeemer.address);

    // To pass existing tests, mock oracle to return price as 1.0
    await mockOracle(Address.DAI_USD, 100000000);
    await mockOracle(Address.USDC_USD, 100000000);
  });

  context("Check redeemable", function () {
    it("Should return zero redeemable when no balance", async function () {
      expect(await redeemer["redeemable(address)"](Address.DAI)).to.be.eq(0, "redeemable should be zero");
    });

    it("Should return valid redeemable", async function () {
      await mintVUSD(Address.USDC, user1);
      expect(await redeemer["redeemable(address)"](Address.USDC)).to.be.gt(0, "redeemable should be > 0");
    });

    it("Should return valid redeemable when query with amount", async function () {
      const depositAmount = await mintVUSD(Address.DAI, user1);
      const cDAI = await ethers.getContractAt("CToken", Address.cDAI);
      await cDAI.exchangeRateCurrent();
      const redeemable = await redeemer["redeemable(address,uint256)"](Address.DAI, depositAmount);
      expect(redeemable).to.be.gt(0, "redeemable should be > 0");
    });

    it("Should return zero redeemable when token is not supported", async function () {
      const tx = await redeemer["redeemable(address,uint256)"](Address.WETH, 100);
      expect(tx).to.be.eq(0, "redeemable should be zero");
    });

    it("Should return zero redeemable when calculated redeemable is > total redeemable", async function () {
      const depositAmount = await mintVUSD(Address.DAI, user1);
      const cDAI = await ethers.getContractAt("CToken", Address.cDAI);
      await cDAI.exchangeRateCurrent();
      await mockOracle(Address.DAI_USD, 100600000); // Price is > 1.0
      const redeemable = await redeemer["redeemable(address,uint256)"](Address.DAI, depositAmount);
      expect(redeemable).to.be.eq(0, "redeemable should be zero");
    });
  });

  context("Redeem token", function () {
    it("Should redeem token and burn VUSD", async function () {
      const token = Address.USDC;
      await mintVUSD(token, user2);
      const amountToWithdraw = await vusd.balanceOf(user2.address);
      await vusd.connect(user2).approve(redeemer.address, amountToWithdraw);
      const USDC = await ethers.getContractAt("ERC20", token);
      expect(await USDC.balanceOf(user2.address)).to.be.eq(0, "Governor balance should be zero");

      const cUSDC = await ethers.getContractAt("CToken", Address.cUSDC);
      await cUSDC.exchangeRateCurrent();

      const redeemAmount = await redeemer["redeemable(address,uint256)"](token, amountToWithdraw);
      await redeemer.connect(user2)["redeem(address,uint256)"](token, amountToWithdraw);
      expect(await USDC.balanceOf(user2.address)).to.be.eq(redeemAmount, "Incorrect USDC balance");
    });

    it("Should allow redeem to another address", async function () {
      const token = Address.DAI;
      await mintVUSD(token, user3);
      const amountToWithdraw = ethers.utils.parseUnits("1000", "ether"); // 1000 DAI
      await vusd.connect(user3).approve(redeemer.address, amountToWithdraw);
      const DAI = await ethers.getContractAt("ERC20", token);
      expect(await DAI.balanceOf(user4.address)).to.be.eq(0, "User balance should be zero");
      await redeemer.connect(user3)["redeem(address,uint256,address)"](token, amountToWithdraw, user4.address);
      expect(await DAI.balanceOf(user4.address)).to.be.eq(amountToWithdraw, "Incorrect DAI balance");
    });

    it("Should revert if tries to redeem more than total redeemable", async function () {
      const token = Address.DAI;
      const depositAmount = await mintVUSD(token, user3);
      await vusd.connect(user3).approve(redeemer.address, depositAmount);
      // Given higher price of DAI at the time of redeem, also there is only 1 user in system. Withdrawing all
      // This will cause redeemable to higher than what was initially deposited due to price difference
      await mockOracle(Address.DAI_USD, 100600000); // Price is > 1.0

      // Due to higher price, redeemable is higher than total redeemable, hence view function return 0
      expect(await redeemer["redeemable(address,uint256)"](token, depositAmount)).to.eq(0, "incorrect redeemable");
      // Redeem will fail, as not enough tokens to redeem
      const tx = redeemer.connect(user3)["redeem(address,uint256)"](token, depositAmount);
      await expect(tx).to.revertedWith("redeem-underlying-failed");
    });
  });

  describe("Update redeem fee", function () {
    it("Should revert if caller is not governor", async function () {
      const tx = redeemer.connect(signers[4]).updateRedeemFee(3);
      await expect(tx).to.be.revertedWith("caller-is-not-the-governor");
    });

    it("Should revert if setting same redeem fee", async function () {
      await redeemer.updateRedeemFee(3);
      const tx = redeemer.updateRedeemFee(3);
      await expect(tx).to.be.revertedWith("same-redeem-fee");
    });

    it("Should revert if redeem fee is above max", async function () {
      const tx = redeemer.updateRedeemFee(10001);
      await expect(tx).to.be.revertedWith("redeem-fee-limit-reached");
    });

    it("Should add new redeem fee", async function () {
      const redeemFee = await redeemer.redeemFee();
      const newRedeemFee = 10;
      const tx = redeemer.updateRedeemFee(newRedeemFee);
      await expect(tx).to.emit(redeemer, "UpdatedRedeemFee").withArgs(redeemFee, newRedeemFee);
      expect(await redeemer.redeemFee()).to.eq(newRedeemFee, "Redeem fee update failed");
    });
  });
});
