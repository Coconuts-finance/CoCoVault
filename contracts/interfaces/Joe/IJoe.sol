//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;

import "./JTokenI.sol";

interface Ijoe is JTokenI {
    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);

    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256, uint256);

    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        JTokenI cTokenCollateral
    ) external returns (uint256);

    function underlying() external view returns (address);

    function joetroller() external view returns (address);
}