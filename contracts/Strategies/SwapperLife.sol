//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.12;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/math/SafeMath.sol';

import '../interfaces/Uni/IUniswapV2Router02.sol';
import '../interfaces/joe/IJoeFactory.sol';
import '../interfaces/joe/IJoePair.sol';
import "../interfaces/PTP/IPTPRouter.sol";

import {UniswapV2Library} from '../Libraries/UniswapV2Library.sol';

contract SwapperLife {

    using SafeMath for uint256;

    IPTPRouter ptpRouter = IPTPRouter(0x66357dCaCe80431aee0A7507e2E361B7e2402370);
    IUniswapV2Router02 joeRouter;  //IJoeRouter(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
    IJoeFactory joeFactory;  //IJoeFactory(0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10);

    address wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    function _setMightyJoeRouter(address _router) internal {
        joeRouter = IUniswapV2Router02(_router);
    }

    function _setJoeFactory(address _factory) internal {
        joeFactory = IJoeFactory(_factory); 
    }

    function _ptpQoute(
        address _from,
        address _to,
        uint256 _amount
    ) internal view returns (uint256) {
        (uint256 amountOut, ) = ptpRouter.quotePotentialSwap(_from, _to, _amount);

        return amountOut;
    }

    function _ptpSwapWithAmount(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _amountOut
    ) internal returns (uint256 actualOut) {
        IERC20(_from).approve(address(ptpRouter), _amountIn);

        (actualOut, ) = ptpRouter.swap(_from, _to, _amountIn, _amountOut, address(this), block.timestamp);
    }

    function _ptpSwap(
        address _from,
        address _to,
        uint256 _amount
    ) internal returns (uint256){
        uint256 amountOut = _ptpQoute(_from, _to, _amount); 

        return _ptpSwapWithAmount(_from, _to, _amount, amountOut);
    }

    //WARNING. manipulatable and simple routing. Only use for safe functions
    function _checkPrice(
        address start,
        address end,
        uint256 _amount
    ) public view returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        
        uint256[] memory amounts = joeRouter.getAmountsOut(_amount, getTokenOutPath(start, end));

        return amounts[amounts.length - 1];

    }

    //need to go from PTP to AVAX to USDC.e
    function _swapFromWithAmount(address _from, address _to, uint256 _amountIn, uint256 _amountOut) internal returns (uint256) {

        IERC20(_from).approve(address(joeRouter), _amountIn);
        
        uint256[] memory amounts = joeRouter.swapExactTokensForTokens(
            _amountIn, _amountOut, getTokenOutPath(_from, _to), address(this), block.timestamp);

        return amounts[amounts.length - 1];
    }

    function _swapFrom(address _from, address _to, uint256 _amountIn) internal returns(uint256){

        uint256 amountOut = _checkPrice(_from, _to, _amountIn);
        
        return _swapFromWithAmount(_from, _to, _amountIn, amountOut);
    }

    function _swapTo(address _from, address _to, uint256 _amountTo) internal returns(uint256) {

        if(_amountTo == 0 || joeFactory.getPair(_from, _to) == address(0)) {
            return 0;
        }
        (uint256 fromReserve, uint256 toReserve) = UniswapV2Library.getReserves(address(joeFactory), _from, _to);

        uint256 amountIn = UniswapV2Library.getAmountIn(_amountTo, fromReserve, toReserve);
        
        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        IERC20(_from).approve(address(joeRouter), amountIn);
        
        uint256[] memory amounts = joeRouter.swapTokensForExactTokens(_amountTo, amountIn, path, address(this), block.timestamp);

        return amounts[1];
    }

    function getTokenOutPath(address _tokenIn, address _tokenOut) internal view returns (address[] memory _path) {
        bool isAvax = _tokenIn == wavax || _tokenOut == wavax;
        _path = new address[](isAvax ? 2 : 3);
        _path[0] = _tokenIn;

        if (isAvax) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = wavax;
            _path[2] = _tokenOut;
        }
    }

}