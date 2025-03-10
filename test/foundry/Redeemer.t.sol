// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "../../lib/forge-std/src/Test.sol";
import "../../contracts/Redeemer.sol";
import "../../contracts/VUSD.sol";
import "../../contracts/interfaces/chainlink/IAggregatorV3.sol";

contract MockTreasury is ITreasury {
    mapping(address => address) private tokenOracles;

    function isWhitelistedToken(address) external pure override returns (bool) {
        return true;
    }

    function oracles(address _token) external view override returns (address) {
        return tokenOracles[_token];
    }

    function withdrawable(address) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function setWhitelistedToken(address _token, bool _whitelisted) external {}

    function setOracle(address _token, address _oracle) external {
        tokenOracles[_token] = _oracle;
    }

    function withdraw(address _token, uint256 _amount, address _receiver) external override {
        IERC20(_token).transfer(_receiver, _amount);
    }

    function withdraw(address _token, uint256 _amount) external override {
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function vusd() external view override returns (address) {}

    function whitelistedTokens() external view override returns (address[] memory) {}
}

contract RedeemerTest is Test {
    VUSD vusd;
    Redeemer redeemer;
    MockTreasury treasury;
    address alice = address(0x111);
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address constant DAI_USD = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    function setUp() public {
        vm.createSelectFork(vm.envString("NODE_URL"), vm.envUint("FORK_BLOCK_NUMBER"));
        treasury = new MockTreasury();
        vusd = new VUSD(address(treasury));
        vusd.updateMinter(address(this));
        vusd.mint(alice, 10000 ether);
        redeemer = new Redeemer(address(vusd));

        console.log("VUSD balance: %s", vusd.balanceOf(alice));
        deal(DAI, address(treasury), 1000 ether);
        treasury.setOracle(DAI, DAI_USD);
    }

    function testUpdatePriceTolerance() public {
        uint256 newTolerance = 1000;
        redeemer.updatePriceTolerance(newTolerance);
        assertEq(redeemer.priceTolerance(), newTolerance, "Price tolerance should be updated");
    }

    function testRedeemWithPriceToleranceExceeded() public {
        redeemer.updatePriceTolerance(0);
        vm.expectRevert("price-tolerance-exceeded");
        redeemer.redeem(DAI, 100, address(0x123));
    }

    function testRedeemWithinPriceTolerance() public {
        uint256 amount = 500 ether;
        uint256 redeemableAmount = redeemer.redeemable(DAI, amount);
        uint256 vusdBalanceBefore = vusd.balanceOf(alice);

        vm.startPrank(alice);
        vusd.approve(address(redeemer), amount);
        redeemer.redeem(DAI, amount);
        vm.stopPrank();

        // assert that vusd balance decrease
        assertEq(vusd.balanceOf(alice), vusdBalanceBefore - amount, "VUSD balance should decrease");
        assertEq(redeemableAmount, IERC20(DAI).balanceOf(alice), "DAI amount should be transferred to user");
    }

    function testRedeemable() public view {
        (, int256 _price, , , ) = IAggregatorV3(DAI_USD).latestRoundData();
        uint256 vusdAmount = 100 ether;
        uint256 redeemableBeforeFee = (vusdAmount * uint256(_price)) / 1e8;
        uint256 expectedRedeemable = redeemableBeforeFee - ((redeemableBeforeFee * redeemer.redeemFee()) / 10000);
        uint256 redeemableAmount = redeemer.redeemable(DAI, vusdAmount);
        assertEq(redeemableAmount, expectedRedeemable, "Redeemable amount should be correct");
    }

    function testUpdateRedeemFee() public {
        uint256 newFee = 50;
        redeemer.updateRedeemFee(newFee);
        assertEq(redeemer.redeemFee(), newFee, "Redeem fee should be updated");
    }

    function testRedeemWithUpdatedFee() public {
        uint256 amount = 10 ether;
        redeemer.updateRedeemFee(0);
        uint256 redeemableWithoutFee = redeemer.redeemable(DAI, amount);
        uint256 newFee = 50; // 0.5%
        redeemer.updateRedeemFee(newFee);
        uint256 expectedRedeemable = redeemableWithoutFee - ((redeemableWithoutFee * newFee) / 10000);

        vm.startPrank(alice);
        vusd.approve(address(redeemer), amount);
        redeemer.redeem(DAI, amount);
        vm.stopPrank();

        uint256 daiBalance = IERC20(DAI).balanceOf(alice);
        assertEq(daiBalance, expectedRedeemable, "Recipient should receive redeemed VUSD with updated fee");
    }
}
