from pathlib import Path
import click

from brownie import Vault, BeefMaster, YakAttack, JoeFoSho, PTPLifez, SingleJoe, StrategyLib, accounts, Token, config, network, project, web3
from eth_utils import is_checksum_address
from brownie.network.gas.strategies import LinearScalingStrategy


API_VERSION = config["dependencies"][0].split("@")[-1]
"""
Vault = project.load(
    Path.home() / ".brownie" / "packages" / config["dependencies"][0]
).Vault
"""
#Variables
vault = Vault.at('0xDecdE3D0e1367155b62DCD497B0A967D6aa41Afd')
lib = StrategyLib.at('0xDB5f0fcfb3428B3e256E4a8e36Af9457866b6e7d')
acct = accounts.at('0xaa9F4EB6273904CC609bdB06e7Df9f26Ed223Ff9', force=True)
beefVault = '0xEbdf71f56BB3ae1D145a4121d0DDCa5ABEA7a946'
beef = BeefMaster.at('0x19284d07aab8Fa6B8C9B29F9Bc3f101b2ad5f661')
yakFarm = '0xf5Ac502C3662c07489662dE5f0e127799D715E1E'
usdc = Token.at('0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664')
yak = YakAttack.at('0x9F1a3536d7B4f27e0e20bc6d9a55588a1a00bf9C')

pp = PTPLifez.at('0x541dCb7b9F340D6b311034D33581563213de11cF')
joe = SingleJoe.at('0x5D95e05E208CB11aa42A90287A75fe610564896B')

gas_strategy = LinearScalingStrategy("30 gwei", "100 gwei", 1.1)

param = { 'from': acct, 'gas_price': gas_strategy }


def main():
    
    print('Vault USDC balance: ', usdc.balanceOf(vault.address))
    print('Yak Strategy balance: ', yak.estimatedTotalAssets())
    print('Beef Strategy balance: ', beef.estimatedTotalAssets())
    print('Acct usdc: ', usdc.balanceOf(acct.address))
    print('Account cvUSDC: ', vault.balanceOf(acct.address))

    #beef.harvest(param)
    #yak.harvest(param)

    print('Vault USDC balance: ', usdc.balanceOf(vault.address))
    print('Yak Strategy balance: ', yak.estimatedTotalAssets())
    print('Beef Strategy balance: ', beef.estimatedTotalAssets())
    print('Acct usdc: ', usdc.balanceOf(acct.address))
    print('Account cvUSDC: ', vault.balanceOf(acct.address))

    joe.harvest(param)

    print('Vault USDC balance: ', usdc.balanceOf(vault.address))
    print('Yak Strategy balance: ', yak.estimatedTotalAssets())
    print('Beef Strategy balance: ', beef.estimatedTotalAssets())
    print('Acct usdc: ', usdc.balanceOf(acct.address))
    print('Account cvUSDC: ', vault.balanceOf(acct.address))