// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
//import { BaseStrategy, StrategyParams } from "./BaseStrategy.sol";
import {BaseStrategy, StrategyParams} from  "../BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Import interfaces for many popular DeFi projects, or add your own!
import {IYakFarm} from "../interfaces/YieldYak/IYakFarm.sol";

contract YakAttack is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IYakFarm public YakFarm;

    //for calculating profit without harvest
    uint256 lastPPS = 0;
    uint256 lastShares = 0;

    constructor(address _vault, address _yakFarm) public BaseStrategy(_vault) {
        // Instantiate vault
        setVault(_yakFarm);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "YakAttack";
    }

    function changeVault(address _vault) public onlyStrategist {
        require(_vault != address(YakFarm), "Cant change to same vault");

        want.safeDecreaseAllowance(address(YakFarm), type(uint256).max);

        setVault(_vault);
    }

    function setVault(address _vault) internal {
        YakFarm = IYakFarm(_vault);

        lastPPS = toWant(1000000);
        lastShares = balanceOfVault();
        want.safeApprove(_vault, type(uint256).max);
    }

    function toWant(uint256 _shares) public view returns (uint256) {
        return YakFarm.getDepositTokensForShares(_shares);
    }

    function toWantPPS(uint256 _shares, uint256 _pps) public view returns (uint256) {
        return _pps.mul(_shares).div(1e6);
    }

    //takes underlying and converts it to Beef Vault share price for withdraw
    //@param _amount The amount in the underlying asset needed
    function toShares(uint256 _amount) internal view returns (uint256) {
        return YakFarm.getSharesForDepositTokens(_amount);
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    //returns balance of unerlying asset
    function balanceOfVault() public view returns (uint256) {
        //check this works
        return YakFarm.balanceOf(address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return toWant(balanceOfVault()).add(balanceOfWant());
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
        //retrun just profit due to stable coin vault with no harvesting needed
        uint256 shares = balanceOfVault();
        uint256 pps = toWant(1000000);
        uint256 prev;
        uint256 current;

        if (shares >= lastShares) {
            prev = toWantPPS(lastShares, lastPPS);
            current = toWant(lastShares);
        } else {
            prev = toWantPPS(shares, lastPPS);
            current = toWant(shares);
        }


        if (current > prev) {
            _profit = current.sub(prev);
            uint256 bal = balanceOfWant();
            if (_profit > bal) {
                uint256 diff = _profit.sub(bal);
                (uint256 _liquidatedAmount, uint256 _lost) = liquidatePosition(diff);

                _profit = balanceOfWant();
            }
        } else {
            _loss = prev.sub(current);
        }

        lastPPS = pps;
        lastShares = shares;
    }

    //invests available tokens
    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }
        // send all of our want tokens to be deposited
        uint256 toInvest = balanceOfWant();
        // stake only if we have something to stake
        if (toInvest > 0) {
            YakFarm.deposit(toInvest);
        }
    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        //check what we have available
        uint256 wantBalance = balanceOfWant();
        uint256 deposited = toWant(balanceOfVault());
        if (_amountNeeded > wantBalance) {
            //if we need more than avaialble find out how much
            uint256 amountToFree = _amountNeeded.sub(wantBalance);

            //check if there is enough in vault
            if (deposited < amountToFree) {
                amountToFree = deposited;
            }
            //withdraw what is needed
            YakFarm.withdraw(toShares(amountToFree));

            //recheck balance of free tokens
            wantBalance = balanceOfWant();

            //check if we got enough tokens from the withdraw
            if (wantBalance >= _amountNeeded) {
                _liquidatedAmount = _amountNeeded;
            } else {
                _liquidatedAmount = wantBalance;
                _loss = _amountNeeded.sub(wantBalance);
            }

            //if we have enough free tokens to start with
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        YakFarm.withdraw(balanceOfVault());

        return balanceOfWant();
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        YakFarm.withdraw(balanceOfVault());
    }

    function protectedTokens() internal view override returns (address[] memory) {
        address[] memory protected = new address[](1);
        protected[0] = address(YakFarm);

        return protected;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei) public view virtual override returns (uint256) {
        // TODO create an accurate price oracle
        return _amtInWei;
    }
}
