// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapper} from "contracts/interfaces/bloq/ISwapper.sol";

contract SwapperMock is ISwapper, Test {
    uint256 slippage;

    function swapExactInput(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        address receiver_
    ) external override returns (uint256 _amountOut) {
        require(
            IERC20(tokenIn_).allowance(msg.sender, address(this)) >= amountIn_,
            "SwapperMock: Not enough tokenIn approved"
        );
        IERC20(tokenIn_).transferFrom(msg.sender, address(this), amountIn_);
        _amountOut = amountOutMin_ + 1;
        deal(tokenOut_, receiver_, IERC20(tokenOut_).balanceOf(receiver_) + _amountOut);
    }

    function getAmountIn(
        address tokenIn_,
        address tokenOut_,
        uint256 amountOut_
    ) external override returns (uint256 _amountIn) {}

    function getAmountOut(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_
    ) external override returns (uint256 _amountOut) {}

    function swapExactOutput(
        address tokenIn_,
        address tokenOut_,
        uint256 amountOut_,
        uint256 amountInMax_,
        address receiver_
    ) external override returns (uint256 _amountIn) {}

    function getAllExchanges() external view override returns (address[] memory) {}

    function masterOracle() external view override returns (address) {}
}
