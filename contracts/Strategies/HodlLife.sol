// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity >=0.6.0 <0.7.0;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "../BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

// Import interfaces for many popular DeFi projects, or add your own!
import '../interfaces/curve/ICurveFi.sol';
import '../interfaces/curve/IGauge.sol';
import '../interfaces/uni/IUniswapV2Router02.sol';

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}

contract HodlLife is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IUniswapV2Router02 router;

    address public constant btcCrv = address(0xf8a57c1d3b9629b77b6726a042ca48990A84Fb49);
    address public constant wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address public constant crv = address(0x172370d5Cd63279eFa6d502DAB29171933a610AF);
    address public constant wbtc = address(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6);

    ICurveFi public pool; //address(0xC2d95EEF97Ec6C17551d45e77B590dc1F9117C67);
    IGauge public gauge; //address(0xffbACcE0CC7C19d46132f1258FC16CF6871D153c);

    uint256 public maxSingleInvest = 200000000;
    uint256 public slippageProtectionIn = 50; //out of 10000. 50 = 0.5%
    uint256 public slippageProtectionOut = 50; //out of 10000. 50 = 0.5%
    uint256 public constant DENOMINATOR = 10_000;

    uint256 minWant;
    uint256 want_decimals;
    uint256 minCrv;
    uint256 minWmatic;

    constructor(
        address _vault, 
        address _pool, 
        address _gauge,
        address _router
    ) public BaseStrategy(_vault) {
        _initializeThis(_pool, _gauge, _router);
    }

    function _initializeThis(
        address _pool,
        address _gauge,
        address _router
    ) internal {
        setPool(_pool);
        setGauge(_gauge);
        router = IUniswapV2Router02(_router);

        want_decimals = IERC20Extended(address(want)).decimals();
        minWant = 10;
        minCrv = 10000000000000000;
        minWmatic = 10000000000000000;
    }

    function setPool(address _pool) internal {
        IERC20(wbtc).safeApprove(_pool, type(uint256).max);

        pool = ICurveFi(_pool);
    }

    function setGauge(address _gauge) internal {
        //approve gauge
        IERC20(btcCrv).approve(_gauge, type(uint256).max);

        gauge = IGauge(_gauge);
    }

    function updateMaxSingleInvest(uint256 _maxSingleInvest) public onlyAuthorized {
        maxSingleInvest = _maxSingleInvest;
    }
    function updateSlippageProtectionIn(uint256 _slippageProtectionIn) public onlyAuthorized {
        slippageProtectionIn = _slippageProtectionIn;
    }
    function updateSlippageProtectionOut(uint256 _slippageProtectionOut) public onlyAuthorized {
        slippageProtectionOut = _slippageProtectionOut;
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "Hodl Like its Hot";
    }

    function balanceOfToken(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function toWant(uint256 _lpBalance) public view returns(uint256) {
        return _lpBalance.mul(pool.get_virtual_price()).div(1e28);
    }

    function toShares(uint256 _wantAmount) public view returns (uint256) {
        //lpAmount = (UnderlyingAmount * 1e(18 + (18 - UInderlyingDecimals))) / virtualPrice
        return _wantAmount.mul(1e28).div(pool.get_virtual_price());
    }

    function lpBalance() public view returns (uint256) {
        return gauge.balanceOf(address(this)).add(balanceOfToken(btcCrv));
    }
 
    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 wantBalance = balanceOfToken(address(want));

        uint256 rewards = estimatedRewards();

        uint256 poolBalance = toWant(lpBalance());

        return wantBalance.add(rewards).add(poolBalance);
    }

    function estimatedRewards() public view returns (uint256) {
        uint256 crvWant = _checkPrice(crv, address(want), balanceOfToken(crv).add(predictCrvAccrued()));
        uint256 wmaticWant = _checkPrice(wmatic, address(want), balanceOfToken(wmatic).add(predictWmaticAccrued()));

        uint256 _bal = crvWant.add(wmaticWant);

        //call it 90% for safety sake
        return _bal.mul(90).div(100);
    }

    function predictCrvAccrued() public view returns(uint256) {
        return gauge.claimable_reward(address(this), crv);
    }

    function predictWmaticAccrued() public view returns(uint256) {
        return gauge.claimable_reward(address(this), wmatic);
    }

    //predicts our profit at next report
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

        //claim rewards
        harvester();
    
        //get base want balance
        uint256 wantBalance = balanceOfToken(address(want));

        uint256 balance = wantBalance.add(toWant(lpBalance()));

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
                needed = needed.sub(wantBalance);
                withdrawSome(needed);

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

        uint256 _wantToInvest = Math.min(toInvest, maxSingleInvest);
        // deposit and stake
        depositSome(_wantToInvest);
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
            if (diff <= minWant) {
                _loss = diff;
            }
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }


    function depositSome(uint256 _amount) internal {
        if(_amount < minWant) {
            return;
        }

        uint256 expectedOut = toShares(_amount);
        
        uint256 maxSlip = expectedOut.mul(DENOMINATOR.sub(slippageProtectionIn)).div(DENOMINATOR);
    
        uint256[2] memory amounts; 
        amounts[0] = _amount;
                  
        pool.add_liquidity(amounts, maxSlip, true);

        gauge.deposit(balanceOfToken(btcCrv));
    }

    function withdrawSome(uint256 _amount) internal {
        if(_amount < minWant) {
            return;
        }

        //let's take the amount we need if virtual price is real.
        uint256 amountNeeded = toShares(_amount);

        if(amountNeeded > gauge.balanceOf(address(this))) {
            harvester();
            amountNeeded =  gauge.balanceOf(address(this));
        }

        gauge.withdraw(amountNeeded);
        
        uint256 toWithdraw = balanceOfToken(btcCrv);

        //if we have less than 18 decimals we need to lower the amount out
        uint256 maxSlippage = toWithdraw.mul(DENOMINATOR.sub(slippageProtectionOut)).div(DENOMINATOR);
        if(want_decimals < 18){
            maxSlippage = maxSlippage.div(10 ** (uint256(uint8(18) - want_decimals)));
        }

        pool.remove_liquidity_one_coin(toWithdraw, 0, maxSlippage, true);
    }

    function harvester() internal {
        if(predictCrvAccrued() < minCrv && predictWmaticAccrued() < minWmatic){
            return;
        }

        gauge.claim_rewards();
        disposeCrv();
        disposeWmatic();
    }

    function disposeCrv() internal {
        uint256 _crv = balanceOfToken(crv);
        if(_crv < minCrv) {
            return;
        }

        _swapFrom(crv, address(want), _crv);
    }

    function disposeWmatic() internal {
        uint256 _Wmatic = balanceOfToken(wmatic);
        if(_Wmatic < minWmatic) {
            return;
        }

        _swapFrom(wmatic, address(want), _Wmatic);
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

    //need to go from PTP to AVAX to USDC.e
    function _swapFromWithAmount(address _from, address _to, uint256 _amountIn, uint256 _amountOut) internal returns (uint256) {

        IERC20(_from).approve(address(router), _amountIn);
        
        uint256[] memory amounts = router.swapExactTokensForTokens(
            _amountIn, _amountOut, getTokenOutPath(_from, _to), address(this), block.timestamp);

        return amounts[amounts.length - 1];
    }

    function _swapFrom(address _from, address _to, uint256 _amountIn) internal returns(uint256){

        uint256 amountOut = _checkPrice(_from, _to, _amountIn);
        
        return _swapFromWithAmount(_from, _to, _amountIn, amountOut);
    }

    function getTokenOutPath(address _tokenIn, address _tokenOut) internal view returns (address[] memory _path) {
        bool isAvax = _tokenIn == wmatic || _tokenOut == wmatic;
        _path = new address[](isAvax ? 2 : 3);
        _path[0] = _tokenIn;

        if (isAvax) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = wmatic;
            _path[2] = _tokenOut;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        harvester();
        gauge.withdraw(gauge.balanceOf(address(this)));
        pool.remove_liquidity_one_coin(balanceOfToken(btcCrv), 0, 0, true);
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        harvester();
        uint256 _crvB = balanceOfToken(crv);
        if (_crvB > 0) {
            IERC20(crv).safeTransfer(_newStrategy, _crvB);
        }
        uint256 _wmaticB = balanceOfToken(wmatic);
        if (_wmaticB > 0) {
            IERC20(wmatic).safeTransfer(_newStrategy, _wmaticB);
        }

        gauge.withdraw(gauge.balanceOf(address(this)));
        IERC20(btcCrv).transfer(_newStrategy, balanceOfToken(btcCrv));

    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](3);
        protected[0] = btcCrv;
        protected[1] = crv;
        protected[2] = wmatic;
        
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

    //manual withdraw incase needed
     //Decimal issue wont withdraw any funds unles greater than 1000000000 == 1 wbtc
    function manualWithdraw(uint256 _amount) external onlyStrategist {
        pool.remove_liquidity_one_coin(_amount, 0, 1, true);
    }

    //Decimal issue is not wihtdrawaling any funds 1000000000 == 1 wbtc

    //manual withdraw incase needed
    function manualUnstake(uint256 _amount) external onlyStrategist {
        gauge.withdraw(_amount);
    }
}