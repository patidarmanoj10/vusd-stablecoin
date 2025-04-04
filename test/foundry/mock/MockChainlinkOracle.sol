// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

contract MockChainlinkOracle {
    int256 private price;

    constructor(int256 _price) {
        price = _price;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, price, 0, block.timestamp, 0);
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function updatePrice(int256 _price) external {
        price = _price;
    }
}
