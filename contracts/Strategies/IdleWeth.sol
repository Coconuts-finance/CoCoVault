// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries

import {
    BaseStrategy,
    StrategyParams
} from  "../BaseStrategy.sol";
import { SafeERC20, SafeMath, IERC20, Address } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import "../interfaces/idle/IdleToken.sol";
import "../interfaces/uni/IUniswapV2Router02.sol";

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}

contract IdleWeth is BaseStrategy{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // Comptroller address for joetroller.finance
    
    IUniswapV2Router02 public router;
    IdleToken idleToken;
    
    address public constant wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    uint256 public minWant; // minimum amount of want to act on

    bool public forceMigrate;

    constructor(
        address _vault, 
        address _token, 
        address _router
    ) public BaseStrategy(_vault) {
        _initializeThis(_token, _router);
    }

    function initialize(
        address _vault, 
        address _token, 
        address _router
    ) external {
        _initialize(_vault, msg.sender, msg.sender, msg.sender);
        _initializeThis(_token, _router);
    }

    function _initializeThis(
        address _token, 
        address _router
    ) internal {
        setIdleToken(_token);
        router = IUniswapV2Router02(_router);
        require(IERC20Extended(address(want)).decimals() <= 18); // dev: want not supported

        // You can set these parameters on deployment to whatever you want
        profitFactor = 100_000; // multiple before triggering harvest
        debtThreshold = 1e30;

        // set minWant to 1e-5 want
        minWant = uint256(uint256(10)**uint256((IERC20Extended(address(want))).decimals())).div(1e5);
    }

    function name() external view override returns (string memory) {
        return "Idle Weth";
    }

    function changeIdleToken(address _token) public onlyStrategist {
        require(_token != address(idleToken), "Cant change to same vault");

        uint256 _allowance = want.allowance(address(this), address(idleToken));
        want.safeDecreaseAllowance(address(idleToken), _allowance);
        
        setIdleToken(_token);
    }

    function setIdleToken(address _pool) internal {
        idleToken = IdleToken(_pool);
        
        want.safeApprove(_pool, type(uint256).max);
    }

    function setMinWant(uint256 _minWant) external onlyStrategist {
        minWant = _minWant;
    }

    function balanceOfToken(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 deposits = getCurrentPosition();

        return balanceOfToken(address(want)).add(deposits);
    }

    //Returns the current position
    //WARNING - this returns just the balance at last time someone touched the idleToken token. Does not accrue interst in between
    function getCurrentPosition() public view returns (uint256) {
        return idleToken.balanceOf(address(this)).mul(idleToken.tokenPrice()).div(1e18);
    }

    //takes into account what could actually be withdrawn after any fees assesed
    function getLivePosition() public view returns (uint256) {
        return idleToken.balanceOf(address(this)).mul(idleToken.tokenPriceWithFee(address(this))).div(1e18);
    }

    function toShares(uint256 _amount) internal view returns(uint256) {
        //lpAmount = (UnderlyingAmount * 1e(18 + (18 - UInderlyingDecimals))) / virtualPrice
        return _amount.mul(1e18).div(idleToken.tokenPriceWithFee(address(this)));
    }

    function expectedReturn() public view returns (uint256) {
        uint256 estimateAssets = estimatedTotalAssets();

        uint256 debt = vault.strategies(address(this)).totalDebt;
        if (debt > estimateAssets) {
            return 0;
        } else {
            return estimateAssets.sub(debt);
        }
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
         _profit = 0;
        _loss = 0; // for clarity. also reduces bytesize
        _debtPayment = 0;

        //get base want balance
        uint256 wantBalance = balanceOfToken(address(want));
        uint256 balance = getCurrentPosition().add(wantBalance);

        //get amount given to strat by vault
        uint256 debt = vault.strategies(address(this)).totalDebt;

        //Check to see if there is nothing invested
        if (balance == 0 && debt == 0) {
            return (_profit, _loss, _debtPayment);
        }

        //Balance - Total Debt is profit
        if (balance > debt) {
            _profit = balance.sub(debt);

            uint256 needed = _profit.add(_debtOutstanding);
            if (needed > wantBalance) {
                withdrawSome(needed.sub(wantBalance));

                wantBalance = balanceOfToken(address(want));

                if (wantBalance < needed) {
                    if (_profit > wantBalance) {
                        _profit = wantBalance;
                        _debtPayment = 0;
                    } else {
                        _debtPayment = Math.min(wantBalance.sub(_profit), _debtOutstanding);
                    }
                } else {
                    _debtPayment = _debtOutstanding;
                }
            } else {
                _debtPayment = _debtOutstanding;
            }
        } else {
            //we will lose money until we claim comp then we will make money
            //this has an unintended side effect of slowly lowering our total debt allowed
            _loss = debt.sub(balance);
            if (_debtOutstanding > wantBalance) {
                withdrawSome(_debtOutstanding.sub(wantBalance));
                wantBalance = balanceOfToken(address(want));
            }

            _debtPayment = Math.min(wantBalance, _debtOutstanding);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        //we are spending all our cash unless we have debt outstanding
        uint256 _wantBal = balanceOfToken(address(want));
        if (_wantBal < _debtOutstanding) {
            withdrawSome(_debtOutstanding.sub(_wantBal));

            return;
        }

        // send all of our want tokens to be deposited
        uint256 toInvest = _wantBal.sub(_debtOutstanding);
        // deposit and stake
        depositSome(toInvest);
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        uint256 wantBalance = balanceOfToken(address(want));
        if (wantBalance > _amountNeeded) {
            // if there is enough free want, let's use it
            return (_amountNeeded, 0);
        }

        // we need to free funds
        uint256 amountRequired = _amountNeeded.sub(wantBalance);
        withdrawSome(amountRequired);

        uint256 freeAssets = balanceOfToken(address(want));
        if (_amountNeeded > freeAssets) {
            _liquidatedAmount = freeAssets;
            uint256 diff = _amountNeeded.sub(_liquidatedAmount);
            if (diff > minWant) {
                _loss = diff;
            }
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function depositSome(uint256 _amount) internal {
        if (_amount < minWant) {
            return;
        }

        idleToken.mintIdleToken(_amount, false, address(this));
    }

    function withdrawSome(uint256 _amountNeeded) internal {
        //should have already called LivePosition()
        uint256 deposited = getCurrentPosition();

        if(_amountNeeded > deposited) {
            idleToken.redeemIdleToken(idleToken.balanceOf(address(this)));
        } else {
            idleToken.redeemIdleToken(toShares(_amountNeeded));
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        idleToken.redeemIdleToken(idleToken.balanceOf(address(this)));

        return balanceOfToken(address(this));
    }

    function prepareMigration(address _newStrategy) internal override {
        idleToken.transfer(_newStrategy, idleToken.balanceOf(address(this)));
    }

    //WARNING. manipulatable and simple routing. Only use for safe functions
    function _checkPrice(
        address start,
        address end,
        uint256 _amount
    ) internal view returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        
        //uint256[] memory amounts = router.getAmountsOut(_amount, getTokenOutPath(start, end));
        uint256[] memory amounts = router.getAmountsOut(_amount, getTokenOutPath(start, end));

        return amounts[amounts.length - 1];
    }

    function getTokenOutPath(address _tokenIn, address _tokenOut) internal view returns (address[] memory _path) {
        bool isWmatic = _tokenIn == wmatic || _tokenOut == wmatic;
        _path = new address[](isWmatic ? 2 : 3);
        _path[0] = _tokenIn;

        if (isWmatic) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = wmatic;
            _path[2] = _tokenOut;
        }
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](1);
        protected[0] = address(idleToken);

        return protected;
    }

    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _checkPrice(wmatic, address(want), _amtInWei);
    }
}