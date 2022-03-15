from pathlib import Path
from sqlite3 import paramstyle
import click

from brownie import Vault, StrategyLib, Token, accounts, config, network, project, web3 #import strategy to be deployed
from eth_utils import is_checksum_address
from brownie.network.gas.strategies import LinearScalingStrategy


#Variables
acct = accounts.add('privKey')
gas_strategy = LinearScalingStrategy("30 gwei", "50 gwei", 1.1)
param = { 'from': acct, 'gas_price': gas_strategy }

#tokens
usdc = '0x2791bca1f2de4661ed88a30c99a7a9449aa84174'
dai = '0x8f3cf7ad23cd3cadbd9735aff958023239c6a063'
weth = '0x7ceb23fd6bc0add59e62ac25578270cff1b9f619'
wbtc = '0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6'
wmatic = '0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270'

#vaults
usdcVault = ''
daiVault = ''
wethVault = ''
wbtcVault = '0x5fa039aFc64dABC8B219b6E85749faD3939D8564'
wmaticVault = ''

#Variables
lib = StrategyLib.at('0x2857092696a0e5337f3d2c0601292c6C5682FC11')

### THESE VARIABLES NEED TO BE UPDATED
vault = Vault.at(usdcVault)
token = Token.at(usdc)
Strategy =  S       # name of strategy that is imported above
### THESE VARIABLES NEED TO BE UPDATED

def main():
    print(f"You are using the '{network.show_active()}' network")
    
    print(f"You are using: 'dev' [{acct.address}]")

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
        # Optional Paramaters for strat
        param
    )
    
    if acct.address == vault.governance():
        #Adjust the debt ratio in order to add new strat if needed
        # _amount = 4400
        # vault.updateStrategyDebtRatio(oldStrat.address, _amount, param)
 
        strategy = strategy.address       # Your strategy address
        debt_ratio = 9800                 # 98%
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
    

