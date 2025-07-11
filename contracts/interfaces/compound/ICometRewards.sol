// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

interface ICometRewards {
    struct RewardOwed {
        address token;
        uint256 owed;
    }

    /**
     * @notice Calculates the amount of a reward token owed to an account
     * @param comet The protocol instance
     * @param account The account to check rewards for
     */
    function getRewardOwed(address comet, address account) external returns (RewardOwed memory);

    /**
     * @notice Claim rewards of token type from a comet instance to owner address
     * @param comet The protocol instance
     * @param src The owner to claim for
     * @param shouldAccrue Whether or not to call accrue first
     */
    function claim(address comet, address src, bool shouldAccrue) external;
}
