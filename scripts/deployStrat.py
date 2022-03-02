from pathlib import Path
from sqlite3 import paramstyle
import click

from brownie import Vault, BeefMaster, YakAttack, SingleJoe, PTPLifez, StrategyLib, Token, accounts, config, network, project, web3
from eth_utils import is_checksum_address
from brownie.network.gas.strategies import LinearScalingStrategy

#Variables
vault = Vault.at('0xDecdE3D0e1367155b62DCD497B0A967D6aa41Afd')
lib = StrategyLib.at('0xDB5f0fcfb3428B3e256E4a8e36Af9457866b6e7d')
acct = accounts.add('')

beefVault = '0xEbdf71f56BB3ae1D145a4121d0DDCa5ABEA7a946'
beef = BeefMaster.at('0x19284d07aab8Fa6B8C9B29F9Bc3f101b2ad5f661')
yakFarm = '0xf5Ac502C3662c07489662dE5f0e127799D715E1E'
yak = YakAttack.at('0x9F1a3536d7B4f27e0e20bc6d9a55588a1a00bf9C')

usdc = Token.at('0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664')

gas_strategy = LinearScalingStrategy("28 gwei", "30 gwei", 1.1)

param = { 'from': acct, 'gas_price': gas_strategy }

def main():
    print(f"You are using the '{network.show_active()}' network")
    #dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
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

    strategy = SingleJoe.deploy(
        vault.address, 
        '0xEd6AaF91a2B084bd594DBd1245be3691F9f637aC', #Pool
        '0x60aE616a2155Ee3d9A68541Ba4544862310933d4', #Router 
        '0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd', #Joe Token
        '0xdc13687554205E5b89Ac783db14bb5bba4A1eDaC',  #Joe Troller
        param
    )
    
    print("Strategy Deployed: ", strategy.address)

    vault.migrateStrategy(beef, strategy, param);

    print("Vault USDC balance: ", usdc.balanceOf(vault.address))
    print("beef Strategy balance: ", beef.estimatedTotalAssets())
    print("New Strat Balance: ", strategy.estimatedTotalAssets())
    print("Acct usdc: ", usdc.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))
    
    tx = strategy.harvest(param)
    print(tx.events)

    print("Vault USDC balance: ", usdc.balanceOf(vault.address))
    print("Old Strategy balance: ", beef.estimatedTotalAssets())
    print("New Strat Balance: ", strategy.estimatedTotalAssets())
    print("Acct usdc: ", usdc.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))

    """
    
    strategy = PTPLifez.deploy(
        vault.address,
        '0x66357dCaCe80431aee0A7507e2E361B7e2402370',    ##pool
        '0x909B0ce4FaC1A0dCa78F8Ca7430bBAfeEcA12871',   #pUsdc
        '0x22d4002028f537599be9f666d1c4fa138522f9c8',   #ptp
        '0x60aE616a2155Ee3d9A68541Ba4544862310933d4',    #router
        '0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10',    #factory
        '0xB0523f9F473812FB195Ee49BC7d2ab9873a98044',    #Master Plat
        1,      #pid
        param
    )
    
    #Adjust the debt ratio in order to add new strat'
    vault.updateStrategyDebtRatio(beef.address, 4000, param)
    
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
    """

