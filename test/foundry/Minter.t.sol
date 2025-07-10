// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "../../lib/forge-std/src/Test.sol";
import "../../contracts/Minter.sol";
import "../../contracts/VUSD.sol";
import "./mock/MockChainlinkOracle.sol";

contract MinterTest is Test {
    using SafeERC20 for IERC20;

    VUSD vusd;
    Minter minter;
    address governor;
    address alice = address(0x111);
    address constant token = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address constant cToken = 0x39AA39c021dfbaE8faC545936693aC917d5E7563; // cUSDC
    MockChainlinkOracle mockOracle;

    function setUp() public {
        vm.createSelectFork(vm.envString("NODE_URL"), vm.envUint("FORK_BLOCK_NUMBER"));
        governor = address(this);
        vusd = new VUSD(address(0x222));
        minter = new Minter(address(vusd), type(uint256).max);
        mockOracle = new MockChainlinkOracle(0.999e8);
        vusd.updateMinter(address(minter));
        minter.removeWhitelistedToken(token);
        minter.addWhitelistedToken(token, cToken, address(mockOracle), 6 hours);
    }

    function parseToTokenAmount(uint256 amount) internal view returns (uint256) {
        return amount * 10 ** IERC20Metadata(token).decimals();
    }

    function parseTokenAmountToVusdAmount(uint256 tokenAmount) internal view returns (uint256) {
        return ((tokenAmount * 10 ** IERC20Metadata(address(vusd)).decimals()) /
            (10 ** IERC20Metadata(token).decimals()));
    }

    function testAddAndRemoveWhitelistedToken() public {
        minter.removeWhitelistedToken(token);
        assertFalse(minter.isWhitelistedToken(token), "Token should not be whitelisted");

        minter.addWhitelistedToken(token, cToken, address(mockOracle), 6 hours);
        assertTrue(minter.isWhitelistedToken(token), "Token should be whitelisted");
    }

    function testUpdateMintingFee() public {
        uint256 newFee = 500;
        minter.updateMintingFee(newFee);
        assertEq(minter.mintingFee(), newFee, "Minting fee should be updated");
    }

    function testStalePeriod() public {
        uint256 newStalePeriod = 3600;
        minter.updateStalePeriod(address(mockOracle), newStalePeriod);
        assertEq(minter.stalePeriod(address(mockOracle)), newStalePeriod, "Stale period should be updated");

        // Test for stale price
        vm.warp(block.timestamp + newStalePeriod + 1);
        uint256 amount = parseToTokenAmount(1000);
        vm.expectRevert("oracle-price-is-stale");
        minter.calculateMintage(token, amount);
    }

    function testUpdateMaxMintAmount() public {
        uint256 newMintLimit = 1000 ether; // amount in VUSD decimal
        minter.updateMaxMintAmount(newMintLimit);
        assertEq(minter.maxMintLimit(), newMintLimit, "Max mint limit should be updated");
    }

    function testUpdatePriceDeviationLimit() public {
        uint256 newDeviationLimit = 500;
        minter.updatePriceTolerance(newDeviationLimit);
        assertEq(minter.priceTolerance(), newDeviationLimit, "Price deviation limit should be updated");
    }

    function testMintFailWithPriceDeviation() public {
        minter.updatePriceTolerance(0); // 0% deviation limit
        uint256 _amount = parseToTokenAmount(10);
        deal(token, address(this), _amount);
        IERC20(token).safeApprove(address(minter), _amount);
        vm.expectRevert("oracle-price-exceed-tolerance");
        minter.mint(token, _amount, 1, address(this));
    }

    function testCalculateMintage() public {
        uint256 amount = parseToTokenAmount(10);
        int256 price = 0.9998e8;
        mockOracle.updatePrice(price);
        uint256 fee = minter.mintingFee();
        uint256 maxFee = minter.MAX_BPS();
        uint256 actualMintage = minter.calculateMintage(token, amount);
        uint256 amountAfterFee = amount - ((amount * fee) / maxFee);
        uint256 expectedMintage = (uint256(price) * amountAfterFee * 10 ** minter.vusdDecimals()) /
            (10 ** IERC20Metadata(token).decimals() * (10 ** mockOracle.decimals()));
        assertEq(actualMintage, expectedMintage, "Incorrect mintage calculation");
    }

    function testMintVUSD() public {
        uint256 amount = parseToTokenAmount(1000);
        deal(token, address(this), amount);
        IERC20(token).safeApprove(address(minter), amount);
        uint256 expectedVUSD = minter.calculateMintage(token, amount);
        minter.mint(token, amount, 1, address(this));
        uint256 vusdBalance = vusd.balanceOf(address(this));
        assertEq(vusdBalance, expectedVUSD, "Incorrect VUSD minted");
    }

    function testSlippage() public {
        uint256 amount = parseToTokenAmount(1000);
        deal(token, address(this), amount);
        IERC20(token).safeApprove(address(minter), amount);
        uint256 minAmountOut = parseTokenAmountToVusdAmount(amount) + 1;
        // throw error if slippage is not handled
        vm.expectRevert("mint-amount-is-less-than-minimum");
        minter.mint(token, amount, minAmountOut, address(this));
    }

    function testMintVUSDWithFee() public {
        uint256 amount = parseToTokenAmount(1000);
        minter.updateMintingFee(5);
        deal(token, address(this), amount);
        IERC20(token).safeApprove(address(minter), amount);
        uint256 expectedVUSD = minter.calculateMintage(token, amount);
        minter.mint(token, amount, 1, address(this));
        uint256 vusdBalance = vusd.balanceOf(address(this));
        assertEq(vusdBalance, expectedVUSD, "Incorrect VUSD minted");
    }

    function testGovernorCanMint() public {
        uint256 amount = parseToTokenAmount(1000);
        uint256 initialSupply = vusd.totalSupply();
        minter.mint(amount);
        uint256 newSupply = vusd.totalSupply();
        assertEq(newSupply, initialSupply + amount, "Governor should be able to mint VUSD");
    }

    function testNonGovernorCannotMint() public {
        uint256 amount = parseToTokenAmount(1000);
        vm.prank(alice);
        vm.expectRevert("caller-is-not-the-governor");
        minter.mint(amount);
    }

    function testMintMaxAvailableVUSD() public {
        uint256 amount = parseToTokenAmount(1000);

        deal(token, alice, amount);

        uint256 expectedVUSD = minter.calculateMintage(token, amount);
        minter.updateMaxMintAmount(expectedVUSD / 2);

        vm.startPrank(alice);

        IERC20(token).safeApprove(address(minter), amount);
        vm.expectRevert("mint-limit-reached");
        minter.mint(token, amount, 1, address(this));
        vm.stopPrank();
    }

    function testCalculateMintageWithPriceVariations() public {
        minter.updatePriceTolerance(300);
        uint256 amountIn = parseToTokenAmount(1000); // 1000 tokens
        MockChainlinkOracle(mockOracle).updatePrice(1.0001e8);
        uint256 mintage = minter.calculateMintage(token, amountIn);
        // When price > 1 USD, mintage should equal amountIn
        assertEq(mintage, parseTokenAmountToVusdAmount(amountIn), "Mintage should equal amountIn when price > 1 USD");

        int256 price = 0.98 * 1e8;
        MockChainlinkOracle(mockOracle).updatePrice(price);

        uint256 mintage2 = minter.calculateMintage(token, amountIn);
        require(price >= 0, "Price must be non-negative");
        uint256 expectedMintage2 = parseTokenAmountToVusdAmount((amountIn * uint256(price)) / 1e8);
        assertEq(mintage2, expectedMintage2, "Mintage should be scaled by price when price < 1 USD");
    }
}
