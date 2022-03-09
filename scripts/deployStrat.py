from pathlib import Path
from sqlite3 import paramstyle
import click

from brownie import Vault, StrategyLib, Token, accounts, config, network, project, web3
from eth_utils import is_checksum_address
from brownie.network.gas.strategies import LinearScalingStrategy

#Variables
vault = Vault.at('')
lib = StrategyLib.at('')
acct = accounts.add('')

token = Token.at('')

gas_strategy = LinearScalingStrategy("28 gwei", "30 gwei", 1.1)

param = { 'from': acct, 'gas_price': gas_strategy }

def main():
    print(f"You are using the '{network.show_active()}' network")
    
    dev = acct
    print(f"You are using: 'dev' [{dev.address}]")

    if input("Is there a Vault for this strategy already? y/[N]: ").lower() != "n":
        click.echo(f"Using vualt at [{vault.address}]")
    else:
        return  # TODO: Deploy one using scripts from Vault project

    print(
        f"""
    Strategy Parameters
     
     token: {vault.token()}
      name: '{vault.name()}'
    symbol: '{vault.symbol()}'
    """
    )
    print('API version: ', vault.apiVersion())
    if input("Deploy Strategy? y/[N]: ").lower() != "y":
        return

    strategy = Strategy.deploy(
        vault.address, 
        param
    )
    
    #Adjust the debt ratio in order to add new strat'
 

    strategy = strategy.address       # Your strategy address
    debt_ratio = 4000                 # 98%
    minDebtPerHarvest = 0             # Lower limit on debt add
    maxDebtPerHarvest = 2 ** 256 - 1  # Upper limit on debt add
    performance_fee = 1000            # Strategist perf fee: 10%

    tx = vault.addStrategy(
        strategy, 
        debt_ratio, 
        minDebtPerHarvest,
        maxDebtPerHarvest,
        performance_fee, 
        param
    )
    

    print('Strategy added to Vault')
    

