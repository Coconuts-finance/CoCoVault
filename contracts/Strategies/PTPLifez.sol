// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
//import { BaseStrategy, StrategyParams } from "./BaseStrategy.sol";
import {BaseStrategy, StrategyParams} from  "../BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

// Import interfaces for many popular DeFi projects, or add your own!
import {SwapperLife} from "./SwapperLife.sol";
import {IPool} from "../interfaces/PTP/IPool.sol";
import {IMasterPlatypus} from "../interfaces/PTP/IMasterPlatypus.sol";

contract PTPLifez is BaseStrategy, SwapperLife {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IPool public pool; //0x66357dCaCe80431aee0A7507e2E361B7e2402370
    IMasterPlatypus masterPlatypus; //0xB0523f9F473812FB195Ee49BC7d2ab9873a98044
    IERC20 pUsdc; //IERC20(0x909B0ce4FaC1A0dCa78F8Ca7430bBAfeEcA12871);

    address PTP; //IERC20(0x22d4002028f537599be9f666d1c4fa138522f9c8);

    uint256 minPtp;
    uint256 minDeposit;
    uint256 pid;

    constructor(
        address _vault,
        address _pool,
        address _pUsdc,
        address _ptp,
        address _router,
        address _factory,
        address _masterPlatypus,
        uint256 _pid
    ) public BaseStrategy(_vault) {
        initializeIt(_pool, _pUsdc, _ptp, _router, _factory, _masterPlatypus, _pid);
    }

    //approve all to the staking contract

    function initializeIt(
        address _pool,
        address _pUsdc,
        address _ptp,
        address _router,
        address _factory,
        address _masterPlatypus,
        uint256 _pid
    ) internal {
        // Instantiate vault
        pUsdc = IERC20(_pUsdc);
        setPool(_pool);
        PTP = _ptp;
        _setMightyJoeRouter(_router);
        _setJoeFactory(_factory);
        setMasterPlatypus(_masterPlatypus);
        pid = _pid;

        minPtp = 10000000000000000;
        minDeposit = 1000;
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "PTPLIFEZ";
    }

    function changePool(address _pool) public onlyStrategist {
        require(_pool != address(pool), "Cant change to same vault");

        uint256 _allowance = want.allowance(address(this), address(pool));
        want.safeDecreaseAllowance(address(pool), _allowance);
        _allowance = pUsdc.allowance(address(this), address(pool));
        pUsdc.safeDecreaseAllowance(address(pool), _allowance);
        setPool(_pool);
    }

    function setPool(address _pool) internal {
        pool = IPool(_pool);
        pUsdc.safeApprove(_pool, type(uint256).max);
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

    function setMasterPlatypus(address _master) internal {
        masterPlatypus = IMasterPlatypus(_master);

        pUsdc.safeApprove(_master, type(uint256).max);
    }

    function changeMasterPlatypus(address _master) external onlyStrategist {
        require(_master != address(masterPlatypus), "Your a Dumbass");

        uint256 _allowance = pUsdc.allowance(address(this), address(masterPlatypus));
        pUsdc.safeDecreaseAllowance(address(masterPlatypus), _allowance);

        setMasterPlatypus(_master);
    }

    function setPid(uint256 _pid) external onlyStrategist {
        pid = _pid;
    }

    function setMinPtp(uint256 _min) external onlyStrategist {
        minPtp = _min;
    }

    function toWant(uint256 _shares) public view returns (uint256) {
        if (_shares == 0) {
            return 0;
        }

        (uint256 _amount, , ) = pool.quotePotentialWithdraw(address(want), _shares);
        return _amount;
    }

    function balanceOfToken(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    //returns balance of unerlying asset
    function balanceOfVault() public view returns (uint256) {
        return pUsdc.balanceOf(address(this));
    }

    function stakedBalance() public view returns (uint256) {
        (uint256 _amount, , ) = masterPlatypus.userInfo(pid, address(this));
        return _amount;
    }

    function invested() public view returns (uint256) {
        return balanceOfVault().add(stakedBalance());
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 bal = toWant(invested()).add(balanceOfToken(address(want)));
        //get estimated PTP and price
        uint256 _claimablePTP = predictPtpAccrued();
        uint256 currentPTP = balanceOfToken(PTP);

        // Use touch price. it doesnt matter if we are wrong as this is not used for decision making
        uint256 estimatedWant = _checkPrice(PTP, address(want), _claimablePTP.add(currentPTP));
        uint256 conservativeWant = estimatedWant.mul(9).div(10); //10% pessimist

        return bal.add(conservativeWant);
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
        harvestPtp();
        //swap rewards to main want
        disposeOfPtp();

        //get base want balance
        uint256 wantBalance = balanceOfToken(address(want));
        uint256 balance = wantBalance.add(toWant(invested()));

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

    function predictPtpAccrued() public view returns (uint256) {
        (uint256 _pendingPtp, , , ) = masterPlatypus.pendingTokens(pid, address(this));
        return _pendingPtp;
    }

    //check if this shit works
    function harvestPtp() internal {
        //harvest that mofo
        if (predictPtpAccrued() < minPtp) {
            return;
        }
        uint256[] memory _pids = new uint256[](1);
        _pids[0] = pid;

        masterPlatypus.multiClaim(_pids);
    }

    //sell joe function

    function disposeOfPtp() internal {
        uint256 _ptp = balanceOfToken(PTP);
        if (_ptp < minPtp) {
            return;
        }

        _swapFrom(PTP, address(want), _ptp);
    }

    //approve all to the staking contract

    //invests available tokens
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

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        //check what we have available
        uint256 wantBalance = balanceOfToken(address(want));
        uint256 deposited = toWant(invested());
        if (_amountNeeded > wantBalance) {
            //harvest first to avoid withdraw fees
            harvestPtp();
            disposeOfPtp();
            wantBalance = balanceOfToken(address(want));

            //if we need more than avaialble find out how much
            if (_amountNeeded > wantBalance) {
                uint256 amountToFree = _amountNeeded.sub(wantBalance);

                //check if there is enough in vault
                if (deposited <= amountToFree) {
                    //withdraw evertything
                    withdrawSome(deposited);

                    _liquidatedAmount = balanceOfToken(address(want));
                    _loss = _amountNeeded.sub(_liquidatedAmount);
                } else {
                    withdrawSome(amountToFree);
                    wantBalance = balanceOfToken(address(want));

                    //check if we got enough tokens from the withdraw
                    if (wantBalance >= _amountNeeded) {
                        _liquidatedAmount = _amountNeeded;
                    } else {
                        _liquidatedAmount = wantBalance;
                        _loss = _amountNeeded.sub(wantBalance);
                    }
                }
            } else {
                _liquidatedAmount = _amountNeeded;
            }

            //if we have enough free tokens to start with
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function depositSome(uint256 _amount) internal {
        if (_amount < minDeposit) {
            return;
        }

        //deposit into the pool
        pool.deposit(address(want), _amount, address(this), block.timestamp);
        //stake the tokens
        masterPlatypus.deposit(pid, pUsdc.balanceOf(address(this)));
    }

    function withdrawSome(uint256 _amountNeeded) internal {
        uint256 bal = pUsdc.balanceOf(address(this));
        if (_amountNeeded > bal) {
            //need to unstake difference
            uint256 staked = stakedBalance();

            if (staked <= _amountNeeded.sub(bal)) {
                masterPlatypus.withdraw(pid, staked);
            } else {
                masterPlatypus.withdraw(pid, _amountNeeded.sub(bal));
            }

            pool.withdraw(address(want), toWant(pUsdc.balanceOf(address(this))), 0, address(this), block.timestamp);
        } else {
            pool.withdraw(address(want), _amountNeeded, 0, address(this), block.timestamp);
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        harvestPtp();
        disposeOfPtp();

        (uint256 staked, , ) = masterPlatypus.userInfo(pid, address(this));
        masterPlatypus.withdraw(pid, staked);

        pool.withdraw(address(want), pUsdc.balanceOf(address(this)), 0, address(this), block.timestamp);

        return balanceOfToken(address(want));
    }

    function prepareMigration(address _newStrategy) internal override {
        harvestPtp();
        IERC20 _ptp = IERC20(PTP);
        uint256 _ptpB = balanceOfToken(PTP);
        if (_ptpB > 0) {
            _ptp.safeTransfer(_newStrategy, _ptpB);
        }
        (uint256 staked, , ) = masterPlatypus.userInfo(pid, address(this));
        masterPlatypus.withdraw(pid, staked);

        pUsdc.transfer(_newStrategy, pUsdc.balanceOf(address(this)));
    }

    function protectedTokens() internal view override returns (address[] memory) {
        address[] memory protected = new address[](2);
        protected[0] = address(pUsdc);
        protected[1] = PTP;

        return protected;
    }

    function ethToWant(uint256 _amtInWei) public view virtual override returns (uint256) {
        return _checkPrice(wavax, address(want), _amtInWei);
    }

    //manual withdraw incase needed
    function manualWithdraw(uint256 _amount) external onlyStrategist {
        pUsdc.approve(address(pool), _amount);
        pool.withdraw(address(want), _amount, 0, address(this), block.timestamp);
    }

    //manual withdraw incase needed
    function manualUnstake(uint256 _pid, uint256 _amount) external onlyStrategist {
        masterPlatypus.withdraw(_pid, _amount);
    }
}
