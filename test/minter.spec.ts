import {ethers} from "hardhat";
import chai from "chai";
import {smock} from "@defi-wonderland/smock";
import {VUSD, VUSD__factory, Minter, Minter__factory} from "../typechain";
import {BigNumber} from "@ethersproject/bignumber";
import tokenSwapper from "./utils/tokenSwapper";
import Address from "./utils/address";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";

const {expect} = chai;

const ZERO_ADDRESS = Address.ZERO;
const DAI_ADDRESS = Address.DAI;
const USDC_ADDRESS = Address.USDC;
const USDT_ADDRESS = Address.USDT;
const WETH_ADDRESS = Address.WETH;

const cDAI_ADDRESS = Address.cDAI;
const cUSDC_ADDRESS = Address.cUSDC;
const cUSDT_ADDRESS = Address.cUSDT;
const cETH_ADDRESS = Address.cETH;

const DAI_USD = Address.DAI_USD;
const ETH_USD = Address.ETH_USD;
const USDT_USD = Address.USDT_USD;

describe("VUSD Minter", async function () {
  let vusd: VUSD, minter: Minter;
  let signers;

  beforeEach(async function () {
    signers = await ethers.getSigners();
    const vusdFactory = (await ethers.getContractFactory("VUSD", signers[0])) as VUSD__factory;
    vusd = await vusdFactory.deploy(signers[8].address);
    expect(vusd.address).to.be.properAddress;

    const minterFactory = (await ethers.getContractFactory("Minter", signers[0])) as Minter__factory;
    minter = await minterFactory.deploy(vusd.address);
    expect(minter.address).to.be.properAddress;
    await vusd.updateMinter(minter.address);
  });

  describe("Calculate mintage", function () {
    it("Should calculate mintage for 1000 DAI deposit", async function () {
      const amount = ethers.utils.parseEther("1000");
      const fee = await minter.mintingFee();
      const maxFee = await minter.MAX_BPS();
      const expectedMintage = amount.sub(amount.mul(fee).div(maxFee));
      const actualMintage = await minter.calculateMintage(DAI_ADDRESS, amount);
      expect(actualMintage).to.be.eq(expectedMintage, "Incorrect mintage calculation");
    });

    it("Should return 0 mintage if not whitelisted token", async function () {
      const amount = ethers.utils.parseEther("1000");
      const actualMintage = await minter.calculateMintage(WETH_ADDRESS, amount);
      expect(actualMintage).to.be.eq("0", "Incorrect mintage calculation");
    });
  });

  describe("Mint VUSD", function () {
    let treasury;

    async function swapEthForToken(toToken: string, caller: SignerWithAddress): Promise<BigNumber> {
      const amount = await tokenSwapper.swapEthForToken("1", toToken, caller);
      const Token = await ethers.getContractAt("ERC20", toToken);
      await Token.connect(caller).approve(minter.address, amount);
      return amount;
    }

    beforeEach(async function () {
      treasury = await minter.treasury();
    });

    it("Should deposit DAI and mint VUSD", async function () {
      const amount = await swapEthForToken(DAI_ADDRESS, signers[1]);
      const cDAI = await ethers.getContractAt("ERC20", cDAI_ADDRESS);
      expect(await cDAI.balanceOf(treasury)).to.be.eq(0, "CToken balance of treasury should be zero");
      const expectedVUSD = await minter.calculateMintage(DAI_ADDRESS, amount);
      await minter.connect(signers[1])["mint(address,uint256)"](DAI_ADDRESS, amount);
      const vusdBalance = await vusd.balanceOf(signers[1].address);
      expect(vusdBalance).to.be.eq(expectedVUSD, "Incorrect VUSD minted");
      expect(await cDAI.balanceOf(treasury)).to.be.gt(0, "Incorrect cToken balance in treasury");
    });

    it("Should deposit DAI and mint VUSD and also take mintingFee", async function () {
      //Update minting fee
      await minter.updateMintingFee(5);
      const amount = await swapEthForToken(DAI_ADDRESS, signers[1]);
      const cDAI = await ethers.getContractAt("ERC20", cDAI_ADDRESS);
      const cDaiBefore = await cDAI.balanceOf(treasury);
      // expect(await cDAI.balanceOf(treasury)).to.be.eq(0, "CToken balance of treasury should be zero");
      const expectedVUSD = await minter.calculateMintage(DAI_ADDRESS, amount);
      await minter.connect(signers[1])["mint(address,uint256)"](DAI_ADDRESS, amount);
      const vusdBalance = await vusd.balanceOf(signers[1].address);
      expect(vusdBalance).to.be.eq(expectedVUSD, "Incorrect VUSD minted");
      const cDaiAfter = await cDAI.balanceOf(treasury);
      expect(cDaiAfter.sub(cDaiBefore)).to.be.gt(0, "Incorrect cToken balance in treasury");
    });

    it("Should deposit USDC and mint VUSD", async function () {
      const amount = await swapEthForToken(USDC_ADDRESS, signers[2]);
      const cUSDC = await ethers.getContractAt("ERC20", cUSDC_ADDRESS);
      expect(await cUSDC.balanceOf(treasury)).to.be.eq(0, "CToken balance of treasury should be zero");
      const expectedVUSD = await minter.calculateMintage(USDC_ADDRESS, amount);
      await minter.connect(signers[2])["mint(address,uint256)"](USDC_ADDRESS, amount);
      const vusdBalance = await vusd.balanceOf(signers[2].address);
      expect(vusdBalance).to.be.eq(expectedVUSD, "Incorrect VUSD minted");
      expect(await cUSDC.balanceOf(treasury)).to.be.gt(0, "Incorrect cToken balance in treasury");
    });

    it("Should deposit USDT and mint VUSD", async function () {
      // Add USDT as whitelisted token
      await minter.addWhitelistedToken(USDT_ADDRESS, cUSDT_ADDRESS, USDT_USD);
      const amount = await swapEthForToken(USDT_ADDRESS, signers[2]);
      const cUSDT = await ethers.getContractAt("ERC20", cUSDT_ADDRESS);
      expect(await cUSDT.balanceOf(treasury)).to.be.eq(0, "CToken balance of treasury should be zero");
      const expectedVUSD = await minter.calculateMintage(USDT_ADDRESS, amount);
      await minter.connect(signers[2])["mint(address,uint256)"](USDT_ADDRESS, amount);
      const vusdBalance = await vusd.balanceOf(signers[2].address);
      expect(vusdBalance).to.be.eq(expectedVUSD, "Incorrect VUSD minted");
      expect(await cUSDT.balanceOf(treasury)).to.be.gt(0, "Incorrect cToken balance in treasury");
    });

    it("Should allow mint to another address", async function () {
      const amount = await swapEthForToken(DAI_ADDRESS, signers[1]);
      const cDAI = await ethers.getContractAt("ERC20", cDAI_ADDRESS);
      const expectedVUSD = await minter.calculateMintage(DAI_ADDRESS, amount);
      await minter.connect(signers[1])["mint(address,uint256,address)"](DAI_ADDRESS, amount, signers[9].address);
      const vusdBalance = await vusd.balanceOf(signers[9].address);
      expect(vusdBalance).to.be.eq(expectedVUSD, "Incorrect VUSD minted");
      expect(await cDAI.balanceOf(treasury)).to.be.gt(0, "Incorrect cToken balance in treasury");
    });

    it("Should mint max available VUSD when approaching mint limit", async function () {
      const DAI = await ethers.getContractAt("ERC20", DAI_ADDRESS);
      const currentMinter = await vusd.minter();

      // mints max available VUSD minus 500 VUSD for edge case testing
      const edgeBuffer = ethers.utils.parseEther("500");
      const availableMintage = await minter.availableMintage();
      await vusd.updateMinter(signers[0].address);
      await vusd.mint(signers[0].address, availableMintage.sub(edgeBuffer));
      await vusd.updateMinter(currentMinter);

      const amount = await swapEthForToken(DAI_ADDRESS, signers[1]);
      const expectedVUSD = await minter.calculateMintage(DAI_ADDRESS, amount);
      await minter.connect(signers[1])["mint(address,uint256)"](DAI_ADDRESS, amount);
      const vusdBalance = await vusd.balanceOf(signers[1].address);

      expect(edgeBuffer).to.be.eq(expectedVUSD, "Incorrect calculateMintage");
      expect(vusdBalance).to.be.eq(expectedVUSD, "Incorrect VUSD minted");

      // if we're using 2000 DAI but only 500 VUSD has been minted
      // we should have some DAI left in our wallet
      const daiBalance = await DAI.balanceOf(signers[1].address);
      expect(daiBalance.gt(0)).to.equal(true);

      // we shouldn't be able to mint more because we reached limit
      const tx = minter.connect(signers[1])["mint(address,uint256)"](DAI_ADDRESS, daiBalance);
      expect(tx).to.be.revertedWith("mint-limit-reached");
    });

    it("Should revert if token is not whitelisted", async function () {
      const amount = ethers.utils.parseEther("1000");
      const tx = minter.connect(signers[1])["mint(address,uint256)"](WETH_ADDRESS, amount);
      await expect(tx).to.be.revertedWith("token-is-not-supported");
    });
  });

  describe("Update minting fee", function () {
    it("Should revert if caller is not governor", async function () {
      const tx = minter.connect(signers[4]).updateMintingFee(3);
      await expect(tx).to.be.revertedWith("caller-is-not-the-governor");
    });
    it("Should revert if setting same minting fee", async function () {
      await minter.updateMintingFee(5);
      const tx = minter.updateMintingFee(5);
      await expect(tx).to.be.revertedWith("same-minting-fee");
    });

    it("Should revert if minting fee is above max", async function () {
      const tx = minter.updateMintingFee(10001);
      await expect(tx).to.be.revertedWith("minting-fee-limit-reached");
    });

    it("Should add new minting fee", async function () {
      const mintingFee = await minter.mintingFee();
      const newMintingFee = 10;
      const tx = minter.updateMintingFee(newMintingFee);
      await expect(tx).to.emit(minter, "UpdatedMintingFee").withArgs(mintingFee, newMintingFee);
      expect(await minter.mintingFee()).to.eq(newMintingFee, "Minting fee update failed");
    });
  });

  describe("Update token whitelist", function () {
    let tokenWhitelist, addressList;
    beforeEach(async function () {
      tokenWhitelist = await minter.whitelistedTokens();
      addressList = await ethers.getContractAt("IAddressList", tokenWhitelist);
    });
    context("Add token in whitelist", function () {
      it("Should revert if caller is not governor", async function () {
        const tx = minter.connect(signers[4]).addWhitelistedToken(DAI_ADDRESS, cDAI_ADDRESS, DAI_USD);
        await expect(tx).to.be.revertedWith("caller-is-not-the-governor");
      });

      it("Should add token address in whitelist", async function () {
        await minter.addWhitelistedToken(WETH_ADDRESS, cETH_ADDRESS, ETH_USD);
        expect(await addressList.length()).to.be.equal("3", "Address added successfully");
        expect(await minter.cTokens(WETH_ADDRESS)).to.be.eq(cETH_ADDRESS, "Wrong cToken");
      });

      it("Should revert if address already exist in list", async function () {
        await expect(minter.addWhitelistedToken(DAI_ADDRESS, cDAI_ADDRESS, DAI_USD)).to.be.revertedWith(
          "add-in-list-failed"
        );
      });
    });
    context("Remove token address from whitelist", function () {
      it("Should revert if caller is not governor", async function () {
        const tx = minter.connect(signers[4]).removeWhitelistedToken(DAI_ADDRESS);
        await expect(tx).to.be.revertedWith("caller-is-not-the-governor");
      });

      it("Should remove token from whitelist", async function () {
        await minter.removeWhitelistedToken(USDC_ADDRESS);
        expect(await addressList.length()).to.be.equal("1", "Address removed successfully");
        expect(await minter.cTokens(USDC_ADDRESS)).to.be.eq(ZERO_ADDRESS, "CToken should be removed");
      });

      it("Should revert if token not in list", async function () {
        await expect(minter.removeWhitelistedToken(WETH_ADDRESS)).to.be.revertedWith("remove-from-list-failed");
      });
    });

    context("Check minting is allowed or not", function () {
      let fakeOracle;
      before(async function () {
        fakeOracle = await smock.fake("IAggregatorV3", {address: DAI_USD});
        await fakeOracle.decimals.returns(8);
      });
      it("Should allow minting if price is in range", async function () {
        await fakeOracle.latestRoundData.returns([1, 100700000, 1, 1, 1]);
        expect(await minter.isMintingAllowed(DAI_ADDRESS), "Minting should be allowed").to.true;
      });

      it("Should revert if minting is not allowed due to price deviation", async function () {
        // 1 wei high than price upper bound
        await fakeOracle.latestRoundData.returns([1, 104000001, 1, 1, 1]);
        expect(await minter.isMintingAllowed(DAI_ADDRESS), "Minting not allowed").to.false;
      });

      it("Should revert if minting is not allowed due to price deviation", async function () {
        // 1 wei less than price lower bound
        await fakeOracle.latestRoundData.returns([1, 95999999, 1, 1, 1]);
        expect(await minter.isMintingAllowed(DAI_ADDRESS), "Minting not allowed").to.false;
      });
    });
  });
});
