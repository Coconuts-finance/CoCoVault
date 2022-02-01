//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;


interface IYakFarm {

    function withdraw(uint256 amount) external;
    function deposit() external payable;
    function deposit(uint256 amount) external;
    function balanceOf(address account) external view returns (uint);
}