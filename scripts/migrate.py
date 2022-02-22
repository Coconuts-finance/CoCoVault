from pathlib import Path
import click

from brownie import (
    Vault,
    Token,
    BeefMaster,
    YakAttack,
    JoeFoSho,
    PTPLifez,
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
vault = Vault.at("0xDecdE3D0e1367155b62DCD497B0A967D6aa41Afd")
lib = StrategyLib.at("0xDB5f0fcfb3428B3e256E4a8e36Af9457866b6e7d")
acct = accounts.add("")

gas_strategy = LinearScalingStrategy("30 gwei", "100 gwei", 1.1)
#yak = YakAttack.at("Old Address")
usdc = Token.at("0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664")

ptp = PTPLifez.at('0xF2FCfB84f46E986fb691Ab35065C6948a3958008')
yakFarm = "0xf5Ac502C3662c07489662dE5f0e127799D715E1E"


param = {"from": acct, "gas_price": gas_strategy}


def main():

    print("Vault USDC balance: ", usdc.balanceOf(vault.address))
    print("Strategy balance: ", ptp.estimatedTotalAssets())
    print("Acct usdc: ", usdc.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))
    
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
   
    print("Strategy Deployed: ", strategy.address)

    vault.migrateStrategy(ptp, strategy, param)

    tx = strategy.harvest(param)
    print(tx.events)

    print("Vault USDC balance: ", usdc.balanceOf(vault.address))
    print("ptp Strategy balance: ", ptp.estimatedTotalAssets())
    print("New Strat Balance: ", strategy.estimatedTotalAssets())
    print("Acct usdc: ", usdc.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))
