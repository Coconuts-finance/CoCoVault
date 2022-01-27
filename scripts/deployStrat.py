from pathlib import Path
import click

from brownie import Vault, BeefMaster, StrategyLib, accounts, config, network, project, web3
from eth_utils import is_checksum_address


API_VERSION = config["dependencies"][0].split("@")[-1]
"""
Vault = project.load(
    Path.home() / ".brownie" / "packages" / config["dependencies"][0]
).Vault
"""
acct = accounts.add('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80')
beefVault = '0xAf9f33df60CA764307B17E62dde86e9F7090426c'
gas_price = 103628712501

def get_address(msg: str) -> str:
    while True:
        val = input(msg)
        if is_checksum_address(val):
            return val
        else:
            addr = web3.ens.address(val)
            if addr:
                print(f"Found ENS '{val}' [{addr}]")
                return addr
        print(f"I'm sorry, but '{val}' is not a checksummed address or ENS")


def main():
    print(f"You are using the '{network.show_active()}' network")
    #dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    dev = acct
    print(f"You are using: 'dev' [{dev.address}]")
    
    param = { 'from': dev, 'gas_price': gas_price }

    if input("Is there a Vault for this strategy already? y/[N]: ").lower() != "n":
        vault = Vault.at(get_address("Deployed Vault: "))
        
        #assert vault.apiVersion() == API_VERSION
    else:
        return  # TODO: Deploy one using scripts from Vault project

    print(
        f"""
    Strategy Parameters
       api: {API_VERSION}
     token: {vault.token()}
      name: '{vault.name()}'
    symbol: '{vault.symbol()}'
    """
    )
    print('API version: ', vault.apiVersion())
    if input("Deploy Strategy? y/[N]: ").lower() != "y":
        return

    lib = StrategyLib.deploy( param )
    print('Library deployed to ', lib.address )
    strategy = BeefMaster.deploy(vault, beefVault, param)

    print("Strategy Deployed: ", strategy.address)

    strategy = strategy.address       # Your strategy address
    debt_ratio = 9800                 # 98%
    minDebtPerHarvest = 0             # Lower limit on debt add
    maxDebtPerHarvest = 2 ** 256 - 1  # Upper limit on debt add
    performance_fee = 1000            # Strategist perf fee: 10%

    vault.addStrategy(
        strategy, 
        debt_ratio, 
        minDebtPerHarvest,
        maxDebtPerHarvest,
        performance_fee, 
        param
    )