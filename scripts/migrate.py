from pathlib import Path
import click

from brownie import (
    Vault,
    Token,
    BeefMaster,
    YakAttack,
    JoeFoSho,
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
acct = accounts.add("8e77fce15451f2ea0597bd5346eb183a64baf8490cc99a335ccda21c0f0b7cbb")

gas_strategy = LinearScalingStrategy("30 gwei", "100 gwei", 1.1)
#yak = YakAttack.at("Old Address")
usdc = Token.at("0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664")

joe = JoeFoSho.at('0xF2FCfB84f46E986fb691Ab35065C6948a3958008')
yakFarm = "0xf5Ac502C3662c07489662dE5f0e127799D715E1E"
new = JoeFoSho.at("0xF2FCfB84f46E986fb691Ab35065C6948a3958008")

param = {"from": acct, "gas_price": gas_strategy}


def main():

    print("Vault USDC balance: ", usdc.balanceOf(vault.address))
    print("Strategy balance: ", joe.estimatedTotalAssets())
    print("Acct usdc: ", usdc.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))

    #vault.migrateStrategy(joe, new, param)

    print("Vault USDC balance: ", usdc.balanceOf(vault.address))
    print("Old Strategy balance: ", joe.estimatedTotalAssets())
    print("new Strategy balance: ", new.estimatedTotalAssets())
    print("Acct usdc: ", usdc.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))

    tx = new.harvest(param)
    print(tx.events)

    print("Vault USDC balance: ", usdc.balanceOf(vault.address))
    print("Yak Strategy balance: ", joe.estimatedTotalAssets())
    print("New Strat Balance: ", new.estimatedTotalAssets())
    print("Acct usdc: ", usdc.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))
