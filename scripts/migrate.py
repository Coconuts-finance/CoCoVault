from pathlib import Path
import click

from brownie import (
    Vault,
    Token,
    BeefMaster,
    YakAttack,
    JoeFoSho,
    PTPLifez,
    SingleJoe,
    StrategyLib,
    accounts,
    config,
    network,
    project,
    web3,
)
from eth_utils import is_checksum_address
from brownie.network.gas.strategies import LinearScalingStrategy

# Adding all
# Variables
vault = Vault.at("")
lib = StrategyLib.at("")
acct = accounts.at('')
token = Token.at('')
old = Strategy.at('')

gas_strategy = LinearScalingStrategy("25 gwei", "100 gwei", 1.1)

param = {"from": acct, "gas_price": gas_strategy}


def main():

    print("Vault USDC balance: ", token.balanceOf(vault.address))
    print("Old Strategy balance: ", old.estimatedTotalAssets())
    print("Acct usdc: ", token.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))
    
    new = Strategy.deploy(
        vault.address, 
        
        param
    )
    
    print("Strategy Deployed: ", strategy.address)
    
    vault.migrateStrategy(old, new, param)

    tx = new.harvest(param)
    print(tx.events)

    print("Vault USDC balance: ", token.balanceOf(vault.address))
    print("Old Strategy balance: ", old.estimatedTotalAssets())
    print("New Strat Balance: ", new.estimatedTotalAssets())
    print("Acct usdc: ", token.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))
