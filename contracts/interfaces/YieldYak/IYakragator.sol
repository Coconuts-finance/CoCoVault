//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IYakregator {

    struct FormattedOfferWithGas {
        uint[] amounts;
        address[] adapters;
        address[] path;
        uint gasEstimate;
    }

    struct FormattedOffer {
        uint[] amounts;
        address[] adapters;
        address[] path;
    }
    
    struct Trade {
        uint amountIn;
        uint amountOut;
        address[] path;
        address[] adapters;
    }

    function findBestPathWithGas(
        uint256 _amountIn, 
        address _tokenIn, 
        address _tokenOut, 
        uint _maxSteps,
        uint _gasPrice
    ) external view returns (FormattedOfferWithGas memory); 

    function findBestPath(
        uint256 _amountIn, 
        address _tokenIn, 
        address _tokenOut, 
        uint _maxSteps
    ) external view returns (FormattedOffer memory);
    
    function swapNoSplitFromAVAX(Trade calldata _trade, address _to, uint _fee) external payable ;
    function swapNoSplitToAVAX(Trade calldata _trade, address _to, uint _fee) external;
}