// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries

import {
    BaseStrategy,
    StrategyParams
} from "../BaseStrategy.sol";
import { SafeERC20, SafeMath, IERC20, Address } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

import "../interfaces/joe/IJoetroller.sol";
import "../interfaces/joe/IJToken.sol";
import "../interfaces/Uni/IUniswapV2Router02.sol";
import "../interfaces/IERC20Extended.sol";


contract JoeFoSho is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // Comptroller address for joetroller.finance
    IJoetroller public joetroller;

    //Only three tokens we use
    address public joe;
    address public weth;
    IJToken public JToken;

    IUniswapV2Router02 public currentRouter; //uni v2 forks only

    uint256 public collateralTarget; // total borrow / total supply ratio we are targeting (100% = 1e18)
    uint256 private blocksToLiquidationDangerZone; // minimum number of blocks before liquidation

    uint256 public minWant; // minimum amount of want to act on

    // Rewards handling
    bool public dontClaimjoe; // enable/disables joe claiming
    uint256 public minjoeToSell; // minimum amount of joe to be sold

    uint256 public iterations; //number of loops we do

    bool public forceMigrate;
    bool public withdrawChecks;

    constructor(
        address _vault, 
        address _JToken, 
        address _router, 
        address _joe, 
        address _joetroller, 
        address _weth
    ) public BaseStrategy(_vault) {
        _initializeThis(_JToken, _router, _joe, _joetroller, _weth);
    }

    function approveTokenMax(address token, address spender) internal {
        IERC20(token).safeApprove(spender, type(uint256).max);
    }

    function name() external view override returns (string memory) {
        return "JoeFoSho";
    }

    function initialize(
        address _vault, 
        address _JToken, 
        address _router, 
        address _joe, 
        address _joetroller, 
        address _weth
    ) external {
        _initialize(_vault, msg.sender, msg.sender, msg.sender);
        _initializeThis(_JToken, _router, _joe, _joetroller, _weth);
    }

    function _initializeThis(
        address _JToken, 
        address _router, 
        address _joe, 
        address _joetroller, 
        address _weth
    ) internal {
        JToken = IJToken(_JToken);
        joe = _joe;
        weth = _weth;
        joetroller = IJoetroller(_joetroller);
        require(IERC20Extended(address(want)).decimals() <= 18); // dev: want not supported
        currentRouter = IUniswapV2Router02(_router);

        //pre-set approvals
        approveTokenMax(joe, address(currentRouter));
        approveTokenMax(address(want), address(JToken));

        // You can set these parameters on deployment to whatever you want
        maxReportDelay = 86400; // once per 24 hours
        profitFactor = 100_000; // multiple before triggering harvest
        debtThreshold = 1e30;
        iterations = 3; //standard 6

        // set minWant to 1e-5 want
        minWant = uint256(uint256(10)**uint256((IERC20Extended(address(want))).decimals())).div(1e5);
        minjoeToSell = 0.001 ether; //may need to be changed depending on what joe is
        collateralTarget = 0.73 ether;
        blocksToLiquidationDangerZone = 46500;
    }

    /*
     * Control Functions
     */

    function setWithdrawChecks(bool _withdrawChecks) external management {
        withdrawChecks = _withdrawChecks;
    }

    function setDontClaimjoe(bool _dontClaimjoe) external management {
        dontClaimjoe = _dontClaimjoe;
    }

    function setRouter(address _currentV2Router) external onlyGovernance {
        currentRouter = IUniswapV2Router02(_currentV2Router);
    }

    function setForceMigrate(bool _force) external onlyGovernance {
        forceMigrate = _force;
    }

    function setMinjoeToSell(uint256 _minjoeToSell) external management {
        minjoeToSell = _minjoeToSell;
    }

    function setIterations(uint256 _iterations) external management {
        require(_iterations > 0 && _iterations <= 100);
        iterations = _iterations;
    }

    function setMinWant(uint256 _minWant) external management {
        minWant = _minWant;
    }

    function setCollateralTarget(uint256 _collateralTarget) external management {
        (, uint256 collateralFactorMantissa, ) = joetroller.markets(address(JToken));
        require(collateralFactorMantissa > _collateralTarget);
        collateralTarget = _collateralTarget;
    }

    /*
     * Base External Facing Functions
     */
    /*
     * An accurate estimate for the total amount of assets (principle + return)
     * that this strategy is currently managing, denominated in terms of want tokens.
     */
    function estimatedTotalAssets() public view override returns (uint256) {
        (uint256 deposits, uint256 borrows) = getCurrentPosition();

        uint256 _claimablejoe = predictjoeAccrued();
        uint256 currentjoe = balanceOfToken(joe);

        // Use touch price. it doesnt matter if we are wrong as this is not used for decision making
        uint256 estimatedWant = priceCheck(joe, address(want), _claimablejoe.add(currentjoe));
        uint256 conservativeWant = estimatedWant.mul(9).div(10); //10% pessimist

        return balanceOfToken(address(want)).add(deposits).add(conservativeWant).sub(borrows);
    }

    function balanceOfToken(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
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

    /*
     * Provide a signal to the keeper that `tend()` should be called.
     * (keepers are always reimbursed by yEarn)
     *
     * NOTE: this call and `harvestTrigger` should never return `true` at the same time.
     * tendTrigger should be called with same gasCost as harvestTrigger
     */
    function tendTrigger(uint256 gasCost) public view override returns (bool) {
        if (harvestTrigger(gasCost)) {
            //harvest takes priority
            return false;
        }

        return getblocksUntilLiquidation() <= blocksToLiquidationDangerZone;
    }

    //WARNING. manipulatable and simple routing. Only use for safe functions
    function priceCheck(
        address start,
        address end,
        uint256 _amount
    ) public view returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        if(start == end){
            return _amount;
        }

        uint256[] memory amounts = currentRouter.getAmountsOut(_amount, getTokenOutPathV2(start, end));

        return amounts[amounts.length - 1];

    }

    /*****************
     * Public non-base function
     ******************/

    //Calculate how many blocks until we are in liquidation based on current interest rates
    //WARNING does not include joeounding so the estimate becomes more innacurate the further ahead we look
    //equation. Compound doesn't include compounding for most blocks
    //((deposits*colateralThreshold - borrows) / (borrows*borrowrate - deposits*colateralThreshold*interestrate));

    function getblocksUntilLiquidation() public view returns (uint256) {
        (, uint256 collateralFactorMantissa, ) = joetroller.markets(address(JToken));

        (uint256 deposits, uint256 borrows) = getCurrentPosition();

        uint256 borrrowRate; // = JToken.borrowRatePerBlock();

        uint256 supplyRate;// = JToken.supplyRatePerBlock();

        uint256 collateralisedDeposit = deposits.mul(collateralFactorMantissa).div(1e18);

        uint256 denom1 = borrows.mul(borrrowRate);
        uint256 denom2 = collateralisedDeposit.mul(supplyRate);

        if (denom2 >= denom1) {
            return type(uint256).max;
        } else {
            uint256 numer = collateralisedDeposit.sub(borrows);
            uint256 denom = denom1.sub(denom2);
            //minus 1 for this block
            return numer.mul(1e18).div(denom);
        }
    }

    // This function makes a prediction on how much joe is accrued
    // It is not 100% accurate as it uses current balances in joeound to predict into the past
    function predictjoeAccrued() public view returns (uint256) {
        (uint256 deposits, uint256 borrows) = getCurrentPosition();
        if (deposits == 0) {
            return 0; // should be impossible to have 0 balance and positive joe accrued
        }

        uint256 distributionPerSecondSupply = joetroller.rewardSupplySpeeds(address(JToken));
        uint256 distributionPerSecondBorrow = joetroller.rewardBorrowSpeeds(address(JToken));

        uint256 totalBorrow; // = JToken.totalBorrows();

        //total supply needs to be echanged to underlying using exchange rate
        uint256 totalSupplyJToken; // = JToken.totalSupply();
        uint256 totalSupply = totalSupplyJToken.mul(JToken.exchangeRateStored()).div(1e18);

        uint256 blockShareSupply = 0;
        if (totalSupply > 0) {
            blockShareSupply = deposits.mul(distributionPerSecondSupply).div(totalSupply);
        }

        uint256 blockShareBorrow = 0;
        if (totalBorrow > 0) {
            blockShareBorrow = borrows.mul(distributionPerSecondBorrow).div(totalBorrow);
        }

        //how much we expect to earn per block
        uint256 blockShare = blockShareSupply.add(blockShareBorrow);

        //last time we ran harvest
        uint256 lastReport = vault.strategies(address(this)).lastReport;
        uint256 timeSinceLast = (block.timestamp.sub(lastReport));

        return timeSinceLast.mul(blockShare);
    }

    //Returns the current position
    //WARNING - this returns just the balance at last time someone touched the JToken token. Does not accrue interst in between
    //JToken is very active so not normally an issue.
    function getCurrentPosition() public view returns (uint256 deposits, uint256 borrows) {
        (uint256 err, uint256 JTokenBalance, uint256 borrowBalance, uint256 exchangeRate) = JToken.getAccountSnapshot(address(this));
        borrows = borrowBalance;

        deposits = JTokenBalance.mul(exchangeRate).div(1e18);
    }

    //statechanging version
    function getLivePosition() public returns (uint256 deposits, uint256 borrows) {
        deposits = JToken.balanceOfUnderlying(address(this));

        //we can use non state changing now because we updated state with balanceOfUnderlying call
        borrows;// = JToken.borrowBalanceStored(address(this));
    }

    //Same warning as above
    function netBalanceLent() public view returns (uint256) {
        (uint256 deposits, uint256 borrows) = getCurrentPosition();
        return deposits.sub(borrows);
    }

    /***********
     * internal core logic
     *********** */
    /*
     * A core method.
     * Called at beggining of harvest before providing report to owner
     * 1 - claim accrued joe
     * 2 - if enough to be worth it we sell
     * 3 - because we lose money on our loans we need to offset profit from joe.
     */
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

        if (balanceOfToken(address(JToken)) == 0) {
            uint256 wantBalance = balanceOfToken(address(want));
            //no position to harvest
            //but we may have some debt to return
            //it is too expensive to free more debt in this method so we do it in adjust position
            _debtPayment = Math.min(wantBalance, _debtOutstanding);
            return (_profit, _loss, _debtPayment);
        }

        (uint256 deposits, uint256 borrows) = getLivePosition();

        //claim joe accrued
        _claimjoe();
        //sell joe
        _disposeOfjoe();

        uint256 wantBalance = balanceOfToken(address(want));

        uint256 investedBalance = deposits.sub(borrows);
        uint256 balance = investedBalance.add(wantBalance);

        uint256 debt = vault.strategies(address(this)).totalDebt;

        //Balance - Total Debt is profit
        if (balance > debt) {
            _profit = balance.sub(debt);
            if (wantBalance < _profit) {
                //all reserve is profit
                _profit = wantBalance;
            } else if (wantBalance > _profit.add(_debtOutstanding)) {
                _debtPayment = _debtOutstanding;
            } else {
                _debtPayment = wantBalance.sub(_profit);
            }
        } else {
            //we will lose money until we claim joe then we will make money
            //this has an unintended side effect of slowly lowering our total debt allowed
            _loss = debt.sub(balance);
            _debtPayment = Math.min(wantBalance, _debtOutstanding);
        }
    }

    /*
     * Second core function. Happens after report call.
     *
     * Similar to deposit function from V1 strategy
     */
    function adjustPosition(uint256 _debtOutstanding) internal override {
        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            return;
        }

        //we are spending all our cash unless we have debt outstanding
        uint256 _wantBal = balanceOfToken(address(want));
        if (_wantBal < _debtOutstanding) {
            //this is graceful withdrawal. dont use backup
            //we use more than 1 because withdrawunderlying causes problems with 1 token due to different decimals
            if (balanceOfToken(address(JToken)) > 1) {
                _withdrawSome(_debtOutstanding.sub(_wantBal));
            }

            return;
        }

        (uint256 position, bool deficit) = _calculateDesiredPosition(_wantBal.sub(_debtOutstanding), true);

        //if we are below minimun want change it is not worth doing
        //need to be careful in case this pushes to liquidation
        uint256 i = 0;
        while (position > minWant) {
            position = position.sub(_noFlashLoan(position, deficit));
            if (i >= iterations) {
                break;
            }
            i++;
        }

    }

    /*************
     * Very important function
     * Input: amount we want to withdraw
     *       cannot be more than we have
     * Returns amount we were able to withdraw. notall if user has some balance left
     *
     * Deleverage position -> redeem our JTokens
     ******************** */
    function _withdrawSome(uint256 _amount) internal returns (bool notAll) {
        (uint256 position, bool deficit) = _calculateDesiredPosition(_amount, false);

        //If there is no deficit we dont need to adjust position
        //if the position change is tiny do nothing
        if (deficit && position > minWant) {

            uint8 i = 0;
            //position will equal 0 unless we haven't been able to deleverage enough with flash loan
            //if we are not in deficit we dont need to do flash loan
            while (position > minWant.add(100)) {
                position = position.sub(_noFlashLoan(position, true));
                i++;
                //A limit set so we don't run out of gas
                if (i >= iterations) {
                    notAll = true;
                    break;
                }
            }
        }
        //now withdraw
        //if we want too much we just take max

        //This part makes sure our withdrawal does not force us into liquidation
        (uint256 depositBalance, uint256 borrowBalance) = getCurrentPosition();

        uint256 tempColla = collateralTarget;

        uint256 reservedAmount = 0;
        if (tempColla == 0) {
            tempColla = 1e15; // 0.001 * 1e18. lower we have issues
        }

        reservedAmount = borrowBalance.mul(1e18).div(tempColla);
        if (depositBalance >= reservedAmount) {
            uint256 redeemable = depositBalance.sub(reservedAmount);
            uint256 balan = JToken.balanceOf(address(this));
            if (balan > 1) {
                if (redeemable < _amount) {
                    JToken.redeemUnderlying(redeemable);
                } else {
                    JToken.redeemUnderlying(_amount);
                }
            }
        }

        if (collateralTarget == 0 && balanceOfToken(address(want)) > borrowBalance) {
            JToken.repayBorrow(borrowBalance);
        }
    }

    /***********
     *  This is the main logic for calculating how to change our lends and borrows
     *  Input: balance. The net amount we are going to deposit/withdraw.
     *  Input: dep. Is it a deposit or withdrawal
     *  Output: position. The amount we want to change our current borrow position.
     *  Output: deficit. True if we are reducing position size
     *
     *  For instance deficit =false, position 100 means increase borrowed balance by 100
     ****** */
    function _calculateDesiredPosition(uint256 balance, bool dep) internal returns (uint256 position, bool deficit) {
        //we want to use statechanging for safety
        (uint256 deposits, uint256 borrows) = getLivePosition();

        //When we unwind we end up with the difference between borrow and supply
        uint256 unwoundDeposit = deposits.sub(borrows);

        //we want to see how close to collateral target we are.
        //So we take our unwound deposits and add or remove the balance we are are adding/removing.
        //This gives us our desired future undwoundDeposit (desired supply)

        uint256 desiredSupply = 0;
        if (dep) {
            desiredSupply = unwoundDeposit.add(balance);
        } else {
            if (balance > unwoundDeposit) {
                balance = unwoundDeposit;
            }
            desiredSupply = unwoundDeposit.sub(balance);
        }

        //(ds *c)/(1-c)
        uint256 num = desiredSupply.mul(collateralTarget);
        uint256 den = uint256(1e18).sub(collateralTarget);

        uint256 desiredBorrow = num.div(den);
        if (desiredBorrow > 1e5) {
            //stop us going right up to the wire
            desiredBorrow = desiredBorrow.sub(1e5);
        }

        //now we see if we want to add or remove balance
        // if the desired borrow is less than our current borrow we are in deficit. so we want to reduce position
        if (desiredBorrow < borrows) {
            deficit = true;
            position = borrows.sub(desiredBorrow); //safemath check done in if statement
        } else {
            //otherwise we want to increase position
            deficit = false;
            position = desiredBorrow.sub(borrows);
        }
    }

    /*
     * Liquidate as many assets as possible to `want`, irregardless of slippage,
     * up to `_amount`. Any excess should be re-invested here as well.
     */
    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _amountFreed, uint256 _loss) {
        uint256 _balance = balanceOfToken(address(want));
        uint256 assets = netBalanceLent().add(_balance);

        (uint256 deposits, uint256 borrows) = getLivePosition();
        if (assets < _amountNeeded) {
            //if we cant afford to withdraw we take all we can
            //withdraw all we can

            //1 token causes rounding error with withdrawUnderlying
            if (balanceOfToken(address(JToken)) > 1) {
                _withdrawSome(deposits.sub(borrows));
            }

            _amountFreed = Math.min(_amountNeeded, balanceOfToken(address(want)));
        } else {
            if (_balance < _amountNeeded) {
                _withdrawSome(_amountNeeded.sub(_balance));

                //overflow error if we return more than asked for
                _amountFreed = Math.min(_amountNeeded, balanceOfToken(address(want)));
            } else {
                _amountFreed = _amountNeeded;
            }
        }

        // To prevent the vault from moving on to the next strategy in the queue
        // when we return the amountRequested minus dust, take a dust sized loss
        if (_amountFreed < _amountNeeded) {
            uint256 diff = _amountNeeded.sub(_amountFreed);
            if (diff <= minWant) {
                _loss = diff;
            }
        }

        if (withdrawChecks) {
            require(_amountNeeded == _amountFreed.add(_loss)); // dev: fourThreeProtection
        }
    }

    function _claimjoe() internal {
        if (dontClaimjoe) {
            return;
        }
        IJToken[] memory tokens = new IJToken[](1);
        tokens[0] = JToken;

        //joetroller.claimReward(0, address(this), tokens);
        //joetroller.claimReward(0, address(this), tokens);
    }

    //sell joe function
    function _disposeOfjoe() internal {
        uint256 _joe = balanceOfToken(joe);
        if (_joe < minjoeToSell) {
            return;
        }

        currentRouter.swapExactTokensForTokens(_joe, 0, getTokenOutPathV2(joe, address(want)), address(this), now);

    }

    function getTokenOutPathV2(address _tokenIn, address _tokenOut) internal view returns (address[] memory _path) {
        bool isWeth = _tokenIn == weth || _tokenOut == weth;
        _path = new address[](isWeth ? 2 : 3);
        _path[0] = _tokenIn;

        if (isWeth) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = weth;
            _path[2] = _tokenOut;
        }
    }

    //lets leave
    //if we can't deleverage in one go set collateralFactor to 0 and call harvest multiple times until delevered
    function prepareMigration(address _newStrategy) internal override {
        if (!forceMigrate) {
            (uint256 deposits, uint256 borrows) = getLivePosition();
            _withdrawSome(deposits.sub(borrows));

            (, , uint256 borrowBalance, ) = JToken.getAccountSnapshot(address(this));

            require(borrowBalance < 10_000);

            IERC20 _joe = IERC20(joe);
            uint256 _joeB = balanceOfToken(address(_joe));
            if (_joeB > 0) {
                _joe.safeTransfer(_newStrategy, _joeB);
            }
        }
    }

    //Three functions covering normal leverage and deleverage situations
    // max is the max amount we want to increase our borrowed balance
    // returns the amount we actually did
    function _noFlashLoan(uint256 max, bool deficit) internal returns (uint256 amount) {
        //we can use non-state changing because this function is always called after _calculateDesiredPosition
        (uint256 lent, uint256 borrowed) = getCurrentPosition();

        //if we have nothing borrowed then we can't deleverage any more
        if (borrowed == 0 && deficit) {
            return 0;
        }
        if(lent == 0){
            JToken.mint(balanceOfToken(address(want)));
            (lent, borrowed) = getCurrentPosition();
        }

        (, uint256 collateralFactorMantissa, ) = joetroller.markets(address(JToken));

        if (deficit) {
            amount = _normalDeleverage(max, lent, borrowed, collateralFactorMantissa);
        } else {
            amount = _normalLeverage(max, lent, borrowed, collateralFactorMantissa);
        }
    }

    //maxDeleverage is how much we want to reduce by
    function _normalDeleverage(
        uint256 maxDeleverage,
        uint256 lent,
        uint256 borrowed,
        uint256 collatRatio
    ) internal returns (uint256 deleveragedAmount) {
        uint256 theoreticalLent = 0;

        //collat ration should never be 0. if it is something is very wrong... but just incase
        if (collatRatio != 0) {
            theoreticalLent = borrowed.mul(1e18).div(collatRatio);
        }
        deleveragedAmount = lent.sub(theoreticalLent);

        if (deleveragedAmount >= borrowed) {
            deleveragedAmount = borrowed;
        }
        if (deleveragedAmount >= maxDeleverage) {
            deleveragedAmount = maxDeleverage;
        }
        uint256 exchangeRateStored = JToken.exchangeRateStored();
        //redeemTokens = redeemAmountIn * 1e18 / exchangeRate. must be more than 0
        //a rounding error means we need another small addition
        if (deleveragedAmount.mul(1e18) >= exchangeRateStored && deleveragedAmount > 10) {
            deleveragedAmount = deleveragedAmount.sub(uint256(10));
            JToken.redeemUnderlying(deleveragedAmount);

            //our borrow has been increased by no more than maxDeleverage
            JToken.repayBorrow(deleveragedAmount);
        }
    }

    //maxDeleverage is how much we want to increase by
    function _normalLeverage(
        uint256 maxLeverage,
        uint256 lent,
        uint256 borrowed,
        uint256 collatRatio
    ) internal returns (uint256 leveragedAmount) {
        uint256 theoreticalBorrow = lent.mul(collatRatio).div(1e18);

        leveragedAmount = theoreticalBorrow.sub(borrowed);

        if (leveragedAmount >= maxLeverage) {
            leveragedAmount = maxLeverage;
        }
        if (leveragedAmount > 10) {
            leveragedAmount = leveragedAmount.sub(uint256(10));
            JToken.borrow(leveragedAmount);
            JToken.mint(balanceOfToken(address(want)));
        }
    }

    //emergency function that we can use to deleverage manually if something is broken
    function manualDeleverage(uint256 amount) external management {
        require(JToken.redeemUnderlying(amount) == 0);
        require(JToken.repayBorrow(amount) == 0);
    }

    //emergency function that we can use to deleverage manually if something is broken
    function manualReleaseWant(uint256 amount) external onlyGovernance {
        require(JToken.redeemUnderlying(amount) == 0); // dev: !manual-release-want
    }

    function protectedTokens() internal view override returns (address[] memory) {}

    //returns our current collateralisation ratio. Should be compared with collateralTarget
    function storedCollateralisation() public view returns (uint256 collat) {
        (uint256 lend, uint256 borrow) = getCurrentPosition();
        if (lend == 0) {
            return 0;
        }
        collat = uint256(1e18).mul(borrow).div(lend);
    }

    // -- Internal Helper functions -- //

    function ethToWant(uint256 _amtInWei) public view override returns (uint256) {
        return priceCheck(weth, address(want), _amtInWei);
    }

    function liquidateAllPositions() internal override returns (uint256 _amountFreed) {
        (_amountFreed, ) = liquidatePosition(vault.debtOutstanding());
        (uint256 deposits, uint256 borrows) = getCurrentPosition();

        uint256 position = deposits.sub(borrows);

        //we want to revert if we can't liquidateall
        if (!forceMigrate) {
            require(position < minWant);
        }
    }

    function mgtm_check() internal view {
        require(msg.sender == governance() || msg.sender == vault.management() || msg.sender == strategist, "!authorized");
    }

    modifier management() {
        mgtm_check();
        _;
    }
}