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
vault = Vault.at("0xDecdE3D0e1367155b62DCD497B0A967D6aa41Afd")
lib = StrategyLib.at("0xDB5f0fcfb3428B3e256E4a8e36Af9457866b6e7d")
acct = accounts.at('0xaa9F4EB6273904CC609bdB06e7Df9f26Ed223Ff9', force=True)

gas_strategy = LinearScalingStrategy("25 gwei", "100 gwei", 1.1)
#yak = YakAttack.at("Old Address")
usdc = Token.at("0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664")

joe = SingleJoe.at('0x5d95e05e208cb11aa42a90287a75fe610564896b')
new = SingleJoe.at('0x19780b6ff970Acc8eA01F2e7d33d224FeF000f6B')
yakFarm = "0xf5Ac502C3662c07489662dE5f0e127799D715E1E"


param = {"from": acct, "gas_price": gas_strategy}


def main():

    print("Vault USDC balance: ", usdc.balanceOf(vault.address))
    print("Old Strategy balance: ", joe.estimatedTotalAssets())
    print("Acct usdc: ", usdc.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))
    """
    strategy = SingleJoe.deploy(
        vault.address, 
        '0xEd6AaF91a2B084bd594DBd1245be3691F9f637aC', #Pool
        '0x60aE616a2155Ee3d9A68541Ba4544862310933d4', #Router 
        '0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd', #Joe Token
        '0xdc13687554205E5b89Ac783db14bb5bba4A1eDaC',  #Joe Troller
        param
    )
    
    print("Strategy Deployed: ", strategy.address)
    """
    vault.migrateStrategy(joe, new, param)

    tx = new.harvest(param)
    print(tx.events)

    print("Vault USDC balance: ", usdc.balanceOf(vault.address))
    print("Old Strategy balance: ", joe.estimatedTotalAssets())
    print("New Strat Balance: ", new.estimatedTotalAssets())
    print("Acct usdc: ", usdc.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))
