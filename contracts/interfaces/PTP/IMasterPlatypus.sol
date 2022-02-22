//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;


interface IMasterPlatypus {

    function pendingTokens(
        uint256 _pid, 
        address _address
    ) external view returns (
        uint256 pendingPtp, 
        address bonusTokenAddress, 
        string memory bonusTokenSymbol,
        uint256 pendingBonusToken);

    function ptpPerSec() external view returns(uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function multiClaim(uint256[] memory _pids) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function userInfo(uint256 _pid, address _address) external view returns (uint256, uint256, uint256);

}