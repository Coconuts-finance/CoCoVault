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
import './SwapperLife.sol';

import "../interfaces/joe/Ijoetroller.sol";
import "../interfaces/joe/IJToken.sol";
import "../interfaces/joe/JTokenI.sol";
import "../interfaces/joe/IJoeRewarder.sol";
import "../interfaces/Uni/IUniswapV2Router02.sol";
import "../interfaces/IERC20Extended.sol";

contract SingleJoe is BaseStrategy, SwapperLife {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // Comptroller address for joetroller.finance
    IJoetroller public joetroller;

    //Only three tokens we use
    address public Joe;
    IJToken public JToken;
    IJoeRewarder public joeRewarder = IJoeRewarder(0x45B2C4139d96F44667577C0D7F7a7D170B420324);

    uint256 public minWant; // minimum amount of want to act on

    // Rewards handling
    bool public dontClaimjoe; // enable/disables joe claiming
    uint256 public minJoe; // minimum amount of joe to be sold
    uint256 lastHarvest;

    bool public forceMigrate;

    constructor(
        address _vault, 
        address _JToken, 
        address _router, 
        address _joe, 
        address _joetroller
    ) public BaseStrategy(_vault) {
        _initializeThis(_JToken, _router, _joe, _joetroller);
    }

    function initialize(
        address _vault, 
        address _JToken, 
        address _router, 
        address _joe, 
        address _joetroller
    ) external {
        _initialize(_vault, msg.sender, msg.sender, msg.sender);
        _initializeThis(_JToken, _router, _joe, _joetroller);
    }

    function _initializeThis(
        address _JToken, 
        address _router, 
        address _joe, 
        address _joetroller
    ) internal {
        setJToken(_JToken);
        Joe = _joe;
        joetroller = IJoetroller(_joetroller);
        require(IERC20Extended(address(want)).decimals() <= 18); // dev: want not supported
        _setMightyJoeRouter(_router);

        // You can set these parameters on deployment to whatever you want
        profitFactor = 100_000; // multiple before triggering harvest
        debtThreshold = 1e30;

        // set minWant to 1e-5 want
        minWant = uint256(uint256(10)**uint256((IERC20Extended(address(want))).decimals())).div(1e5);
        minJoe = 1000000000000000;
        lastHarvest = block.timestamp;
    }

    function name() external view override returns (string memory) {
        return "SingleJoe";
    }

    function changeJToken(address _JToken) public onlyStrategist {
        require(_JToken != address(JToken), "Cant change to same vault");

        uint256 _allowance = want.allowance(address(this), address(JToken));
        want.safeDecreaseAllowance(address(JToken), _allowance);
        
        setJToken(_JToken);
    }

    function setJToken(address _pool) internal {
        JToken = IJToken(_pool);
        
        want.safeApprove(_pool, type(uint256).max);
    }

    function setMightyJoeRouter(address _router) external onlyStrategist {
        require(_router != address(0), "Must be valid address");
        _setMightyJoeRouter(_router);
    }

    function setJoeFactory(address _factory) external onlyStrategist {
        require(_factory != address(0), "Must be valid address");
        _setJoeFactory(_factory);
    }

    function setJoeRewarder(address _rewarder) external onlyStrategist {
        require(_rewarder != address(0), "Must be valid Address");
        joeRewarder = IJoeRewarder(_rewarder);
    }

    function setMinJoe(uint256 _minJoe) external onlyStrategist {
        minJoe = _minJoe;
    }

    function setMinWant(uint256 _minWant) external onlyStrategist {
        minWant = _minWant;
    }

    function balanceOfToken(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 deposits = getCurrentPosition();

        uint256 _claimablejoe = predictjoeAccrued();
        uint256 currentjoe = balanceOfToken(Joe);

        // Use touch price. it doesnt matter if we are wrong as this is not used for decision making
        uint256 estimatedWant = _checkPrice(Joe, address(want), _claimablejoe.add(currentjoe));
        uint256 conservativeWant = estimatedWant.mul(9).div(10); //10% pessimist

        return balanceOfToken(address(want)).add(deposits).add(conservativeWant);
    }

    // This function makes a prediction on how much joe is accrued
    // It is not 100% accurate as it uses current balances in joeound to predict into the past
    function predictjoeAccrued() public view returns (uint256) {
        uint256 balance = JToken.balanceOf(address(this));
        if (balance == 0) {
            return 0; // should be impossible to have 0 balance and positive joe accrued
        }

        //MAY NEEED to call reward distributor not joetroller
        uint256 rewardSupplyRate = joeRewarder.rewardSupplySpeeds(0, address(JToken));
     
        //total supply needs to be echanged to underlying using exchange rate
        uint256 totalSupply = JToken.totalSupply();
       
        //Rate * (Deposits / supply)
        uint256 blockShare = rewardSupplyRate.mul(balance).div(totalSupply);
    
        //last time we ran harvest
        uint256 timeSinceLast = block.timestamp.sub(lastHarvest);

        return timeSinceLast.mul(blockShare);
    }

    //Returns the current position
    //WARNING - this returns just the balance at last time someone touched the JToken token. Does not accrue interst in between
    //JToken is very active so not normally an issue.
    function getCurrentPosition() public view returns (uint256 deposits) {
        return JToken.balanceOf(address(this)).mul(JToken.exchangeRateStored()).div(1e18);
    }

    //statechanging version
    function getLivePosition() public returns (uint256) {
        return JToken.balanceOf(address(this)).mul(JToken.exchangeRateCurrent()).div(1e18);
    }

    function getBalanceOfUnderlying() external returns(uint256) {
        return JToken.balanceOfUnderlying(address(this));
    }

    function exchnageRate() external returns (uint256 ) {
        return JToken.exchangeRateCurrent();
    }

    function updateJoe() public returns(uint256) {
        JToken.exchangeRateCurrent();
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
        harvestJoe();
        //swap rewards to main want
        disposeOfJoe();

        //get base want balance
        uint256 wantBalance = balanceOfToken(address(want));
        updateJoe();
        uint256 balance = wantBalance.add(getCurrentPosition());

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
        //check what we have available
        uint256 wantBalance = balanceOfToken(address(want));
        updateJoe();
        if (_amountNeeded > wantBalance) {
            
            uint256 amountToFree = _amountNeeded.sub(wantBalance);

            withdrawSome(amountToFree);

            wantBalance = balanceOfToken(address(want));

            //if we need more than avaialble find out how much
            if (_amountNeeded > wantBalance) {
                
                harvestJoe();
                disposeOfJoe();
                wantBalance = balanceOfToken(address(want));

                //check if we got enough tokens from the withdraw
                if (wantBalance >= _amountNeeded) {
                    _liquidatedAmount = _amountNeeded;
                } else {
                    _liquidatedAmount = wantBalance;
                    _loss = _amountNeeded.sub(wantBalance);
                }
            
            } else {
                _liquidatedAmount = _amountNeeded;
            }

            //if we have enough free tokens to start with
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        harvestJoe();
        disposeOfJoe();
        JToken.redeem(JToken.balanceOf(address(this)));

        return balanceOfToken(address(want));
    }

    function depositSome(uint256 _amount) internal {
        if (_amount < minWant) {
            return;
        }

        JToken.mint(_amount);
    }

    function withdrawSome(uint256 _amountNeeded) internal {
        //should have already called LivePosition()
        uint256 deposited = getCurrentPosition();

        if(_amountNeeded > deposited) {
            JToken.redeem(JToken.balanceOf(address(this)));
        } else {
            JToken.redeemUnderlying(_amountNeeded);
        }
    }

    function harvestJoe() public {
        //harvest that mofo
        if (predictjoeAccrued() < minJoe) {
            return;
        }
        
        JTokenI[] memory tokens = new JTokenI[](1);
        address[] memory addresses = new address[](1);
        tokens[0] = JTokenI(address(JToken));
        addresses[0] = payable(address(this));

        joetroller.claimReward(0, addresses, tokens, false, true );
        lastHarvest = block.timestamp;
    }

    //sell joe function
    function disposeOfJoe() public {
        uint256 _joe = balanceOfToken(Joe);
        if (_joe < minJoe) {
            return;
        }

        _swapFrom(Joe, address(want), _joe);
    }

    function prepareMigration(address _newStrategy) internal override {
        harvestJoe();
        IERC20 _joe = IERC20(Joe);
        uint256 _joeB = balanceOfToken(Joe);
        if (_joeB > 0) {
            _joe.safeTransfer(_newStrategy, _joeB);
        }

        JToken.transfer(_newStrategy, JToken.balanceOf(address(this)));
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        protected[0] = address(JToken);
        protected[1] = Joe;

        return protected;
    }

    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _checkPrice(wavax, address(want), _amtInWei);
    }
}