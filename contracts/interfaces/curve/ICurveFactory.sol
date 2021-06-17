// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

interface ICurveFactory {
    event MetaPoolDeployed(address coin, address base_pool, uint256 A, uint256 fee, address deployer);

    function deploy_metapool(
        address _base_pool,
        string calldata _name,
        string calldata _symbol,
        address _coin,
        uint256 _A,
        uint256 _fee
    ) external returns (address);

    function find_pool_for_coins(address _from, address _to) external view returns (address);
}
