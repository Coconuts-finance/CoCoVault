//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;


interface IGauge {

    function deposit(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function withdraw(uint256) external;

    function claim_rewards() external;

    function claimable_reward(
        address _owner,
        address _token
    ) external view returns (uint256 _claimable);
}
