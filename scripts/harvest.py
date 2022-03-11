from pathlib import Path
import click

from brownie import (
    Vault,
    YakAttack,
    PTPLifez,
    StrategyLib,
    accounts,
    Token,
    config,
    network,
    project,
    web3,
)
from eth_utils import is_checksum_address
from brownie.network.gas.strategies import LinearScalingStrategy


API_VERSION = config["dependencies"][0].split("@")[-1]
"""
Vault = project.load(
    Path.home() / ".brownie" / "packages" / config["dependencies"][0]
).Vault
"""
# Variables
vault = Vault.at("0xDecdE3D0e1367155b62DCD497B0A967D6aa41Afd")

acct = accounts.add("")
yak = YakAttack.at("0x9F1a3536d7B4f27e0e20bc6d9a55588a1a00bf9C")
pp = PTPLifez.at("0x541dCb7b9F340D6b311034D33581563213de11cF")
token = Token.at("0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664")
gas_strategy = LinearScalingStrategy("26 gwei", "30 gwei", 1.1)

param = {"from": acct, "gas_price": gas_strategy}


def main():

    print("Vault token balance: ", token.balanceOf(vault.address))
    print("Yak assets :", yak.estimatedTotalAssets())
    print("PP assets :", pp.estimatedTotalAssets())
    print("Acct token: ", token.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))
    print("Vault PPS ", vault.pricePerShare())

    yak.setEmergencyExit(param)
    yak.harvest(param)
    pp.harvest(param)

    print("Vault token balance: ", token.balanceOf(vault.address))
    print("Yak assets :", yak.estimatedTotalAssets())
    print("PP assets :", pp.estimatedTotalAssets())
    print("Acct token: ", token.balanceOf(acct.address))
    print("Account cvUSDC: ", vault.balanceOf(acct.address))
    print("Vault PPS ", vault.pricePerShare())
