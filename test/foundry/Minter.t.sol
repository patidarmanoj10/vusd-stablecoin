// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "../../lib/forge-std/src/Test.sol";
import "../../contracts/Minter.sol";
import "../../contracts/VUSD.sol";
import "../../contracts/interfaces/chainlink/IAggregatorV3.sol";

contract MinterTest is Test {
    VUSD vusd;
    Minter minter;
    address governor;
    address alice = address(0x111);
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address constant DAI_USD = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    function setUp() public {
        vm.createSelectFork(vm.envString("NODE_URL"), vm.envUint("FORK_BLOCK_NUMBER"));
        governor = address(this);
        vusd = new VUSD(address(0x222));
        minter = new Minter(address(vusd), type(uint256).max);
        vusd.updateMinter(address(minter));
    }

    function testAddAndRemoveWhitelistedToken() public {
        minter.removeWhitelistedToken(DAI);
        assertFalse(minter.isWhitelistedToken(DAI), "Token should not be whitelisted");

        minter.addWhitelistedToken(DAI, cDAI, DAI_USD);
        assertTrue(minter.isWhitelistedToken(DAI), "Token should be whitelisted");
    }

    function testUpdateMintingFee() public {
        uint256 newFee = 500;
        minter.updateMintingFee(newFee);
        assertEq(minter.mintingFee(), newFee, "Minting fee should be updated");
    }

    function testUpdateMaxMintAmount() public {
        uint256 newMintLimit = 1000 ether;
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
        uint256 _amount = 10 ether;
        deal(DAI, address(this), _amount);
        IERC20(DAI).approve(address(minter), _amount);
        vm.expectRevert("oracle-price-exceed-tolerance");
        minter.mint(DAI, _amount);
    }

    function testCalculateMintage() public view {
        uint256 amount = 1000 ether;
        IAggregatorV3 oracle = IAggregatorV3(DAI_USD);
        (, int256 price, , , ) = oracle.latestRoundData();
        uint256 amountIn = (uint256(price) * amount) / 10 ** oracle.decimals();
        uint256 fee = minter.mintingFee();
        uint256 maxFee = minter.MAX_BPS();
        uint256 expectedMintage = amountIn - ((amountIn * fee) / maxFee);
        uint256 actualMintage = minter.calculateMintage(DAI, amount);
        assertEq(actualMintage, expectedMintage, "Incorrect mintage calculation");
    }

    function testMintVUSD() public {
        uint256 amount = 1000 ether;
        deal(DAI, address(this), 10 * amount);
        IERC20(DAI).approve(address(minter), amount);
        uint256 expectedVUSD = minter.calculateMintage(DAI, amount);
        minter.mint(DAI, amount);
        uint256 vusdBalance = vusd.balanceOf(address(this));
        assertEq(vusdBalance, expectedVUSD, "Incorrect VUSD minted");
    }

    function testMintVUSDWithFee() public {
        uint256 amount = 1000 ether;
        minter.updateMintingFee(5);
        deal(DAI, address(this), amount);
        IERC20(DAI).approve(address(minter), amount);
        uint256 expectedVUSD = minter.calculateMintage(DAI, amount);
        minter.mint(DAI, amount);
        uint256 vusdBalance = vusd.balanceOf(address(this));
        assertEq(vusdBalance, expectedVUSD, "Incorrect VUSD minted");
    }

    function testGovernorCanMint() public {
        uint256 amount = 1000 ether;
        uint256 initialSupply = vusd.totalSupply();
        minter.mint(amount);
        uint256 newSupply = vusd.totalSupply();
        assertEq(newSupply, initialSupply + amount, "Governor should be able to mint VUSD");
    }

    function testNonGovernorCannotMint() public {
        uint256 amount = 1000 ether;
        vm.prank(alice);
        vm.expectRevert("caller-is-not-the-governor");
        minter.mint(amount);
    }

    function testMintMaxAvailableVUSD() public {
        uint256 amount = 1000 ether;

        deal(DAI, alice, amount);
        IERC20(DAI).approve(address(minter), amount);

        uint256 expectedVUSD = minter.calculateMintage(DAI, amount);
        minter.updateMaxMintAmount(expectedVUSD / 2);

        vm.startPrank(alice);

        IERC20(DAI).approve(address(minter), amount);
        vm.expectRevert("mint-limit-reached");
        minter.mint(DAI, amount);
    }
}
