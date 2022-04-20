// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "../BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

// Import interfaces for many popular DeFi projects, or add your own!
import "../interfaces/curve/ICurveFi.sol";
import "../interfaces/curve/IGauge.sol";
import "../interfaces/uni/IUniswapV2Router02.sol";
import "../interfaces/aave/V2/IAaveIncentivesController.sol";
import "../interfaces/aave/V2/ILendingPool.sol";
import "../interfaces/aave/V2/IProtocolDataProvider.sol";
import "../interfaces/chainlink/AggregatorV3Interface.sol";

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}

//TODO
// add a rebalance function to call even if there is no new funds
//check if eth/btc is out of wack. 
//Can just borrow one if collat ratio is below the target and deposit into curve or remove one_coin() then swap to repay debt if above

contract CaaveNew is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IUniswapV2Router02 router;

    //aave Contracts
    ILendingPool lendingPool; //0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9
    IProtocolDataProvider private constant protocolDataProvider =
        IProtocolDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);
    IAaveIncentivesController private constant aaveIncentivesController = 
        IAaveIncentivesController(0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5);

    //curve contracts
    ICurveFi public crvPool; // 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46\
    IGauge public gauge; // 0x6955a55416a06839309018A8B0cB72c4DDC11f15
    address public constant crvToken = address(0xc4AD29ba4B3c580e6D59105FFf484999997675Ff);

    //ChainLink Price Feeds
    AggregatorV3Interface internal btcPriceFeed = AggregatorV3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
    AggregatorV3Interface internal ethPriceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    //borrow tokens
    address public constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant wbtc = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    //reward tokens
    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant aave = address(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);

    //aave tokens
    address public aWant; 
    address public varWbtc; 
    address public varWeth; 

    //used along the denominator or 10,000
    uint256 targetCollatRatio = 5000; // The LTV we are levering up to
    uint256 lowerCollatBound = 4500; // the lower bound that will cause us to rebalance
    uint256 upperCollatBound = 5500; //the upper bound that will cause us to rebalance
    uint256 maxCollatRatio = 6500; // Closest to liquidation we'll risk
    uint256 curveMultiplier = 6000; // amount to multiply deposits by to determin total curve deposits
    uint256 aaveMultiplier = 8000; // amount to multiply deposits by to determine how much to put into Aave
    uint256 third = 3333; // get a third with den for deposit calcs

    uint256 maxSingleInvest;
    uint256 slippageProtectionIn = 30; //out of 10000. 50 = 0.5%
    uint256 slippageProtectionOut = 30; //out of 10000. 50 = 0.5%
    uint256 constant DENOMINATOR = 10_000;
    uint256 constant denomPrecision = 4;

    //underlying token values
    uint256 wantIndex = 0;
    uint256 wbtcIndex = 1;
    uint256 wethIndex = 2;

    mapping(address => uint256) index;

    uint256 want_decimals;
    uint256 minWant;
    uint256 minCrv;
    uint256 minAave;

    uint256 lastHarvest;
    uint256 minReport = 0; //1000

    constructor(
        address _vault,
        address _lendingPool,
        address _crvPool,
        address _gauge,
        address _router
    ) public BaseStrategy(_vault) {
        _initializeThis(_lendingPool, _crvPool, _gauge, _router);
    }

    function _initializeThis(
        address _lendingPool,
        address _crvPool,
        address _gauge,
        address _router
    ) internal {
        setcrvPool(_crvPool);
        setGauge(_gauge);
        setRouter(_router);
        setLendingPool(_lendingPool);

        address _aToken;
        address _debtToken;
         // Set aave tokens
        (_aToken, , ) =
            protocolDataProvider.getReserveTokensAddresses(address(want));
        aWant = _aToken;

        (, , _debtToken) =
            protocolDataProvider.getReserveTokensAddresses(weth);
        varWeth = _debtToken;

        (, , _debtToken) =
            protocolDataProvider.getReserveTokensAddresses(wbtc);
        varWbtc = _debtToken;

        want_decimals = IERC20Extended(address(want)).decimals();
        minWant = 10 ** (want_decimals.sub(3));
        minCrv = 10000000000000000; 
        minAave = 10000000000; 
        maxSingleInvest = 10 ** (want_decimals.add(6));
        lastHarvest = block.timestamp;

        //Set index mapping for crv swap
        index[address(want)] = wantIndex;
        index[wbtc] = wbtcIndex;
        index[weth] = wethIndex;
    }

    function setcrvPool(address _crvPool) internal {
        IERC20(wbtc).approve(_crvPool, type(uint256).max);
        IERC20(weth).approve(_crvPool, type(uint256).max);
        want.approve(_crvPool, type(uint256).max);
        IERC20(crvToken).approve(_crvPool, type(uint256).max);

        crvPool = ICurveFi(_crvPool);
    }

    function setGauge(address _gauge) internal {
        //approve gauge
        IERC20(crvToken).approve(_gauge, type(uint256).max);

        gauge = IGauge(_gauge);
    }

    function setRouter(address _router) internal {
        want.approve(_router, type(uint256).max);
        IERC20(aave).approve(_router, type(uint256).max);
        IERC20(crv).approve(_router, type(uint256).max);

        router = IUniswapV2Router02(_router);
    }

    function setLendingPool(address _pool) internal {
        want.approve(_pool, type(uint256).max);
        IERC20(wbtc).approve(_pool, type(uint256).max);
        IERC20(weth).approve(_pool, type(uint256).max);

        lendingPool = ILendingPool(_pool);
    }

    function updateRouter(address _router) external onlyAuthorized {
        require(_router != address(0), "Need real address");

        //decrease allowances
        uint256 _allowance = want.allowance(address(this), address(router));
        want.safeDecreaseAllowance(address(router), _allowance);
        _allowance = IERC20(aave).allowance(address(this), address(router));
        IERC20(aave).safeDecreaseAllowance(address(router), _allowance);
        _allowance = IERC20(crv).allowance(address(this), address(router));
        IERC20(crv).safeDecreaseAllowance(address(router), _allowance);

        setRouter(_router);
    }

    function updateMaxSingleInvest(uint256 _maxSingleInvest) external onlyAuthorized {
        maxSingleInvest = _maxSingleInvest;
    }

    function updateSlippageProtectionIn(uint256 _slippageProtectionIn) external onlyAuthorized {
        slippageProtectionIn = _slippageProtectionIn;
    }

    function updateSlippageProtectionOut(uint256 _slippageProtectionOut) external onlyAuthorized {
        slippageProtectionOut = _slippageProtectionOut;
    }

    function updateMinCrv(uint256 _min) external onlyAuthorized {
        minCrv = _min;
    }

    function updateMinAave(uint256 _min) external onlyAuthorized {
        minAave = _min;
    }

    function updateMinWant(uint256 _min) external onlyAuthorized {
        minWant = _min;
    }

    function updateMinReport(uint256 _min) external onlyAuthorized {
        minReport = _min;
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "Caave";
    }

    function balanceOfToken(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function toWant(uint256 _lpBalance) public view returns (uint256) {
        //return _lpBalance.mul(crvPool.get_virtual_price()).div(1e28);
        if (_lpBalance == 0) {
            return 0;
        }

        return crvPool.calc_withdraw_one_coin(_lpBalance, wantIndex);
    }

    //can calc a third of each
    function toShares(uint256 _wantAmount) public view returns (uint256) {
        uint256[3] memory amounts;
        uint256 dollars = aThird(_wantAmount);
        amounts[wantIndex] = dollars;
        amounts[wbtcIndex] = wantToBtc(dollars);
        amounts[wethIndex] = wantToEth(dollars);
        return crvPool.calc_token_amount(amounts, true);
    }

    function lpBalance() public view returns (uint256) {
        return gauge.balanceOf(address(this)).add(balanceOfToken(crvToken));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 wantBalance = want.balanceOf(address(this));

        uint256 rewards = estimatedRewards();

        //need to get the net position of aave deposits - borrowed
        uint256 aaveBalance = getAaveBalance();

        uint256 poolBalance = toWant(lpBalance());

        return wantBalance.add(rewards).add(aaveBalance).add(poolBalance);
    }

    function getAaveBalance() public view returns (uint256) {
        (uint256 totalCollateralETH, uint256 totalDebtETH, , , , ) = lendingPool.getUserAccountData(address(this));

        return ethToWant(totalCollateralETH.add(totalDebtETH));
    }

    function getAavePositions() public view returns (uint256 deposits, uint256 borrows) {
        (, uint256 totalDebtETH, , , , ) = lendingPool.getUserAccountData(address(this));
        deposits = balanceOfToken(aWant);
        borrows = ethToWant(totalDebtETH); 
    }

    function estimatedRewards() public view returns (uint256) {
        uint256 crvWant = _checkPrice(crv, address(want), balanceOfToken(crv).add(predictCrvAccrued()));
        uint256 aaveWant = _checkPrice(aave, address(want), balanceOfToken(aave).add(predictAaveAccrued()));

        uint256 _bal = crvWant.add(aaveWant);

        //call it 90% for safety sake
        return _bal.mul(90).div(100);
    }

    function predictCrvAccrued() public view returns (uint256) {
        return gauge.claimable_reward(address(this), crv);
    }

    function predictAaveAccrued() public view returns(uint256) {
        return aaveIncentivesController.getRewardsBalance(getAaveAssets(), address(this));
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
        uint256 wantBalance = want.balanceOf(address(this));

        //NEEED TO ADD AAVE BALANCE that cant be manipulated
        uint256 balance = wantBalance.add(toWant(lpBalance())).add(getAaveBalance());

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

                wantBalance = want.balanceOf(address(this));

                if (wantBalance < needed) {
                    if (_profit >= wantBalance) {
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
                wantBalance = want.balanceOf(address(this));
            }

            _debtPayment = Math.min(wantBalance, _debtOutstanding);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        //we are spending all our cash unless we have debt outstanding
        uint256 _wantBal = want.balanceOf(address(this));
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

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        uint256 wantBalance = want.balanceOf(address(this));
        if (wantBalance > _amountNeeded) {
            // if there is enough free want, let's use it
            return (_amountNeeded, 0);
        }

        // we need to free funds
        uint256 amountRequired = _amountNeeded.sub(wantBalance);
        withdrawSome(amountRequired);

        uint256 freeAssets = want.balanceOf(address(this));
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

        (uint256 deposits, uint256 borrows) = getAavePositions();

        //check current collat ratio
        uint256 collatRatio = getCollatRatio(deposits, borrows);

        //how much to deposit into aave
        uint256 deposit = _amount.mul(aaveMultiplier).div(DENOMINATOR);

        //If above upperbound we need to adjust collat
        // need to adjust max collat for decimals ie(wantDecimals - DENOMINTOR Precision)
        if (collatRatio > upperCollatBound.mul(10 **(want_decimals.sub(denomPrecision)))) {
            //check the collateral needed for current borrow
            uint256 collatNeeded = borrows.mul(DENOMINATOR).div(targetCollatRatio);
            uint256 diff = collatNeeded.sub(deposits);

            //check if _amount would bring the us back to under target
            if (diff > _amount) {
                //IF not withdraw enough to bring us back to target
                uint256 needed = collatNeeded.sub(deposits.add(_amount));
                deleverage(needed);
                _depositCollateral(
                    Math.min(
                        want.balanceOf(address(this)), 
                        _amount.add(aThird(needed.mul(curveMultiplier).div(DENOMINATOR)))
                    )
                );
                return;
            } else {
                //we can deposit a portion of _amount to bring us back to target
                if (_amount.sub(diff) < minWant) {
                    //not worth leveraging just deposit all
                    _depositCollateral(_amount);
                    return;
                }

                _depositCollateral(diff);
                _amount = _amount.sub(diff);
                deposit = _amount.mul(aaveMultiplier).div(DENOMINATOR);
            }
        }
        //ADd a section that check if under lower collatRatio

        //levereage as normal
        leverage(_amount, deposit);
    }

    function leverage(uint256 _amount, uint256 _deposit) internal {
        uint256 kept = _amount.sub(_deposit);

        _depositCollateral(_deposit);
        uint256 wbtcDeposit = _borrow(wbtc, wantToBtc(kept));
        uint256 wethDeposit = _borrow(weth, wantToEth(kept));

        uint256 expectedOut = toShares(kept.mul(3));
        //can add a function to pass in the exact amounts to calculate shares
        uint256 maxSlip = expectedOut.mul(DENOMINATOR.sub(slippageProtectionIn)).div(DENOMINATOR);

        uint256[3] memory amounts;
        amounts[wantIndex] = kept;
        amounts[wbtcIndex] = wbtcDeposit;
        amounts[wethIndex] = wethDeposit;

        crvPool.add_liquidity(amounts, maxSlip);

        gauge.deposit(balanceOfToken(crvToken));
    }

    function withdrawSome(uint256 _amount) internal returns (uint256) {
        if (_amount < minWant) {
            return 0;
        }

        uint256 needed = _amount;
        //check the currect collat ratio
        (uint256 deposits, uint256 borrows) = getAavePositions();

        //check current collat ratio
        uint256 collatRatio = getCollatRatio(deposits, borrows);

        //check if we can just remove excess collateral
        //ADJUST THE target for decimal
        if (collatRatio < targetCollatRatio.mul(1e14)) {
            uint256 wantedDeposit = getDepositFromBorrow(borrows);
            if (deposits.sub(wantedDeposit) >= _amount) {
                return _withdrawCollateral(_amount);
            } else {
                needed = _amount.sub(deposits.sub(wantedDeposit));
            }
        }

        uint256 dollars = deleverage(needed);

        if(dollars != 1) {
            return _withdrawCollateral(_amount.sub(dollars));
        } else {
            return want.balanceOf(address(this));
        }

        
    }

    function deleverage(uint256 _needed) internal returns (uint256){
          // dollars worth to pull from curve
        uint256 toWithdraw = _needed.mul(curveMultiplier).div(DENOMINATOR);
       
        //shares that need to be pulled out
        uint256 shares = toShares(toWithdraw);

        //check to see if we have enough
        if (shares > gauge.balanceOf(address(this))) {
            liquidateAllPositions();
            //return 1 so that withdrawSome doesnt try to overWithdraw
            return 1;
        }

        //withdraw from that gauge
        gauge.withdraw(shares);

        //1/3 of thecurve balance in dollars
        uint256 dollars = aThird(toWithdraw);

        //get min to be recieved
        uint256[3] memory amounts;
        amounts[wantIndex] = dollars.mul(DENOMINATOR.sub(slippageProtectionOut)).div(DENOMINATOR);
        amounts[wbtcIndex] = wantToBtc(dollars).mul(DENOMINATOR.sub(slippageProtectionOut)).div(DENOMINATOR);
        amounts[wethIndex] = wantToEth(dollars).mul(DENOMINATOR.sub(slippageProtectionOut)).div(DENOMINATOR);

        crvPool.remove_liquidity(shares, amounts);

        _repay(wbtc, Math.min(balanceOfToken(wbtc), balanceOfToken(varWbtc)));
        _repay(weth, Math.min(balanceOfToken(weth), balanceOfToken(varWeth)));

        return dollars;

    }

    function aThird(uint256 _amount) internal view returns (uint256) {
        return _amount.mul(third).div(DENOMINATOR);
    }

    function _depositCollateral(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        lendingPool.deposit(address(want), amount, address(this), 0);
        return amount;
    }

    function _withdrawCollateral(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        uint256 toWithdraw = Math.min(amount, balanceOfToken(aWant));
        return lendingPool.withdraw(address(want), toWithdraw, address(this));
    }

    function _repay(address _token, uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        return lendingPool.repay(_token, amount, 2, address(this));
    }

    function _borrow(address _token, uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        lendingPool.borrow(_token, amount, 2, 0, address(this));
        return amount;
    }

    function getCollatRatio(uint256 deposits, uint256 borrows) public view returns (uint256) {
        if (deposits == 0) {
            return 5000;
        }

        return borrows.mul(1e18).div(deposits);
    }

    function getBorrowFromDeposit(uint256 deposit) internal view returns (uint256) {
        return deposit.mul(targetCollatRatio).div(DENOMINATOR);
    }

    function getDepositFromBorrow(uint256 borrow) internal view returns (uint256) {
        return borrow.mul(DENOMINATOR).div(targetCollatRatio);
    }

    function harvester() internal {
        if (block.timestamp < lastHarvest.add(minReport)) {
            return;
        }

        gauge.claim_rewards();
        claimAaveRewards();
        disposeCrv();
        disposeAave();
        lastHarvest = block.timestamp;
    }

    function claimAaveRewards() internal{
        uint256 pending = predictAaveAccrued();
        if(pending < minAave) {
            return;
        }
        // claim stkAave from lending and borrowing, this will reset the cooldown
        aaveIncentivesController.claimRewards(
            getAaveAssets(),
            predictAaveAccrued(),
            address(this)
        );
    }

    function disposeCrv() internal {
        uint256 _crv = balanceOfToken(crv);
        if (_crv < minCrv) {
            return;
        }

        _swapFrom(crv, address(want), _crv);
    }

    function disposeAave() internal {
        uint256 _aave = balanceOfToken(aave);
        if (_aave < minAave) {
            return;
        }

        _swapFrom(aave, address(want), _aave);
    }

    //Based on want having 6 decimals
    function wantToBtc(uint256 _want) internal view returns(uint256) {
        return _want.mul(1e10).div(getWbtcPrice());
    }

    //based on want having 6 decimals, oracle returns eth in 8 decimals
    function wantToEth(uint256 _want) internal view returns(uint256) {
        return _want.mul(1e20).div(getWethPrice());
    }

    //price of btc based on oracle call
    function getWbtcPrice() internal view returns(uint256) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = btcPriceFeed.latestRoundData();
        return uint256(price);
    }

    //return price of eth based on oracle call
    function getWethPrice() internal view returns(uint256) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = ethPriceFeed.latestRoundData();
        //does not adjust for decimals that are returned with 8
        return uint256(price);
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

        uint256[] memory amounts = router.getAmountsOut(_amount, getTokenOutPath(start, end));

        return amounts[amounts.length - 1];
    }

    function _checkCrvPrice(
        address _from,
        address _to,
        uint256 _amount
    ) public view returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        return crvPool.get_dy_underlying(index[_from], index[_to], _amount);
    }

    function _crvSwapWithAmount(
        uint256 _from,
        uint256 _to,
        uint256 _fromAmount,
        uint256 _toMin
    ) internal{
        crvPool.exchange_underlying(_from, _to, _fromAmount, _toMin);
    }

    function _crvSwapFrom(
        address _from,
        address _to,
        uint256 _amount
    ) public{
         if (_amount == 0) {
            return;
        }

        uint256 to = _checkCrvPrice(_from, _to, _amount);
        _crvSwapWithAmount(index[_from], index[_to], _amount, to.mul(DENOMINATOR.sub(slippageProtectionIn)).div(DENOMINATOR));
    }

    //need to go from PTP to AVAX to USDC.e
    function _swapFromWithAmount(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _amountOut
    ) internal returns (uint256) {
        //IERC20(_from).approve(address(router), _amountIn);

        uint256[] memory amounts = router.swapExactTokensForTokens(
            _amountIn,
            _amountOut,
            getTokenOutPath(_from, _to),
            address(this),
            block.timestamp
        );

        return amounts[amounts.length - 1];
    }

    function _swapFrom(
        address _from,
        address _to,
        uint256 _amountIn
    ) internal returns (uint256) {
        uint256 amountOut = _checkPrice(_from, _to, _amountIn);

        return _swapFromWithAmount(_from, _to, _amountIn, amountOut);
    }

    function getTokenOutPath(address _tokenIn, address _tokenOut) internal view returns (address[] memory _path) {
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

    function getAaveAssets() internal view returns (address[] memory assets) {
        assets = new address[](3);
        assets[0] = aWant;
        assets[1] = varWbtc;
        assets[2] = varWeth;
    }

    function liquidateAllPositions() internal override returns (uint256) {
        gauge.withdraw(gauge.balanceOf(address(this)), true);
        claimAaveRewards();
        disposeCrv();
        disposeAave();
        
        uint256 shares = balanceOfToken(crvToken);

        uint256 wbtcOwed = balanceOfToken(varWbtc);
        uint256 wethOwed = balanceOfToken(varWeth);
        uint256[3] memory amounts;
        //adjust the want for any slippage to make sure we get the amound of debt we have owed
        amounts[wantIndex] = aThird(toWant(shares)).mul(DENOMINATOR.sub(slippageProtectionOut)).div(DENOMINATOR);
        amounts[wbtcIndex] = wbtcOwed;
        amounts[wethIndex] = wethOwed;

        crvPool.remove_liquidity(shares, amounts);

        _repay(wbtc, wbtcOwed);
        _repay(weth, wethOwed);
        
        _withdrawCollateral(balanceOfToken(aWant));

        //run check to swap back anyt extra that we swapped to wbtc/weth
        uint256 _wbtcB = balanceOfToken(wbtc);
        if (_wbtcB > 0) {
            _crvSwapFrom(wbtc, address(want), _wbtcB);
        }
        uint256 _wethB = balanceOfToken(weth);
        if (_wethB > 0) {
            _crvSwapFrom(weth, address(want), _wethB);
        }

        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        gauge.withdraw(gauge.balanceOf(address(this)), true);
        claimAaveRewards();
        
        uint256 shares = balanceOfToken(crvToken);

        uint256 wbtcOwed = balanceOfToken(varWbtc);
        uint256 wethOwed = balanceOfToken(varWeth);
        uint256[3] memory amounts;
        //adjust the want for any slippage to make sure we get the amound of debt we have owed
        amounts[wantIndex] = aThird(toWant(shares)).mul(DENOMINATOR.sub(slippageProtectionOut)).div(DENOMINATOR);
        amounts[wbtcIndex] = wbtcOwed;
        amounts[wethIndex] = wethOwed;

        crvPool.remove_liquidity(shares, amounts);

        _repay(wbtc, wbtcOwed);
        _repay(weth, wethOwed);
        
        uint256 _crvB = balanceOfToken(crv);
        if (_crvB > 0) {
            IERC20(crv).safeTransfer(_newStrategy, _crvB);
        }
        uint256 _aaveB = balanceOfToken(aave);
        if (_aaveB > 0) {
            IERC20(aave).safeTransfer(_newStrategy, _aaveB);
        }
        //run check to swap back anyt extra that we swapped to wbtc/weth
        uint256 _wbtcB = balanceOfToken(wbtc);
        if (_wbtcB > 0) {
            _crvSwapFrom(wbtc, address(want), _wbtcB);
        }
        uint256 _wethB = balanceOfToken(weth);
        if (_wethB > 0) {
            _crvSwapFrom(weth, address(want), _wethB);
        }

        IERC20(aWant).transfer(_newStrategy, balanceOfToken(aWant));
    }


    function protectedTokens() internal view override returns (address[] memory) {
        address[] memory protected = new address[](8);
        protected[0] = crvToken;
        protected[1] = crv;
        protected[2] = aave;
        protected[3] = wbtc;
        protected[4] = weth;
        protected[5] = aWant;
        protected[6] = varWbtc;
        protected[7] = varWeth;

        return protected;
    }

    function ethToWant(uint256 _amtInWei) public view virtual override returns (uint256) {
        //adjust for decimals from oracle
        //need to div by 1e(18 + (18 - want_Decimals)) // Assumes want has 6 decimals
        //can also not correct oracle decimals and div(1e20) 
        return (getWethPrice().mul(1e10)).mul(_amtInWei).div(1e30);
    }

    //Decimal issue is not wihtdrawaling any funds 1000000000 == 1 wbtc
    //manual withdraw incase needed
    function manualUnstake(uint256 _amount) external onlyStrategist {
        gauge.withdraw(_amount);
    }

    //manual withdraw incase needed
    //@param _amount in crvTokens
    function manualWithdraw(uint256 _amount) external onlyStrategist {
        crvPool.remove_liquidity_one_coin(_amount, wantIndex, 1);
    } 

    function manualRepay(uint256 _amount, address _toRepay) external onlyStrategist {
        _repay(_toRepay, _amount);
    }

    function manualSwap(address _from, address _to, uint256 _amount) external onlyStrategist {
        _crvSwapFrom(_from, _to, _amount);
    }

}
