// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {VUSD} from "contracts/VUSD.sol";
import {Redeemer} from "contracts/Redeemer.sol";
import {MockChainlinkOracle} from "test/foundry/mock/MockChainlinkOracle.sol";
import {MockTreasury} from "test/foundry/mock/MockTreasury.sol";
import {USDC} from "test/foundry/utils/Address.sol";

contract RedeemerTest is Test {
    VUSD vusd;
    Redeemer redeemer;
    MockTreasury treasury;
    address alice = address(0x111);
    address constant token = USDC;
    MockChainlinkOracle mockOracle;

    function setUp() public {
        vm.createSelectFork(vm.envString("NODE_URL"), vm.envUint("FORK_BLOCK_NUMBER"));
        treasury = new MockTreasury();
        vusd = new VUSD(address(treasury));
        vusd.updateMinter(address(this));
        vusd.mint(alice, 10000 ether);
        mockOracle = new MockChainlinkOracle(1.01e8);
        deal(token, address(treasury), 1000 ether);
        treasury.setOracle(token, address(mockOracle));
        redeemer = new Redeemer(address(vusd));
    }

    function parseVusdAmountToTokenAmount(uint256 vusdAmount) internal view returns (uint256) {
        return ((vusdAmount * (10 ** IERC20Metadata(token).decimals())) /
            (10 ** IERC20Metadata(address(vusd)).decimals()));
    }

    function testDefaultStalePeriods() public view {
        // default is set in constructor
        assertEq(redeemer.stalePeriod(address(mockOracle)), 24 hours, "Stale period should be 24 hour");
    }

    function testUpdatePriceTolerance() public {
        uint256 newTolerance = 1000;
        redeemer.updatePriceTolerance(newTolerance);
        assertEq(redeemer.priceTolerance(), newTolerance, "Price tolerance should be updated");
    }

    function testRedeemWithPriceToleranceExceeded() public {
        redeemer.updatePriceTolerance(0);
        vm.expectRevert("price-tolerance-exceeded");
        redeemer.redeem(token, 100, 1, address(0x123));
    }

    function testRedeemWithinPriceTolerance() public {
        uint256 amount = 500 ether;
        uint256 redeemableAmount = redeemer.redeemable(token, amount);
        uint256 vusdBalanceBefore = vusd.balanceOf(alice);

        uint256 tokenBalanceBefore = IERC20(token).balanceOf(alice);
        vm.startPrank(alice);
        vusd.approve(address(redeemer), amount);
        redeemer.redeem(token, amount, 1, alice);
        vm.stopPrank();

        // assert that vusd balance decrease
        assertEq(vusd.balanceOf(alice), vusdBalanceBefore - amount, "VUSD balance should decrease");
        uint256 tokensReceived = IERC20(token).balanceOf(alice) - tokenBalanceBefore;
        assertEq(redeemableAmount, tokensReceived, "token amount should be transferred to user");
    }

    function testRedeemable() public view {
        (, int256 _price, , , ) = mockOracle.latestRoundData();
        uint256 vusdAmount = 100 ether;
        uint256 redeemableBeforeFee = parseVusdAmountToTokenAmount((vusdAmount * 1e8) / uint256(_price));
        uint256 expectedRedeemable = redeemableBeforeFee - ((redeemableBeforeFee * redeemer.redeemFee()) / 10000);
        uint256 redeemableAmount = redeemer.redeemable(token, vusdAmount);
        assertEq(redeemableAmount, expectedRedeemable, "Redeemable amount should be correct");
    }

    function testSlippage() public {
        uint256 amount = 100 ether;
        uint256 redeemableAmount = redeemer.redeemable(token, amount);

        vm.startPrank(alice);
        vusd.approve(address(redeemer), amount);
        vm.expectRevert("redeemable-amount-is-less-than-minimum");
        redeemer.redeem(token, amount, redeemableAmount + 1, alice);
        vm.stopPrank();
    }

    function testUpdateRedeemFee() public {
        uint256 newFee = 50;
        redeemer.updateRedeemFee(newFee);
        assertEq(redeemer.redeemFee(), newFee, "Redeem fee should be updated");
    }

    function testStalePeriod() public {
        uint256 newStalePeriod = 2 hours;
        redeemer.updateStalePeriod(address(mockOracle), newStalePeriod);
        assertEq(redeemer.stalePeriod(address(mockOracle)), newStalePeriod, "Stale period should be updated");

        // Test for stale price
        vm.warp(block.timestamp + newStalePeriod + 1);
        vm.expectRevert("oracle-price-is-stale");
        redeemer.redeemable(token, 100);
    }

    function testRedeemWithUpdatedFee() public {
        uint256 amount = 10 ether;
        redeemer.updateRedeemFee(0);
        uint256 redeemableWithoutFee = redeemer.redeemable(token, amount);
        uint256 newFee = 50; // 0.5%
        redeemer.updateRedeemFee(newFee);
        uint256 expectedRedeemable = redeemableWithoutFee - ((redeemableWithoutFee * newFee) / 10000);

        uint256 tokenBalanceBefore = IERC20(token).balanceOf(alice);
        vm.startPrank(alice);
        vusd.approve(address(redeemer), amount);
        redeemer.redeem(token, amount, 1, alice);
        vm.stopPrank();

        uint256 tokensReceived = IERC20(token).balanceOf(alice) - tokenBalanceBefore;
        assertApproxEqAbs(
            tokensReceived,
            expectedRedeemable,
            1,
            "Recipient should receive redeemed VUSD with updated fee"
        );
    }

    function testCalculateRedeemableWithPriceVariations() public {
        uint256 amountIn = 1000 * 1e18; // 1000 tokens
        MockChainlinkOracle(mockOracle).updatePrice(0.999e8);
        redeemer.updateRedeemFee(0);
        uint256 redeemable = redeemer.redeemable(token, amountIn);
        // When price > 1 USD, mintage should equal amountIn
        assertEq(
            redeemable,
            parseVusdAmountToTokenAmount(amountIn),
            "Mintage should equal amountIn when price > 1 USD"
        );

        int256 price = 1.001 * 1e8;
        MockChainlinkOracle(mockOracle).updatePrice(price);

        redeemable = redeemer.redeemable(token, amountIn);
        require(price >= 0, "Price must be non-negative");
        uint256 expectedRedeemable = parseVusdAmountToTokenAmount((amountIn * 1e8) / uint256(price));
        assertEq(redeemable, expectedRedeemable, "Mintage should be scaled by price when price < 1 USD");
    }
}
