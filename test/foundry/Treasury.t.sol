// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VUSD} from "contracts/VUSD.sol";
import {Minter} from "contracts/Minter.sol";
import {Treasury} from "contracts/Treasury.sol";
import {SwapperMock} from "test/foundry/mock/SwapperMock.sol";
import {ETH_USD, WETH, USDC, USDC_USD, USDT, cWETHv3, cUSDCv3, cUSDTv3} from "test/foundry/utils/Address.sol";

contract TreasuryTest is Test {
    using SafeERC20 for IERC20;

    VUSD vusd;
    Minter minter;
    Treasury treasury;

    address governor;
    address keeper;
    address redeemer;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.createSelectFork(vm.envString("NODE_URL"), vm.envUint("FORK_BLOCK_NUMBER"));
        governor = address(this);
        keeper = makeAddr("keeper");
        redeemer = makeAddr("vusd-redeemer");

        vusd = new VUSD(governor);
        minter = new Minter(address(vusd), type(uint256).max);
        vusd.updateMinter(address(minter));

        treasury = new Treasury(address(vusd));
        vusd.updateTreasury(address(treasury));
        treasury.addKeeper(keeper);
        treasury.updateRedeemer(redeemer);

        SwapperMock _swapper = new SwapperMock();
        treasury.updateSwapper(address(_swapper));
    }

    function _mintVUSD(address token, address to, uint256 amount) internal {
        // Give user tokens
        deal(token, to, amount);
        vm.startPrank(to);
        IERC20(token).safeApprove(address(minter), amount);
        minter.mint(token, amount, 1, to);
        vm.stopPrank();
    }

    // --- Withdrawable ---

    function test_withdrawable_whenNoBalance() public view {
        assertEq(treasury.withdrawable(USDC), 0, "Withdrawable should be zero");
    }

    function test_withdrawable() public {
        uint256 amount = 1000e6;
        _mintVUSD(USDT, alice, amount);
        assertGt(treasury.withdrawable(USDT), 0, "Withdrawable should be > 0");
    }

    function test_withdrawable_whenTokenIsNotSupported() public view {
        assertEq(treasury.withdrawable(WETH), 0, "Withdrawable should be zero");
    }

    // --- Withdraw ---

    function test_withdraw_revertIfNotGovernorOrRedeemer() public {
        uint256 amount = 1000e6;
        _mintVUSD(USDC, bob, amount);
        vm.prank(bob);
        vm.expectRevert("caller-is-not-authorized");
        treasury.withdraw(USDC, amount);
    }

    function test_withdraw_revertIfTokenNotSupported() public {
        vm.expectRevert("token-is-not-supported");
        treasury.withdraw(WETH, 1000);
    }

    function test_withdraw_byRedeemer() public {
        uint256 amount = 1000e6;
        _mintVUSD(USDC, alice, amount);
        assertEq(IERC20(USDC).balanceOf(redeemer), 0, "User balance should be zero");
        uint256 amountToWithdraw = amount / 2;
        vm.prank(redeemer);
        treasury.withdraw(USDC, amountToWithdraw);
        assertEq(IERC20(USDC).balanceOf(redeemer), amountToWithdraw, "Incorrect USDC balance");
    }

    function test_withdraw_whenRedeemToAnotherAddress() public {
        uint256 amount = 1000e6;
        _mintVUSD(USDT, bob, amount);
        address recipient = alice;
        assertEq(IERC20(USDT).balanceOf(recipient), 0, "Recipient balance should be zero");
        uint256 amountToWithdraw = amount / 2;
        vm.prank(redeemer);
        treasury.withdraw(USDT, amountToWithdraw, recipient);
        assertEq(IERC20(USDT).balanceOf(recipient), amountToWithdraw, "Incorrect USDT balance");
    }

    function test_withdraw_byGovernor() public {
        uint256 amount = 1000e6;
        _mintVUSD(USDC, bob, amount);
        assertEq(IERC20(USDC).balanceOf(governor), 0, "Governor balance should be zero");
        uint256 amountToWithdraw = amount / 2;
        treasury.withdraw(USDC, amountToWithdraw);
        assertEq(IERC20(USDC).balanceOf(governor), amountToWithdraw, "Incorrect USDC balance");
    }

    // --- WithdrawMulti by governor ---

    function test_withdrawMulti_byGovernor() public {
        uint256 amount = 1000e6;
        _mintVUSD(USDT, alice, amount);
        uint256 balanceBefore = IERC20(USDT).balanceOf(governor);
        address[] memory tokens = new address[](1);
        tokens[0] = USDT;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount / 2;
        treasury.withdrawMulti(tokens, amounts);
        uint256 balanceAfter = IERC20(USDT).balanceOf(governor);
        assertEq(balanceAfter, balanceBefore + amounts[0], "Incorrect USDT balance");
    }

    function test_withdrawMulti_revertIfInputMismatch() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDT;
        uint256[] memory amounts = new uint256[](0);
        vm.expectRevert("input-length-mismatch");
        treasury.withdrawMulti(tokens, amounts);
    }

    // --- Withdraw all ---

    function test_withdrawAll_byGovernor() public {
        uint256 amount = 1000e18;
        _mintVUSD(USDT, alice, amount);
        uint256 balanceBefore = IERC20(USDT).balanceOf(governor);
        uint256 withdrawable = treasury.withdrawable(USDT);
        address[] memory tokens = new address[](1);
        tokens[0] = USDT;
        treasury.withdrawAll(tokens);
        uint256 balanceAfter = IERC20(USDT).balanceOf(governor);
        // Accept gte due to possible yield
        assertGe(balanceAfter, balanceBefore + withdrawable, "Incorrect USDT balance");
    }

    function test_withdrawAll_revertIfTokenNotSupported() public {
        address[] memory tokens = new address[](1);
        tokens[0] = WETH;
        vm.expectRevert("token-is-not-supported");
        treasury.withdrawAll(tokens);
    }

    // --- Migrate to new treasury ---

    function test_migrate_revertIfNewTreasuryZero() public {
        vm.expectRevert("new-treasury-address-is-zero");
        treasury.migrate(address(0));
    }

    function test_migrate_revertIfVusdMismatch() public {
        // Deploy a treasury with a different VUSD address (use USDC as dummy)
        Treasury newTreasury = new Treasury(USDC);
        vm.expectRevert("vusd-mismatch");
        treasury.migrate(address(newTreasury));
    }

    function test_migrate_transfersAllComets() public {
        // Mint to get comets in treasury
        uint256 usdcAmount = 100e6;
        uint256 usdtAmount = 100e6;
        _mintVUSD(USDC, bob, usdcAmount);
        _mintVUSD(USDT, alice, usdtAmount);

        // Deploy new treasury
        Treasury newTreasury = new Treasury(address(vusd));
        vusd.updateTreasury(address(newTreasury));

        assertEq(IERC20(cUSDCv3).balanceOf(address(newTreasury)), 0, "cUSDCv3 balance should be zero");
        assertEq(IERC20(cUSDTv3).balanceOf(address(newTreasury)), 0, "cUSDTv3 balance should be zero");

        uint256 cUSDCBalance = IERC20(cUSDCv3).balanceOf(address(treasury));
        uint256 cUSDTBalance = IERC20(cUSDTv3).balanceOf(address(treasury));

        treasury.migrate(address(newTreasury));

        assertEq(IERC20(cUSDCv3).balanceOf(address(treasury)), 0, "cUSDCv3 balance should be zero");
        assertEq(IERC20(cUSDTv3).balanceOf(address(treasury)), 0, "cUSDTv3 balance should be zero");
        assertApproxEqAbs(
            IERC20(cUSDCv3).balanceOf(address(newTreasury)),
            cUSDCBalance,
            5,
            "cUSDCv3 in new treasury is wrong"
        );
        assertApproxEqAbs(
            IERC20(cUSDTv3).balanceOf(address(newTreasury)),
            cUSDTBalance,
            5,
            "cUSDTv3 in new treasury is wrong"
        );
    }

    // --- Add token in whitelist ---

    function test_addWhitelistedToken_revertIfNotGovernor() public {
        vm.prank(bob);
        vm.expectRevert("caller-is-not-the-governor");
        treasury.addWhitelistedToken(WETH, cWETHv3, ETH_USD);
    }

    function test_addWhitelistedToken_revertIfTokenZero() public {
        vm.expectRevert("token-address-is-zero");
        treasury.addWhitelistedToken(address(0), cWETHv3, ETH_USD);
    }

    function test_addWhitelistedToken_revertIfCometZero() public {
        vm.expectRevert("comet-address-is-zero");
        treasury.addWhitelistedToken(WETH, address(0), ETH_USD);
    }

    function test_addWhitelistedToken_success() public {
        uint256 prevTokenCount = treasury.whitelistedTokens().length;
        uint256 prevCometCount = treasury.cometList().length;
        treasury.addWhitelistedToken(WETH, cWETHv3, ETH_USD);
        assertEq(treasury.whitelistedTokens().length, prevTokenCount + 1, "Address added successfully");
        assertEq(treasury.cometList().length, prevCometCount + 1, "comet address added successfully");
        assertEq(treasury.comets(WETH), cWETHv3, "Wrong comet");
    }

    function test_addWhitelistedToken_revertIfAlreadyExists() public {
        vm.expectRevert("add-in-list-failed");
        treasury.addWhitelistedToken(USDC, cUSDCv3, USDC_USD);
    }

    // --- Remove token address from whitelist ---

    function test_removeWhitelistedToken_revertIfNotGovernor() public {
        vm.prank(bob);
        vm.expectRevert("caller-is-not-the-governor");
        treasury.removeWhitelistedToken(USDC);
    }

    function test_removeWhitelistedToken_success() public {
        uint256 prevTokenCount = treasury.whitelistedTokens().length;
        uint256 prevCometCount = treasury.cometList().length;
        treasury.removeWhitelistedToken(USDT);
        assertEq(treasury.whitelistedTokens().length, prevTokenCount - 1, "Address removed successfully");
        assertEq(treasury.cometList().length, prevCometCount - 1, "comet address removed successfully");
        assertEq(treasury.comets(USDT), address(0), "Comet should be removed");
    }

    function test_removeWhitelistedToken_revertIfNotInList() public {
        vm.expectRevert("remove-from-list-failed");
        treasury.removeWhitelistedToken(WETH);
    }

    // --- Claim COMP ---

    function test_claimCompAndConvertTo_revertIfTokenNotSupported() public {
        vm.expectRevert("token-is-not-supported");
        treasury.claimCompAndConvertTo(WETH, 1);
    }

    function test_claimCompAndConvertTo_revertIfNotAuthorized() public {
        vm.prank(bob);
        vm.expectRevert("caller-is-not-authorized");
        treasury.claimCompAndConvertTo(USDC, 1);
    }

    function test_claimCompAndConvertTo_governor() public {
        uint256 usdcAmount = 1000e6;
        _mintVUSD(USDC, alice, usdcAmount);

        vm.warp(block.timestamp + 1000);

        uint256 cUSDTBalanceBefore = IERC20(cUSDTv3).balanceOf(address(treasury));
        treasury.claimCompAndConvertTo(USDT, 100);
        uint256 cUSDTBalanceAfter = IERC20(cUSDTv3).balanceOf(address(treasury));
        assertGt(cUSDTBalanceAfter, cUSDTBalanceBefore, "cUSDTv3 balance should be increased after claim");
    }

    function test_claimCompAndConvertTo_keeper() public {
        uint256 usdcAmount = 1000e6;
        _mintVUSD(USDC, bob, usdcAmount);

        vm.warp(block.timestamp + 1000);

        uint256 cUSDCBalanceBefore = IERC20(cUSDCv3).balanceOf(address(treasury));
        vm.prank(keeper);
        treasury.claimCompAndConvertTo(USDC, 100);
        uint256 cUSDCBalanceAfter = IERC20(cUSDCv3).balanceOf(address(treasury));
        assertGt(cUSDCBalanceAfter, cUSDCBalanceBefore, "cUSDCv3 balance should be increased after claim");
    }

    // --- Sweep token ---

    function test_sweepToken_success() public {
        // Give treasury some USDT
        uint256 usdtAmount = 100e6;
        deal(USDT, address(treasury), usdtAmount);

        uint256 balanceBefore = IERC20(USDT).balanceOf(governor);
        treasury.sweep(USDT);
        uint256 balanceAfter = IERC20(USDT).balanceOf(governor);

        assertEq(balanceAfter - balanceBefore, usdtAmount, "Sweep token amount is not correct");
    }

    function test_sweepToken_revertIfCToken() public {
        vm.expectRevert("comet-is-not-allowed-to-sweep");
        treasury.sweep(cUSDTv3);
    }
}
