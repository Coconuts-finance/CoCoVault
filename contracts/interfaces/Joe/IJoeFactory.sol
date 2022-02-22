//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;



interface IJoeFactory {

    function getPair(address token0, address token1) external view returns (address);
    
}