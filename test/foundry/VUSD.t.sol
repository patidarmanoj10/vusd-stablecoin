// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VUSD} from "contracts/VUSD.sol";
import {Minter} from "contracts/Minter.sol";
import {Treasury} from "contracts/Treasury.sol";
import {USDC} from "test/foundry/utils/Address.sol";

contract VUSDTest is Test {
    using SafeERC20 for IERC20;

    VUSD vusd;
    Minter minter;
    address governor;
    Treasury treasury;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public {
        vm.createSelectFork(vm.envString("NODE_URL"), vm.envUint("FORK_BLOCK_NUMBER"));
        governor = address(this);

        vusd = new VUSD(governor);
        minter = new Minter(address(vusd), type(uint256).max);
        vusd.updateMinter(address(minter));

        treasury = new Treasury(address(vusd));
        vusd.updateTreasury(address(treasury));
    }

    // --- Update minter address ---

    function test_updateMinter_revertIfNotGovernor() public {
        vm.prank(bob);
        vm.expectRevert("caller-is-not-the-governor");
        vusd.updateMinter(carol);
    }

    function test_updateMinter_revertIfZeroAddress() public {
        vm.expectRevert("minter-address-is-zero");
        vusd.updateMinter(address(0));
    }

    function test_updateMinter_revertIfSameMinter() public {
        address newMinter = vusd.minter();
        vm.expectRevert("same-minter");
        vusd.updateMinter(newMinter);
    }

    function test_updateMinter_success() public {
        address newMinter = carol;
        assertNotEq(vusd.minter(), newMinter);
        vusd.updateMinter(newMinter);
        assertEq(vusd.minter(), newMinter, "Minter update failed");
    }

    // --- Update treasury address ---

    function test_updateTreasury_revertIfNotGovernor() public {
        vm.prank(bob);
        vm.expectRevert("caller-is-not-the-governor");
        vusd.updateTreasury(carol);
    }

    function test_updateTreasury_revertIfZeroAddress() public {
        vm.expectRevert("treasury-address-is-zero");
        vusd.updateTreasury(address(0));
    }

    function test_updateTreasury_revertIfSameTreasury() public {
        address newTreasury = vusd.treasury();
        vm.expectRevert("same-treasury");
        vusd.updateTreasury(newTreasury);
    }

    function test_updateTreasury_success() public {
        address newTreasury = carol;
        assertNotEq(vusd.treasury(), newTreasury);
        vusd.updateTreasury(newTreasury);
        assertEq(vusd.treasury(), newTreasury, "Treasury update failed");
    }

    // --- Mint VUSD ---

    function test_mint_revertIfNotMinter() public {
        vm.expectRevert("caller-is-not-minter");
        vusd.mint(alice, 10000);
    }

    // --- Multi transfer ---

    function test_multiTransfer_revertIfArityMismatch() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10;
        amounts[1] = 15;
        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        vm.expectRevert("input-length-mismatch");
        vusd.multiTransfer(recipients, amounts);
    }

    function test_multiTransfer_revertIfNoBalance() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vusd.multiTransfer(recipients, amounts);
    }

    function test_multiTransfer_success() public {
        // Mint VUSD to alice via minter
        uint256 usdcAmount = 1000e6;
        deal(USDC, alice, usdcAmount);
        vm.startPrank(alice);
        IERC20(USDC).safeApprove(address(minter), usdcAmount);
        minter.mint(USDC, usdcAmount, 1, alice);
        vm.stopPrank();

        uint256 vusdBalance = vusd.balanceOf(alice);
        assertGt(vusdBalance, 0, "Incorrect VUSD balance");
        uint256 halfBalance = vusdBalance / 2;

        address[] memory recipients = new address[](2);
        recipients[0] = bob;
        recipients[1] = carol;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = halfBalance;
        amounts[1] = halfBalance;

        vm.prank(alice);
        vusd.multiTransfer(recipients, amounts);

        assertEq(vusd.balanceOf(alice), 0, "Sender balance should be zero");
        assertEq(vusd.balanceOf(bob), halfBalance, "Multi transfer failed for bob");
        assertEq(vusd.balanceOf(carol), halfBalance, "Multi transfer failed for carol");
    }
}
