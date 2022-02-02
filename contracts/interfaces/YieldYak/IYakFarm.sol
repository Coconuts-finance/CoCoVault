//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;


interface IYakFarm {

     // ERC20 Functions
    
    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function decimals() external returns(uint256);

    //deposit and withdraw functions
    function withdraw(uint256 amount) external;
    function deposit() external payable;
    function deposit(uint256 amount) external;

    /**
     * @notice Calculate receipt tokens for a given amount of deposit tokens
     * @dev If contract is empty, use 1:1 ratio
     * @dev Could return zero shares for very low amounts of deposit tokens
     * @param amount deposit tokens
     * @return receipt tokens
     */
    function getSharesForDepositTokens(uint256 amount) external view returns (uint256);

    /**
     * @notice Calculate deposit tokens for a given amount of receipt tokens
     * @param amount receipt tokens
     * @return deposit tokens
     */
    function getDepositTokensForShares(uint256 amount) external view returns (uint256);

}