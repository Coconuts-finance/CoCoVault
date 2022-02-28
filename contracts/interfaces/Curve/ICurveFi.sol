
//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;


interface ICurveFi {

    function get_virtual_price() external view returns (uint256);

    function add_liquidity(
        //list of amounts of tokens to deposit
        uint256[2] calldata amounts,
        //min of lp tokens out
        uint256 min_mint_amount,
        bool use_underlying
    )external returns (uint256); //Returns the amount of LP tokens received in exchange for the deposited tokens.

    function remove_liqudity(
        //lp tokens to be redeemed
        uint256 amount,
        //list of tokens to be recieved
        uint256[2] calldata amounts,
        bool useUnderlying
     ) external returns (uint256); //Returns a list of the amounts for each coin that was withdrawn.

    function remove_liquidity_imbalance(
        uint256[] calldata _amounts,

        uint256 _minAmount,
        bool _useUnderlying
    ) external returns(uint256);

    function remove_liquidity_one_coin(
        //  / Amount of LP tokens to burn in the withdrawal
         uint256 tokenAmount,
         //: Index value of the coin to withdraw
         int128 i,
         // Minimum amount of coin to receive
         uint256 minAmount,
        
         bool useUnderlying
     ) external returns(uint256); //Returns the amount of coin i received.

    function calc_withdraw_one_coin(
        //amount of lp tokens to withdraw
        uint256 _tokenAmount,
        //index of the coin to withdraw
        int128 i
    ) external view returns(uint256);

}

